/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_XGTC_H_
#define _XFER_XGTC_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"
#include "se_transfer.h"

bool convert_to_bitvec(ref<bmp_data> bmp, int desc_count, ptr<bitvec> bmp_ret);

/* flow control state - maintained per-sender */
struct desc_entry {
    const dot_desc desc_id;
    dot_descriptor d;
    chunk_cb cb;

    ihash_entry<desc_entry> hlink;
    tailq_entry<desc_entry> qlink;
    
    desc_entry(dot_descriptor d, chunk_cb cb): desc_id(d.id), d(d), cb(cb) { }
    ~desc_entry() { }
};

struct flow_ctrl_entry {
    const str hint_str;
    
    oid_hint hint;

    ihash<const dot_desc, desc_entry, &desc_entry::desc_id, &desc_entry::hlink> pending_hash;
    tailq<desc_entry, &desc_entry::qlink> pending_queue;

    ihash<const dot_desc, desc_entry, &desc_entry::desc_id, &desc_entry::hlink> issue_hash;
    tailq<desc_entry, &desc_entry::qlink> issue_queue;

    unsigned long long bytes_desired;
    unsigned long long bytes_outstanding;
    double last_qlen_uptime;
    double start_time;
    double rtt;
    vec<double> chunk_reqtime;

    ihash_entry<flow_ctrl_entry> hlink;

    flow_ctrl_entry(oid_hint hint, dot_descriptor d, chunk_cb cb);
    ~flow_ctrl_entry();
};

class xferPlugin_xgtc : public xferPlugin {
    
    gtcd *m;
    
public:
    bool configure(str s, str pluginClass);

    /* Calls from the GTC */
    void xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			 descriptors_cb cb, CLOSURE);
    void xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs);
    void xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
		    bitmap_cb cb, CLOSURE);
    void xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb, CLOSURE);
    void cancel_chunk(ref<dot_descriptor> d, cancel_cb cb, CLOSURE);
    void cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb, CLOSURE);

    void update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints);
    
    long long get_qspace(str hname);
    
    xferPlugin_xgtc(gtcd *_m, xferPlugin *next_xp);
    ~xferPlugin_xgtc();

private:
    void get_chunk(ref<dot_descriptor> d, bool max_request, double rtt, ref<vec<oid_hint> > hints,
                   callback<void, str, ptr<desc_result> >::ptr cb, CLOSURE);
    void get_descriptors_int(ref<dot_oid_md> oid, int offset, descriptors_cb cb,
			     rconn_entry *conn);
    void get_desc_internal_cb(descriptors_cb cb, ref<dot_oid_md> oid,
                              rconn_entry *conn,
			      ref<xfergtc_get_descriptors_res> res, 
                              clnt_stat err);

    void get_chunk_int(ref<dot_descriptor> d, bool max_request, double rtt, chunk_cb cb, size_t offset,
                       ref<suio> data, rconn_entry *conn, oid_hint hint, CLOSURE);
    void get_bitmap_int(ref<dot_oid_md> oid, int offset, 
			bitmap_cb cb, rconn_entry *conn,
			ref<bitvec> bmp);
    void get_bitmap_internal_cb(bitmap_cb cb, ref<dot_oid_md> oid,
				rconn_entry *conn,
				ref<xfergtc_get_bitmap_res> res, 
				ref<bitvec> bmp, clnt_stat err);
    bool cancel_chunk_int(dot_desc id);

    /* flow control stuff... */
    long bytes_rcvd;
    void get_more_chunks_int(oid_hint hint, bool bw_token, double rtt);
    bool get_more_chunks_int(oid_hint hint, ref<dot_descriptor> d, size_t offset,
			     bool bw_token);

    void dump_xput();
    ihash<const str, flow_ctrl_entry, &flow_ctrl_entry::hint_str, &flow_ctrl_entry::hlink> flow_control_cache;

};


#endif /* _XFER_XGTC_H_ */
