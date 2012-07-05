/*
 * Copyright (c) 2005-2008 Carnegie Mellon University and Intel Corporation.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtcd.h"
#include "serial.h"
#include "gtc_ext_interface.h"

static ptr<aclnt>  gtc_c;
static ptr<asrv>   gcp_s;
static dot_xferId         xferId;
static suio r_data;
static suio w_data;
static bool end;
static bool dot_timeout;
static bool read_data;
static int written_data_rpcs;
static bool conn_est;
static int dot_err;
static bool put_finalized;
static str oid_hints_armored;
static timecb_t *xfer_timeout;

#define MAX_ARMOR_LEN   ((size_t)900)

static void
log(const char *fmt, ...) {
    /* Ignore for now */
}

static void
get_data_cb(ref<gtc_get_data_res> res, clnt_stat err)
{
    // log("!! in recv data");
    const str fname = "gc::get_data(): GTC_PROC_GET_DATA";
    if (err) {
	warn << fname << " RPC failure: " << err << "\n";
	dot_err = -1;
	return;
    }
    if (!res->ok) {
	warn << fname << " returned:\n  `" << *res->errmsg << "'\n";
	dot_err = -1;
	return;
    }

    r_data.copy(res->resok->data.base(), res->resok->data.size());
    read_data = true;

    if (res->resok->end) {
	// warn << "gc::Finished GET.\n";
	end = true;
    }
}

static void
put_data_cb(ref<gtc_put_data_res> res, clnt_stat err)
{
    // log("!! in recv data");
    const str fname = "gc::put_data(): GTC_PROC_PUT_DATA";
    if (err) {
	warn << fname << " RPC failure: " << err << "\n";
	dot_err = -1;
	return;
    }
    if (!res->ok) {
	warn << fname << " returned:\n  `" << *res->errmsg << "'\n";
	dot_err = -1;
	return;
    }

    written_data_rpcs--;
}

static void
gtc_conn_start(ref<gtc_get_init_res> res, clnt_stat err)
{
    //log("!! in gtc_conn_start");
    const str fname = "gc::get_start(): GTC_PROC_GET_INIT";
    if (err) {
	warn << fname << " RPC failure: " << err << "\n";
	dot_err = -1;
	return;
    }
    if (!res->ok) {
	warn << fname << " returned:\n`" << *res->errmsg << "'\n";
	dot_err = -1;
	return;
    }

    xferId = *res->id;
    conn_est = true;
}

static void
gtc_get_data_init(str oid, ref<vec<oid_hint> > hints, int fd)
{

    // log("!! in gtc_connected");
    /* Setup GTC connection */
    ref<axprt> gtc_x = axprt_unix::alloc(fd, MAX_PKTSIZE);
    gtc_c = aclnt::alloc(gtc_x, gtc_program_1);

    gtc_get_init_arg fetch_arg;
    fetch_arg.oid.id = oid;
    fetch_arg.hints.set(hints->base(), hints->size());
    fetch_arg.xmode = XFER_SEQUENTIAL;
    ref<gtc_get_init_res> res = New refcounted<gtc_get_init_res>;

    //warn << "gc::gc asking for oid " << oid << "\n";
    gtc_c->call(GTC_PROC_GET_INIT, &fetch_arg, res,
		wrap(gtc_conn_start, res));
}

static void
gtc_put_data_init(int fd)
{

    // log("!! in gtc_put_data_init");
    /* Setup GTC connection */
    ref<axprt> gtc_x = axprt_unix::alloc(fd, MAX_PKTSIZE);
    gtc_c = aclnt::alloc(gtc_x, gtc_program_1);

    ref<gtc_put_init_res> res = New refcounted<gtc_put_init_res>;
    gtc_c->call(GTC_PROC_PUT_INIT, NULL, res,
		wrap(gtc_conn_start, res));
}

static void
timeout_fn()
{
    dot_timeout = true;
    xfer_timeout = NULL;
}

static int wait_for_conn_est() {
    while (!conn_est) {
	acheck();
	if (dot_err == -1)
	    return -1;
    }
    return 0;
}

