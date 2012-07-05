/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

/*
 * Protocol Specification for Data-Oriented Transfer (DOT)
 */

typedef unsigned hyper dot_offset;
typedef unsigned int dot_count;

typedef opaque dot_oid<>;
typedef opaque dot_desc<>;

typedef opaque hint_hash[20];

struct xfer_hint {
    unsigned int protocol; /* Unused. Should be a URI */
    unsigned int priority; /* Unused */
    unsigned int weight; /* Unused */
    unsigned int port;
    string hostname<>;
};

struct xdisk_hint {
    string name<>;
    string target_dir<>;
    unsigned int size;
    int modtime;	
    string ignore_str<>; 
    string file_type<>;
    string ignore_path<>;
};

struct oid_hint {
    string name<>;
};

struct hint_vec {
    oid_hint hints<>;	
};

struct metadata_entry {
    string module<>;
    string key<>;
    string val<>;
};

struct metadata {
    metadata_entry list<>;
};

struct dot_descriptor {
    dot_desc id;
    unsigned int length;
    metadata md;
};

struct dot_oid_md {
    dot_oid id;
    metadata md;
};

enum xfer_mode {
    XFER_SEQUENTIAL,
    XFER_OUT_OF_ORDER
};

typedef unsigned int dot_xferId;
typedef unsigned int dot_sId;
typedef opaque dot_data<>;
typedef opaque dot_chunk<>;

typedef string dot_errmsg<>;

/* RPC arguments and results */

typedef metadata gtc_put_init_arg;

union gtc_put_init_res switch (bool ok) {
    case false:
        dot_errmsg errmsg;
    case true:
        dot_xferId id;
};

struct gtc_put_data_arg {
    dot_xferId id;
    dot_offset offset;
    dot_count count;
    dot_data data;
};

union gtc_put_data_res switch (bool ok) {
    case false:
        dot_errmsg errmsg;
    case true:
        void;
};

typedef dot_xferId gtc_put_commit_arg;

struct gtc_get_oid_res_ok {
    dot_oid_md oid;
    oid_hint hints<>;
};

union gtc_put_commit_res switch (bool ok) {
    case false:
        dot_errmsg errmsg;
    case true:
        gtc_get_oid_res_ok resok;
};

struct  gtc_get_init_arg {
    dot_oid_md oid;
    oid_hint hints<>;
    xfer_mode xmode;
};

typedef gtc_put_init_res gtc_get_init_res;

typedef dot_xferId gtc_get_data_arg;

struct gtc_get_data_res_ok {
    dot_offset offset;
    dot_count count;
    dot_data data;
    bool end;
};
union gtc_get_data_res switch (bool ok) {
    case false:
        dot_errmsg errmsg;
    case true:
        gtc_get_data_res_ok resok;
};


/* Procedures */

program GTC_PROGRAM {
    version GTC_VERSION {
        void
        GTC_PROC_NULL(void) = 0;

        gtc_put_init_res
        GTC_PROC_PUT_INIT(void) = 1;

	gtc_put_init_res
        GTC_PROC_PUT_PATH_INIT(gtc_put_init_arg) = 2;

        gtc_put_data_res
        GTC_PROC_PUT_DATA(gtc_put_data_arg) = 3;

        gtc_put_commit_res
        GTC_PROC_PUT_COMMIT(gtc_put_commit_arg) = 4;

        gtc_put_commit_res
        GTC_PROC_PUT_FD(void) = 5;

	gtc_put_commit_res
        GTC_PROC_PUT_PATH_FD(gtc_put_init_arg) = 6;

        gtc_get_init_res
        GTC_PROC_GET_INIT(gtc_get_init_arg) = 7;

        gtc_get_data_res
        GTC_PROC_GET_DATA(gtc_get_data_arg) = 8;
    } = 1;
} = 400000;

%#include "gtc_prot_strbuf.h"
