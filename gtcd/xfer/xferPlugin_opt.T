/*
 * Copyright (c) 2005-2008 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_opt.h"
#include <math.h>

opt_matrix mat;

//statistics
static unsigned int total_opt_calls = 0;
unsigned int total_disk_calls = 0;
static unsigned int total_compute_calls = 0;

unsigned int pressure_disk = 0;
unsigned int pressure_nw = 0;
static unsigned int pressure_cpu = 0;
unsigned int pressure_aiod = 0;

static unsigned int total_blocks = 0;
unsigned int xdisk_blocks = 0;
unsigned int xdisk_bytes = 0;
unsigned int net_blocks = 0;
unsigned int net_dup_blocks = 0;
unsigned int net_bytes = 0;
unsigned int net_dup_bytes = 0;

static unsigned int hint_tracker = 0;
bool is_end_game = true;

bool abort_flag = false;

#ifdef TIME_SERIES
int print_interval = 1;
double chunk_start = 0;
double chunk_last = 0;
int xdisk_time_bytes = 0;
int net_time_bytes = 0;
int xdisk_raw_time_bytes = 0;
int net_raw_time_bytes = 0;
#endif

#ifdef TIME_TRACE
double start_dump = 0;
#endif

void
heap_impl::heap_clear()
{
    v.clear();
}

void
heap_impl::print_vec()
{
    //debug
    DPRINTF(DEBUG_OPT, debug_sep);
    for (size_t i = 0; i < v.size(); i++)
	DPRINTF(DEBUG_OPT, "%s --> %f\n", (v[i])->id.cstr(), (v[i])->cpb);
    DPRINTF(DEBUG_OPT, debug_sep);
}

void
heap_impl::heap_push(os_entry *ose)
{
    v.push_back(ose);
    push_heap(v.begin(), v.end(), Compare_os_entry());
    //warnx("After heap push\n");
    //print_vec();
}

void
heap_impl::heap_pop(os_entry *ose)
{
    //warnx("Before heap pop\n");
    //print_vec();
    os_entry *t = v.front();
    if (t->id != ose->id) {
        fatal << "not popping first element\n";
    }
    pop_heap(v.begin(), v.end(), Compare_os_entry());
    os_entry *g = v[v.size()-1];
    v.pop_back();
    if (g->id != t->id) 
	fatal << "What did i pop\n";
    //warnx("After heap pop\n");
    //print_vec();
}

os_entry *
heap_impl::heap_top()
{
    return v.front();
}

void
heap_impl::heap_make()
{
    //warnx << "heap_impl::heap_make()\n";
    make_heap(v.begin(), v.end(), Compare_os_entry());
    //print_vec(v);
}

void
heap_impl::heap_sort(ptr<vec<str > > op)
{
    std::vector<os_entry *> s = v;
    
    //warnx("After heap copy\n");
    //print_vec(s);
    sort_heap(s.begin(), s.end(), Compare_os_entry());
    //dwarn(DEBUG_OPT) << "After heap sort " << s.size() << "\n";
    //print_vec();
    
    for (int i = s.size() - 1; i >= 0; i--) {
	op->push_back((s[i])->id);
    }
}
/*********************/
void
opt_matrix::dump_hints()
{
    return;
    warnx << debug_sep << "Hints -->\n";
    size_t size = mat.s.size();
    ht_entry *hte;
    for (size_t i = 0; i < size; i++) {
	hte = mat.s[i]; 
	if (hte) 
	    if (hte->hints->size())
		warnx << (*(hte->hints))[0].target_dir
		      << (*(hte->hints))[0].name << "\n";
    }
    warnx << debug_sep;
}

void
opt_matrix::dump_table()
{
    warnx << debug_sep << "Cols -->\n";
    ds_entry *dse;
    for (dse = mat.desc_store.first(); dse; dse = mat.desc_store.next(dse)) {
	warnx << dse->desc << "\n";
    }
    warnx << "Rows -->\n";
    os_entry *ose;
    for (ose = mat.op_store.first(); ose; ose = mat.op_store.next(ose)) {
	warnx << ose->id << "\n";
    }
    warnx << debug_sep << "Hints -->\n";
    ht_entry *hte;
    for (hte = mat.hint_store.first(); hte; hte = mat.hint_store.next(hte)) {
	warnx << "hint\n";
    }
    warnx << debug_sep;
}

void
opt_matrix::add_col(ds_entry *dse)
{
    if (desc_store[dse->desc]) {
	dwarn(DEBUG_OPT) << "Duplicate descriptor\n";
	return;
    }
    desc_store.insert(dse);
}

void
opt_matrix::delete_col(dot_desc d)
{
    ds_entry *dse = desc_store[d];
    desc_store.remove(dse);
    delete dse;
}

void
opt_matrix::add_row(os_entry *ose)
{
    if (op_store[ose->id]) {
	dwarn(DEBUG_OPT) << "Duplicate op\n";
	return;
    }
    op_store.insert(ose);
    heap->heap_push(ose);
}

void
opt_matrix::delete_row(str opid)
{
    os_entry *ose = op_store[opid];
    op_store.remove(ose);
    delete ose;
}

void
opt_matrix::refresh_rows_complete()
{
    heap->heap_make();
}

void
opt_matrix::sort_rows(ptr<vec<str > > op)
{
    heap->heap_sort(op);
}

