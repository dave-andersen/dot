/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_xset.h"

static ihash<const dot_oid, oid_netcache_entry, &oid_netcache_entry::oid, &oid_netcache_entry::hlink, do_hash> oidCache;

static oid_hint glob_hint;
extern int odht_port;
extern str odht_ip;
str glob_hint_prefix;

//cache to cache sources per chunk
static ihash<const dot_desc, chunk_cache_entry, &chunk_cache_entry::cid, &chunk_cache_entry::hlink, dd_hash> chunkCache;

/*Have a near source cache*/
struct local_src_entry {
    ihash_entry<local_src_entry> hlink;
    str key;
    bool near;
    local_src_entry(str k, bool n) :
	key(k), near(n) { }
    ~local_src_entry() { }
};
static ihash<const str, local_src_entry, &local_src_entry::key, &local_src_entry::hlink> local_src_cache;

int
hint_to_prefix(str hint, str *name)
{
    hint_res result;
    if (parse_hint(hint, "gtc", &result) < 0)
	return 0;

    dwarn(DEBUG_SET) << "Host is " << result.hint.hostname << "\n";
    static rxx dot("\\.");
    vec<str> parts;
    split(&parts, dot, result.hint.hostname);

    *name = strbuf() << parts[0] << "." << parts[1]
		     <<	"." << parts[2];
    dwarn(DEBUG_SET) << "Prefix for " << hint << " --> "
		     << *name << "\n";
    return 1;
}

bool
near_source(str hint)
{
    local_src_entry *lse = local_src_cache[hint];
    if (lse) {
	dwarn(DEBUG_SET) << "Cache hit " << hint << " --> "
			 << lse->near << "\n";
	return lse->near;
    }
    
    bool near = false;
    str prefix;
    if (hint_to_prefix(hint, &prefix))
	if (prefix == glob_hint_prefix)
	    near = true;

    lse = New local_src_entry(hint, near);
    local_src_cache.insert(lse);
    dwarn(DEBUG_SET) << "Near for " << hint << " --> "
		     << near << "\n";
    return(near);
}

//---------------------------------------------------------------------
hint_cache::hint_cache(oid_hint h, str k)
    : hint(h), name(k)
{
    dwarn(DEBUG_SET) << "hint_cache:: Creating hint_cache for " << name << "\n";
}

hint_cache::~hint_cache()
{
    dwarn(DEBUG_SET) << "hint_cache:: Deleting hint_cache for " << name << "\n";
}

//---------------------------------------------------------------------
chunk_cache_entry::chunk_cache_entry(const dot_desc o)
    : cid(o) 
{
    dwarn(DEBUG_SET) << "chunk_cache_entry:: Creating chunk_cache_entry for "
		     << cid << "\n";
    chunkCache.insert(this);
}

chunk_cache_entry::~chunk_cache_entry()
{
    dwarn(DEBUG_SET) << "chunk_cache_entry:: Deleting chunk_cache_entry for "
		     << cid << "\n";
    //remove all the hints in the hints_hash too
    hint_cache *drpc;

    while ((drpc = hints_hash.first()) != NULL) {
	warn << "chunk_cache_entry:: Removing " << drpc->name <<"\n";
	hints_hash.remove(drpc);
	delete drpc;
    }
    
    chunkCache.remove(this);
}

//---------------------------------------------------------------------
src_info::src_info(oid_hint h, dot_oid oidin, unsigned int size)
{
    hint = h;
    
    if (gtc_hint_to_name(h.name, &key))
	fatal << "No hints in src_info\n";
        
    time = -1;
    oid = oidin;

    inprogress = false;
    
    bmp = New refcounted<bitvec>(size);

    hints_arg = New refcounted<vec<oid_hint> >;
    hints_arg->push_back(hint);

    oid_arg = New refcounted<dot_oid_md>();
    oid_arg->id = oid;
    
    dwarn(DEBUG_SET) << "src_info:: Creating src_info for " << key << "\n";
    
}

src_info::~src_info()
{
    dwarn(DEBUG_SET) << "src_info:: Deleting src_info for " << key << "\n";
}

//---------------------------------------------------------------------

oid_netcache_entry::oid_netcache_entry(const dot_oid o, update_cb cbin, gtcd *min)
    : oid(o), slist(New refcounted<ordered_descriptor_list>),
      shingles_done(0), oids_done(0), oid_insert_done(0), cb(cbin), m(min)
{
    next_event = false;
    ident_count = 0;
    sim_count = 0;
    dwarn(DEBUG_SET) << "oid_netcache_entry:: Creating oid_netcache_entry for "
		     << oid << "\n";
    oidCache.insert(this);
}

oid_netcache_entry::~oid_netcache_entry()
{
    dwarn(DEBUG_SET) << "oid_netcache_entry:: Deleting oid_netcache_entry for "
		     << oid << "\n";
    oidCache.remove(this);
}

