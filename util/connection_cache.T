#include "connection_cache.h"

/* XXX todo:
 * - Make it so we can use this class for either fds or to attache
 * RPC clients to it.
 *
 * Parameterzie for # of connections, timeout, etc.
 *
 * Figure out a way to track that we're using a connection
 * so we don't time it out.
 * 
 * change xferplugin gtc to use it
 *
 * Find other occurrences of this behavior (dht.T needs it, for instance, but
 * doesn't currently have it) and use there.  Others?
 *
 * Write some testcases.
 */

connectionCache::connectionCache()
{
}

connectionCache::~connectionCache()
{
}

void
connectionCache::connected(str ip, int port, stream_type t, int fd)
{
    strbuf key;
    key << ip << ":" << port << ":" << t;

    pending_conn_entry *pce = pendingConnCache[key];
    if (!pce) {
	warn << "Unable to find entry in pending Conn Cache for " << key << "\n";
	return;
    }

    if (fd == -1) {
	for (unsigned int i = 0; i < pce->pending_cbs.size(); i++) {
            (*pce->pending_cbs[i])(NULL);
        }
        pendingConnCache.remove(pce);
        delete pce;
        return;
    }
    
    conn_entry *ce = New conn_entry(key, fd, t);
    connCache.insert(ce);
    
    for (unsigned int i = 0; i < pce->pending_cbs.size(); i++)
	connect(ip, port, t, pce->pending_qstate[i],
		pce->pending_cbs[i]);
    
    pendingConnCache.remove(pce);
    delete pce;
}

void
connectionCache::connect(str ip, int port, stream_type t,
			 bool canq, ce_cb cb)
{
    strbuf key;
    key << ip << ":" << port << ":" << t;
    conn_entry *conn = connCache[key];

    if (conn) {
	if (conn->qcount < MAX_CONNS_IN_FLIGHT || !canq) {
	    if (canq) conn->qcount++;
	    dwarn(DEBUG_CONNCACHE) << "connectionCache::Just connected to "
				   << key << " " << conn->qcount << "\n";
	    (*cb)(conn);
	    return;
	}

	dwarn(DEBUG_CONNCACHE) << "connectionCache::Queuing to "
			       << key << "\n";
	conn->wait_cb.insert_tail(New wait_conn_entry(cb));
	return;
    }

    pending_conn_entry *pce = pendingConnCache[key];
    if (pce) {
	dwarn(DEBUG_CONNCACHE) << "connectionCache::queuing in pending connection "
			       << key << "\n";
	pce->pending_cbs.push_back(cb);
	pce->pending_qstate.push_back(canq);
	return;	
    }
    dwarn(DEBUG_CONNCACHE) << "connectionCache::making new connection "
			   << key << "\n";
    pce = New pending_conn_entry(key);
    pendingConnCache.insert(pce);
    pce->pending_cbs.push_back(cb);
    pce->pending_qstate.push_back(canq);
    tcpconnect(ip, port, wrap(this, &connectionCache::connected, ip, port, t));
}

void 
connectionCache::int_reap_conn_entries(conn_entry *conn)
{
    conn->refcount--;
    if (conn->refcount <= 0) {
        dwarn(DEBUG_CONNCACHE) << "about to delete stale fd connection to " << conn->key << "\n" ;
	connCache.remove(conn);
        delete conn;
    }
}

bool
connectionCache::pressure_from_network()
{
    if (!pressure)
	return false;
    
    int fd = -1;
    conn_entry *cne = connCache.first();
    while (cne != NULL) {
	fd = cne->fd;
	
	if (cne->x->pending_pkts()) {
	    DPRINTF(DEBUG_OPT&DEBUG_L1, "pressure_from_network:: Buffer pressure\n");
	    return true;
	}
	
	struct timeval ztv = { 0, 0 };
	if (fdwait(fd, fd, true, false, &ztv) > 0) {
	    DPRINTF(DEBUG_OPT&DEBUG_L1, "pressure_from_network:: %s | %d is set\n",
		    cne->key.cstr(), fd);
	    return true;
	}

	cne = connCache.next(cne);
    } 
    
    DPRINTF(DEBUG_OPT&DEBUG_L1, "pressure_from_network:: NONE\n");
    return(false);
}

pending_conn_entry::pending_conn_entry(const str key)
    : key(key)
{
}
    
