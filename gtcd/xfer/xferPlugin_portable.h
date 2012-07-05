/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_PLUGIN_PORTABLE_H_
#define _XFER_PLUGIN_PORTABLE_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"

class xferPlugin_portable : public xferPlugin {

    xferPlugin *xp;
    timecb_t *ps_check;
    struct stat sb_cached;
    bool prev_cache;

    void check_device();
    void check_descs(desc_request *d);

    ihash<const dot_desc, desc_request, &desc_request::desc_id, &desc_request::hlink, dd_hash> 
    desc_request_cache;
    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
		   chunk_cb cb, CLOSURE);
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

    xferPlugin_portable(gtcd *m, xferPlugin *next_xp);
    ~xferPlugin_portable() { }
};

#endif /* _XFER_PLUGIN_PORTABLE_H_ */