void
oid_netcache_entry::net_lookup()
{
    dht_get_cb cb1 = wrap(this, &oid_netcache_entry::get_fp_oids_done);
    
    dwarn(DEBUG_SET) << debug_sep
		     << "oid_netcache_entry::net_lookup: finding shingles for "
		     << oid << "\n";
    
    // Output items in priority_queue using top()
    // and use pop() to get to next item until
    // priority_queue is empty
    
    shingles_done = 0;
    while (!slist->empty()) {

	dot_desc ds = slist->top();
	slist->pop();
	
	dwarn(DEBUG_SET) << "Lookup shingle " << shingles_done
			 << " " << ds << "\n";
	ref<dht_rpc> dht = New refcounted<odht_rpc>(odht_ip, odht_port, m);
	status.push_back(dht);
	get_fp_oids(dht, ds, cb1);
	shingles_done++;
    }
    
    dwarn(DEBUG_SET) << "Looking up " << shingles_done << " shingles\n"
		     << debug_sep;
    
    //now lookup my own objectid
    oid_info *drpc = oidstatus[oid];
    if (drpc) {
	dwarn(DEBUG_SET) << "oid_netcache_entry:: oidstatus already has this oid for further lookup... may be in progress\n";
    }
    else {
	dwarn(DEBUG_SET) << "Looking up object id " << oid << "\n";
	cbs cb1 = wrap(this, &oid_netcache_entry::net_lookup_oid_done, oid);
	drpc = New oid_info(oid, cb1, self_descs, m);
	dht_get_cb cb2 = wrap(drpc, &oid_info::get_oid_sources_done);
	oidstatus.insert(drpc);
	get_oid_sources(drpc->dht, drpc->oid, cb2);
	oids_done++;
    }
    
    //also start the process for inserting myself as a partial source
    oid_insert_done = 1;
    oidinsert_status = New refcounted<odht_rpc>(odht_ip, odht_port, m);
    put_oid_source(oidinsert_status, oid, glob_hint, wrap(this, &oid_netcache_entry::put_oid_source_done));

    //timer for refreshing bitmaps
    delaycb(0, REFRESH_BITMAP, wrap(this, &oid_netcache_entry::get_bitmap_refresh));
}

void
oid_netcache_entry::net_lookup_refresh()
{
    //reset variables
    next_event = false;
    shingles_done = 0;
    oids_done = 0;
    oid_insert_done = 0;

    oid_info *drpc;
    for (drpc = oidstatus.first(); drpc; drpc = oidstatus.next(drpc)) {
	dht_get_cb cb2 = wrap(drpc, &oid_info::get_oid_sources_done);
	get_oid_sources(drpc->dht, drpc->oid, cb2);
	oids_done++;
    }
}

void
oid_netcache_entry::net_insert_refresh()
{
    put_oid_source(oidinsert_status, oid,
		   glob_hint, wrap(this, &oid_netcache_entry::put_oid_source_done));
}

void
oid_netcache_entry::get_fp_oids_done(str err, ptr<vec<bamboo_value> > results)
{
    if (err) {
	dwarn(DEBUG_SET|DEBUG_ERRS) << "oid_netcache_entry::get_fp_oids_done: look up has an error "
 	     << err <<"\n";
    }
    else {

	dwarn(DEBUG_SET) << "oid_netcache_entry::get_fp_oids_done: success\n";
	
	for (size_t i = 0; i < results->size(); i++) {
	    
	    odht_val res;
	    bytes2xdr(res, (*results)[i]);
	    
	    if (res.ok) {
		dwarn(DEBUG_SET) << "oid_netcache_entry::get_fp_oids_done: GETTING VALUES THAT ARE OIDs \n";
		continue;
	    }
	    
	    oid_info_odht obj = *(res.cid_info);
	    
	    if (obj.appnum != APPDOT_VERSION) {
		dwarn(DEBUG_SET) << "odht_getcid_rpc::get_fp_oids_done: GETTING VALUES THAT ARE NOT MINE "
				 << obj.appnum << "\n";
		continue;
	    }
	    
	    dwarn(DEBUG_SET) << "OID is " << obj.oid << "\n";

	    oid_info *drpc = oidstatus[obj.oid];
	    if (drpc) {
		dwarn(DEBUG_SET) << "oid_netcache_entry::get_fp_oids_done: oidstatus already has this oid for further lookup... may be in progress\n";
	    }
	    else {
		dwarn(DEBUG_SET) << "oid_netcache_entry::get_fp_oids_done: Starting lookup for "
				 << obj.oid << "\n";
		
		oids_done++;

		cbs cb1 = wrap(this, &oid_netcache_entry::net_lookup_oid_done, obj.oid);
		drpc = New oid_info(obj.oid, cb1, NULL, m);
		dht_get_cb cb2 = wrap(drpc, &oid_info::get_oid_sources_done);
		oidstatus.insert(drpc);
		get_oid_sources(drpc->dht, drpc->oid, cb2);
	    }
	}
	
	dwarn(DEBUG_SET) << debug_sep;
    }

    shingles_done--;

    if (shingles_done <= 0 && oids_done <= 0 && oid_insert_done <= 0) {
	
	//can get rid of cid objects and insert object
	//keep the oid objects to refresh the lookup
	if (!next_event &&
	    (MAX_PEERS_ALBT - ident_count) > 0) {
	    delaycb(REFRESH_OID_LOOKUP, 0, wrap(this, &oid_netcache_entry::net_lookup_refresh));
	    next_event = true;
	}
    }
}

