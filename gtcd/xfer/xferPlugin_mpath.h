/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef XFER_MPATH_H
#define XFER_MPATH_H   

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"

#include "xferPlugin_portable.h"

// for the pending queue structure
struct descs {
    chunk_cb cb;
    dot_descriptor dd;
    const dot_desc desc_name;
    ref<vec<oid_hint> > oidhint;
    int i; // just for debugging purpose - to be removed
    tailq_entry<descs> link;
    ihash_entry<descs> hlink;

    // descs (chunk_cb cbk, dot_descriptor dot_desc, ref<vec<oid_hint> > hints);
    descs (chunk_cb cbk, dot_descriptor dot_desc, ref<vec<oid_hint> > hints, int i); //for debugging
    // descs ();
    ~descs ();
};


struct xp_state {

    ihash<const dot_desc, descs, &descs::desc_name, &descs::hlink, dd_hash> 
        desc_request_cache;
    unsigned int outstanding_requests;
    xp_state() {
	outstanding_requests = 0;
    }
};

// num of descs given by the mpath plugin queue
// to the xfer plugin at a given time
const unsigned int DESC_LIST_SIZE = 25;

class xferPlugin_mpath: public xferPlugin {

    storagePlugin *sp;
    ref<vec<dot_descriptor> > main_desc_list;

    tailq<descs, &descs::link> q_pending_desc;  // main pending queue
    // For cancelling stuff
    ihash<const dot_desc, descs, &descs::desc_name, &descs::hlink, dd_hash> 
        hash_pending_desc;
    
    unsigned int num_of_plugins;
    vec<xferPlugin*> xfplugins;
    xferPlugin_portable *pp;
    xp_state *wait_list_xp;

    void send_descs_to_xp();
    void get_chunks_done(unsigned int flag, chunk_cb cb, str s, 
			 ptr<desc_result> res);
    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb, CLOSURE);
    void handle_cancel(ptr<vec<nw_status> > status);
    
public:
    bool configure(str s, str pluginClass) { return true; }

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
    
    xferPlugin_mpath(gtcd *m, vec<xferPlugin*> xplist);
    ~xferPlugin_mpath();
};


#endif /* XFER_MPATH_H */
