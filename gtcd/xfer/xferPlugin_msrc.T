/*
 * Copyright (c) 2005-2008 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_msrc.h"

#ifdef ANIMATION
FILE *anime_fd;
#endif

#ifdef TIME_TRACE
static int block_count = 0;
static double begin;
static struct timeval start, end;
#endif
extern bool is_end_game;

descs_msrc::descs_msrc(chunk_cb cb_in, dot_descriptor dot_desc, 
		       ref<vec<oid_hint> > oidhints, int i, int dupin)
    : desc_name(dot_desc.id), dd(dot_desc),
      oidhint(oidhints), i(i), dups(dupin)
{
    cb.push_back(cb_in);
}

descs_msrc::descs_msrc(vec<chunk_cb> cb_in, dot_descriptor dot_desc, 
		       ref<vec<oid_hint> > oidhints, int i, int dupin)
    : desc_name(dot_desc.id), dd(dot_desc),
      oidhint(oidhints), i(i), dups(dupin)
{
    cb = cb_in;
}

descs_msrc::~descs_msrc()
{
}

descs_msrc *
xferPlugin_msrc::check_if_serve(dot_descriptor in)
{
    descs_msrc *d;
    
    //check pending q first
    if ((d = hash_pending_desc[in.id])) {
	return d;
    }

    //check individual src queues
    for (u_int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	if (wait_list_src[i] == NULL) continue;
	if ((d = wait_list_src[i]->desc_request_cache[in.id]))
	    return d;
    }
    
    return NULL;
}

bool
update_rarest_index(src_view_entry *sve)
{
    //update rarest_index.  Returns true if sve is empty, false otherwise.
    u_int bin_size = sve->bin_vec.size();
    for (size_t k = sve->rarest_index; k < bin_size; k++) 
	if (sve->bin_vec[k]) {
	    sve->rarest_index = k;
	    return false;
	}

    sve->rarest_index = 0;
    return(true);
}

void
xferPlugin_msrc::insert_in_src_view(src_view_entry *sve,
				    unsigned int pos, bin_entry *be)
{
    dwarn(DEBUG_MSRC) << "Inserting in view " << sve->key
		      << " " << be->desc_name << " at pos " << pos << "\n";
    
    size_t bin_size = sve->bin_vec.size();
    if (bin_size <= pos) {
	for (size_t i = bin_size; i <= pos; i++) {
	    sve->bin_vec.push_back(NULL);
	}
    }
    
    bin *b = sve->bin_vec[pos];
    if (!b) 
	b = sve->bin_vec[pos] = New bin;
    
    b->insert(be);
}

bin_entry *
xferPlugin_msrc::remove_from_src_view(src_view_entry *sve,
				      unsigned int pos, dot_desc desc_name)
{
    dwarn(DEBUG_MSRC) << "Removing from view " << sve->key
		      << " " << desc_name << " at pos " << pos << "\n";
    
    bin *b = sve->bin_vec[pos];
    assert(b);
    bin_entry *be = (b->hash)[desc_name];
    assert(be);
    b->remove(be);
    
    if (b->hash.size() <= 0) {
	sve->bin_vec[pos] = NULL;
	delete b;
	if (sve->rarest_index == (int) pos) {
	    update_rarest_index(sve);
	}
    }
    return(be);
}

void
xferPlugin_msrc::update_src_view(descs_msrc *d, ptr<vec<oid_hint> > old_hints,
				 ref<vec<oid_hint> > new_hints)
{
    //print_src_view();
    dwarn(DEBUG_MSRC) << debug_sep;
    size_t old_hints_size = 0;
    if (old_hints)
	old_hints_size = old_hints->size();
    
    size_t num_hints = old_hints_size + new_hints->size();
    dwarn(DEBUG_MSRC) << "Updating for " << d->desc_name << "\n";
    dwarn(DEBUG_MSRC) << "Num_hints " << num_hints << " old_hints_size "
		      << old_hints_size << " new_hints " << new_hints->size() << "\n";
    
    //update bins in old hints
    if (old_hints_size) {
	for (size_t i = 0; i < old_hints_size; i++) {
	    str key;
	    if (gtc_hint_to_name((*old_hints)[i].name, &key) < 0) 
		continue;

	    dwarn(DEBUG_MSRC) << "In old, looking for " << key << "\n";
	    src_view_entry *sve = src_view[key];
	    assert(sve);

	    //move this desc from its old bin
	    bin_entry *be = remove_from_src_view(sve, old_hints_size,
						 d->desc_name);

	    insert_in_src_view(sve, num_hints, be);
	    if (sve->rarest_index < 0 ||
		sve->rarest_index > (int) num_hints)
		sve->rarest_index = num_hints;
	}
    } //if there are old_hints
    
    size_t new_hints_size = new_hints->size();
    for (size_t i = 0; i < new_hints_size; i++) {
	str key;
	if (gtc_hint_to_name((*new_hints)[i].name, &key) < 0) 
	    continue;

	dwarn(DEBUG_MSRC) << "In new, putting " << key << "\n";
	src_view_entry *sve = src_view[key];
	if (!sve) {
	    sve = New src_view_entry(key);
	    src_view.insert(sve);
	}

	bin_entry *be = New bin_entry(d->desc_name);
	insert_in_src_view(sve, num_hints, be);
	
	if (sve->rarest_index < 0 ||
	    sve->rarest_index > (int) num_hints)
	    sve->rarest_index = num_hints;
    }
    //print_src_view();
    dwarn(DEBUG_MSRC) << debug_sep;
}

void
xferPlugin_msrc::clean_src_view(descs_msrc *d)
{
    //print_src_view();
    size_t num_hints = d->oidhint->size();
    for (size_t i = 0; i < num_hints; i++) {
	str key;
	if (gtc_hint_to_name((*(d->oidhint))[i].name, &key) < 0) 
	    continue;

	src_view_entry *sve = src_view[key];
	if (!sve) continue;
	
	bin_entry *be = remove_from_src_view(sve, num_hints,
					     d->desc_name);
	if (update_rarest_index(sve)) {
	    src_view.remove(sve);
	    dwarn(DEBUG_MSRC) << "Ridding " << sve->key << "\n";
	    delete sve;
	}
	
	delete be;
    }
    //print_src_view();
}

tamed void 
xferPlugin_msrc::xp_get_chunks(ref< vec<dot_descriptor> > missing_descs, ref<hv_vec > hints,
		    chunk_cb cb)
{
    size_t size = missing_descs->size();
    int randpos[size];

    dwarn(DEBUG_MSRC) << "Get chunks called for " << size << " descs\n";
    /* Compute a random permutation of the descriptors */
    for (size_t i = 0; i < size; i++) {
	int victim = arandom() % (i+1);
	randpos[i] = randpos[victim];
	randpos[victim] = i;
    }
	
    //created the pending desc queue
    for (size_t i = 0; i < size; i++) {
	int num = randpos[i];

	descs_msrc *d;
	if ((d = check_if_serve((*missing_descs)[num]))) {
	    //push the call back into the existing object 
	    d->cb.push_back(cb);

	    //append new hints if any
	    ref<vec<oid_hint> > new_hints  = New refcounted<vec<oid_hint> >;
	    size_t cur_size = (*hints)[num]->size();
	    for (size_t j = 0; j < cur_size; j++) {
		oid_hint oh_hint = (*(*hints)[num])[j];
		bool match = false;
		size_t old_size = d->oidhint->size();
		for (size_t k = 0; k < old_size; k++)
		    if (oh_hint.name == (*(d->oidhint))[k].name) {
			match = true;
			break;
		    }

		if (!match) 
		    new_hints->push_back(oh_hint);
	    }

	    if (new_hints->size() > 0) {
		//update src view if the descriptor is still in q
		if (hash_pending_desc[d->desc_name])
		    update_src_view(d, d->oidhint, new_hints);
		*d->oidhint += *new_hints;
		dwarn(DEBUG_MSRC) << "Updating " << d->desc_name << "\n";
	    }
	}
	else {
	    d = New descs_msrc(cb, (*missing_descs)[num], (*hints)[num], num, 0);
	    hash_pending_desc.insert(d);
	    update_src_view(d, NULL, d->oidhint);
	    dwarn(DEBUG_MSRC) << "Inserting new " << d->desc_name << "\n";
	}
    }