void
oid_netcache_entry::pick_sources(dot_oid other_oid)
{
    oid_info *drpc = oidstatus[other_oid];
    src_hash *srcs;
    unsigned int *src_count;
    int src_limit;

    if (other_oid == oid) {
	srcs = &ident_srcs;
	src_count = &ident_count;
	src_limit = MAX_PEERS_ALBT - ident_count;
    } else {
	srcs = &sim_srcs;
	src_count = &sim_count;
	src_limit = MAX_PEERS_ALBT - (ident_count + sim_count);
    }
    if (src_limit <= 0) return;
    
    ref<vec<oid_hint> > new_hints = New refcounted<vec<oid_hint> >;
    ptr<vec<oid_hint> > near_hints = New refcounted<vec<oid_hint> >;
    for (size_t i = 0; i < drpc->hints->size(); i++) {
	str src_name;
	if (gtc_hint_to_name((*(drpc->hints))[i].name, &src_name)) {
	    fatal << "No hints in pick_sources from\n";
	}
	
	src_info *src = (*srcs)[src_name];
	/* only for similar sources */
	/* This is because the same host:port could be serving two similar files
	   and get_bitmap is per oid...so we have another entry to ask for the
	   other similar object*/
	if (!src ||
	    (src && (other_oid != oid) && src->oid != other_oid)) {
	    //check if it is a near source
	    if (near_source((*(drpc->hints))[i].name)) 
		near_hints->push_back((*(drpc->hints))[i]);
	    else
		new_hints->push_back((*(drpc->hints))[i]);
	}
    }

    /*Insert at most src_limit new hints starting with near_hints*/
    unsigned int nwanted = src_limit;
    unsigned int newhint = 0;
    size_t nleft = near_hints->size();
    ptr<vec<oid_hint> > cur_hints;
    if (nleft <= 0) {
	nleft = new_hints->size();
	cur_hints = new_hints;
    }
    else
	cur_hints = near_hints;

    while (nwanted > 0 && nleft > 0) {
	if ((arandom() % nleft) < nwanted) {
	    dwarn(DEBUG_SET) << "Picking src " << (*(cur_hints))[newhint].name << "\n";
	    src_info *src = New src_info((*(cur_hints))[newhint], other_oid, drpc->descs->size());
	    srcs->insert(src);
	    *src_count = *src_count + 1;
	    nwanted--;
	}
	nleft--;
	newhint++;
	if (nleft <= 0
	    && near_hints->size() > 0) {
	    newhint = 0;
	    nleft = new_hints->size();
	    cur_hints = new_hints;
	}
    }
    
    //start getbitmap for everyone with -1 as time
    double cur_time = get_cur_time();

    for (src_info *src = srcs->first(); src; src = srcs->next(src)) {
	if (src->time < 0) {

	    //warn << "Getting bitmap for "<< src->key << "\n";

	    src->time = cur_time;
	    src->inprogress = true;
		
	    bitmap_cb cb_bmp = wrap(this, &oid_netcache_entry::get_bitmap_cb, src);
	    m->xp->xp_get_bitmap(src->oid_arg, src->hints_arg, cb_bmp);
	}
    }

    unsigned int total_srcs = ident_count + sim_count;
    //scale bitmap interval
    REFRESH_BITMAP_ALBT = max((total_srcs*(REFRESH_BITMAP/1000000))/1000, (unsigned int)2);
    warn << "SET: Picked " << total_srcs << " for " << oid << " " << REFRESH_BITMAP_ALBT << "\n";
    dwarn(DEBUG_SET) << debug_sep;
}