void
opt_matrix::sort_cols()
{
    s.clear();
        
    ht_entry *hte;
    for (hte = mat.hint_store.first(); hte; hte = mat.hint_store.next(hte)) {
	s.push_back(hte);
    }
    
    sort(s.begin(), s.end(), Compare_ht_entry());

    //DPRINTF(DEBUG_OPT, "--------------------------------------------\n"); 
    //DPRINTF(DEBUG_OPT, "After sort_cols\n"); 
    //for (size_t i = 0; i < s.size(); i++) { 
    //DPRINTF(DEBUG_OPT, "%d --> %f\n", s[i]->num, (s[i])->avail); 
    //} 
    //DPRINTF(DEBUG_OPT, "--------------------------------------------\n"); 
}

os_entry *
opt_matrix::extract_min_row()
{
    return heap->heap_top();
}

/**********ht_entry**************************************/
static str
hash_hint_function(ref<vec<oid_hint> > oh)
{
    hint_vec v;
    v.hints = *oh;

    hint_hash h;
    if (!sha1_hashxdr (&h, v))
	return NULL;
    return str(h.base(), h.size());
}

ht_entry::ht_entry(str k, ptr<vec<oid_hint> > oh,
		   ds_entry *a)
    :oidhint(oh)
{
    key = k;
    counter = 0;
    
    a->hint_index = 0 ;
    a->hint_ptr = this;
    
    desc_vec = New refcounted<vec<ds_entry *> >;
    desc_vec->push_back(a);
    counter++;
    
    hints = New refcounted<vec<xdisk_hint> >;
    spl_hints = New refcounted<vec<vec<const char *> *> >;
    sp_ptr = New refcounted<vec<char *> >;
    
    avail = -1;

    //opt
    ask = a->ask;
    cur_ask_pos = ask ? 1 : 0;
    
    //debug
    num = hint_tracker;
    hint_tracker++;

    mat.hint_store.insert(this);
    mat.s.push_back(this);
    
    dwarn(DEBUG_OPT) << "Creating new hint " << num << "\n";
}

ht_entry::~ht_entry()
{
    dwarn(DEBUG_OPT) << "Deleting hint " << num << "\n";
    mat.hint_store.remove(this);
    size_t size = mat.s.size();
    for (size_t i = 0; i < size; i++) {
	if (mat.s[i] == this) {
	    mat.s[i] = NULL;
	    break;
	}
    }
    size = spl_hints->size();
    for (size_t i = 0; i < size; i++) {
	free((*sp_ptr)[i]);
	(*spl_hints)[i]->clear();
	delete (*spl_hints)[i];
    }
}

void
ht_entry::add_desc(ds_entry *a)
{
    desc_vec->push_back(a);
    a->hint_ptr = this;
    a->hint_index = desc_vec->size() - 1; 
    counter++;

    //opt
    ask = ask && a->ask;
    if (ask)
	cur_ask_pos = a->hint_index + 1;
}

void
ht_entry::remove_desc(ds_entry *a)
{
    (*desc_vec)[a->hint_index] = NULL;
    counter--;
}
/**********ht_entry**************************************/

/**********ds_entry**************************************/
ds_entry::ds_entry(chunk_cb cb, dot_descriptor dot_des)
{
    dd = dot_des;
    desc = dot_des.id;
    ccb.push_back(cb);
    ask = false;

    hint_ptr = NULL;
    hint_index = -1;
    backup_hint = NULL;
    ordernum = total_blocks;

    mat.add_col(this);
}

ds_entry::~ds_entry()
{
    delete_from_hint();
}

void
ds_entry::update_info(chunk_cb cb)
{
    ccb.push_back(cb);
    ordernum = total_blocks;
}

void
ds_entry::delete_from_hint()
{
    hint_ptr->remove_desc(this);
    if (hint_ptr->counter <= 0)
	delete hint_ptr;
}

void
ds_entry::print_hints()
{
    warnx << "ds_entry::ds_entry: Printing hints for " << desc << "\n";
    for (size_t i = 0; i < hint_ptr->oidhint->size(); i++) {
	warnx << (*(hint_ptr->oidhint))[i].name << "\n";
    }
}

void
ds_entry::cancel()
{
    ask = false;
    hint_ptr->ask = false;
    if (hint_ptr->cur_ask_pos > hint_index)
	hint_ptr->cur_ask_pos = hint_index;
}

/**********ds_entry**************************************/
void
xferPlugin_opt::matrix_add_descs(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		 chunk_cb cb)
{
    //create columns for the incoming chunks
    size_t dv_size =  dv->size();
    for (size_t i = 0; i < dv_size; i++) {
	dot_descriptor cid = (*dv)[i];
	ds_entry *dse = mat.desc_store[cid.id];
	total_blocks++;
	if (!dse) {
	    dse = New ds_entry(cb, cid);
	    cur_change_chunks++;
	}
	else 
	    dse->update_info(cb);
	
	dwarn(DEBUG_OPT&DEBUG_L1) << "Fetching " << dse->desc << "\n";
    }
    dwarn(DEBUG_OPT&DEBUG_L1) << debug_sep;
}