#ifdef TIME_TRACE
    begin = return_time(SECONDS);
#endif

    // start sending the descs to the xfer plugins
    send_descs_to_src();
}

int
xferPlugin_msrc::check_srcplugin_exist(str key)
{
    src_state *ss = NULL;
    for (size_t i = 0; i < NUM_ALLOWED_SRCS; i++) {
	ss = wait_list_src[i];
	if (ss && ss->key == key)
	    return i;
    }

    return -1;
}

src_state *
xferPlugin_msrc::add_new_src(str key)
{
    src_state *in = New src_state(key);

    for (size_t i = 0; i < NUM_ALLOWED_SRCS; i++) {
        if (!wait_list_src[i]) {
            wait_list_src[i] = in;
	    num_of_srcs++;
            return(in);
        }
    }

    fatal << "xferPlugin_msrc::add_new_src: no free slots\n";
    return(NULL);
}

bool
xferPlugin_msrc::check_src_bad(str key)
{
    bad_src_entry *bse = bad_srcs[key];
    if (bse &&
	(return_time(SECONDS) - bse->time_went_bad) < SRC_RECHECK_TIMEOUT)
	return true;

    if (bse){
	bad_srcs.remove(bse);
	delete bse;
    }
    return false;
}

src_state *
xferPlugin_msrc::pick_new_rarest_src(int index)
{
    int min_hints_src = INT_MAX;
    src_view_entry *min_sve = NULL;
    src_view_entry *sve;
    
    for (sve = src_view.first(); sve; sve = src_view.next(sve)) {
	if (check_srcplugin_exist(sve->key) < 0 &&
	    !check_src_bad(sve->key)) { //available good src
	    dwarn(DEBUG_MSRC) << "Checking source " << sve->key
			      << " " << sve->rarest_index << " and min "
			      << min_hints_src << "\n";
	    if (sve->rarest_index < min_hints_src) {
		min_hints_src = sve->rarest_index;
		min_sve = sve;
	    }
	}
    }

    if (min_sve)  { //make a source of it
	assert(!wait_list_src[index]);
	src_state *ss = wait_list_src[index] = New src_state(min_sve->key);
	num_of_srcs++;
	dwarn(DEBUG_MSRC) << "Picked rarest source " << ss->key << "\n";
	return(ss);
    }
    else {
	dwarn(DEBUG_MSRC) << "No source to pick\n";
	return NULL;
    }
}

