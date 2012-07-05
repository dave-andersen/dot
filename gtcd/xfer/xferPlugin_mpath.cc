/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_mpath.h"

/*
 * XXX: Note, this code is not currently tested.  Everything for
 * multi-path downloads other than binding multiple local interfaces
 * is handled by xferPlugin_msrc.
 */


// Special casing for now
#define PSP_XP_ID            0xCAFEBABE

descs::descs(chunk_cb cb, dot_descriptor dot_desc, 
             ref<vec<oid_hint> > oidhints, int i)
    : cb(cb), dd(dot_desc), desc_name(dot_desc.id),
      oidhint(oidhints), i(i)
{
}

descs::~descs()
{
}

xferPlugin_mpath::xferPlugin_mpath(gtcd *m, vec<xferPlugin*> xplist) 
  :  sp(m->sp), main_desc_list(New refcounted<vec<dot_descriptor> >),
     num_of_plugins(xplist.size()), xfplugins(xplist)
{
    pp = m->pp;
    wait_list_xp = New xp_state[num_of_plugins];
    warn << "mPath constructor: num_of_xps=" << num_of_plugins <<  "\n";
}
 
void
xferPlugin_mpath::xp_get_chunks(ref< vec<dot_descriptor> > missing_descs, 
			     ref<hv_vec > hints, chunk_cb cb, ptr<closure_t>)
{
    for (unsigned int i = 0; i < missing_descs->size(); i++) {
	// XXX - Memory Leak
	descs *d = New descs(cb, (*missing_descs)[i], (*hints)[i], i);
        q_pending_desc.insert_tail(d);
	hash_pending_desc.insert(d);
    }
    pp->xp_get_chunks(missing_descs, hints,
		   wrap(this, &xferPlugin_mpath::get_chunks_done, PSP_XP_ID, cb));
    // start sending the descs to the xfer plugins
    send_descs_to_xp();
}

// sends descs from the pending queue to
// the respective xfer plugins
void
xferPlugin_mpath::send_descs_to_xp()
{    
    ref<vec<vec<descs> > > descs_for_xp = New refcounted<vec<vec<descs> > >;
    for (unsigned int i = 0; i < num_of_plugins; i++) {
        vec<descs> desc;
        descs_for_xp->push_back(desc);    
    }

    for (unsigned int i = 0; i < num_of_plugins; i++) {
        
        while (wait_list_xp[i].outstanding_requests < DESC_LIST_SIZE) {
            
            // are there more descs on the pending queue ?
            if (descs *d_xp = q_pending_desc.first) {
		// remove desc from pending hash table first so that we can
		// insert it into the other hash table
		hash_pending_desc.remove(d_xp);
                q_pending_desc.remove(d_xp);
		
                (*descs_for_xp)[i].push_back(*d_xp); // issue desc to the xp
                wait_list_xp[i].desc_request_cache.insert(d_xp); // enqueue desc on wait-q
		wait_list_xp[i].outstanding_requests++;


            }
            else {
                break;  //no more descs in pending queue
            }
        }
    }

    for (unsigned int i = 0; i < num_of_plugins; i++) {
      
	//sending descs to xp1
	for (unsigned int j = 0; j < (*descs_for_xp)[i].size(); j++) {
	    
	    //sending one chunk at a time such that
	    //atleast DESC_LIST_SIZE requests are in the pipe
	    
	    ref<vec<dot_descriptor> > desc_to_get = 
		New refcounted<vec<dot_descriptor> >;
	    
	    desc_to_get->push_back(((*descs_for_xp)[i])[j].dd);
	    
	    ref<hv_vec > hints = New refcounted<hv_vec >;
	    hints->push_back(((*descs_for_xp)[i])[j].oidhint) ;
	    
	    chunk_cb cb = ((*descs_for_xp)[i])[j].cb;
	    
	    xfplugins[i]->xp_get_chunks(desc_to_get, hints, 
				     wrap(this, &xferPlugin_mpath::get_chunks_done,
					  i, cb));
	}
	
    }
}