void
oid_netcache_entry::get_bitmap_cb(src_info *src, str err, ptr<bitvec> bmp)
{
    src->inprogress = false;
    src->time = get_cur_time();
    
    if (err) {
	dwarn(DEBUG_SET|DEBUG_ERRS) << "oid_netcache_entry::get_bitmap_cb:: Error " << err << "\n";
	return;
    }

    assert(bmp->size() == src->bmp->size());
    
    //copy the bmp over
    size_t size = bmp->size(); 
    for (size_t i = 0; i < size; i++) {
        if ((*bmp)[i] == 1)
            (*src->bmp)[i] = 1;
    }

    int match1 = 0;
    int match2 = 0;
    int POS_INF = 3000000;
    
    oid_info *drpc = oidstatus[src->oid];
    
    ref<vec<dot_descriptor> > missing_descs = New refcounted<vec<dot_descriptor> >;
    ref<hv_vec> missing_hints = New refcounted<hv_vec> ;
    
    //match the descriptors and insert hints into chunk cache and call update finally
    size = drpc->bv->size(); 
    for (size_t i = 0; i < size; i++) {

	if (((*(drpc->bv))[i] == 1))
	    match1++;
	
	if (((*(drpc->bv))[i] == 1) && ((*(src->bmp))[i] == 1)) {

	    match2++;

	    // i am interested in this descriptor and it is present in this source
	    // add it as hint
	    ref<vec<oid_hint> > new_hints = New refcounted<vec<oid_hint> >;

	    bool fresh_hints = xferPlugin_xset::insert_chunk_cache((*(drpc->descs))[i].id, src->hints_arg, new_hints);
	
	    dwarn(DEBUG_SET) << "Adding new hints for " << (*(drpc->descs))[i].id << " from " << src->key << "\n";
    
	    if (fresh_hints) {
		dwarn(DEBUG_SET) << "Really adding new hints for " << (*(drpc->descs))[i].id << "\n";
		missing_descs->push_back((*(drpc->descs))[i]);
		missing_hints->push_back(new_hints);
	    } //fresh_hints
	}
    }

    if (match1 == match2) {
	//I got everything i need so don't refresh bitmap again and again
	src->time = src->time + POS_INF;
    }

    dwarn(DEBUG_SET) << "oid_netcache_entry::get_bitmap_cb:: Bitmap from "
		     << src->key << " with " << match1
		     << " blocks and has " <<  match2 << "blocks\n";
    
    if (missing_descs->size() > 0) {
	//update_hints call back deployed
	(*cb)(missing_descs, missing_hints);
    }

}

void
oid_netcache_entry::get_bitmap_refresh_sources(src_hash *srcs)
{
    //start getbitmap for everyone who have not gotten a refresh for T seconds
    double cur_time = get_cur_time();
    for (src_info *src = srcs->first(); src; src = srcs->next(src)) {
	assert(src->time != -1);
	
	if ((cur_time - src->time) >= REFRESH_BITMAP_ALBT && !(src->inprogress)) {
	    src->time = cur_time;
	    src->inprogress = true;
	    bitmap_cb cb_bmp = wrap(this, &oid_netcache_entry::get_bitmap_cb, src);
	    m->xp->xp_get_bitmap(src->oid_arg, src->hints_arg, cb_bmp);
	}
    }
}

void
oid_netcache_entry::get_bitmap_refresh()
{
    get_bitmap_refresh_sources(&sim_srcs);
    get_bitmap_refresh_sources(&ident_srcs);

    delaycb(0, REFRESH_BITMAP, wrap(this, &oid_netcache_entry::get_bitmap_refresh));
}

struct match_entry {
    ihash_entry<match_entry> hlink;
    dot_desc id;
    match_entry(dot_desc in) :
	id(in) { }
    ~match_entry() { }
};


void
oid_netcache_entry::net_lookup_oid_done(dot_oid other_oid, str err)
{ 
    oids_done--;
    
    if (err) {
	dwarn(DEBUG_SET|DEBUG_ERRS) << "oid_netcache_entry::net_lookup_oid_done: looking up OID "
				    << oid << " failed: " << err << "\n";
    }
    else {
	
	dwarn(DEBUG_SET) << "oid_netcache_entry::net_lookup_oid_done: called for oid "
			 << oid << " with other id "<< other_oid << "\n";

	oid_info *drpc = oidstatus[other_oid];
	
	if (!drpc->bv) {

	    size_t other_size = (drpc->descs)->size();
	    drpc->bv = New refcounted<bitvec>(other_size);
	    //clear the bitvector
	    drpc->bv->setrange(0, drpc->bv->size(), 0);
	    unsigned int match = 0;

	    //match the descriptors and create a bitvector
	    ihash<const dot_desc, match_entry, &match_entry::id, &match_entry::hlink, dd_hash> temp;
	    size_t self_size = self_descs->size();
	    for (size_t i = 0; i < self_size; i++) {
		temp.insert(New match_entry((*self_descs)[i].id));
	    }
	    
	    ptr<vec<dot_descriptor> > other = drpc->descs;
	    for (size_t i = 0; i < other_size ; i++) {
		match_entry *me = temp[(*other)[i].id];
		if (me) {
	            match++;
		    (*(drpc->bv))[i] = 1;
                }
	    }
	
	    dwarn(DEBUG_SET) << "oid_netcache_entry::net_lookup_oid_done: matched "
			     << match <<"\n";
	    
	} //drpc->bv does not exist

	//pick any sources we want from this new oid
	pick_sources(other_oid);
    }

    if (shingles_done <= 0 && oids_done <= 0 && oid_insert_done <= 0) {
	//can get rid of cid objects and insert object
	//keep the oid objects to refresh the lookup
	if (!next_event &&
	    (MAX_PEERS_ALBT - ident_count) > 0) {
	    delaycb(REFRESH_OID_LOOKUP, 0, wrap(this, &oid_netcache_entry::net_lookup_refresh));
	    next_event = true;
	}
    }
}