void
make_hint_from_src(src_state *ss, ref<hv_vec > hints, unsigned int dsize)
{
    assert(dsize > 0);
    ref<vec<oid_hint> > hints1  = New refcounted<vec<oid_hint> >;
    oid_hint oh;
    oh.name = ss->hname;
    hints1->push_back(oh);
    hints->push_back(hints1);
    dsize--;
    for (size_t l = 0; l < dsize; l++) {
	ref<vec<oid_hint> > t  = New refcounted<vec<oid_hint> >(*hints1);
	hints->push_back(t);
    }
}

void
xferPlugin_msrc::try_fillup_src(src_state *ss, ptr<vec<dot_descriptor> > descs_to_get)
{
    dwarn(DEBUG_MSRC) << "Filling up " << ss->key << "\n";
    
    src_view_entry *sve = src_view[ss->key];
    if (!sve)
	return;

    ref<vec<descs_msrc *> > descs_for_xp = New refcounted<vec<descs_msrc *> >;
    size_t bin_size = sve->bin_vec.size();
    for (size_t i = sve->rarest_index; i < bin_size; i++) {
	bin *b = sve->bin_vec[i];
	if (!b) continue;

	bin_entry *be = b->randq.first;
	while (be && (ss->outstanding_bytes < ss->allowed_bytes)) {
	    descs_msrc *d_xp = hash_pending_desc[be->desc_name];
	    dwarn(DEBUG_MSRC) << "Fetching from " << ss->key << " desc " << be->desc_name
			      << " " << d_xp->dd.length << "\n";

	    if (!d_xp)
		fatal << "What happened to the descriptor\n";
	    
	    hash_pending_desc.remove(d_xp);
	    ss->desc_request_cache.insert(d_xp);
	    ss->outstanding_requests++;
	    ss->outstanding_bytes += d_xp->dd.length;
	    
	    descs_to_get->push_back(d_xp->dd);
	    descs_for_xp->push_back(d_xp);
	    
	    be = b->randq.next(be);
	}

	if (ss->outstanding_bytes >= ss->allowed_bytes)
	    break;
    }

    //clean up src_view
    size_t size = descs_for_xp->size();
    for (size_t i = 0; i < size; i++) 
	clean_src_view((*descs_for_xp)[i]);
}

