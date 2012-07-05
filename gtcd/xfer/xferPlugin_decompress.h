/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_DECOMP_H_
#define _XFER_DECOMP_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"

#include "zlib.h"

class xferPlugin_decompress: public xferPlugin {
  
private:
    gtcd *m;
    xferPlugin *xp;

public:
    bool configure(str s, str pluginClass) { return true; }
    
    /* Calls from the GTC */
    void xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			 descriptors_cb cb, CLOSURE);
    void xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
		    bitmap_cb cb, CLOSURE);
    void xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs);
    void xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb, CLOSURE);

    void cancel_chunk(ref<dot_descriptor> d, cancel_cb cb, CLOSURE);
    void cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb, CLOSURE);

    void update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints);
    
    xferPlugin_decompress(gtcd *m, xferPlugin *next_xp) : m(m), xp(next_xp)
        { assert(m); assert(xp); }
    ~xferPlugin_decompress() { }

 private:
    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb, CLOSURE);
    void get_descriptors_cb(descriptors_cb cb1, str s, ptr<vec<dot_descriptor> > descs, bool end);
    void get_bitmap_cb(bitmap_cb cb1, str s, ptr<bitvec> bmp);
    void get_chunk_cb(chunk_cb cb1, str s, ptr<desc_result> res);
    void get_chunks_cb(chunk_cb cb1, str s, ptr<desc_result> res);
      
};


#endif /* _XFER_NET_H_ */
