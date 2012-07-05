#ifndef _GCP_H_
#define _GCP_H_ 1

#include "async.h"
#include "arpc.h"
#include "tame.h"
#include "gcp_prot.h"
#include "gtc.h"
#include "util.h"
#include "bigint.h"
#include "debug.h"

#define DEFAULT_GCP_RSH "ssh"
#define MAX_ALLOWED_FILES 100
#define NUM_CONCURRENT_PUTS 1

typedef callback<void, str, ptr<gcp_put_arg > >::ref put_done_cb;

class gcp_put {
    str file;
    str destpath;
    ref<aclnt> gtc_c;
    put_done_cb cb;

    dot_xferId xferId;
    unsigned int pendingRPCs;

    int in_fd;

    struct stat statbuf;
    oid_type type;
    ptr<suio>  buf;
    
    void send_file(bool passfd);
    void gcp_send(str err, ptr<dot_oid_md> oid, ptr<vec<oid_hint> > hints);

public:
    gcp_put(str file, str dp, ref<aclnt> gtc, bool passfd,
            struct stat b, oid_type t, put_done_cb cb);
    gcp_put(ptr<suio> in, ref<aclnt> gtc,
	    oid_type t, put_done_cb cb);
    ~gcp_put();
};

extern void do_put(char **files, int numfiles, ref<aclnt> gtc_c, 
                   ptr<aclnt> gcp_c, char *destpath, bool passfd, CLOSURE);
extern void get_dispatch(ref<aclnt> gtc_c, svccb *sbp);
void get_td(gcp_put_arg arg, svccb *sbp, ref<aclnt> gtc_c);
void generate_disk_hint(str compname, unsigned int size,
			int modtime, oid_hint *h, str);
void handle_get_arg(gcp_put_arg arg, ref<aclnt> gtc_c, svccb *sbp);
void get_oid(gcp_put_arg, svccb *sbp, ref<aclnt> gtc_c, str ignore, cbv cb);
void get_oid_done(ptr<gcp_sput_arg> td, str destpath, svccb *sbp, ref<aclnt> gtc_c);
void get_done(svccb *sbp);
void dump_put_info(ptr<gcp_put_arg > arg);
int process_ent(const char *fpath, const struct stat *sb,
		int typeflag, struct FTW *ftwbuf, CLOSURE);
#endif /* _GCP_H_ */