void
xferPlugin_msrc::update_allowed_bytes(src_state *ss)
{
    //update allowed bytes
    long long rem = xp->get_qspace(ss->hname);
    if (rem < 0)
	ss->allowed_bytes = ss->outstanding_bytes + NUM_ALLOWED_REQS*CHUNK_SIZE;
    else
	ss->allowed_bytes = ss->outstanding_bytes + rem;
        
    dwarn(DEBUG_MSRC) << "Allow " << ss->key << " "
		      << ss->allowed_bytes << " with " << rem << "\n";
}

void
xferPlugin_msrc::delete_source_if_empty(size_t srcidx)
{
    src_state *ss = wait_list_src[srcidx];
    if (ss && ss->outstanding_requests == 0) {
	dwarn(DEBUG_MSRC) << "Deleting source " << ss->key << "\n";
	delete ss;
	wait_list_src[srcidx] = NULL;
	num_of_srcs--;
    }
}	

//sends descs from the pending queue to
//the respective xfer plugins
void
xferPlugin_msrc::send_descs_to_src()
{
    dwarn(DEBUG_MSRC) << debug_sep;
    
    if (hash_pending_desc.size() > 0) {
	dwarn(DEBUG_MSRC) << "Sending descs from q\n";
	bool pick_failed = false;
	
	for (unsigned int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	    ptr<vec<dot_descriptor> > descs_to_get = NULL;
	    src_state *ss = wait_list_src[i];
	    
            if (ss) {
		update_allowed_bytes(ss);
		
		//no space in the source
		if (ss->outstanding_bytes >= ss->allowed_bytes)
		    continue;
		
		dwarn(DEBUG_MSRC) << "Trying to fill " << ss->key
				  << " " << ss->outstanding_requests << "\n";
		//a source with some space, can we put anything?
		descs_to_get = New refcounted<vec<dot_descriptor> >;
		try_fillup_src(ss, descs_to_get);
		dwarn(DEBUG_MSRC) << "Filled " << ss->key
				  << " " << ss->outstanding_requests << " "
				  << ss->outstanding_bytes << " " << ss->allowed_bytes << "\n";

		if (ss->outstanding_requests <= 0) {
		    dwarn(DEBUG_MSRC) << "Deleting source " << ss->key << "\n";
		    //delete this source
		    delete ss;
		    wait_list_src[i] = NULL;
		    num_of_srcs--;
		}
	    }
	    ss = wait_list_src[i];
	    //may be was always empty or just got empty
	    //add a new source
	    if (!ss && !pick_failed) {
		ss = pick_new_rarest_src(i);
		if (!ss) {
		    pick_failed = true;
		    continue;
		}
		update_allowed_bytes(ss);
		if (!descs_to_get)
		    descs_to_get = New refcounted<vec<dot_descriptor> >;
		try_fillup_src(ss, descs_to_get);
		dwarn(DEBUG_MSRC) << "Filled " << ss->key
				  << " " << ss->outstanding_requests << " "
				  << ss->outstanding_bytes << " " << ss->allowed_bytes << "\n";
	    }

	    //send descs to the next plugin
	    if (descs_to_get && descs_to_get->size()) {
		//this source has non-dup blocks too
		ss->isdup = false;
		
		ref<hv_vec > hints  = New refcounted<hv_vec >;
		make_hint_from_src(ss, hints, descs_to_get->size());
		
		xp->xp_get_chunks(descs_to_get, hints, 
				  wrap(this, &xferPlugin_msrc::get_chunks_done, ss->key));
	    }
	}
    }

    if (hash_pending_desc.size() == 0 && is_end_game) {
	//try and duplicate blocks
	dwarn(DEBUG_MSRC) << "Duplicating descs\n";
	print_wait_list();

	for (unsigned int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	    delete_source_if_empty(i);
	}
	
	//go through issue qs of each non-duplicate source
	for (unsigned int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	    src_state *ss = wait_list_src[i];
	    if (!ss || ss->isdup) continue;
	    
	    descs_msrc *d_xp;
	    for (d_xp = ss->desc_request_cache.first();
		 d_xp;
		 d_xp = ss->desc_request_cache.next(d_xp)) {
		
		dwarn(DEBUG_MSRC) << "Trying to duplicate " << d_xp->desc_name << "\n";
		
		if (d_xp->dups > 0) {
		    continue;
		}

		size_t num_hints = (d_xp->oidhint)->size();
		str dup_src = NULL;
		for (size_t j = 0; j < num_hints; j++) {
                    str key;
		    if (gtc_hint_to_name((*(d_xp->oidhint))[j].name, &key) < 0) 
			continue;

		    src_state *src = NULL;
		    int index = check_srcplugin_exist(key);
		    if (index >= 0) {
			src = wait_list_src[index];
			update_allowed_bytes(src);
		    }
		    
		    if (src && (src->isdup &&
				src->outstanding_bytes < src->allowed_bytes)) {
			dup_src = key;
			break;
		    }
		    
		    if (!src && num_of_srcs < NUM_ALLOWED_SRCS &&
			!check_src_bad(key)) 
			dup_src = key;
		}
		
		if (dup_src) {
		    src_state *new_src = NULL;
		    int index = check_srcplugin_exist(dup_src);
		    if (index >= 0)
			new_src = wait_list_src[index];
		    else {
			new_src = add_new_src(dup_src);
			update_allowed_bytes(new_src);
		    }
		    
		    dwarn(DEBUG_MSRC) << "Making duplicate connection to "
				      << dup_src << " for " << d_xp->desc_name << "\n";
		    
		    //duplicate the request
		    d_xp->dups++;
		    descs_msrc *d = New descs_msrc(d_xp->cb, d_xp->dd, d_xp->oidhint, d_xp->i, 1);
		    new_src->desc_request_cache.insert(d); // enqueue desc on wait-q
		    new_src->outstanding_requests++;
		    new_src->outstanding_bytes += d->dd.length;
		    new_src->isdup = true;
		    
		    //send it
		    ptr<vec<dot_descriptor> > descs_to_get = New refcounted<vec<dot_descriptor> >;
		    descs_to_get->push_back(d->dd);
		    dwarn(DEBUG_MSRC) << "Sending duplicate " << d->dd.id << "\n";
		    ref<hv_vec > hints  = New refcounted<hv_vec >;
		    make_hint_from_src(new_src, hints, 1);
		    xp->xp_get_chunks(descs_to_get, hints, 
				      wrap(this, &xferPlugin_msrc::get_chunks_done, dup_src));
		} 
		
	    } // foreach entry in desc request cache
	} //for i
    }

    dwarn(DEBUG_MSRC) << debug_sep;
}

