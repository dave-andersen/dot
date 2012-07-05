#include "gcp.h"
#include <libgen.h>
static struct timeval start;
static struct timeval end;
extern struct timeval gcp_start;
static int td_pending;
static bool err_flag = false;

void
finish(str name, cbv cb, str err)
{
    td_pending--;

    if (err) {
	warnx << "Error " << err << "\n"; 
	err_flag = true;
    }

    str n = strbuf() << name << "." << getpid();
    if (return_fd(n)) {
	if (rename(n, name) < 0) 
	    warn << "Rename failed\n";
    }

    dwarn(DEBUG_CLIENT) << "Just finished " << name << "\n";

    if (cb)
	(*cb)();
}

void
generate_disk_hint(str compname, unsigned int size,
		   int modtime, oid_hint *h, str ig_path)
{
    char *line, *brkt;
    
    str newname;
    if (compname[0] != '/') {
	char cwd[PATH_MAX+1];
	if (!getcwd (cwd, sizeof (cwd)))
	    fatal << "getcwd failed\n";
	
	newname = strbuf() << cwd << "/" << compname;
	dwarn(DEBUG_CLIENT) << "./ New name is " << newname << "\n";
    } else {
	newname = compname;
    }

    char *ptr = strdup(newname);

    //1. remove two consec slashes
    //2. if there is a ./ remove it
    //3. if there is a ../ adjust the path
    for (line = strtok_r(ptr, "/", &brkt);  
         line; line = strtok_r(NULL, "/", &brkt)) {
        str a(line, strlen(line));
        if (a == "." ) continue;
	if (a == "..") {
	    const char *lastslash = strrchr(newname, '/');
	    newname = str(newname, lastslash-newname);
	    continue;
	}
	if (newname == "/" || newname == "")
	    newname = strbuf() << newname << a;
	else
	    newname = strbuf() << newname << "/" << a ;
    }

    dwarn(DEBUG_CLIENT) << "Clean path is " << newname << "\n";

    /* Some basename/dirname headers don't specify the const.  Ugh. */
    char *tmp = strdup(newname);
    str target_path = dirname(tmp);
    str name = basename(tmp);
    free(tmp);

    free(ptr);
    
    if (!ig_path)
	ig_path = target_path;
    
    //name of the file, target directory, size, mod time, pid
    name = strbuf() << "xdisk://" << name << ":"
		    << target_path << ":" << size
		    << ":" << modtime << ":" << getpid()
		    << ":" << ig_path;
    h->name = name;
    dwarn(DEBUG_CLIENT) << "Xdisk hint is " << h->name << "\n";
}

static void
setup_path(file_struct fs, const char *path)
{
    struct stat sb;
    if (stat(path, &sb) == 0) {
	if (!S_ISDIR(sb.st_mode))
	    fatal("Not a dir: %s\n", path);
	return;
    }
    
    dwarn(DEBUG_CLIENT) << "setup_path: " << path << "\n";

    if (mkdir(path, S_IRWXU) < 0)
        warn("mkdir failed: %m: %s\n", path);
    else if (chmod(path, fs.mode) < 0)
        warn("chmod failed: %m: %s\n", path);
}

static void
setup_symlink(file_struct fs, const char *path, const char *target)
{
    dwarn(DEBUG_CLIENT) << "setup_symlink: " << path
        << " -> " << target << "\n";

    if (strlen(target) == 0)
        warn("empty symlink target: %s\n", path);
    else if (symlink(target, path) < 0)
        warn("symlink failed: %m: %s\n", path);
}

static int
setup_file(file_struct fs, ptr<str> name)
{
    struct stat sb;
       
    dwarn(DEBUG_CLIENT) << "setup_file " << fs.destpath << " and " << fs.filename << "\n";
    
    if (fs.destpath && 0 == stat(fs.destpath, &sb) && (sb.st_mode & S_IFDIR)) {
	*name = strbuf() << fs.destpath << "/" << fs.filename;
	dwarn(DEBUG_CLIENT) << "Name is " << *name << "\n";
    } 
    else {
	*name = fs.destpath;
    }

    str outfile = strbuf() << *name << "." << getpid();

    dwarn(DEBUG_CLIENT) << "Opening 2 " << outfile << "\n";

    int outfd = get_new_fd(outfile);
    if (outfd < 0) {
        warn("open failed: %m: %s\n", outfile.cstr());
        return -1;
    }

    if (fchmod(outfd, fs.mode) < 0) {
        warn("fchmod failed: %m: %s\n", outfile.cstr());
	close(outfd);
        return -1;
    }

    dwarn(DEBUG_CLIENT) << "Returning " << outfd << "\n";
    return 0;
}

void
get_done(svccb *sbp)
{
    if (td_pending <= 0 || err_flag) {
	
	gettimeofday(&end, NULL);
	fprintf(stderr, "time for GCP_PROC_PUT data xfer == %.4f\n",
		timeval_diff(&start, &end));
	fprintf(stderr, "time for GCP_PROC_PUT start-finish == %.4f\n",
		timeval_diff(&gcp_start, &end));

	gcp_put_res res(true);
	
	if (err_flag) {
	    res.set_ok(false);
	    str err("get failed");
	    *res.errmsg = err;
	}
	
	if (sbp)
	    sbp->replyref(res);
	else
	    exit(err_flag ? 1 : 0);
    }
}