void
xferPlugin_opt::matrix_add_ops(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
			       chunk_cb cb)
{
    size_t dv_size =  dv->size();
    for (size_t i = 0; i < dv_size; i++) {
	dot_descriptor cid = (*dv)[i];
	ref<vec<oid_hint > > h = (*hints)[i];
	
	ds_entry *dse = mat.desc_store[cid.id];
	if (!dse)
	    fatal << "I just put in the descriptor\n";
	
	//extract cache hit op first
	os_entry *last = *(mat.pending_q.plast);
	xfplugins[XDISK]->xp_get_ops(NULL, cid);
	if (*(mat.pending_q.plast) != last) {
	    if (!dse->backup_hint)
		dse->backup_hint = New refcounted<vec<oid_hint > >;
	    //make a copy of the hints
	    size_t hsize = h->size();
	    for (size_t k = 0; k < hsize; k++) 
		dse->backup_hint->push_back((*h)[k]);

	    matrix_add_hint(dse, NULL);
	    continue;
	}

	matrix_add_hint(dse, h);
	//extract other ops now if new hint
	if (dse->hint_ptr->counter == 1) 
	    xfplugins[XDISK]->xp_get_ops(dse->hint_ptr->key, cid);
    }

    othertypes_notify_new_ops(0);
    matrix_add_ops_fromq();
    dwarn(DEBUG_OPT) << debug_sep;
}

void
xferPlugin_opt::matrix_add_ops_fromq()
{
    os_entry *ose = mat.pending_q.first;
    if (ose)
	mat.dump_hints();
    while (ose != NULL) {
	cost_per_block(ose);
	cur_change_chunks += ose->sum_p;
	ose->it_num = cur_iteration + 1;
	
	mat.add_row(ose);
	
	mat.pending_q.remove(ose);
	ose = mat.pending_q.first;
    }
    //mat.heap->print_vec();
}

void 
xferPlugin_opt::matrix_add_hint(ds_entry *dse, ptr<vec<oid_hint> > oh)
{
    if (!oh) {
	if (dse->hint_ptr) {
	    if (dse->hint_ptr->key != "CACHE_HIT")
		fatal << "How possible is it?\n";
	    return;
	}
	
	//this is cache hint
	str key("CACHE_HIT");
	ht_entry *hte = mat.hint_store[key];
	if (hte) 
	    hte->add_desc(dse);
	else 
	    hte = New ht_entry(key, oh, dse);
	
	dwarn(DEBUG_OPT&DEBUG_L1) << "matrix_add_hint:: Create Hint "
				  << dse->dd.id << " " << hte->num
				  << " " << dse->hint_index << "\n";
	return;
    }

    ptr<vec<oid_hint> > mine;
    if (dse->hint_ptr) {
	mine =  New refcounted<vec<oid_hint > >(*(dse->hint_ptr->oidhint));
	size_t oh_size = oh->size();
    	//update the hints
	for (size_t j = 0; j < oh_size; j++) {
	    oid_hint oh_hint = (*oh)[j];
	    bool match = false;
	    size_t mine_size = mine->size();
	    for (size_t i = 0; i < mine_size; i++) 
		if (oh_hint.name == (*mine)[i].name) {
		    match = true;
		    break;
		}
	    	
	    if (!match) 
		mine->push_back(oh_hint);
	}
	
	dwarn(DEBUG_OPT&DEBUG_L1) << "matrix_add_hint:: Update Hint " << dse->dd.id << " "
				    << dse->hint_ptr->num << " " << dse->hint_index << "\n";

	if (mine->size() == dse->hint_ptr->oidhint->size())
	    return;
	
	//delete myself from my old hint
	dse->delete_from_hint();
    }
    else 
	mine = oh;
    
    str key = hash_hint_function(mine);
    ht_entry *hte = mat.hint_store[key];
    if (hte) 
	hte->add_desc(dse);
    else {
	if (mine == oh)
	    mine = New refcounted<vec<oid_hint > >(*(oh));
	hte = New ht_entry(key, mine, dse);
    }
    
    dwarn(DEBUG_OPT&DEBUG_L1) << "matrix_add_hint:: Hint " << dse->dd.id
			      << " " << hte->num << " " << dse->hint_index << "\n";
    return;
}

void
xferPlugin_opt::matrix_remove_op(str opid)
{
    os_entry *ose = mat.op_store[opid];
    double change = ose->sum_p - ose->success;
    if (change < 0) {
	change = 0;
    }
    cur_change_chunks += change;

    mat.delete_row(opid);
    othertypes_notify_new_ops(1);
    matrix_add_ops_fromq();
}

#ifdef DISK_ONLY
static int get_chunk_count = 0;
static struct timeval start,end;
#endif

tamed void 
xferPlugin_opt::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb)
{
#ifdef DISK_ONLY
    get_chunk_count++;
    gettimeofday(&start, NULL);
#endif
    
#ifdef TIME_TRACE
    start_dump = return_time(SECONDS);
#endif

    matrix_add_descs(dv, hints, cb);
    matrix_add_ops(dv, hints, cb);
 
    is_end_game = false;
    
    //debug
    //print hints
    /*   for (size_t i = 0; i < dv_size; i++) { */
    /*     	dot_desc cid = (*dv)[i].id; */
    /*     	ds_entry *dse = mat.desc_store[cid]; */
    /*     	dse->print_hints(); */
    /*     } */
    /*     mat.dump_table(); */
    
    perform_optimization();
}

