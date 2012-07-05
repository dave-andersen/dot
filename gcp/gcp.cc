#include "gcp.h"
#include "rxx.h"
#include "parseopt.h"
#include <getopt.h>

typedef enum { CLIENT_PUT, CLIENT_GET, CLIENT_PUT_ONLY, CLIENT_GET_ONLY } client_mode_t;

/* These are globals that several functions need */
static ptr<aclnt> gtc_c;
static ptr<aclnt> gcp_c;
static ptr<asrv> gcp_s;
static char **files;
static int nfiles;
static client_mode_t mode_xfer;
const char *remote_gcp_path = "gcp";
bool passfd = false;
// XXX: Hmm...this variable is reference in another file.
bool passdp = false;

struct timeval gcp_start;

static void
usage()
{
    fprintf(stderr,
	    "usage: gcp [OPTIONS] SRC [SRC ...] DEST\n"
            "       gcp [OPTIONS] --put-only SRC [SRC ...]\n"
            "       gcp [OPTIONS] --get-only dot://OID:hints:type xdisk-hint DEST\n"
	    "       gcp [OPTIONS] --get-only current.dot DEST\n");
}

static void
help()
{
    usage();
    fprintf(stderr,
            "\n"
	    "  -h                  help (this message)\n"
	    "  -f                  pass fds to the GTCD\n"
	    "  -d                  Pass data path to help gtc caching\n"
	    "  -p <gtcd socket>    use specified GTCD socket\n"
	    "  --receive           Operate in receive mode\n"
	    "  --put-only          Put only, do not ssh\n"
            "  --get-only          Get only, do not ssh\n"
            "  --remote-gcp-path   Path to gcp on remote machine\n"
            "  --debug <level>     Set debug level ('--debug list' for help)\n"
	    "\n"
	    "  DEST is [user@]host:/path/on/remote/end\n\n");
}

static void
run_gtcd()
{
    str gtcd_path = find_program("gtcd");
    if (!gtcd_path)
        fatal << "Could not locate gtcd\n";

    vec<char *> av;
    av.push_back(const_cast<char *>(gtcd_path.cstr()));
    av.push_back(NULL);

    pid_t pid = spawn(av[0], av.base());
    if (waitpid (pid, NULL, 0) < 0)
        fatal("Could not lauch a new gtcd: %m\n");
}

static void
rsh_reap(int kid)
{
    // XXX:
    fatal << "rsh_reap kid exited: " << kid << "\n";
}

static ref<aclnt>
run_rsh(char *desthost)
{
    vec<str> av;
    str gcp_rsh = getenv("GCP_RSH");
    if (!gcp_rsh) {
	gcp_rsh = DEFAULT_GCP_RSH;
    }

    str gcp_rsh_path = find_program(gcp_rsh);
    if (!gcp_rsh_path)
	fatal << "Could not locate ssh program " << gcp_rsh << "\n";
	
    av.push_back(gcp_rsh_path);
    av.push_back("-x");
    av.push_back("-a");
    av.push_back(desthost);
    dwarn(DEBUG_CLIENT) << "Running rsh to " << desthost << "\n";
    av.push_back(strbuf() << remote_gcp_path << " --receive --debug " << debug);

    ptr<axprt_unix> gcp_x (axprt_unix_aspawnv(av[0], av));
    if (!gcp_x) {
	fatal << "Could not start remote\n";
    }
    gcp_x->allow_recvfd = false;
    pid_t pid = axprt_unix_spawn_pid;
    dwarn(DEBUG_CLIENT) << "Started rsh pid " << pid << "\n";
    chldcb(pid, wrap(rsh_reap));
    return aclnt::alloc(gcp_x, gcp_program_1);
}

static void acceptconn() {    
    ref<axprt> gcp_x =
	axprt_pipe::alloc(STDIN_FILENO, STDOUT_FILENO, MAX_PKTSIZE);
    gcp_s = asrv::alloc(gcp_x, gcp_program_1, wrap(get_dispatch, gtc_c));
    
}

static void
client_put()
{
    if (nfiles < 2) {
        usage();
        exit(-1);
    }

    // the last element of files[] is the destination (host:path)
    nfiles--;

    if (nfiles < 1) {
        usage();
        exit(-1);
    }
    char *desthost = files[nfiles];
    char *destpath = strchr(desthost, ':');
    if (!destpath) {
        warnx << "Invalid destination host: " << desthost << "\n";
        usage();
        exit(-1);
    }
    *destpath++ = '\0';

    gcp_c = run_rsh(desthost);
    do_put(files, nfiles, gtc_c, gcp_c, destpath, passfd);
}

