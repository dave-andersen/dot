#include "gcp.h"
#include "ftw.h"
#include <libgen.h>

static struct timeval tv_hash_start;
static struct timeval tv_data_start; // This is also tv_hash_end
static struct timeval tv_data_end;
static int td_pending;
static bool err_flag;
static ptr<vec<cbv> > cbq;
static callback<void>::ptr final_cb;

extern bool passdp;

static ptr<gcp_sput_arg> td;
static ptr<aclnt> gtc_c;
static ptr<aclnt> gcp_c;
static char *destpath;
static bool passfd;

gcp_put::gcp_put(str file, str dp, ref<aclnt> gtc,
                 bool passfd, struct stat b, oid_type t,
		 put_done_cb cb)
    : file(file), destpath(dp), gtc_c(gtc),
      cb(cb), statbuf(b), type(t)
{
    pendingRPCs = 0;

    send_file(passfd);
}

gcp_put::gcp_put(ptr<suio> in, ref<aclnt> gtc,
                 oid_type t, put_done_cb cb)
    : gtc_c(gtc), cb(cb), type(t), buf(in)
{
    pendingRPCs = 0;

    vNew put_client_suio(in, gtc_c, wrap(this, &gcp_put::gcp_send));
}

void
gcp_put::send_file(bool passfd)
{
    gettimeofday(&tv_hash_start, NULL);

    if (file == "-")
	in_fd = STDIN_FILENO;
    else
	in_fd = open(file, O_RDONLY);
    
    if (in_fd == -1) {
	strbuf sb;
	sb.fmt("Could not open input file: %s: %m", file.cstr());
	(*cb) (sb, NULL);
        delete this;
	return;
    }

    dwarn(DEBUG_CLIENT) << "Sending file " << file << " with fd "
			<< in_fd << "\n";

    put_client_cb cb = wrap(this, &gcp_put::gcp_send);
    
    if (passfd && passdp) /* Pass both */
	vNew put_client_fd(in_fd, file, gtc_c, cb);
    else if (passfd && !passdp) /* FD only */
	vNew put_client_fd(in_fd, gtc_c, cb);
    else if (!passfd && passdp) /* DP only */
	vNew put_client(in_fd, file, gtc_c, cb);
    else if (!passfd && !passdp) /* Neither */
	vNew put_client(in_fd, gtc_c, cb);
}

void 
gcp_put::gcp_send(str err, ptr<dot_oid_md> oid, ptr<vec<oid_hint> > hints)
{
    if (err) {
        strbuf sb;
	sb << "gcp_put:  Putting to the GTC failed! " << err << "\n";
	(*cb) (err, NULL);
        delete this;
	return;
    }
    
    ptr<gcp_put_arg> arg = New refcounted<gcp_put_arg>;
    arg->oid = *oid;
    arg->hints.set(hints->base(), hints->size());
    arg->type = type;
    if (type == OID_FILE) {
	//dwarn(DEBUG_CLIENT) << "Just put " << file << " with oid " << oid->id <<"\n";
	arg->file.size = statbuf.st_size;
	arg->file.uid = statbuf.st_uid;
	arg->file.gid = statbuf.st_gid;
	arg->file.mode = statbuf.st_mode;
	arg->file.modtime = statbuf.st_mtime;

	char *tmp = strdup(file); /* basename broken prototype coping */
	arg->file.filename = str(basename(tmp));
	free(tmp);
	
	arg->file.destpath = destpath;
    }
    else
	dwarn(DEBUG_CLIENT) << "Just put TD with oid " << oid->id <<"\n";

    //dwarn(DEBUG_CLIENT) << "-------------------------------------------------\n";
    (*cb) (NULL, arg);
    delete this;
}

gcp_put::~gcp_put()
{
    dwarn(DEBUG_CLIENT) << "Destroying gcp_put of " << file << "\n";
}