void
oid_netcache_entry::put_oid_source_done(str err)
{
    oid_insert_done = 0;

    if (err)
	dwarn(DEBUG_SET|DEBUG_ERRS) << "Partial OID status:: " << err << "\n";
    else
	dwarn(DEBUG_SET) << "Partial OID status:: Success\n";
    

    if (shingles_done <= 0 && oids_done <= 0 && oid_insert_done <= 0) {
	
	//can get rid of cid objects and insert object
	//keep the oid objects to refresh the lookup
	if (!next_event &&
	    (MAX_PEERS_ALBT - ident_count) > 0) {
	    delaycb(REFRESH_OID_LOOKUP, 0, wrap(this, &oid_netcache_entry::net_lookup_refresh));
	    next_event = true;
	}
    }

    //refresh the put
    delaycb((int)(0.75*OPENDHT_TTL), 0, wrap(this, &oid_netcache_entry::net_insert_refresh));
}

//--------------------------------------------------------------------

/*
 * OID info functions
 */

oid_info::oid_info(const dot_oid &oid, cbs cb, ptr<vec<dot_descriptor> > descs, gtcd *m)
    : oid(oid), cb(cb), descs(descs), m(m), hints(NULL), bv(NULL)
{
    dht = New refcounted<odht_rpc>(odht_ip, odht_port, m);
}

void
extract_hints_from_dht(ptr<vec<bamboo_value> > results, ptr<vec<oid_hint> > srcdata)
{
    dwarn(DEBUG_SET) << "oid_info::get_oid_sources_done:: Results are --> \n";
    
    for (size_t i = 0; i < results->size(); i++) {
	
	odht_val res;
	bytes2xdr(res, (*results)[i]);
	    
	if (!res.ok) {
	    dwarn(DEBUG_SET) << "oid_info::get_oid_sources_done:: GETTING VALUES THAT ARE CIDs \n";
	    continue;
	}
	
	oid_hint_odht obj = *(res.oid_info);
	if (obj.appnum != APPDOT_VERSION) {
	    dwarn(DEBUG_SET) << "oid_info::get_oid_sources_done:: GETTING VALUES THAT ARE NOT MINE or are CIDs "
			     << obj.appnum << "\n";
	    continue;
	}
	
	oid_hint obj1;
	obj1.name = strbuf() << "gtc://" << obj.hostname << ":" << obj.port;
        
	dwarn(DEBUG_SET) << "oid_info::get_oid_sources_done:: hostname is " << obj.hostname << "\n";

	//if it is myself, skip it
	if (obj1.name == glob_hint.name) {
	    dwarn(DEBUG_SET) << "Skipping " << glob_hint.name << "\n";
	    continue;
	}
        
	srcdata->push_back(obj1);
	dwarn(DEBUG_SET) << debug_sep;
    }
}

void
oid_info::get_oid_sources_done(str err, ptr<vec<bamboo_value> > results) 
{
    if (err) {
	str s = strbuf() << "oid_info::get_oid_sources_done:: " << err << "\n";
	dwarn(DEBUG_SET|DEBUG_ERRS) << s;
	
        //set status in parent
        (*cb)(s);
        return ;
    }

    ptr<vec<oid_hint> > srcdata = New refcounted<vec<oid_hint> >;
    extract_hints_from_dht(results, srcdata);
     
    if (!hints)
	hints = srcdata;
    else {
	//have existing hints, append srcdata to the existing hints
	for (size_t i = 0; i < srcdata->size(); i++) {
	    bool found = false;
	    for (size_t j = 0; j < hints->size(); j++) {
		if ((*srcdata)[i].name == (*hints)[j].name) {
		    found = true;
		    break;
		}
	    }
	    
	    //append hints
	    if (!found) {
		hints->push_back((*srcdata)[i]);
	    }
	}
    }
    
    if (descs == NULL) {
	
	dwarn(DEBUG_SET) << "oid_info::start_descriptors: Getting descriptors for " << oid << "\n";
	
	ref<dot_oid_md> new_oid = New refcounted<dot_oid_md>();
	
	new_oid->id = oid;
	
	m->xp->xp_get_descriptors(new_oid, hints, wrap(this, &oid_info::get_descriptors_cb));
	
	return;
    }
    else
	dwarn(DEBUG_SET) << "Have Descriptors of my own\n";
    
    //set status in parent
    (*cb)(NULL);
} 