extern "C" int
dot_write_fn(int fd, void *buf, unsigned int len, int timeout,
	     void *unused_context)
{
    // log("!! in dot_write_fn()");
    if (dot_err == -1 || wait_for_conn_est() == -1) {
	return -1;
    }

    if (written_data_rpcs != 0) {
	log("bug in gtc external interface");
	fatal << "bug in gtc_ext";
    }
    dot_timeout = false;

    // Install timeout and write data
    if (timeout > 0) {
	xfer_timeout = delaycb(timeout, 0, wrap(timeout_fn));
    }
    char *ptr = (char *) buf;
    size_t num_bytes = len;
    while (num_bytes > 0) {
	gtc_put_data_arg arg;
	ref<gtc_put_data_res> res = New refcounted<gtc_put_data_res>;
	arg.id = xferId;
	arg.offset = 0;
	arg.count = min(SEND_SIZE, num_bytes);
	arg.data.set(ptr, arg.count);
	ptr += arg.count;
	
	written_data_rpcs++;
	gtc_c->call(GTC_PROC_PUT_DATA, &arg, res, wrap(put_data_cb, res));
	if (num_bytes <= SEND_SIZE) {
	    break;
	}
	else {
	    num_bytes -= SEND_SIZE;
	}
    }

    while (!dot_timeout && written_data_rpcs > 0) {
	acheck();
	if (dot_err == -1) {
	    return -1;
	}
    }

    if (dot_timeout) {
	return -1;
    }
    else {
	if (xfer_timeout) {
	    timecb_remove(xfer_timeout);
	}
	return len;
    }

}

extern "C" int
dot_read_fn(int fd, void *buf, unsigned int len, int timeout,
	    void *unused_context)
{
    // log("!! in dot_read_fn");
    if (dot_err == -1) {
	return dot_err;
    }
    
    if (r_data.resid() >= len || end) {
	if (r_data.resid() == 0) {
	    return 0; // Signals EOF
	}
	int nb = min(r_data.resid(), (size_t) len);
	int ret = r_data.copyout(buf, nb);
	if (ret == -1) {
	    return -1;
	}
	else {
	    r_data.rembytes(nb);
	    return nb;
	}
    }

    read_data = false;
    dot_timeout = false;

    if (wait_for_conn_est() == -1) {
	return -1;
    }

    // Install timeout and read data
    if (timeout > 0) {
	xfer_timeout = delaycb(timeout, 0, wrap(timeout_fn));
    }
    gtc_get_data_arg darg = xferId;
    ref<gtc_get_data_res> dres = New refcounted<gtc_get_data_res>;
    gtc_c->call(GTC_PROC_GET_DATA, &darg, dres, wrap(get_data_cb, dres));

    while (!dot_timeout && !read_data) {
	acheck();
	if (dot_err == -1) {
	    return -1;
	}
    }

    if (dot_timeout) {
	return -1;
    }
    else {
	if (xfer_timeout) {
	    timecb_remove(xfer_timeout);
	}
	int nb = min(r_data.resid(), (size_t) len);
	int ret = r_data.copyout(buf, nb);
	if (ret == -1) {
	    return -1;
	}
	else {
	    r_data.rembytes(nb);
	    return nb;
	}
    }
}

int
dearmor_oid_hints(str asc, str *oid, ref<vec<oid_hint> > hints) {

    // First, remove newlines and carriage returns.
    // log("in dearmor == %s", asc.cstr());
    // -1 for the ".\r\n"
    int asclen = strlen(asc);
    char *pre_dea = (char *)malloc(asclen + 1);
    int pd_off = 0;
    
    for (int asc_off = 0; asc_off < asclen; asc_off++) {
	if (asc[asc_off] != '\r' && asc[asc_off] != '\n')
	    pre_dea[pd_off++] = asc[asc_off];
    }
    pre_dea[pd_off] = '\0';

    str dearm = dearmor64A(pre_dea);
    free(pre_dea);
    
    // Second, extract the oid and hints from it

    if (!dearm) {
	log("error in dearmor_oid_hints: null dearm!");
	return -1;
    }

    const char *old_ptr = dearm;
    const char *ptr = strstr(dearm, ":");
    if (!ptr) {
	return -1;
    }
    
    *oid = hex2bytes(str(dearm, ptr-old_ptr));

    oid_hint hint;
    str hostname;
    unsigned int port;
    
    while(ptr) {
	bzero (&hint, sizeof(hint));
	// Get host
	old_ptr = ptr;
	ptr = strstr(ptr+1, ":");
	if (ptr) {
	    hostname = str(old_ptr+1, ptr-(old_ptr+1));
	} 
	else 
	    break;

	if (*(ptr+1) != '\0') {
	    port = atoi(ptr+1);
	} else {
	    break;
	}
	ptr = strstr(ptr+1, ":");

	hint.name = strbuf() << "gtc://" << hostname << ":" << port;
	hints->push_back(hint);
    }
    return 0;
}