conn_entry::conn_entry(const str &k, int fd, stream_type t)
    : key(k), fd(fd), refcount(0), qcount(0)
{
    dwarn(DEBUG_CONNCACHE) << "creating conn_entry for " << k
			   << " to " << fd << "\n";
    tcp_nodelay(fd);
    if (t == AXPRT_STREAM)
	x = (axprt_stream::alloc(fd, MAX_PKTSIZE));
    else
	fatal << "Unknown stream type\n";
}

conn_entry::~conn_entry()
{
    for (wait_conn_entry *i = wait_cb.first; i; i = wait_cb.next(i)) {
	(*(i->cb))(NULL);
    }
}

void
conn_entry::release(bool canq)
{
    if (canq) {
	qcount--;
	wait_conn_entry *n = wait_cb.first;
	if (n) {
	    ce_cb w = n->cb;
	    wait_cb.remove(n);
	    qcount++;
	    dwarn(DEBUG_CONNCACHE) << "release::Just connected to "
				   << key << "\n";
	    (*w)(this);
	}
    }
}

/*
  rpcconnCache
*/

rpcconnCache::rpcconnCache(connectionCache *c)
    : cache(c), tcb(NULL)
{
    if (!tcb) {
	dwarn(DEBUG_CONNCACHE) << "RPCCache: Setting timer\n";
	delaycb(CONN_ENTRY_IDLE_SEC/10, CONN_ENTRY_IDLE_NSEC, 
		wrap(this, &rpcconnCache::reap_conn_entries));
    }
}

rpcconnCache::~rpcconnCache()
{
}

tamed void
rpcconnCache::connect(rpc_info r, rce_cb cb)
{
    tvars {
	strbuf key;
	conn_entry *c;
	rconn_entry *conn;
    }

    dwarn(DEBUG_CONNCACHE) << "rpcconnCache::connect received\n";
    twait {
	cache->connect(r.ip, r.port, r.stream, r.canq, mkevent(c));
    }
    
    if (!c) {
	(*cb)(NULL);
	return;
    }

    key << r.ip << ":" << r.port << ":" << r.stream << ":" << r.program->name;
    conn = connCache[key];

    if (conn)
	assert(conn->ce == c);
    
    if (!conn) {
	assert(c);
	conn = New rconn_entry(key, c);
	conn->clnt = (aclnt::alloc(conn->ce->x, *(r.program)));
	connCache.insert(conn);
    }

    gettimeofday(&conn->tv, NULL);
    conn->refcount++;
    
    (*cb)(conn);
}

void 
rpcconnCache::int_reap_conn_entries(rconn_entry *conn)
{
    struct timeval tv;
    gettimeofday(&tv, NULL);

    dwarn(DEBUG_CONNCACHE) << "Came to reap " << conn->key << "\n";
    if (conn->refcount <= 0 &&
        tv.tv_sec - conn->tv.tv_sec > CONN_ENTRY_IDLE_SEC) {
        dwarn(DEBUG_CONNCACHE) << "about to delete stale connection to " << conn->key << "\n" ;
	connCache.remove(conn);
	cache->int_reap_conn_entries(conn->ce);
        delete conn;
    }
}

void 
rpcconnCache::reap_conn_entries()
{
    //dwarn(DEBUG_CONNCACHE) << "RPCCache: Resetting timer\n";
    connCache.traverse(wrap(this, &rpcconnCache::int_reap_conn_entries));
    tcb = delaycb(CONN_ENTRY_IDLE_SEC/10, CONN_ENTRY_IDLE_NSEC, 
                  wrap(this, &rpcconnCache::reap_conn_entries));
}

rconn_entry::rconn_entry(const str &k, conn_entry *c)
    : key(k), ce(c), refcount(0)
{
    dwarn(DEBUG_CONNCACHE) << "creating rconn_entry for " << k << "\n";
    ce->refcount++;
}

rconn_entry::~rconn_entry()
{
    dwarn(DEBUG_CONNCACHE) << "deleting rconn_entry for " << key << "\n";
}

void
rconn_entry::release(bool canq)
{
    dwarn(DEBUG_CONNCACHE) << "releasing rconn_entry " << key
			   << " cur ref " << refcount << "\n";
    gettimeofday(&tv, NULL);
    refcount--;
    ce->release(canq);
}
