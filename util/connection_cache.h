#include "async.h"
#include "arpc.h"
#include "tame.h"
#include "ihash.h"
#include "debug.h"
#include "params.h"
/*
 * connectionCache is like a tcpconnect that only establishes
 * a single connection to a host.  Multiple concurrent connect
 * requests get buffered and called back together when the connection
 * is finally established.
 */

struct pending_conn_entry;
struct conn_entry;
struct rconn_entry;

typedef callback<void, conn_entry *>::ref ce_cb;
typedef callback<void, rconn_entry *>::ref rce_cb;

enum stream_type {
    AXPRT_STREAM,
};

struct rpc_info {
    str ip;
    int port;
    stream_type stream;
    const rpc_program *program;
    bool canq;
};

struct pending_conn_entry {
    const str key;
    ihash_entry<pending_conn_entry> hlink;
    vec<ce_cb> pending_cbs;
    vec<bool> pending_qstate;
    pending_conn_entry (const str key);
};

struct wait_conn_entry {
    tailq_entry<wait_conn_entry> link;
    ce_cb cb;
    wait_conn_entry (ce_cb c) : cb(c) {}
};

struct conn_entry {
    const str key;
    int fd;
    int refcount;
    int qcount; //keeping track of bw consuming requests
    ptr<axprt> x; //stream object
    tailq<wait_conn_entry, &wait_conn_entry::link> wait_cb;
    ihash_entry<conn_entry> hlink;

    conn_entry (const str &key, int fd, stream_type t);
    ~conn_entry ();
    void release(bool canq);
};

struct rconn_entry {
    const str key;
    conn_entry *ce;
    int refcount;
    ptr<aclnt> clnt;
    struct timeval tv;

    ihash_entry<rconn_entry> hlink;
 
    rconn_entry (const str &key, conn_entry *c);
    ~rconn_entry ();
    void release(bool canq);
};

class connectionCache {
public:
    connectionCache();
    ~connectionCache();

    void connect(str ip, int port, stream_type t, bool canq, ce_cb cb);
    bool pressure_from_network();
    void int_reap_conn_entries(conn_entry *conn);
 
private:
    void connected(str ip, int port, stream_type t, int fd);
         
    ihash<const str, pending_conn_entry, &pending_conn_entry::key,
	  &pending_conn_entry::hlink> pendingConnCache;
    
    ihash<const str, conn_entry, &conn_entry::key, &conn_entry::hlink> 
    connCache;
};

class rpcconnCache {
public:
    rpcconnCache(connectionCache *);
    ~rpcconnCache();
    
    void connect(rpc_info rpc, rce_cb cb, CLOSURE);
private:
    void int_reap_conn_entries(rconn_entry *conn);
    void reap_conn_entries();
    
    connectionCache *cache;
    timecb_t *tcb;
    ihash<const str, rconn_entry, &rconn_entry::key, &rconn_entry::hlink> 
    connCache;
};
    
