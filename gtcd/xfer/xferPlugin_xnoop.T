/* -*- c++ -*- */
/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_xnoop.h"

//can't use twait in the functions below since the get_descriptors 
// and the get_chunks calls in xferPlugin_gtc etc call back multiple times
// and TAME thinks that the function is overcalled.
// TAME probably keeps a counter as to how many times a function call was made with in twait
// and hence allows only that many callbacks

tamed void
xferPlugin_xnoop::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    warn << "xferPlugin_xnoop::get_descriptors: called\n";
  
    xp->xp_get_descriptors(oid, hints,
			wrap(this, &xferPlugin_xnoop::get_descriptors_cb, cb));
}

void
xferPlugin_xnoop::get_descriptors_cb(descriptors_cb cb1, str s, ptr<vec<dot_descriptor> > descs, bool end)
{
    warn << "xferPlugin_xnoop:: get_descriptors_cb called\n";
    (*cb1)(s, descs, end);
}

tamed void 
xferPlugin_xnoop::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb)
{
    warn << "xferPlugin_xnoop::get_chunk: called\n";
    //xp->get_chunk(d, hints, cb);
}

tamed void 
xferPlugin_xnoop::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb)
{
    warn << "xferPlugin_xnoop::get_chunks: called\n";
  
    xp->xp_get_chunks(dv, hints, cb); 
  
    warn << "xferPlugin_xnoop::get_chunks: called back\n";
}

tamed void 
xferPlugin_xnoop::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    warn << "xferPlugin_xnoop::cancel_chunk: called\n";
    xp->cancel_chunk(d, cb);
}

tamed void 
xferPlugin_xnoop::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    warn << "xferPlugin_xnoop::cancel_chunks: called\n";
    xp->cancel_chunks(dv, cb);
}

void 
xferPlugin_xnoop::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    warn << "xferPlugin_xnoop::xp_notify_descriptors: called\n";
    xp->xp_notify_descriptors(oid, descs);
}

void 
xferPlugin_xnoop::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    warn << "xferPlugin_xnoop::update_hints: called\n";
    xp->update_hints(dv, hints);
}

tamed void
xferPlugin_xnoop::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    warn << "xferPlugin_xnoop::get_bitmap: called\n";
    xp->xp_get_bitmap(oid, hints, wrap(this, &xferPlugin_xnoop::get_bitmap_cb, cb));
}

void
xferPlugin_xnoop::get_bitmap_cb(bitmap_cb cb1, str s, ptr<bitvec> bmp)
{
    warn << "xferPlugin_xnoop:: get_bitmap called\n";
    (*cb1)(s, bmp);
}