void
oid_info::get_descriptors_cb(str s, ptr<vec<dot_descriptor> > descsin, bool end)
{
    if (s) {
		
	//CHECK
	descs = New refcounted<vec<dot_descriptor> >;
	dwarn(DEBUG_SET) << "oid_info::get_descriptors_cb " << s << "\n";
	(*cb)(s);
	return;
    }
    
    if (!descs) {
	descs = descsin;
    }
    else {
	*descs += *descsin;
    }
    
    if (end) {
	(*cb)(NULL);
    } 
}

//--------------------------------------------------------------------

void
xferPlugin_xset::get_hints_chunk_cache(dot_desc cid, ref<vec<oid_hint > > hintsin)
{
  chunk_cache_entry *cce = chunkCache[cid];
  
  if (cce) {
      dwarn(DEBUG_SET) << debug_sep;
      dwarn(DEBUG_SET) << "xferPlugin_xset::get_hints_chunk_cache: Cache hits for " << cid << "will be --> \n";
      
      hint_cache *he;
      for (he = cce->hints_hash.first(); he; he = cce->hints_hash.next(he)) {
	  dwarn(DEBUG_SET) << "Hint is " << he->name << "\n" << debug_sep;
	  hintsin->push_back(he->hint);
      }
  }
  else {
      //fatal << "I just put in hints\n";
  }
}


bool
xferPlugin_xset::insert_chunk_cache(dot_desc cid, ptr<vec<oid_hint> > srcdata, ref<vec<oid_hint> > new_hints)
{
    chunk_cache_entry *cce = chunkCache[cid];
    
    if (cce) {
	dwarn(DEBUG_SET) << "xferPlugin_xset::insert_chunk_cache: chunkCache already has this cid for lookup\n";
    }
    else {
	dwarn(DEBUG_SET) << "xferPlugin_xset::insert_chunk_cache: Making entry for " << cid << "\n";
	cce = New chunk_cache_entry(cid);
    }
    
    bool isnew = false;
    
    //push the hints into cce
    for (size_t i = 0; i < srcdata->size() ; i++) {
    
	hint_res result;
	if (parse_hint((*srcdata)[i].name, "gtc", &result) < 0) {
	    continue;
	}
        str key = strbuf() << result.hint.hostname << ":" << result.hint.port;
	hint_cache *he = cce->hints_hash[key];
	
	if (he)
	    continue;
	
	isnew = true;
	
	dwarn(DEBUG_SET) << "Inserting new hints " << key << "\n";
	
	he = New hint_cache((*srcdata)[i], key);
	cce->hints_hash.insert(he);
	
	//for now
	new_hints->push_back((*srcdata)[i]);
    }

#if 0
    //Dump chunk cache when needed
    dwarn(DEBUG_SET) << "Cache hits will be --> \n";
    hint_cache *he;
    for (he = cce->hints_hash.first(); he; he = cce->hints_hash.next(he))
	dwarn(DEBUG_SET) << "Hint is " << he->name << "\n"
			 << debug_sep;
#endif
    
    //true indicates that they are fresh hints
    return(isnew);
}

tamed void
xferPlugin_xset::xp_get_descriptors(ref<dot_oid_md> oid,
				    ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    /*
     * The following code allows SET to get descriptors from peers
     * instead of only from the source.  It works, but it is
     * slower on PlanetLab, because the peers are often slower!
     * If we want to use this in practice, we should extend it
     * so that it tries to get the descriptors from two peers
     * in parallel and uses the fastest one...
     */
    
#if 0
    /* tvars { */
/*  	ptr<dht_rpc> dht; */
/*  	str err; */
/*  	ptr<vec<bamboo_value> > results; */
/*  	struct timeval t; */
/*      } */
/*      gettimeofday(&t, NULL); */
/*      warn << "Looking up object id for descriptors " << oid ->id << "\n"; */
/*      dht = New refcounted<odht_rpc>(odht_ip, odht_port, m); */
/*      twait { */
/*  	get_oid_sources(dht, oid->id, mkevent(err, results)); */
/*      } */

/*      struct timeval tv; */
/*      gettimeofday(&tv, NULL); */
/*      printf("Time to get sources for descs - %.4f\n", timeval_diff(&t, &tv)); */
  
/*      if (err) { */
/*  	warn << "Getting sources from DHT for descriptors failed " */
/*  	     << err << "\n"; */
/*  	xp->xp_get_descriptors(oid, hints, cb); */
/*  	return; */
/*      } */
  
/*      ptr<vec<oid_hint> > srcdata = New refcounted<vec<oid_hint> >; */
/*      extract_hints_from_dht(results, srcdata); */
/*      //pick a random hint */
/*      int hintnum =  arandom() % srcdata->size(); */
/*      ptr<vec<oid_hint> > newhint = New refcounted<vec<oid_hint> >; */
/*      newhint->push_back((*srcdata)[hintnum]); */
/*      warnx << "Getting descriptors from " << (*srcdata)[hintnum].name << "\n"; */
/*      xp->xp_get_descriptors(oid, newhint, cb); */
#endif /* all fetching-from-peers code disabled */

     xp->xp_get_descriptors(oid, hints, cb);
     return;

}