void
xferPlugin_mpath::handle_cancel(ptr<vec<nw_status> > status)
{
}

// callback function invoked for some smart book-keeping 
// functions in the future for intelligent loadbalancing and
// multi-path transfers
void
xferPlugin_mpath::get_chunks_done(unsigned int xp_id, 
                          chunk_cb cb, str s, ptr<desc_result> res)
{
    static int useless_work = 0;

    if (s) {
	// XXX - If it fails on one plugin, send to another
	fatal << "error checking code not implemented";	
    }

    descs *d;
    bool xp_id_rem = false;
    bool other_rem = false;

    if (xp_id != PSP_XP_ID) {
	//remove desc from wait-q
	d = wait_list_xp[xp_id].desc_request_cache[res->desc->id];
	if (d) {
	    xp_id_rem = true;
	    wait_list_xp[xp_id].desc_request_cache.remove(d);
	    wait_list_xp[xp_id].outstanding_requests--;
	    cancel_cb cb = wrap(this, &xferPlugin_mpath::handle_cancel);
	    pp->cancel_chunk(res->desc, cb);
	}
	else {
	    warn << "Error: Unable to find descriptor in XP " << 
		++useless_work << "\n";
	}
    }
    else {
	d = hash_pending_desc[res->desc->id];
	other_rem = true;
	// If its not in the pending queue, we will simply do some
	// extra fetches over the network
	if (d) {
	    // warn << "removing " << res->desc->id << " from pending hash queue\n";
	    hash_pending_desc.remove(d);
	    q_pending_desc.remove(d);
	} 
    }
    
    for (unsigned int i = 0; i < num_of_plugins; i++) {
	if (i != xp_id) {
	    descs *d = wait_list_xp[i].desc_request_cache[res->desc->id];
	    if (d) {
		wait_list_xp[i].desc_request_cache.remove(d);
		wait_list_xp[i].outstanding_requests--;
		cancel_cb cb = wrap(this, &xferPlugin_mpath::handle_cancel);
		xfplugins[i]->cancel_chunk(New refcounted<dot_descriptor>(d->dd),
					   cb);
	    }
	}
    }

    if (d) {
	delete d;
    }

    if (xp_id_rem || other_rem) {
	// Only if we haven't returned data earlier
	(*cb)(s,res);
    }

    if (xp_id_rem || other_rem) {
	send_descs_to_xp();
    }
}


void
xferPlugin_mpath::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
			    chunk_cb cb, ptr<closure_t>)
{
    ref<vec<dot_descriptor> > v = New refcounted<vec<dot_descriptor> >;
    v->push_back(*d);
    
    ref<hv_vec > hints1 = New refcounted<hv_vec >;
    hints1->push_back(hints) ;
    
    xp_get_chunks(v, hints1, cb);
}

void
xferPlugin_mpath::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
				  descriptors_cb cb, ptr<closure_t>)
{
    xfplugins[0]->xp_get_descriptors(oid, hints, cb);
}

void 
xferPlugin_mpath::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb,
			       ptr<closure_t>)
{
    return;
}

void 
xferPlugin_mpath::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb,
				ptr<closure_t>)
{
    return;
}

xferPlugin_mpath::~xferPlugin_mpath()
{
    warn << "mPath destructor\n";
}

void 
xferPlugin_mpath::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    for (unsigned int i = 0; i < num_of_plugins; i++) {
	xfplugins[i]->xp_notify_descriptors(oid, descs);
    }
}

void 
xferPlugin_mpath::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    for (unsigned int i = 0; i < num_of_plugins; i++) {
	xfplugins[i]->update_hints(dv, hints);
    }
}

void
xferPlugin_mpath::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
				  bitmap_cb cb, ptr<closure_t>)
{
    xfplugins[0]->xp_get_bitmap(oid, hints, cb);
}