str
armor_oid_hints(gtc_put_commit_res *oid_hints)
{
    if (!oid_hints->ok) {
	return NULL;
    }

    strbuf complete;
    complete << oid_hints->resok->oid.id;
    for (unsigned int i = 0; i < oid_hints->resok->hints.size(); i++) {
	hint_res result;
	if (parse_hint(oid_hints->resok->hints[i].name, "gtc", &result) < 0)
	    fatal << "No hints in armor_oid_hints\n";
	complete << ":" << result.hint.hostname << ":" << result.hint.port;
    }

    str pre_armor = armor64A(complete);
    // warn << "pre_armor == '" << pre_armor << "' and length == "
    // << pre_armor.len() << "\n";

    strbuf armor;
    const char *ptr = pre_armor;
    // Now, lets break this up into MAX_ARMOR_LEN
    for (unsigned int i = 0; i < pre_armor.len(); i += MAX_ARMOR_LEN) {
	int len = min(MAX_ARMOR_LEN, pre_armor.len()-i);
	armor << str(ptr, len) << "\r\n";
	ptr += len;
    }
    //warn << "armor of oid+host+port " << complete <<" == \n\n" << armor << "\n\n";
    ref<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;
    return armor;
}

static int
int_gtc_connect()
{
    int sockfd;

    r_data.clear();
    w_data.clear();
    gtc_c = NULL;
    gcp_s = NULL;
    xferId = 0;
    dot_err = 0;
    read_data = false;
    written_data_rpcs = 0;
    dot_timeout = false;
    end = false;
    put_finalized = false;
    xfer_timeout = NULL;
    conn_est = false;

#if 0
    struct sockaddr_in servaddr;
    sockfd = socket(PF_INET, SOCK_STREAM, 0);
    bzero(&servaddr, sizeof(servaddr));
    servaddr.sin_family = AF_INET;
    servaddr.sin_port = htons(12000);
    inet_pton(AF_INET, "127.0.0.1", &servaddr.sin_addr);
    
    if (connect(sockfd, (sockaddr *) &servaddr, sizeof(servaddr)) == -1) {
	return -1;
    }
#else
    sockfd = unixsocket_connect(get_gtcd_socket());
    if (sockfd < 0) {
        //warn("%s: %m\n", gcp_connect_host.cstr());
        return -1;
    }
#endif

    return sockfd;
}

extern "C" int
dot_get_data(const char *armored_oid_hints)
{
    int sockfd;
    str oid;
    ref<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;

    if (dearmor_oid_hints(armored_oid_hints, &oid, hints) == -1) {
	return -1;
    }
    // log("about to connect to the gtc");

    if ((sockfd = int_gtc_connect()) == -1) {
	return -1;
    }

    gtc_get_data_init(oid, hints, sockfd);

    if (wait_for_conn_est() == -1) {
	return -1;
    }

    // sockfd is really a placeholder. It should not be used
    // directly by the caller.
    return sockfd;
}

extern "C" int
dot_put_data()
{
    int sockfd;
    if ((sockfd = int_gtc_connect()) == -1) {
	return -1;
    }

    gtc_put_data_init(sockfd);

    if (wait_for_conn_est() == -1) {
	log("conn_est failed");
	return -1;
    }
    return sockfd;
}

static void
put_end_cb(ref<gtc_put_commit_res> res, clnt_stat err)
{
    if (err) {
	log("put_end_cb(): GTC_PROC_PUT_COMMIT RPC failure: ");
	dot_err = -1;
	return;
    }
    
    if (!res->ok) {
	log("put_end(): GTC_PROC_PUT_COMMIT returned: %s", (*res->errmsg).cstr());
	dot_err = -1;
	return;
    }
    oid_hints_armored = armor_oid_hints(res);
    put_finalized = true;
}


extern "C" const char *
dot_put_data_commit()
{
    gtc_put_commit_arg arg;
    arg = xferId;
    // log("xferId in dot_put_data_commit() == %d", xferId);
    ref<gtc_put_commit_res> res = New refcounted<gtc_put_commit_res>;
    gtc_c->call(GTC_PROC_PUT_COMMIT, &arg, res,
		wrap(put_end_cb, res));

    while (!put_finalized) {
	acheck();
	if (dot_err == -1) {
	    log ("returning null");
	    return NULL;
	}
    }
    //log ("we have %s as the oid/hints", oid_hints_armored.cstr());
    return oid_hints_armored;
}
