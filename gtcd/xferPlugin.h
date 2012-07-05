/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _PLUGIN_XFER_H_
#define _PLUGIN_XFER_H_

#include "plugin.h"
#include "gtc_prot.h"
#include "amisc.h"
#include "async.h"
#include "arpc.h"
#include "storagePlugin.h"

typedef ptr<vec<oid_hint > > hv;
typedef vec<hv > hv_vec;

enum nw_status { CANCELLED, NOT_CANCELLED };
typedef callback<void, ptr< vec<nw_status> > >::ref cancel_cb;

class xferPlugin : virtual public Plugin {

public:
    virtual bool configure(str s, str pluginClass) = 0;

    /* Calls from the GTC */
    virtual void xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
				 descriptors_cb cb, CLOSURE) = 0;
    virtual void xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs) = 0;
    virtual void xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			    bitmap_cb cb, CLOSURE) = 0;
    virtual void xp_get_chunks(ref< vec<dot_descriptor> > dv, 
			       ref<hv_vec > hints, chunk_cb cb, CLOSURE) = 0;
    virtual void cancel_chunk(ref<dot_descriptor> d, cancel_cb cb, CLOSURE) = 0;
    virtual void cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb, CLOSURE) = 0;
    virtual void update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints) = 0;
    virtual void set_more_plugins(vec<xferPlugin*> xplist) { };
    virtual void set_parent(xferPlugin* prt) { };
    virtual void set_next_plugin(xferPlugin* next_plg) { };

    virtual void xp_get_ops(str, dot_descriptor dv) { };
    virtual void xp_dump_statistics() { };
    virtual long long get_qspace(str hname) { return(-1); };
    
    virtual ~xferPlugin() {}
};

// for the pending queue structure
struct desc_request {
    chunk_cb cb;
    const dot_desc desc_id;
    unsigned int length;

    ihash_entry<desc_request> hlink;

    desc_request (chunk_cb cbk, dot_descriptor dot_desc);
    ~desc_request ();
};

#endif /* _PLUGIN_XFER_H_ */