void
xferPlugin_opt::get_chunks_cb(str opid, unsigned int plugin, str s, ptr<desc_result> res)
{
    if (res == NULL && s) {
	//error in operation (can be net or disk)
	warnx << "get_chunks_cb:: something wrong in get_chunks "
	      << plugin << "\n";
	if (plugin == XDISK) {
	    disk_busy = false;
	    cur_disk_op = NULL;
	    matrix_remove_op(opid);
	}
    }
    else if (res == NULL && !s) {
	//disk operation completed
	assert(plugin == XDISK);
	disk_busy = false;
	cur_disk_op = NULL;

	fprintf(stderr, "xferPlugin_opt::pick_xdisk_op: Completed %s with %d blocks and Time %f\n",
		mat.op_store[opid]->id.cstr(), mat.op_store[opid]->success, mat.op_store[opid]->time);

        //change for del row and adding rows
	matrix_remove_op(opid);
	//mat.dump_table();
    }
    else {
	ds_entry *dse = mat.desc_store[res->desc->id];

        if (plugin == XDISK) {
	    if (dse && dse->hint_ptr->hints->size())
		dwarn(DEBUG_OPT) << "xferPlugin_opt::get_chunks_cb: Just got back from XDISK "
				 << res->desc->id << " " << (*(dse->hint_ptr->hints))[0].target_dir
				 << (*(dse->hint_ptr->hints))[0].name << "\n";
	    else
		dwarn(DEBUG_OPT) << "xferPlugin_opt::get_chunks_cb: Just got back from XDISK "
				 << res->desc->id << "\n";

	    if (dse) {
#ifdef DISK_ONLY
		//got first useful chunk from disk, so claim done
		gettimeofday(&end, NULL);
		fprintf(stderr, "time for disk data search-time == %.4f\n",
			timeval_diff(&start, &end));
		xp_dump_statistics();
		exit(1);
#endif		
		mat.op_store[opid]->success++;
		xdisk_blocks++;
		xdisk_bytes += dse->dd.length;
#ifdef TIME_SERIES
		xdisk_time_bytes += dse->dd.length;
#endif
		//if asked from NET, can we cancel it please
		if (dse->ask)
		    cancel_chunk(res->desc, wrap(this, &xferPlugin_opt::cancel_from_net, dse->desc));
#ifdef TIME_TRACE
	        str buf = strbuf() << res->desc->id;
  	        fprintf(stdout, "DUMPLOG %s %f -1\n", buf.cstr(), (return_time(SECONDS)-start_dump));
#endif
	    }
	    else {
		DPRINTF(DEBUG_OPT, "xferPlugin_opt::get_chunks_cb: Duplicate XDISK work\n");
		/* xdisk doesn't have dups since the data is not returned from xdisk if the desc
		  is not in the table */
	    }
	}
	else if (plugin == NET) {
	    if (dse && dse->hint_ptr->hints->size())
		dwarn(DEBUG_OPT) << "xferPlugin_opt::get_chunks_cb: Just got back from NET "
				 << res->desc->id << " " << (*(dse->hint_ptr->hints))[0].target_dir
				 << (*(dse->hint_ptr->hints))[0].name << "\n";
	    else
		dwarn(DEBUG_OPT) << "xferPlugin_opt::get_chunks_cb: Just got back from NET "
				 << res->desc->id << "\n";
	    missd_entry *msd = missing_net[res->desc->id];
	    assert (msd);
	    missing_net.remove(msd);
	    net_scheduled--;
	    if (net_scheduled < 0)
		net_scheduled = 0;
	    
	    if (dse) {
		net_blocks++;
		net_bytes += dse->dd.length;
#ifdef TIME_SERIES
		net_time_bytes += dse->dd.length;
		net_raw_time_bytes += dse->dd.length;
#endif
#ifdef TIME_TRACE
	        str buf = strbuf() << res->desc->id;
                fprintf(stdout, "DUMPLOG %s %f 1\n", buf.cstr(), (return_time(SECONDS)-start_dump));
#endif
	    }
	    else {
		DPRINTF(DEBUG_OPT, "xferPlugin_opt::get_chunks_cb: Duplicate NET work\n");
		net_dup_blocks++;
#ifdef TIME_SERIES
		net_dup_bytes += res->desc->length;
		net_raw_time_bytes += res->desc->length;
#endif
	    }
	}
	
	if (dse) {
	    cur_change_chunks++;
	    size_t ccb_size = dse->ccb.size();
	    for (size_t in = 0; in < ccb_size; in++) {
		chunk_cb cb = dse->ccb[in];
		(*cb)(s, res);
	    }
	    mat.delete_col(dse->desc);
	}

	if (mat.desc_store.size() <= 0) 
	   abort_flag = true;
    }

    perform_optimization();
}

