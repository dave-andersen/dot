/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _GTCD_H_
#define _GTCD_H_ 1

#include "async.h"
#include "arpc.h"
#include "qhash.h"
#include "list.h"
#include "gtc_prot.h"
#include "chunkerPlugin.h"
#include "xferPlugin.h"
#include "storagePlugin.h"
#include "servePlugin.h"
#include "util.h"
#include "tame.h"
#include "params.h"
#include "debug.h"
#include "connection_cache.h"

#include <openssl/evp.h>

#define GTCD "gtcd"

typedef callback<void, void>::ptr xfer_cb;
typedef callback<void, svccb *>::ptr asrv_cb;

#define SEND_SIZE      ((size_t)(MAX_PKTSIZE - 0x1000))

class dd_hash {
public:
  dd_hash() {}
  hash_t operator() (const dot_desc &d) const {
      return *((unsigned int *)d.base());
  }
};

class do_hash {
public:
  do_hash() {}
  hash_t operator() (const dot_oid &d) const {
    return *((unsigned int *)d.base());
  }
};

enum desc_status {
    DESC_UNKNOWN,
    DESC_ON_STORAGE,
    DESC_REQUESTED,
    DESC_DONE,
    DESC_ERROR
};

struct putfd_state {
    svccb *sbp;
    dot_sId sid;
    int fd;
    int pending;
};

class xferData {
public:
    // XXX - Should id and sid be merged?
    dot_xferId id;
    dot_sId sid;
    xfer_mode xmode;
    ptr<vec<dot_descriptor> > descs;
    ptr<vec<desc_status> > descs_status;
    qhash<const dot_desc, ptr<vec<unsigned int> >, dd_hash> descs_hash;
    unsigned int descs_count;
    unsigned int descs_xfered;
    unsigned int descs_start;
    unsigned int starting_offset;
    suio buf;
    int buf_offset; // buf data offset into original object
    bool fetching;
    // Did we want data but had to pause ?
    xfer_cb xcb;
    str err;
    ptr< vec<oid_hint> > hints;
    str desc_verify;
    
    xferData();
    bool descriptors_verify();
};

bool pressure_from_client();
bool pressure_from_network();
int parse_hint(str hint, str protocol, hint_res *res);
int make_hint(hint_res ip, str protocol, oid_hint *op);
int gtc_hint_to_name(str hint, str *name);
int return_metadata_index(str module, str key, metadata *md);
chunkerPlugin * instantiate_chunker_plugin(vec<str> p);

class storagePlugin;
class xferPlugin;
class chunkerPlugin;
class xferPlugin_portable;
class servePlugin;

/* 
 * The main gtcd.  Only one of these is created for an entire gtcd.
 * A "class client" is instantiated per unix domain socket connection.
 */

/* gtcd.T */
class gtcd
{
    qhash<dot_xferId, ref<xferData> > xferTable;
    dot_xferId xferCounter;

    void abort();

    void put_commit(svccb *sbp);
    void put_data(svccb *sbp);
    void put_init(svccb *sbp, bool init_with_path);
    void put_data_cb(svccb *sbp, str s);
    void put_sp_cb(str s);
    void put_commit_cb(svccb *sbp, str s, ptr<dot_oid_md> oid);
    void get_descriptors_cb(svccb *sbp, unsigned int offset, str s, 
			    ptr< vec<dot_descriptor> > descs);

    void put_fd(svccb *sbp, bool put_with_path);
    void put_fd_main(ref<putfd_state> st);
    void put_fd_read(ref<putfd_state> st);
    void put_fd_read_cb(ref<putfd_state> st, str s);
		      
    void transfer_data(svccb *sbp, dot_xferId xferId);
    void actual_transfer_data(svccb *sbp, dot_xferId xferId);
    void get_chunk_cb(svccb *sbp, dot_xferId xferId, unsigned int desc_no,
		      long offset, str s, ptr<desc_result> res);
    void get_init_cb(svccb *sbp, ref<dot_oid_md> doid, bool last_try, 
		     dot_xferId id,str s, ptr< vec<dot_descriptor> > descs,
                     bool end);
    void get_init(svccb *sbp, CLOSURE);
    void get_data(svccb *sbp);
    void get_descriptors(svccb *sbp);
    void fetch_data(dot_xferId xferId);
    void xp_fetch_data_cb(dot_xferId xferId, str s, ptr<desc_result> res);

public:
    storagePlugin *sp;
    xferPlugin *xp;
    xferPlugin_portable *pp;
    chunkerPlugin *cp;
    servePlugin *sep;
    connectionCache *connCache;
    rpcconnCache *rpcCache;

    void set_xferPlugin(xferPlugin *p) { xp = p; }
    void set_storagePlugin(storagePlugin *p) { sp = p; }
    void set_xferPlugin_portable(xferPlugin_portable *p) { pp = p; }
    void set_chunkerPlugin(chunkerPlugin *p) { cp = p; }
    void set_servePlugin(servePlugin *p) { sep = p; }

    void serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb,
			   CLOSURE);
    void serve_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    void serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void dispatch(svccb *sbp);

    gtcd() :
        xferCounter(1), sp(NULL), xp(NULL), pp(NULL), cp(NULL)
    { }
    // xferCounter = 0 is a special case

    ~gtcd();
};

class client
{
public:
    uid_t uid;
    gid_t gid;

    ref<axprt_unix> x;
    ref<asrv> c;
    
    list_entry<client> link;

    client(int fd, const sockaddr_un &sun, asrv_cb cb);
    ~client();
};

#endif /* _GTCD_H_ */