tamed void 
xferPlugin_xset::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
			  chunk_cb cb)
{
    dwarn(DEBUG_SET) << "xferPlugin_xset::get_chunk: called\n";
}

tamed void 
xferPlugin_xset::xp_get_chunks(ref< vec<dot_descriptor> > dv,
			       ref<hv_vec > hints1, chunk_cb cb)
{
    //first add the hints i have so far into chunk cache
    for (size_t i = 0; i < dv->size(); i++) {
	dot_desc cid  = (*dv)[i].id;
	//allocated since insert_chunk_cache interface needs it
	//otherwise useless
	ref<vec<oid_hint> > new_hints = New refcounted<vec<oid_hint> >;
	insert_chunk_cache(cid, (*hints1)[i], new_hints);
    }

    //add my hints here per chunk
    for (size_t i = 0; i < dv->size(); i++) {
	dot_desc cid  = (*dv)[i].id;
	(*hints1)[i]->clear();
	get_hints_chunk_cache(cid, (*hints1)[i]);
    }
    
    xp->xp_get_chunks(dv, hints1, cb);
}


tamed void 
xferPlugin_xset::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    dwarn(DEBUG_SET) << "xferPlugin_xset::cancel_chunk: called\n";
    xp->cancel_chunk(d, cb);
}

tamed void 
xferPlugin_xset::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    xp->cancel_chunks(dv, cb);
}

void 
xferPlugin_xset::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    // check oidCache if a lookup is in progress
    oid_netcache_entry *oce = oidCache[oid->id];
    
    if (oce) {
	dwarn(DEBUG_SET) << "xferPlugin_xset::xp_notify_descriptors: oidCache already has this oid for lookup... may be in progress\n";
    }
    else {
	
	update_cb cb = wrap(this, &xferPlugin_xset::update_hints);
	oce = New oid_netcache_entry(oid->id, cb, m);
	oce->self_descs = descs;
	
	//add the descriptors to the oce
	for (size_t i = 0; i < descs->size(); i++) {
	    
	    dot_desc descript = (*descs)[i].id;
	    int size_q = oce->slist->size();
	    
	    if (size_q > NUM_SHINGLES - 1) {
		oce->slist->push(descript);
		//remove the largest element
		oce->slist->pop();
	    }
	    else 
		oce->slist->push(descript);
	}
	
	//call lookup
	ref<vec<oid_hint> > hint = New refcounted<vec<oid_hint> >;
	m->sep->get_default_hint(hint);
	glob_hint = (*hint)[0];
	
	//extract the prefix of the hint
	if (!hint_to_prefix(glob_hint.name, &glob_hint_prefix))
	    fatal << "Default hint is bad\n";
	
	delaycb(0, 0, wrap(oce, &oid_netcache_entry::net_lookup));
	
    } //else
    
    //pass it along
    xp->xp_notify_descriptors(oid, descs);
}

void 
xferPlugin_xset::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    dwarn(DEBUG_SET) << "Updating hints for " << dv->size() << "\n";
    dwarn(DEBUG_SET) << debug_sep;

#if 0
    //print out descriptor to hints mapping if needed
    for (size_t j = 0; j < dv->size(); j++) { 
	dwarn(DEBUG_SET) << "For " << j << " missing descriptor " << (*dv)[j].id << "\n" ; 
	/*copy current hints as is */
	for (size_t i = 0; i < (*hints)[j]->size(); i++)
 	    dwarn(DEBUG_SET) << "Hint " << i << " is "<< (*(*hints)[j])[i].name << "\n"; 
    }
#endif
    
    xp->update_hints(dv, hints);
}

xferPlugin_xset::~xferPlugin_xset()
{
    dwarn(DEBUG_SET) << "xferPlugin_xset::~xferPlugin_net deleting\n";
    
    chunk_cache_entry *drpc;

    while ((drpc = chunkCache.first()) != NULL) {
	dwarn(DEBUG_SET) << "deleting " << drpc->cid <<"\n";
	delete drpc;
    }
}

tamed void
xferPlugin_xset::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    dwarn(DEBUG_SET) << "xferPlugin_xset::get_bitmap: called for " << oid->id
		     << " from " << (*hints)[0].name << "\n";
    
    xp->xp_get_bitmap(oid, hints, cb);
}