tamed void
xferPlugin_opt::perform_optimization()
{
    tvars {
	str err;
	ptr<opt_result> res;
    }
    
    total_opt_calls++;
    cur_iteration++;

    dwarn(DEBUG_OPT) << debug_sep;
   
    twait {
	if (opt_type == "random")
	    random_pick_op_descs(mkevent (err, res));
	else if (opt_type == "bfs")
	    bfs_pick_op_descs(mkevent (err, res));
	else if (opt_type == "allstats")
	    allstats_pick_op_descs(mkevent (err, res));
	else
	    pick_op_descs(mkevent (err, res));
    }

    if (err) {
	warnx << "Error in optimization\n";
	return;
    }
    
    if (res->missing_xdisk_hints) {
	xfplugins[XDISK]->xp_get_chunks(res->missing_xdisk, res->missing_xdisk_hints,
					wrap(this, &xferPlugin_opt::get_chunks_cb, cur_disk_op, XDISK));
    }
    
    if (res->missing_net && res->missing_net->size() > 0) {
#ifdef DISK_ONLY
	//to get td and stuff, make this 1
	if (get_chunk_count <= 0)
#endif
	    xfplugins[NET]->xp_get_chunks(res->missing_net, res->missing_net_hints,
					  wrap(this, &xferPlugin_opt::get_chunks_cb, err, NET));
    }

    dwarn(DEBUG_OPT) << debug_sep;
}

tamed void
xferPlugin_opt::pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb)
{    
    ptr<opt_result> res = New refcounted<opt_result>;
    
    bool p1 = pressure_from_client();
    bool p2 = pressure_from_network();
    bool p3 = pressure_from_computation();

    if (p1) pressure_disk++;
    if (p2) pressure_nw++;
    if (p3) pressure_cpu++;
    
    bool disk_pressure =  p1 || p2;
    bool cpu_pressure = disk_pressure || p3;
	
    pick_block_alloc(res);
    
    if (!disk_pressure) {
	dwarn(DEBUG_OPT) << "No pressure from disk\n";
	pick_xdisk_op(res);
    }

    if (!cpu_pressure) {
	dwarn(DEBUG_OPT) << "No pressure from CPU\n";
	if (!cpu_busy) {
	    cpu_busy = true;
	    delaycb(0, 0, wrap(this, &xferPlugin_opt::pick_computation));
	}
	else
	    dwarn(DEBUG_OPT) << "Cpu already busy\n";
    }

    (*cb)(NULL, res);
}

bool
xferPlugin_opt::pressure_from_computation()
{
    if (!pressure)
	return false;

    double inter_arrival = return_time(CYC_SEC) - last_opt_time;
    DPRINTF(DEBUG_OPT, "pressure_from_computation:: opt_time is %f and inter_arrival is %f\n", opt_time,
	    inter_arrival);
    
    if (opt_time && opt_time > inter_arrival/10)
	return true;
	
    int perc_change = THRESH_CHANGE + 1;
    if (prev_pending_chunks > 0) 
	perc_change = (100 * (int) cur_change_chunks)/prev_pending_chunks;
    
    DPRINTF(DEBUG_OPT, "Perc_change is %d\n", perc_change);
    
    if (perc_change > THRESH_CHANGE) 
	return false;
    
    return true;
}

void
xferPlugin_opt::pick_computation()
{    
    dwarn(DEBUG_OPT) << debug_sep;
    dwarn(DEBUG_OPT) << "Performing computation\n";
    double time = return_time(CYC_SEC);
    prev_pending_chunks = mat.desc_store.size();
    cur_change_chunks = 0;
    unsigned int row_count = 0;
    unsigned int col_count = 0;
    
    //compute rows first
    os_entry *ose = mat.op_store.first();
    if (ose) {
	mat.dump_hints();
	while (ose != NULL) {
	    row_count++;
	    if (ose->type >= SET_XFER) {
		//not xdisk op
		ose = mat.op_store.next(ose);
		continue;
	    }
	    
	    //update only old ops
	    if (ose->it_num != cur_iteration) {
		cost_per_block(ose);
		ose->it_num = cur_iteration;
	    }
	    
	    ose = mat.op_store.next(ose); 
	}
	
	mat.refresh_rows_complete();
	//mat.heap->print_vec();
	
	if (MIN_BLOCKS < ALL_BLOCKS && !is_end_game) {
	    //compute cols now
	    ptr<vec<str > > r = New refcounted<vec<str > >;
	    //push the current op
	    if (cur_disk_op)
		r->push_back(cur_disk_op);
	    mat.sort_rows(r);
	    
	    ht_entry *hte = mat.hint_store.first();
	    
	    //only if there is something to compute
	    if (hte)
		total_compute_calls++;
	    
	    while (hte != NULL) {
		col_count++;
		desc_avail(hte, r);
		hte = mat.hint_store.next(hte);
	    }
	    
	    mat.sort_cols();
	    net_scheduled = 0;
	    mat.dump_hints();
	}
    } //some ops exist

    last_opt_time = return_time(CYC_SEC);
    opt_time = last_opt_time - time;
    cpu_busy = false;

    fprintf(stderr, "xferPlugin_opt::pick_computation: Completed computation for %d x %d = %d in time %f\n",
	    row_count, col_count, row_count*col_count, opt_time);
    DPRINTF(DEBUG_OPT, "Time taken is %f\n", opt_time);
    dwarn(DEBUG_OPT) << debug_sep;
}

