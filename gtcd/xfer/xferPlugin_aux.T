#include "xferPlugin_opt.h"

extern opt_matrix mat;

extern unsigned int total_disk_calls;
extern unsigned int pressure_disk;
extern unsigned int pressure_nw;

//queues for bfs
static tailq<os_entry, &os_entry::blink> chit_q;
static tailq<os_entry, &os_entry::blink> hash_q;
static tailq<os_entry, &os_entry::blink> stat_q;
static str last_stat = NULL;

void
xferPlugin_opt::random_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb)
{
    ptr<opt_result> res = New refcounted<opt_result>;
    
    //added to the table and now I get here
    pick_block_alloc(res);
    random_pick_xdisk_op(res);
    (*cb)(NULL, res);
}

void
xferPlugin_opt::random_pick_xdisk_op(ptr<opt_result> res)
{
    res->missing_xdisk = NULL;
    res->missing_xdisk_hints = NULL;
    
    ds_entry *dse = mat.desc_store.first();
    os_entry *ose = mat.op_store.first();
    
    //no more descriptors or ops or disk is busy
    if (!dse || !ose || disk_busy) 
	return;

    bool p1 = pressure_from_client();
    bool p2 = pressure_from_network();

    if (p1) pressure_disk++;
    if (p2) pressure_nw++;
    
    if (p1 || p2) {
	dwarn(DEBUG_OPT) << "Pressure from disk\n";
	return;
    }

    total_disk_calls++;
    unsigned int randnum = arandom() % mat.op_store.size();
    unsigned int count = 0;
    dwarn(DEBUG_OPT) << "Randnum is " << randnum << " and size is "
		     << mat.op_store.size() << "\n";
    
    //pick a random op and send it to disk
    while (ose != NULL) {
	if (count == randnum) break;
	ose = mat.op_store.next(ose);
	count++;
    }

    if (!ose)
	fatal << "Why didnt anything get picked\n";
    
    cur_disk_op = ose->id;
    disk_busy = true;

    res->missing_xdisk = New refcounted<vec<dot_descriptor> >;
    res->missing_xdisk_hints = New refcounted<hv_vec >;
    ref<vec<oid_hint > > new_hint = New refcounted<vec<oid_hint > > ;
    oid_hint h;   hint_res r;
    r.hint2 = ose->id;
    make_hint(r, "intern", &h);
    new_hint->push_back(h);
    res->missing_xdisk_hints->push_back(new_hint);

    DPRINTF(DEBUG_OPT, "xferPlugin_opt::pick_xdisk_op: picking xdisk op %s with hint %s\n",
	    cur_disk_op.cstr(), h.name.cstr());
}

/***BFS***/

void
xferPlugin_opt::bfs_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb)
{
    ptr<opt_result> res = New refcounted<opt_result>;
    
    //added to the table and now I get here
    pick_block_alloc(res);
    bfs_pick_xdisk_op(res);
    (*cb)(NULL, res);
}

void
xferPlugin_opt::othertypes_notify_new_ops(int mode)
{
    if (opt_type != "bfs" && opt_type != "allstats")
	return;

    dwarn(DEBUG_OPT) << "Notifying of new ops " << mode << "\n";
    if (mode == 0) {
	os_entry *ose;
	for (ose = mat.pending_q.first; ose; ose = mat.pending_q.next(ose)) {
	    if (mat.op_store[ose->id]) {
		dwarn(DEBUG_OPT) << "Duplicate op\n";
	    }
	    else if (ose->type == DISK_CHIT) {
		chit_q.insert_tail(ose);
	    }
	    else {
		assert (ose->type == DISK_STAT);
		
		if (opt_type == "bfs")
		    last_stat = ose->id;
		else 
		    stat_q.insert_head(ose);
	    }
	}
	return;
    }
    
    //this is the result of an operation
    if (mode == 1) {
	os_entry *ose;
	for (ose = mat.pending_q.first; ose; ose = mat.pending_q.next(ose)) {
	    if (mat.op_store[ose->id]) {
		dwarn(DEBUG_OPT) << "Duplicate op\n";
	    }
	    else if (opt_type == "bfs") {
		if (ose->type == DISK_HASH) 
		    hash_q.insert_tail(ose);
		else {
		    assert (ose->type == DISK_STAT);
		    //dwarn(DEBUG_OPT) << "Qing " << ose->id << "\n";
		    stat_q.insert_tail(ose);
		}
	    }
	    else if (ose->type == DISK_STAT) {
		stat_q.insert_head(ose);
	    }
	    
	}	
    }
}