xferPlugin_xset::xferPlugin_xset(gtcd *m, xferPlugin *next_xp)
    : m(m), xp(next_xp)
{
    assert(m); assert(xp);
    if (!odht_ip) 
	odht_ip = get_odht_ip();
    
    if (!odht_ip) {
	fatal << "No odht rendezvous point\n";
    }

    warn << "Setting " << odht_port << " " << odht_ip << "\n";
}

 
/*optimizer interface*/

//TODOBINDU
/*
1. check push_back hint in insert_chunk_cache - ok
3. detect similar hints in get_chunks when i insert into hintvector - ok
4. what happens when a shingle has no hits in oids or hints --> check - shd be ok
6. check for deletion stuff cid_done and oid_done -- done
7. as soon as the lookup is finished, dht calls update_hints as he gets info. if the xfer plugin - done
does not have any outstanding stuff he can neglect it. also shd put hints in get_chunks call
11. make chunk cache to have unique hints - ok
12. get_chunks -- shd i insert default hint into chunkcache - inserting done
9. when i call update gtc might not have those descriptors in the missing list or waiting q - shd be ok since i am sending the stuff in get_chunks too
16. confirm opendht rpcs new data structures
15. TAME overcalled error
20. when shingle id and oid are same for a file with 1 shingle - use appnum
13. call back finish_getoid is weird since can't call back tamed function


2. look at vec and not vector
5. check oid in getoid_rpc class from derived class
8. get_descriptors from xp directly
10. more efficient matching right now O(N2)
11. share same connection to all rpc calls
12. when hints for oids come back in stages.... get_descriptors will not start until all hints have come back
14. change oidl_cb to cbs call back type - done


17. IMP when u have a ptr<> it has to be initialized can't be NULL
18. all the redefinitions in xfer and storage plugin
19. put 20byte strings in oid
20. Check SEND_SIZE for odht rpc calls
------

partial sources

1. duplication of put procedures - ok
2. global way of getting hints
3. stop the bitmap exchange after the download is done and delete the oid cache entry

 if (shingles_done <= 0 && oids_done <= 0 && oid_insert_done <= 0) {
	
	//all this entry's work is done
	//explicity remove getoid objects from hashtable since they are not ref counted
	dht_getoid_rpc *drpc = oidstatus.first();
	
	while (drpc != NULL) {
	    
	    warn << "oid_netcache_entry::del_getoid_rpc for " << drpc->oid <<"\n";
	    oidstatus.remove(drpc);
	    delete drpc;
	    drpc = oidstatus.first();
	}
	
	//will take care of getcid objects and oidinsert_status
	delete this; 
    }

4. do i refresh the shingle to oid mapping too may be not in the course of this download

5. when refreshing the oid->src mapping, currently doing 2 for loops for choosing unique srcs

6. when obtaining bitmaps, if all descs are present stop refreshing and mark as seed.


	dht_getoid_rpc *drpc = oidstatus[other_oid];
	
	ref<vec<dot_descriptor> > missing_descs = New refcounted<vec<dot_descriptor> >;
	ref<hv_vec> missing_hints = New refcounted<hv_vec> ;
	
	unsigned int match = 0;
	
	//match the descriptors and insert hints into chunk cache and call update finally
	for (size_t i = 0; i < self_descs->size(); i++) {
	    
	    ref<vec<oid_hint> > new_hints = New refcounted<vec<oid_hint> >;
	    
	    for (size_t j = 0; j < (drpc->descs)->size() ; j++) {
		
		if ((*self_descs)[i].id == (*(drpc->descs))[j].id ) {
		    
		    match++;
		    
		    //warn << "match in descriptors " << (*self_descs)[i].id << "\n";
		    
		    bool fresh_hints = xferPlugin_xset::insert_chunk_cache((*self_descs)[i].id, drpc->hints, new_hints);
		    
		    //warn << "New hints " << fresh_hints << "\n";
		    
		    if (fresh_hints) {

			missing_descs->push_back((*(drpc->descs))[j]);
			missing_hints->push_back(new_hints);
		    } //fresh_hints
		    
		    break;
		} //if
	    }
	} //for all chunks
	
	//warn << "oid_netcache_entry::net_lookup_oid_done: matched " << match <<"\n";
	
	if (missing_descs->size() > 0) {
	    //update_hints call back deployed
	    (*cb)(missing_descs, missing_hints);
	}

7. the bitmap once obtained, is always assumed to be true ie new bitmaps are addiitions to old ones not entirely new

8. can't share info across oid lookups

9. take care of deleting src_info

10. if two new hints are the same, they are picked twice

11. Refresh oid can be intelligent for similar sources, back off on bitmap updates if no changes
*/