bool
create_arg_from_cmdline(ptr<gcp_put_arg> arg)
{
    static rxx getrx ("^dot://([0-9a-fA-F]{40}):(.+):(\\d+):(\\d)$");
    if (!getrx.match(files[0])) {
        warn("Could not parse DOT descriptor: %s\n", files[0]);
	return(false);
    }

    char *destpath = files[nfiles-1];
    
    int portnum, t;
    str oid = hex2bytes(getrx[1]);
    str hostname = getrx[2];
    convertint(getrx[3], &portnum);
    convertint(getrx[4], &t);

    assert(oid);
    arg->oid.id.set((char *)oid.cstr(), oid.len());

    if (portnum == 0)
        fatal("Port number cannot be zero: %d\n", portnum);
    oid_hint h;
    /* add default gtc plugin hint */
    h.name = strbuf() << "gtc://" << hostname << ":" << portnum;
    //arg.hints.set(hints->base(), hints->size());
    arg->hints.push_back(h);
    arg->type = (oid_type) (t);
    arg->file.destpath = strbuf() << destpath;

    if (t == OID_TREE) {
	dwarn(DEBUG_CLIENT) << "Getting a tree\n";
    	return true;
    }

    if (t != OID_FILE) {
	dwarn(DEBUG_CLIENT) << "Cannot get only a dir/symlink\n";
	return false;
    }
    
    dwarn(DEBUG_CLIENT) << "Getting a single object\n";
    struct stat sb;
    if (stat(files[1], &sb) < 0) {
	warn("Could not stat hint file (ignoring): %m: %s\n", files[1]);
	return false;
    }
    arg->file.size = sb.st_size;
    arg->file.uid = sb.st_uid;
    arg->file.gid = sb.st_gid;
    arg->file.mode = sb.st_mode;
    arg->file.modtime = sb.st_mtime;
	
    char *lastslash = strrchr(destpath, '/');
    if (!lastslash) {
	warn << "No file name\n";
	return false;
    }

    arg->file.filename = str(lastslash + 1);

    if (arg->file.filename.len() <= 0) {
	warn << "No file name\n";
	return false;
    }
    return true;
}

enum config_state_t { CONFIG_NONE, CONFIG_OID, CONFIG_HINT };

bool
create_arg_from_file(ptr<gcp_put_arg> arg)
{
    str file = files[0];

    if (!file) {
        file = CONFDIR "/current.dot";
        warn("No .dot file specified...using %s\n", file.cstr());
    }

    parseargs pa(file);
    int line;
    vec<str> av;
    enum config_state_t state = CONFIG_NONE;
    char *destpath = files[nfiles-1];
    str oid;

    while (pa.getline(&av, &line)) {
        if (!strcasecmp(av[0], "[oid]")) {
	    //get oid
            pa.getline(&av, &line);
	    oid = hex2bytes(av[0]);
	    assert(oid);
	    dot_oid oo;
	    oo.set((char *)oid.cstr(), oid.len());
	    arg->oid.id = oo;
	    dwarn(DEBUG_CLIENT) << "Parsed oid " << arg->oid.id << "\n";
	    state = CONFIG_OID;
	}
	else if (!strcasecmp(av[0], "[hints]")) {
            state = CONFIG_HINT;
        }
	else if (!strcasecmp(av[0], "[type]")) {
	    //get type
            pa.getline(&av, &line);
            int t; convertint(av[0], &t);
	    arg->type = (oid_type) (t);
	    dwarn(DEBUG_CLIENT) << "Parsed type " << arg->type << "\n";
	    if (arg->type == OID_TREE) {
		arg->file.destpath = strbuf() << destpath;
		break;
	    }
	    if (arg->type != OID_FILE) {
		dwarn(DEBUG_CLIENT) << "Cannot get only a dir/symlink\n";
		return false;
	    }
        }
	else if (!strcasecmp(av[0], "[stat]")) {
	    assert(arg->type != OID_TREE);
	    //get stat info
            pa.getline(&av, &line);
	    convertint(av[0], &(arg->file.size));
	    arg->file.filename = av[1];
	    arg->file.destpath = strbuf() << destpath;
	    convertint(av[3], &(arg->file.modtime));
	    convertint(av[4], &(arg->file.uid));
	    convertint(av[5], &(arg->file.gid));
	    convertint(av[6], &(arg->file.mode));
	    dwarn(DEBUG_CLIENT) << "Parsed file " << arg->file.filename
				<< " " << arg->file.destpath << "\n";
	}
	else if (state == CONFIG_OID) {
	    metadata_entry m;
	    m.module = av[0];
	    m.key = av[1];
	    m.val = av[2];
	    arg->oid.md.list.push_back(m);
	}
	else if (state == CONFIG_HINT) {
	    oid_hint h;
	    h.name = av[0];
	    arg->hints.push_back(h);
	    dwarn(DEBUG_CLIENT) << "Parsed hint " << h.name << "\n";
	}
	else {
	    warnx << "Problem parsing current.dot\n";
	    return false;
	}
    }

    dwarn(DEBUG_CLIENT) << debug_sep;
    return true;
}