void
xferPlugin_opt::cost_per_block(os_entry * ose)
{
    float sum_p = 0;
    float sum_cost = 0;
    ose->sum_p = 0;
    ose->sum_cp = 0;
    ose->cpb = LARGE_COST;

    DPRINTF(DEBUG_OPT,"%s", debug_sep.cstr());
    DPRINTF(DEBUG_OPT, "cost_per_block for %s\n", ose->id.cstr());

    if (ose->type == DISK_CHIT) {
	sum_p = ose->get_benefit(NULL);
	sum_cost = ose->get_xfer_cost(NULL) * sum_p;

	ose->sum_p = sum_p;
	ose->sum_cp = sum_cost;
		
	if (ose->sum_p != 0) {
	    ose->cpb = (ose->get_cost() + ose->sum_cp)/(ose->sum_p);
	}
    }

    if (ose->type == DISK_HASH) {
	ht_entry *hte;
	for (hte = mat.hint_store.first(); hte; hte = mat.hint_store.next(hte)) {
	    float p = ose->get_benefit(hte);
	    //sum_p += hte->counter * p;
	    sum_p = max(sum_p, hte->counter * p);
	}

	ose->sum_p = sum_p;
	ose->sum_cp = sum_cost;
		
	if (ose->sum_p != 0) {
	    ose->cpb = (ose->get_cost() + ose->sum_cp)/(ose->sum_p);
	}
    }

    double adj = -1;
    if (ose->type == DISK_STAT) {
	ht_entry *hte;
	for (hte = mat.hint_store.first(); hte; hte = mat.hint_store.next(hte)) {
	    double p = ose->get_benefit(hte);
	    sum_p += hte->counter * p;
	    adj = max(adj, p);
	}

	ose->sum_p = sum_p;
	ose->sum_cp = ose->get_xfer_cost(NULL)*sum_p;

	if (ose->sum_p != 0) {
	    ose->cpb = (ose->get_cost() + (ose->sum_cp/adj))/(ose->sum_p);
	    ose->cpb = ADJ_WT * ose->cpb;
	}
    }
    
    DPRINTF(DEBUG_OPT, "cost_per_block --> cpb %f || opcost %f || sump %f || xfercost %f || adj %f\n",
	    ose->cpb, ose->get_cost(), ose->sum_p, ose->sum_cp, adj);
    DPRINTF(DEBUG_OPT,"%s", debug_sep.cstr());
}

void
xferPlugin_opt::desc_avail(ht_entry * hte, ptr<vec<str > > r)
{
    os_entry *ose;
    float p_prod = 1;
    float avail = 0; //LARGE_COST;
    float p, cost;
    float NET_COST = 0.2; //seconds to get a 16KB chunk on a 0.5Mbps link
    
    //sorted order of ops
    //the formula is Cop1 + (1-p1)Cop2 + (1-p1)(1-p2)Cop2+....
    //we let it fall off the end
    size_t k = r->size();
    for (size_t i = 0; i < k; i++) {
	ose = mat.op_store[(*r)[i]];
	cost = ose->get_cost() + ose->sum_cp;
	avail += p_prod * cost;
	p = ose->get_benefit(hte);
	//DPRINTF(DEBUG_OPT, "%s cost is %f p is %f and next p %f\n",
	//ose->id.cstr(), cost, p_prod, p);
	p_prod = p_prod * (1-p);
    }
    avail += p_prod * NET_COST;
    //DPRINTF(DEBUG_OPT, "desc_avail cost is %f p is %f\n", NET_COST, p_prod);
    
    hte->avail = avail;
    if (hte->hints->size())
	DPRINTF(DEBUG_OPT, "%s/%s desc_avail %f\n", (*(hte->hints))[0].target_dir.cstr(),
		(*(hte->hints))[0].name.cstr(), avail);
    else
	DPRINTF(DEBUG_OPT, "desc_avail %f\n", avail);
    
}

void
xferPlugin_opt::pick_xdisk_op(ptr<opt_result> res)
{
    double THRESHOLD_COST_CHANGE = 0.001;
	
    res->missing_xdisk = NULL;
    res->missing_xdisk_hints = NULL;
        
    ds_entry *dse = mat.desc_store.first();
    os_entry *ose = mat.op_store.first();
    
    //no more descriptors or ops or disk is busy
    if (!dse || !ose || disk_busy) 
	return;

    total_disk_calls++;
    if (ose)
	mat.dump_hints();
    while (1) {
	ose = mat.extract_min_row();
	
	if (ose->it_num == cur_iteration)
	    break;
	
	double c = ose->cpb;
	cost_per_block(ose);
	ose->it_num = cur_iteration;
	double diff = fabs(ose->cpb - c);
	//old cost is the almost the same as new cost
	if (diff < THRESHOLD_COST_CHANGE)
	    break;
	
	DPRINTF(DEBUG_OPT, "Diff is %f for %s\n", diff, ose->id.cstr());
	mat.heap->heap_pop(ose);
	mat.heap->heap_push(ose);
		
	os_entry *os_new = mat.extract_min_row();
	if (os_new->id == ose->id) {
	    break;
	}
    }
    
    str opid = ose->id;
    //have to pop the heap here
    mat.heap->heap_pop(ose);
    cur_disk_op = opid;
    disk_busy = true;

    res->missing_xdisk  = New refcounted<vec<dot_descriptor> >; 
    res->missing_xdisk_hints = New refcounted<hv_vec >;
    ref<vec<oid_hint > > new_hint = New refcounted<vec<oid_hint > > ;
    oid_hint h;   hint_res r;
    r.hint2 = opid;
    make_hint(r, "intern", &h);
    new_hint->push_back(h);
    res->missing_xdisk_hints->push_back(new_hint);

    DPRINTF(DEBUG_OPT, "xferPlugin_opt::pick_xdisk_op: picking xdisk op %s with hint %s\n",
	    opid.cstr(), h.name.cstr());
}

