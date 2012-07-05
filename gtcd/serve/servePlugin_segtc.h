/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _SERVE_SEGTC_H_
#define _SERVE_SEGTC_H_

#include "servePlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"

void convert_from_bitvec(ref<bmp_data> bmp_ret, unsigned int desc_count, ptr<bitvec> bmp);

struct stat_entry {
    const dot_desc cid;
    ihash_entry<stat_entry> hlink;
    int count;
    
    stat_entry (const dot_desc o);
    ~stat_entry();
};

class xferGtcConn; /* private helper for connections */
class servePlugin_segtc;

class xferGtcConn {
private:
    in_addr ipaddr;
    u_int16_t tcpport;
    ref<axprt> x;
    ref<asrv> c;

public:
    list_entry<xferGtcConn> link;
    double bandwidth;
    int getwritefd()
    { return x->getwritefd(); }
    str get_remote_ip()
    { 
      return strbuf("%s", inet_ntoa(ipaddr));
    }
    str get_remote_port()
    {
      return strbuf("%d", (int)tcpport);
    }
    
    xferGtcConn(int fd, const sockaddr_in &sin, servePlugin_segtc *parent);
    
    ~xferGtcConn() {
	dwarn(DEBUG_SERVE_GTC) << "Connection closed from " <<
	    inet_ntoa(ipaddr) << ":" << tcpport << "\n";
    }
};

class servePlugin_segtc : public servePlugin {
    friend class xferGtcConn;

    int sock;
    gtcd *m;
    vec<servePlugin*> seplugins;
    servePlugin* parent;
    list<xferGtcConn, &xferGtcConn::link> subconnlist;
    int serve_gtc_listen_port;

    /* flow control stuff */
    double idle_time_start;
    double idle_time;
    long prev_qlen;
    long prev_chunk_size;
    double chunk_enqueue_time;
    double start_time;
    void chunk_reply_followup(svccb *sbp);
    void bitmap_reply_followup(svccb *sbp);
    void chunk_write_cb(axprt_pipe *sbp);
    void bitmap_write_cb(axprt_pipe *sbp);
    
public:
    bool configure(str s, str pluginClass);
    void set_more_plugins(vec<servePlugin*> seplist) {
	if (seplist.size() > 0)
	    fatal << __PRETTY_FUNCTION__ << " next_sep is not NULL\n"
		  << "Make sure that this server plugin comes last\n";
    }
    void set_parent(servePlugin* prt) {
	parent = prt;
    }
    
    void serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb,
			   CLOSURE);
    void serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void serve_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    void get_default_hint(ref<vec<oid_hint> > hint);
    
    
    servePlugin_segtc(gtcd *_m, servePlugin* next_sep);
    ~servePlugin_segtc();
    
private:
    void remote_get_descriptors(svccb *sbp, CLOSURE);
    void remote_get_chunk(xferGtcConn *xgc, svccb *sbp, CLOSURE);
    void remote_get_bitmap(svccb *sbp, CLOSURE);
    
    void remote_get_chunk_cb(svccb *sbp, str errmsg, ptr<desc_result> dres);
    void remote_get_bitmap_cb(svccb *sbp, unsigned int offset, str s, 
			      ptr<bitvec> bmp);
    void accept_connection(int s);
    void dump_statcache();
    
protected:
    void dispatch(xferGtcConn *helper, svccb *sbp);
};


#endif /* _SERVE_SEGTC_H_ */