// callback function invoked for some smart book-keeping 
// functions in the future for intelligent loadbalancing and
// multi-path transfers
void
xferPlugin_msrc::get_chunks_done(str xp_key, 
				 str s, ptr<desc_result> res)
{
    int xp_id = check_srcplugin_exist(xp_key);
    descs_msrc *d = NULL;
    if (s) {
	//If it fails on one plugin, send to another
	warn << "MSRC:: error checking triggered for " << xp_key 
	     << " due to " << s << "\n";
	
	if (xp_id >= 0) {
	    src_state *xp_ss = wait_list_src[xp_id];
	    //move its descriptors back to pending q
	    while ((d = xp_ss->desc_request_cache.first())) {
		xp_ss->desc_request_cache.remove(d);
		if (d->dups <= 0 || !(check_if_serve(d->dd))) {
		    d->dups = 0;
		    hash_pending_desc.insert(d);
		    update_src_view(d, NULL, d->oidhint);
		}
		else
		    delete d;
	    }
	    wait_list_src[xp_id] = NULL;
	    delete xp_ss;
	    /*did not cancel from gtc because it will cancel dup and original
	      and the state gets more clumsy*/
	}

	bad_src_entry *bse = New bad_src_entry(xp_key, return_time(SECONDS));
	bad_srcs.insert(bse);

	//print_src_view();
	
	send_descs_to_src();
	return;
    }

    static int useless_work1 = 0;
    dwarn(DEBUG_MSRC) << "get_chunks_done:: Chunk came back for " << xp_key
	 << " and " << res->desc->id << "\n";
    
    if (xp_id < 0) {
	warn << "Error2: Unable to find descriptor and src in XP " << xp_key << " "
	     << ++useless_work1 << "\n";
	return;
    }
    
    src_state *ss = wait_list_src[xp_id];
    assert(ss);
    ss->fetched_bytes += res->desc->length;
    
    d = ss->desc_request_cache[res->desc->id];
    if (d) {
	dwarn(DEBUG_MSRC) << "Removing from source " << ss->key << "\n";
	    
	ss->desc_request_cache.remove(d);
	ss->outstanding_requests--;
	ss->outstanding_bytes -= res->desc->length;
	
#ifdef TIME_TRACE
        double now = return_time(SECONDS);
        double time_elapsed = now - begin;
        block_count++;
	str buf = strbuf() << d->desc_name;
        fprintf(stdout,"BLOCKTIME %f %d %d %s %s\n",time_elapsed, block_count,
                d->i, ss->hostname.cstr(), buf.cstr());
        fflush(stdout);
#endif
#ifdef ANIMATION
	str buf = strbuf("%f", return_time(SECONDS))
	             << " " << ss->hostname << " "
		     << ss->port << " " << res->desc->id << "\n";
	
	fprintf(anime_fd, "%s", buf.cstr());
	fflush(anime_fd);
#endif	
	ss->served_requests++;
	
	dwarn(DEBUG_MSRC) << "Returning data\n";
        // Only if we haven't returned data earlier
        for (size_t c = 0; c < d->cb.size(); c++)
            (*(d->cb[c]))(s, res);

	if (d->dups > 0) {
	    //cancel
	    dwarn(DEBUG_MSRC) << "Pulling out " << res->desc->id << "\n";
	    cancel_chunk(res->desc, wrap(this, &xferPlugin_msrc::cancel_chunk_cb, res->desc));
	}
	delete d;
    }
    else {
	warn << "Error1: Unable to find descriptor in XP " << xp_key << " "
	     << ++useless_work1 << "\n";
	ss->outstanding_requests--;
	ss->outstanding_bytes -= res->desc->length;
    }
    send_descs_to_src();
}