void
xferPlugin_opt::bfs_pick_xdisk_op(ptr<opt_result> res)
{
    res->missing_xdisk = NULL;
    res->missing_xdisk_hints = NULL;
    
    ds_entry *dse = mat.desc_store.first();
    os_entry *ose = mat.op_store.first();
    
    //no more descriptors or ops or disk is busy
    if (!dse || !ose || disk_busy) 
	return;

    bool p1 = pressure_from_client();
    bool p2 = pressure_from_network();

    if (p1) pressure_disk++;
    if (p2) pressure_nw++;
    
    if (p1 || p2) {
	dwarn(DEBUG_OPT) << "Pressure from disk\n";
	return;
    }

    total_disk_calls++;

    if ((ose = chit_q.first)) 
	chit_q.remove(ose);
    else if ((ose = hash_q.first)) 
	hash_q.remove(ose);
    else if ((ose = stat_q.first)) 
	stat_q.remove(ose);
    else if (last_stat) {
	ose = mat.op_store[last_stat];
	last_stat = NULL;
    }
    else
	ose = mat.op_store.first();

    if (!ose)
	fatal << "Something wrong in bfs_pick_xdisk_op\n";

    cur_disk_op = ose->id;
    disk_busy = true;

    res->missing_xdisk = New refcounted<vec<dot_descriptor> >;
    res->missing_xdisk_hints = New refcounted<hv_vec >;
    ref<vec<oid_hint > > new_hint = New refcounted<vec<oid_hint > > ;
    oid_hint h;   hint_res r;
    r.hint2 = ose->id;
    make_hint(r, "intern", &h);
    new_hint->push_back(h);
    res->missing_xdisk_hints->push_back(new_hint);
    
    DPRINTF(DEBUG_OPT, "xferPlugin_opt::pick_xdisk_op: picking xdisk op %s with hint %s\n",
	    cur_disk_op.cstr(), h.name.cstr());
}

/***All stats first***/
bool
xferPlugin_opt::allstats_only_hash()
{
    os_entry *ose = mat.op_store.first();
    //there are no ops at all
    if (!ose)
	return false;

    if (chit_q.first || stat_q.first)
	return false;

    if (cur_disk_op &&
	(mat.op_store[cur_disk_op]->type == DISK_STAT ||
	 mat.op_store[cur_disk_op]->type == DISK_CHIT))
	return false;

    return true;
}

void
xferPlugin_opt::allstats_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb)
{
    if (allstats_only_hash()) {
	dwarn(DEBUG_OPT) << "Going to opt\n";
	if (last_stat == "DIRTY") {
	    //heap needs to repopulated
	    dwarn(DEBUG_OPT) << "Remaking with heap\n";
	    mat.heap->heap_clear();
	    os_entry *ose;
	    for (ose = mat.op_store.first(); ose; ose = mat.op_store.next(ose)) {
		mat.heap->heap_push(ose);
	    }
	    last_stat = "CLEAN";
	}
	pick_op_descs(cb);
	return;
    }

    ptr<opt_result> res = New refcounted<opt_result>;

    allstats_pick_xdisk_op(res);
    pick_block_alloc(res);
    (*cb)(NULL, res);
}
/* XXX - Incredible amounts of code duplication between these op picking
   functions.  Todo:  Clean them up! */
void
xferPlugin_opt::allstats_pick_xdisk_op(ptr<opt_result> res)
{
    res->missing_xdisk = NULL;
    res->missing_xdisk_hints = NULL;
    
    ds_entry *dse = mat.desc_store.first();
    os_entry *ose = mat.op_store.first();
    
    //no more descriptors or ops or disk is busy
    if (!dse || !ose || disk_busy) 
	return;

    bool p1 = pressure_from_client();
    bool p2 = pressure_from_network();

    if (p1) pressure_disk++;
    if (p2) pressure_nw++;
    
    if (p1 || p2) {
	dwarn(DEBUG_OPT) << "Pressure from disk\n";
	return;
    }

    if ((ose = chit_q.first)) 
	chit_q.remove(ose);
    else if ((ose = stat_q.first))
	stat_q.remove(ose);
     
    if (!ose) {
	fatal << "Something wrong in pick_xdisk_op\n";
    }

    total_disk_calls++;

    last_stat = "DIRTY"; //heap is dirty
    
    cur_disk_op = ose->id;
    disk_busy = true;

    res->missing_xdisk = New refcounted<vec<dot_descriptor> >;
    res->missing_xdisk_hints = New refcounted<hv_vec >;
    ref<vec<oid_hint > > new_hint = New refcounted<vec<oid_hint > > ;
    oid_hint h;   hint_res r;
    r.hint2 = ose->id;
    make_hint(r, "intern", &h);
    new_hint->push_back(h);
    res->missing_xdisk_hints->push_back(new_hint);
    
    DPRINTF(DEBUG_OPT, "xferPlugin_aux::allstats_pick_xdisk_op: picking xdisk op %s with hint %s\n",
	    cur_disk_op.cstr(), h.name.cstr());
    return;
}