void
xferPlugin_opt::cancel_from_net(dot_desc desc, ptr<vec<nw_status> > status)
{
    if ((*status)[0] == CANCELLED) {
	missd_entry *msd = missing_net[desc];
	if (msd) {
	    missing_net.remove(msd);
	    net_scheduled--;
	    if (net_scheduled < 0) 
		net_scheduled = 0;
	    ds_entry *dse = mat.desc_store[desc];
	    if (dse)
		dse->cancel();
	}
    }
}

tamed void
xferPlugin_opt::pick_block_alloc(ptr<opt_result> res)
{
    tvars {
	ptr<vec<nw_status> > status;
	ds_entry *dse;
	missd_entry *msd;
	ptr<vec<dot_descriptor> > missing_net_vec;
    }
    
    res->missing_net = NULL;
    res->missing_net_hints = NULL;
        
    dwarn(DEBUG_OPT) << debug_sep;
    DPRINTF(DEBUG_OPT, "Trying to fill netq since sched is %d\n", net_scheduled);
    
    dse = mat.desc_store.first();
    if (!dse)
	return;

    if (is_end_game)
	return;
    
    //if I am reconsidering net, generate set to cancel
    if (net_scheduled <= 0) {
	missing_net_vec = New refcounted<vec<dot_descriptor> >;
	for (msd = missing_net.first(); msd; msd = missing_net.next(msd)) {
	    missing_net_vec->push_back(msd->dd);
	}

	dwarn(DEBUG_OPT) << "Cancelling chunks " << missing_net_vec->size() << "\n";

	twait {
	    cancel_chunks(missing_net_vec, mkevent(status));
	}
	
	size_t size = missing_net_vec->size();
	for (size_t i = 0; i < size; i++) {
	    if ((*status)[i] == CANCELLED) {
		msd = missing_net[(*missing_net_vec)[i].id];
		missing_net.remove(msd);
		dse = mat.desc_store[(*missing_net_vec)[i].id];
		if (!dse) continue;
		dse->cancel();
	    }
	    else
		net_scheduled++;
	}
    }

    dwarn(DEBUG_OPT) << "Net already has " << net_scheduled << "\n";
      
    int max_blocks = max(MIN_BLOCKS, (int)(mat.desc_store.size()/3));
    if (net_scheduled >= max_blocks) {
	DPRINTF(DEBUG_OPT, "Returning since filled %d\n", net_scheduled);
	return;
    }
    
    res->missing_net = New refcounted<vec<dot_descriptor> >;
    res->missing_net_hints = New refcounted<hv_vec >;
        
    size_t size = mat.s.size();
    ht_entry *hte;

    is_end_game = true;
    for (size_t i = 0; i < size; i++) {
	
	hte = mat.s[i]; 
	if (!hte) continue;
	if (hte->ask) continue; //everything has been asked

	if (net_scheduled >= max_blocks) {
	    is_end_game = false;
	    break;
	}

	int start_pt = hte->cur_ask_pos;
       	int ht_size = hte->desc_vec->size();
	ref<vec<ds_entry *> > desc_vec = hte->desc_vec;
	
	dwarn(DEBUG_OPT&DEBUG_L1) << "Hint " << i << " has stuff remaining from "
			 << start_pt << "\n";
	int j;
	for (j = start_pt; j < ht_size; j++) {

	    //if (net_scheduled >= max_blocks) break;
	    
	    dse = (*(desc_vec))[j];
	    if (!dse) continue;
	    if (dse->ask) continue;
	    
	    net_scheduled++;
	    dse->ask = true;

	    ptr<vec<oid_hint > > hint;
	    if (hte->oidhint)
		hint =  New refcounted<vec<oid_hint > >(*(hte->oidhint));
	    else {
		assert(hte->key == "CACHE_HIT"); assert(dse->backup_hint);
		hint =  New refcounted<vec<oid_hint > >(*(dse->backup_hint));
	    }
		
	    if (dse->hint_ptr->hints->size())
		dwarn(DEBUG_OPT) << "pick_block_alloc sending " << dse->desc
				 << " " << (*(dse->hint_ptr->hints))[0].target_dir
				 << (*(dse->hint_ptr->hints))[0].name << "\n";
	    else
		dwarn(DEBUG_OPT) << "pick_block_alloc sending " << dse->desc << "\n";
	    
	    res->missing_net->push_back(dse->dd);
	    res->missing_net_hints->push_back(hint);
	    missing_net.insert(New missd_entry(dse->dd));
	}

	hte->cur_ask_pos = j;
	if (j == ht_size)
	    hte->ask = true;
    }

    dwarn(DEBUG_OPT) << "Set end_game to " << is_end_game << "\n";
    DPRINTF(DEBUG_OPT, "Filled netq to atleast %d\n", net_scheduled);
    dwarn(DEBUG_OPT) << debug_sep;
    return;
}

tamed void 
xferPlugin_opt::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    xfplugins[NET]->cancel_chunk(d, cb);
}