void
xferPlugin_msrc::print_wait_list()
{
    return;
    warnx << debug_sep;
    for (unsigned int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	if (wait_list_src[i] == NULL) continue;

	warnx << "Src " << i << " host " << wait_list_src[i]->hostname << ":"
	     << wait_list_src[i]->port << " "
	     << wait_list_src[i]->outstanding_requests << "\n";

    }
    warnx << debug_sep;
}

void
xferPlugin_msrc::print_src_view()
{
    warnx << debug_sep;
    src_view_entry *sve;
    for (sve = src_view.first(); sve; sve = src_view.next(sve)) {
	warnx << "View for " << sve->key << " -->\n";
	for (size_t i = 0; i < sve->bin_vec.size(); i++) {
	    if (!sve->bin_vec[i]) continue;
	    warnx << "Bin " << i << " -- ";
	    typeof(sve->bin_vec[i]->randq) *qptr = &(sve->bin_vec[i]->randq);
	    for (bin_entry *be = qptr->first; be; be = qptr->next(be)) {
		warnx << be->desc_name << " ";
	    }
	    warnx << "\n";
	}
	warnx << "**************\n";
    }
    warnx << debug_sep;
}


tamed void
xferPlugin_msrc::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    xp->xp_get_descriptors(oid, hints, cb);
}

tamed void
xferPlugin_msrc::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    tvars {
        ptr<vec<nw_status> > status;
    }

    twait {
        xp->cancel_chunk(d, mkevent(status));
    }

    (*status)[0] = handle_cancel_chunk(*d, (*status)[0]);
    (*cb)(status);
    send_descs_to_src();
}

void
xferPlugin_msrc::cancel_chunk_cb(ref<dot_descriptor> desc,
				 ptr<vec<nw_status> > status)
{
    if ((*status)[0] == CANCELLED)
	return;
    
    descs_msrc *d = NULL;
    for (unsigned int i = 0; i < NUM_ALLOWED_SRCS; i++) {
	src_state *ss = wait_list_src[i];
        if (!ss) continue;
	d = ss->desc_request_cache[desc->id];
        if (d) {
	    dwarn(DEBUG_MSRC) << "Could not cancel " << desc->id
			      << " from " << ss->key << "\n";
	    ss->desc_request_cache.remove(d);
	    delete d;
	}
    }
}