extern struct timeval gcp_start;
void
put_oid_done(ref<gcp_put_res> res, clnt_stat err)
{
    if (err) {
        warn << "Could not send put command to receiver: " << err << "\n";
	exit(1);
    }
    if (!res->ok) {
	warn << "put_done returned " << *res->errmsg << "\n";
        exit(1);
    }
    
    gettimeofday(&tv_data_end, NULL);
    
    // XXX - Why does warn not support floats??
    printf ("Put succeeded - Hash Time: %.2f, Data Time %.2f, Total Running Time %.2f \n ",
	    timeval_diff(&tv_hash_start, &tv_data_start),
	    timeval_diff(&tv_data_start, &tv_data_end),
	    timeval_diff(&gcp_start, &tv_data_end));

    exit(0);
}

void
dump_put_info(ptr<gcp_put_arg > arg)
{
    FILE *fp = fopen("current.dot", "w");
    if (!fp)
	fatal << "Cannot open op file current.dot\n";

    str t = strbuf() << arg->oid.id;
    fprintf(fp, "[oid]\n%s\n", t.cstr());
    for (unsigned int i = 0; i < arg->oid.md.list.size(); i++) {
	t = strbuf() << arg->oid.md.list[i].module << " " <<
	    arg->oid.md.list[i].key << " " << arg->oid.md.list[i].val;
	fprintf(fp, "%s\n", t.cstr());
    }

    fprintf(fp, "[hints]\n");
    for (unsigned int i = 0; i < arg->hints.size(); i++) {
	t = arg->hints[i].name;
	fprintf(fp, "%s\n", t.cstr());
    }

    fprintf(fp, "[type]\n");
    fprintf(fp, "%d\n", arg->type);
    
    fprintf(fp, "[stat]\n");
    t = strbuf() << arg->file.size << " " << arg->file.filename << " "
		 << arg->file.destpath << " " << arg->file.modtime << " "
		 << arg->file.uid << " " << arg->file.gid << " "
		 << arg->file.mode;
    fprintf(fp, "%s\n", t.cstr());

    fclose(fp);
}

void
put_oid(ptr<aclnt> gcp_c, char *destpath,
	str err, ptr<gcp_put_arg > arg)
{
    if (err) {
	warnx << err << "\n";
        return;
    }

    if (gcp_c == NULL) {
	str foo = strbuf() << arg->oid.id;
	printf("PUT_OID:%s\n", foo.cstr());
	dump_put_info(arg);
	exit(0);
    }

    //put in the destination directory
    arg->file.destpath = str(destpath);

    //dont care if i include file name here for single oid transfers
    //dwarn(DEBUG_CLIENT) << "Hence my destination is " << arg->file.destpath << "\n";

    ref<gcp_put_res> cli_res = New refcounted<gcp_put_res>;
    gettimeofday(&tv_data_start, NULL);
    gcp_c->call(GCP_PROC_PUT, arg, cli_res,
                wrap(put_oid_done, cli_res));
}


static void
do_putinto_td(str err, ptr<gcp_put_arg> arg)
{
    td_pending--;
    
    if (err) {
        warnx << err << "\n";
	err_flag = true;
        return;
    }

    td->list.push_back(*arg);

    if (td_pending < NUM_CONCURRENT_PUTS) {
	if (cbq->size()) {
	    cbv cb = cbq->pop_front();
	    (*cb)();
	}
	else if (td_pending <= 0 && final_cb)
	    (*final_cb)();
    }
}

static str
get_rel_path(const char *fpath, int level)
{
    const char *r = fpath + strlen(fpath);
    str rel_path;

    level++;
    if (level == 1)
        rel_path = "./";
    else {
        while (r >= fpath && level > 0) {
            if (*r == '/')
                level--;
            r--;
        }
        const char *p = strrchr(++r, '/');
        assert(p);
        rel_path = str(r, p-r+1);
    }

    dwarn(DEBUG_CLIENT) << "Relative path " << rel_path << "\n";
    return rel_path;
}

static str
xreadlink(const char *path)
{
    char buf[PATH_MAX];
    int n = readlink(path, buf, sizeof(buf));
    if (n < 0) {
        warn("readlink failed: %m: %s\n", path);
        return "";
    }
    return str(buf, n);
}