tamed void 
xferPlugin_opt::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    xfplugins[NET]->cancel_chunks(dv, cb);
}

void 
xferPlugin_opt::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    size_t np = xfplugins.size();
    for (size_t i = 0; i < np; i++) {
	xfplugins[i]->xp_notify_descriptors(oid, descs);
    }
}

void 
xferPlugin_opt::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    fatal << "xferPlugin_opt::update_hints: called\n";
}

tamed void
xferPlugin_opt::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    dwarn(DEBUG_OPT) << "xferPlugin_opt::get_bitmap: called\n";
    xfplugins[NET]->xp_get_bitmap(oid, hints, cb);
}

//can't use twait in the functions below since the get_descriptors 
// and the get_chunks calls in xferPlugin_gtc etc call back multiple times
// and TAME thinks that the function is overcalled.
// TAME probably keeps a counter as to how many times a function call was made with in twait
// and hence allows only that many callbacks
tamed void
xferPlugin_opt::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    tvars {
	str err;
	ptr<vec<dot_descriptor> > descs;
	bool end;
    }
    twait {
	//first see if there is a cache hit in disk plugin
	xfplugins[XDISK]->xp_get_descriptors(oid, hints,
				  mkevent (err, descs, end));
    }
    
    if (err) {
	xfplugins[NET]->xp_get_descriptors(oid, hints, cb);
    }
    else {
	(*cb)(err, descs, end);
    }
}

bool
xferPlugin_opt::configure(str s, str pluginClass)
{
    opt_type = s;
    dwarn(DEBUG_OPT) << "Optimization type is " << opt_type << "\n";
    return true;
}

void
xferPlugin_opt::set_more_plugins(vec<xferPlugin*> xplist)
{
    warn << "xferPlugin_opt::set_more_plugins setting more plugins\n";
    xfplugins = xplist;
}

void
xferPlugin_opt::wrap_perform_optimization()
{
    perform_optimization();
}

xferPlugin_opt::xferPlugin_opt(gtcd *m, xferPlugin *next_xp) :
    m(m), net_scheduled(0), disk_busy(false)
{
    assert(m);
    //state for optimization
    cur_change_chunks = 0;
    prev_pending_chunks = 0;
    cur_iteration = 0;

    cur_disk_op = NULL;

    cpu_busy = false;
    opt_time = 0;
    last_opt_time = 0;
    
    opt_cb = wrap(this, &xferPlugin_opt::wrap_perform_optimization);

#ifdef TIME_SERIES
    chunk_last = return_time(SECONDS);
    delaycb(1, 0, wrap(this, &xferPlugin_opt::dump_time_series));
#endif
}

#ifdef TIME_SERIES
void
xferPlugin_opt::dump_time_series()
{
    double now = return_time(SECONDS);
    double elapsed_start = now - chunk_start;
    double elapsed_last = now - chunk_last;

    double xdisk_xput = (xdisk_time_bytes*8)/(elapsed_last*1000); //Kbps
    double net_xput = (net_time_bytes*8)/(elapsed_last*1000);

    double xdisk_raw_xput = (xdisk_raw_time_bytes*8)/(elapsed_last*1000); //Kbps
    double net_raw_xput = (net_raw_time_bytes*8)/(elapsed_last*1000);

    printf("TIMETIME %f %d %d || %f %d %d %f %f || %d %d %f %f\n", elapsed_start, xdisk_bytes, net_bytes,
	   elapsed_last, xdisk_time_bytes, net_time_bytes, xdisk_xput, net_xput,
	   xdisk_raw_time_bytes, net_raw_time_bytes, xdisk_raw_xput, net_raw_xput);

    chunk_last = now;
    xdisk_time_bytes = 0;
    net_time_bytes = 0;
    xdisk_raw_time_bytes = 0;
    net_raw_time_bytes = 0;
    delaycb(1, 0, wrap(this, &xferPlugin_opt::dump_time_series));
}
#endif

void
xferPlugin_opt::xp_dump_statistics()
{
    fprintf(stderr, "%s"
	    "OPT STATS\n"
	    "TOTAL %d , XDISK %d (%d) || NET %d (%d) DUP %d (%d)\n",
	    debug_sep.cstr(),
	    total_blocks, xdisk_blocks, xdisk_bytes,
	    net_blocks, net_bytes, net_dup_blocks, net_dup_bytes);
    
    fprintf(stderr, "CALLS %d , || DISKOPS %d COMPUTES %d\n", total_opt_calls, total_disk_calls, total_compute_calls);
    fprintf(stderr, "PRESSURE STATS DISK %d || NW %d || CPU %d || aiod %d\n", pressure_disk, pressure_nw, pressure_cpu, pressure_aiod);
    fprintf(stderr, "%s", debug_sep.cstr());

    xfplugins[XDISK]->xp_dump_statistics();
    xfplugins[NET]->xp_dump_statistics();
}

/*TODO
1. IMP - hv_vec structures that are updated are from gtcd.
2. deleting rows in cost matrix when all chunks are fetched
3. deleting from uo_entry
4. consolidate get_costs in net by using add_costs etc
5. get_hints in get_costs in net
6. async notification of hints
7. update_info for dse to ignore existing hints -> double for loop

NEED  to fix hints in cache hint group that go to xfer etc
*/