static void
get_only()
{
    ptr<gcp_put_arg> arg = New refcounted<gcp_put_arg >;
    bool ok = false;

    if (nfiles == 3)
	ok = create_arg_from_cmdline(arg);
    else if (nfiles == 2)
	ok = create_arg_from_file(arg);

    if (!ok) {
	usage();
	exit(-1);
    }

    handle_get_arg(*arg, gtc_c, NULL);
}

static void
ctrlconnect()
{
    /* Setup control connection */
    switch (mode_xfer) {
    case CLIENT_PUT:
        client_put();
        break;
    case CLIENT_GET:
	acceptconn();
        break;
    case CLIENT_PUT_ONLY:
	do_put(files, nfiles, gtc_c, NULL, NULL, passfd);
        break;
    case CLIENT_GET_ONLY:
        get_only();
        break;
    default:
        usage();
	exit(-1);
    }
}

static void
gtc_connected(char **argv, int argc, int fd)
{
    /* Setup GTC connection */
    ref<axprt_unix> gtc_x = axprt_unix::alloc(fd, MAX_PKTSIZE);
    gtc_c = aclnt::alloc(gtc_x, gtc_program_1);

    files = argv;
    nfiles = argc;

    ctrlconnect();
}

int
main(int argc, char * argv[])
{
    str gtc_sock(get_gtcd_socket());
    setprogname(argv[0]);
    mode_xfer = CLIENT_PUT;

    int long_index;
    static struct option long_options[] = {
        {"remote-gcp-path",     1, 0, 0},
        {"get-only",            0, 0, 1},
        {"put-only",            0, 0, 2},
        {"debug",               1, 0, 3},
        {"receive",             0, 0, 4},
        {0, 0, 0, 0}
    };
    
    extern char *optarg;
    extern int optind;
    char ch;
    while ((ch = getopt_long(argc, argv, "hdfp:",
                             long_options, &long_index)) != -1)
	switch(ch) {
        case 0:
            //warn << long_options[long_index].name << " = = "
            //     << optarg << "\n";
            remote_gcp_path = optarg;
            break;
        case 1:
            mode_xfer = CLIENT_GET_ONLY;
            break;
	case 2:
	    mode_xfer = CLIENT_PUT_ONLY;
	    break;
        case 3:
            if (set_debug(optarg))
                exit(-1);
            break;
	case 4:
	    mode_xfer = CLIENT_GET;
	    break;
 	case 'p':
 	    gtc_sock = optarg;
 	    break;
	case 'f':
            passfd = true;
            break;
	case 'd':
            passdp = true;
            break; 
	case 'h':
	    help();
	    exit(0);
	default:
	    usage();
	    exit(-1);
	}

    argc -= optind;
    argv += optind;

    gettimeofday(&gcp_start, NULL);    

    int fd = unixsocket_connect(gtc_sock);
    if (fd < 0) {
        warn("Could not connect to GTCD: %s: %m\n", gtc_sock.cstr());
        warn("Trying to launch a new GTCD...\n");
        run_gtcd();
        fd = unixsocket_connect(gtc_sock);
        if (fd < 0)
            fatal("Could not connect to new gtcd: %m\n");
    }

    gtc_connected(&argv[0], argc, fd);

    amain();
}