tamed int
process_ent(const char *fpath, const struct stat *sb,
            int typeflag, struct FTW *ftwbuf)
{
    tvars {
        str rel_path;
        str cname;
        struct stat sb_cpy;
    }

    dwarn(DEBUG_CLIENT)
        << "fpath = " << fpath
        << "\ntypeflag = " << typeflag
        << "\nbase_path = " << ftwbuf->base
        << "\nfts_level = " << ftwbuf->level
        << "\n";
    
    switch (typeflag) {
    case FTW_SL:
    case FTW_D:
    {
        dwarn(DEBUG_CLIENT) << ((typeflag == FTW_D) ? "DIRECTORY" : "SYMLINK") << "\n";

        rel_path = get_rel_path(fpath, ftwbuf->level);
        td_pending++;
	    
        ptr<gcp_put_arg> arg = New refcounted<gcp_put_arg>;
        arg->file.size = sb->st_size;
        arg->file.uid = sb->st_uid;
        arg->file.gid = sb->st_gid;
        arg->file.mode = sb->st_mode;
        arg->file.modtime = sb->st_mtime;
        arg->file.destpath = strbuf() << rel_path << (fpath + ftwbuf->base);
        if (typeflag == FTW_SL) {
            arg->type = OID_SYMLINK;
            arg->file.filename = xreadlink(fpath);
        }
        else {
            arg->type = OID_DIR;
            arg->file.filename = "";
        }
        do_putinto_td(NULL, arg);
        break;
    }
    case FTW_F:
    {
        dwarn(DEBUG_CLIENT) << "FILE\n";

        rel_path = get_rel_path(fpath, ftwbuf->level);
	cname = strbuf() << fpath;
	sb_cpy = *sb;

	while (td_pending >= NUM_CONCURRENT_PUTS) {
	    dwarn(DEBUG_CLIENT) << "Pending loop " << cname << "\n";
            twait { cbq->push_back(mkevent()); }
	}
	
	dwarn(DEBUG_CLIENT) << "Going to put " << rel_path
			    << "/" << cname << "\n";
        td_pending++;
                
        vNew gcp_put(cname, rel_path, gtc_c, passfd, sb_cpy, OID_FILE,
                     wrap(do_putinto_td));
        break;
    }
    default:
        warnx("process_ent: unknown typeflag: %d\n", typeflag);
    }
    
    DEFAULT_RETURN { return 0; }
}

int
wrap_process_ent(const char *fpath, const struct stat *sb,
            int typeflag, struct FTW *ftwbuf)
{
    return(process_ent(fpath, sb, typeflag, ftwbuf));
}

tamed void
do_put(char **files, int numfiles, ref<aclnt> _gtc_c, ptr<aclnt> _gcp_c,
       char *_destpath, bool _passfd)
{
    td_pending = 0;
    err_flag = false;

    gtc_c = _gtc_c;
    gcp_c = _gcp_c;
    destpath = _destpath;
    passfd = _passfd;
    
    if (numfiles <= 0)
        exit(0);

    td = New refcounted<gcp_sput_arg>;
    cbq = New refcounted<vec<cbv> >;
    final_cb = NULL;

    while (numfiles-- > 0)
        nftw(*files++, wrap_process_ent, 16, FTW_PHYS);

    while (td_pending > 0 || cbq->size() > 0) {
	dwarn(DEBUG_CLIENT) << "Bigger loop\n";
        twait { final_cb =  mkevent (); }
    }

    warnx << "Done putting " << td->list.size() << " files\n";
    
    if (err_flag) {
	warnx << "Error in one of the files\n";
	exit(1);
    }
    
    if (td->list.size() == 0) {
	warnx << "No valid files found\n";
	exit(1);
    }
    else if (td->list.size() == 1 && td->list[0].type == OID_FILE) {
	dwarn(DEBUG_CLIENT) << "Sending directly without TD\n";
	//If only one file, send it directly;  don't use a TD
	ptr<gcp_put_arg> arg = New refcounted<gcp_put_arg>;
	*arg = td->list[0];
	put_oid(gcp_c, destpath, NULL, arg);
    }
    else {
	rpc_bytes<> value;
	ptr<suio> in = New refcounted<suio>;
	if (!xdr2bytes(value, *td))
	    fatal << "Could not marshal tree descriptor\n";
	in->copy(value.base(), value.size());
	dwarn(DEBUG_CLIENT) << "Putting TD of size "
			    << value.size() << "\n";
	vNew gcp_put(in, gtc_c, OID_TREE,
		     wrap(put_oid, gcp_c, destpath));
    }
}