void
get_oid_done(ptr<gcp_sput_arg> td, str destpath,
	     svccb *sbp, ref<aclnt> gtc_c)
{
    if (!td || err_flag || td->last_index >= td->list.size()) {
	get_done(sbp);
	return;
    }

    gcp_put_arg arg = td->list[td->last_index];
    td->last_index++;

    //adjust the relative path
    arg.file.destpath = strbuf() << destpath << "/" << arg.file.destpath;

    cbv cb = wrap(get_oid_done, td, destpath, sbp, gtc_c);
    get_oid(arg, sbp, gtc_c, NULL, cb);
}

void
get_oid(gcp_put_arg arg, svccb *sbp, ref<aclnt> gtc_c, str ignore, cbv cb)
{
    switch (arg.type) {
    case OID_FILE:
    {
        int outfd;
        ptr<str> name = New refcounted<str>;
        
	if ((outfd = setup_file(arg.file, name)) >= 0) {
            ref<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;
            for (unsigned int i = 0;  i < arg.hints.size(); i++) {
                hints->push_back(arg.hints[i]);
            }
            dwarn(DEBUG_CLIENT) << "Final name is " << *name << "\n";
	    dwarn(DEBUG_CLIENT) << "Handling oid " << arg.oid.id << "\n";
            oid_hint h;
            generate_disk_hint(*name, arg.file.size, arg.file.modtime, &h, ignore);
            hints->push_back(h);
            
            td_pending++;
            
            str fn = strbuf() << *name << "." << getpid();
            vNew get_client(arg.oid, hints, outfd, fn, gtc_c,
                            wrap(finish, *name, cb));
	    return;
        }
        else {
            if (sbp) {
		gcp_put_res res (false);
		*res.errmsg = "could not open remote file...giving up";
                sbp->replyref(res);
	    }
	    err_flag = true;
	}
        break;
    }
    case OID_SYMLINK:
        setup_symlink(arg.file, arg.file.destpath, arg.file.filename);
	break;

    case OID_DIR:
	setup_path(arg.file, arg.file.destpath);
        break;

    default:
	err_flag = true;
	if (sbp) {
	    gcp_put_res res (false);
	    *res.errmsg = "unknown oid_type";
            sbp->replyref(res);
	}
	break;
    }
}

void
get_td_done(ptr<suio> buf, svccb *sbp, ref<aclnt> gtc_c,
	    str destpath, str err)
{
    if (err) {
	warnx << err << "\n";
	gcp_put_res res (false);
        *res.errmsg = err;
	if (sbp)
	    sbp->replyref(res);
        else
            exit(1);
	return;
    }

    dwarn(DEBUG_CLIENT) << "Got back td\n";
    rpc_bytes<> value;
    ptr<gcp_sput_arg> td = New refcounted<gcp_sput_arg>;
    
    value.setsize(buf->resid());
    buf->copyout(value.base(), value.size());
    if (!bytes2xdr(*td, value)) {
        err = "Could not unmarshal tree descriptor";
	warnx << err << "\n";
	gcp_put_res res (false);
        *res.errmsg = err;
	if (sbp)
	    sbp->replyref(res);
        else
            exit(1);
	return;
    }

    td->last_index = 0;
    for (unsigned int i = 0; i < td->list.size(); i++) {
	
	if (td_pending >= MAX_ALLOWED_FILES) break;

	gcp_put_arg arg = td->list[td->last_index];
	td->last_index++;

	//adjust the relative path
        arg.file.destpath = strbuf() << destpath << "/" << arg.file.destpath;
	
	cbv cb = wrap(get_oid_done, td, destpath, sbp, gtc_c);
	get_oid(arg, sbp, gtc_c, NULL, cb);
    }

    get_done(sbp);
}

void
get_td(gcp_put_arg arg, svccb *sbp, ref<aclnt> gtc_c)
{
    ref<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;
    for(unsigned int i = 0;  i < arg.hints.size(); i++) 
	hints->push_back(arg.hints[i]);

    str destpath = arg.file.destpath;
    struct stat sb;

    if (stat(destpath, &sb) < 0) {
	warnx << "Path does not exist " << destpath << "\n";
	if (mkdir(destpath, S_IRWXU) < 0)
	    fatal << "Cannot create " << destpath << "\n";
    }
    else if (!S_ISDIR(sb.st_mode))
	fatal << "Cannot create " << destpath << "\n";
    
    ptr<suio> buf = New refcounted<suio>;
    vNew get_client(arg.oid, hints, buf, gtc_c,
		    wrap(get_td_done, buf, sbp, gtc_c, destpath));
}

void
handle_get_arg(gcp_put_arg arg, ref<aclnt> gtc_c, svccb *sbp)
{
    gettimeofday(&start, NULL);
    if (arg.type == OID_TREE) 
	get_td(arg, sbp, gtc_c);
    else {
	ptr<gcp_sput_arg> td = NULL;
	cbv cb = wrap(get_oid_done, td, arg.file.destpath, sbp, gtc_c);
	get_oid(arg, sbp, gtc_c, "NONE", cb);
	get_done(sbp);
    }
}

void
get_dispatch(ref<aclnt> gtc_c, svccb *sbp)
{
    if (!sbp) {
	dwarn(DEBUG_CLIENT)("gc::dispatch(): client closed connection\n");
	/* XXX - need something to keep track of our state.  */
	exit(0);
    }

    td_pending = 0;
    err_flag = false;
    
    switch(sbp->proc()) {
    case GCP_PROC_PUT: {
	gcp_put_arg *arg = sbp->Xtmpl getarg<gcp_put_arg>();
	handle_get_arg(*arg, gtc_c, sbp);
	break;
    }
    default:
	sbp->reject(PROC_UNAVAIL);
	break;
    }
}
