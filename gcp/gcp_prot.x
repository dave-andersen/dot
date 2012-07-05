/*
 * Protocol Specification for the DOT GCP program
 */

%#include "gtc_prot.h"

struct file_struct {
    hyper size;
    string filename<>;
    string destpath<>;
    int modtime;
    int uid;
    int gid;
    int mode;
};

enum oid_type {
    OID_TREE,
    OID_FILE,
    OID_DIR,
    OID_SYMLINK
};

struct gcp_put_arg {
    dot_oid_md oid;
    oid_hint hints<>;
    file_struct file;
    oid_type type;
};

struct gcp_sput_arg {
  gcp_put_arg list<>;
  unsigned int last_index;
};

union gcp_put_res switch (bool ok) {
    case false:
        dot_errmsg errmsg;
    case true:
	void;
};

/* RPC arguments and results */

program GCP_PROGRAM {
    version GCP_VERSION {
        void
        GCP_PROC_NULL(void) = 0;

	gcp_put_res
	GCP_PROC_PUT(gcp_put_arg) = 1;

    } = 1;
} = 400001;