nw_status
xferPlugin_msrc::handle_cancel_chunk(dot_descriptor desc, nw_status s)
{
    descs_msrc *d = hash_pending_desc[desc.id];
    if (d) {
	hash_pending_desc.remove(d);
	clean_src_view(d);
	delete d;
	s = CANCELLED;
    }
    else if (s == CANCELLED) {
	for (unsigned int j = 0; j < NUM_ALLOWED_SRCS; j++) {
	    if (wait_list_src[j] == NULL)  continue;
	    descs_msrc *d = wait_list_src[j]->desc_request_cache[desc.id];
	    if (d) {
		wait_list_src[j]->desc_request_cache.remove(d);
		wait_list_src[j]->outstanding_requests--;
		wait_list_src[j]->outstanding_bytes -= d->dd.length;
		delete d;
	    }
	}
    }

    return(s);
}

tamed void
xferPlugin_msrc::cancel_chunks(ref<vec<dot_descriptor> > dv, cancel_cb cb)
{
    dwarn(DEBUG_MSRC) << "cancel_chunks called\n";
    tvars {
        ptr<vec<nw_status> > status;
    }

    twait {
        xp->cancel_chunks(dv, mkevent(status));
    }

    //warn << "xferPlugin_msrc::cancel_chunks: called\n";
    for (size_t i = 0; i < dv->size(); i++)
        (*status)[i] = handle_cancel_chunk((*dv)[i], (*status)[i]);

    (*cb)(status);
    send_descs_to_src();
}

void 
xferPlugin_msrc::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
#ifdef TIME_TRACE
    gettimeofday(&start, NULL);
#endif
    
    //warnx << "xferPlugin_msrc::xp_notify_descriptors: called\n";
    xp->xp_notify_descriptors(oid, descs);
}

tamed void 
xferPlugin_msrc::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
			   chunk_cb cb)
{
    warn << "xferPlugin_msrc::get_chunk: called\n";
}

void 
xferPlugin_msrc::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
#ifdef TIME_TRACE
    gettimeofday(&end, NULL);
    fprintf(stderr, "@@@@@xferPlugin_msrc::update_hints time for notifydes-updatehints == %.2f\n",
    	    timeval_diff(&start, &end));
#endif
    dwarn(DEBUG_MSRC) << "Updating hints\n";
    size_t size = dv->size();
    for (size_t i = 0; i < size; i++) {
	descs_msrc *d;
	if ((d = check_if_serve((*dv)[i]))) {
	    //update src view if the descriptor is still in q
	    if (hash_pending_desc[d->desc_name]) {
		dwarn(DEBUG_MSRC) << "Updating " << d->desc_name << "\n";
		update_src_view(d, d->oidhint, (*hints)[i]);
	    }
	    *d->oidhint += *((*hints)[i]);
	} 
    } 
    
    send_descs_to_src();
}

xferPlugin_msrc::xferPlugin_msrc(gtcd *m, xferPlugin *next_xp)
    : m(m), xp(next_xp), num_of_srcs(0)
{
    assert(m);
    assert(xp);

    //pre init make wait_list_src for all sources. and 
    //then associate each index with a source...i can't keep deleting and adding
    //entries because code uses index into wait_list_src to see whose block came back
    warn << "Num conns " << NUM_ALLOWED_REQS << " num srcs " << NUM_ALLOWED_SRCS << "\n";
    for (unsigned int i = 0; i < NUM_ALLOWED_SRCS ; i++) 
	wait_list_src.push_back(NULL);

    is_end_game = true;
    
#ifdef ANIMATION
    const str file = "/tmp/animation";
    warn << "xferPlugin_msrc::xferPlugin_msrc opening animation file " << file << "\n";
    
    anime_fd = fopen(file, "w");
    
    if (anime_fd == NULL) {
	strbuf sb;
	sb.fmt("Could not open animation output file: %s: %m", file.cstr());
	fatal << sb;
    }
    
    file = "Time SourceIP Sourceport descid\n";
    fprintf(anime_fd, "%s", file.cstr());
    fflush(anime_fd);
#endif
    
}

tamed void
xferPlugin_msrc::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    xp->xp_get_bitmap(oid, hints, cb);
}

void
xferPlugin_msrc::xp_dump_statistics()
{
    for (unsigned int i = 0; i < NUM_ALLOWED_SRCS ; i++) {
	if (wait_list_src[i])
	    delete wait_list_src[i];
    }
}

/* TODO
1. fix memory leak -- descs hanging around if chunks_done does not come back make it come back from gtc with failed desc info
3. duplicates it only once
*/
