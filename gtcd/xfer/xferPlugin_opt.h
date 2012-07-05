/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_OPT_H_
#define _XFER_OPT_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"
#include "se_transfer.h"
#include "params.h"
#include "sha1.h"
#include "xferPlugin_xgtc.h"

struct opt_result {
    ptr< vec<dot_descriptor> > missing_xdisk;
    ptr< vec<dot_descriptor> > missing_net;
    ptr<hv_vec > missing_xdisk_hints;
    ptr<hv_vec > missing_net_hints;
    
    opt_result() {
	missing_xdisk = NULL;
	missing_net = NULL;
	missing_xdisk_hints = NULL;
	missing_net_hints = NULL;
    }
    ~opt_result() { }
};

class xferPlugin_opt;
class ds_entry;

class ht_entry {
public:
    str key;
    ihash_entry<ht_entry> link;
    
    ptr<vec<oid_hint> > oidhint;
    ptr<vec<xdisk_hint> > hints;

    //keeping the split hints around
    ptr<vec<vec<const char *> *> > spl_hints;
    ptr<vec<char *> > sp_ptr;
    
    unsigned int counter;
    ptr<vec<ds_entry *> > desc_vec;
    double avail;

    //opt
    bool ask;
    int cur_ask_pos; //start asking from this index
    
    //debug
    int num;

    ht_entry(str k, ptr<vec<oid_hint> > oh, ds_entry *a);
    ~ht_entry();
    void add_desc(ds_entry *a);
    void remove_desc(ds_entry *a);
};

class Compare_ht_entry {
public:
    int operator()(const ht_entry *x, const ht_entry *y) {
	    return x->avail > y->avail;
    }
};

class ds_entry {
public:
    dot_desc desc;
    ihash_entry<ds_entry> link;

    vec<chunk_cb > ccb;
    dot_descriptor dd;
    bool ask;

    ht_entry *hint_ptr;
    //index in the hint ptr's vec
    int hint_index;
    
    //if the hint grp is a cache hit,
    //we need backuphint if cache hit fails
    ptr<vec<oid_hint> > backup_hint;
    
    //debug
    int ordernum;

    ds_entry(chunk_cb cb, dot_descriptor dot_des);
    ~ds_entry();
    void update_info(chunk_cb cb);
    void print_hints();
    void delete_from_hint();
    void cancel();
};

struct item_info {
    str name;
    str file_type;
    struct stat s;
};

class os_entry {
public:
    dot_desc desc;
    str id;
    ihash_entry<os_entry> link;
    tailq_entry<os_entry> tlink;
    tailq_entry<os_entry> blink;
    
    double op_cost;
    double sum_p;
    double sum_cp;
    double cpb; //cost per block
    int it_num;
    //number of blocks
    //obtained by this operation
    unsigned int success;
    double time;

    xfer_op type;
    str path;
    
    virtual double get_cost() = 0;
    virtual void perform_op(CLOSURE) = 0;
    virtual float get_benefit(ht_entry *) = 0;
    virtual double get_xfer_cost(ht_entry *) = 0;
    virtual void dump_info() = 0;
    virtual bool is_chit_op() = 0;
    virtual ~os_entry() { };
};

class Compare_os_entry {
public:
    int operator()(const os_entry *x, const os_entry *y) {
	    return x->cpb > y->cpb;
    }
};

#include <vector>
#include <algorithm>
class heap_impl {
private:  
    std::vector<os_entry *> v;
public:
    void heap_push(os_entry *ose);
    void heap_pop(os_entry *ose);
    os_entry *heap_top();
    void heap_make();
    void heap_sort(ptr<vec<str > > op);
    void print_vec();
    void heap_clear();
};

class opt_matrix {

public:
    
    ihash<const dot_desc, ds_entry, &ds_entry::desc, &ds_entry::link, dd_hash> desc_store;
    ihash<const str, os_entry, &os_entry::id, &os_entry::link> op_store;
    ihash<const str, ht_entry, &ht_entry::key, &ht_entry::link> hint_store;

    //pending ops list
    tailq<os_entry, &os_entry::tlink> pending_q;
    //to maintain sorted ops
    heap_impl *heap;
    //to keep sorted descs
    std::vector<ht_entry *> s;

    opt_matrix() { heap = New heap_impl(); }
    ~opt_matrix() { delete heap; }
        
    void dump_table();
    void dump_hints();
    
    void add_col(ds_entry *);
    void delete_col(dot_desc);
    void add_row(os_entry *);
    void delete_row(str);

    void refresh_rows_complete();
    os_entry *extract_min_row();
    void sort_rows(ptr<vec<str > > op);
    void sort_cols();
};

class missd_entry {
public:
    dot_desc desc;
    dot_descriptor dd;
    
    ihash_entry<missd_entry> link;

    missd_entry(dot_descriptor in) : desc(in.id), dd(in) { }
    ~missd_entry();
};

class xferPlugin_opt : public xferPlugin {
  
private:
    gtcd *m;
    //state for optimization
    str opt_type;
    
    int cur_iteration;
    double cur_change_chunks;
    unsigned int prev_pending_chunks;

    //current net status
    ihash<const dot_desc, missd_entry, &missd_entry::desc, &missd_entry::link, dd_hash> missing_net;
    int net_scheduled;

    //current disk status
    str cur_disk_op;
    bool disk_busy;

    //current cpu status
    bool cpu_busy;
    double opt_time;
    double last_opt_time;
    
public:
    vec<xferPlugin*> xfplugins;
    
    bool configure(str s, str pluginClass);

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

    void set_more_plugins(vec<xferPlugin*> xplist);
    void xp_dump_statistics();
    
    xferPlugin_opt(gtcd *m, xferPlugin *next_xp);
    ~xferPlugin_opt() { }

private:
    void matrix_add_descs(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
			  chunk_cb cb);
    void matrix_add_ops(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
			chunk_cb cb);
    void matrix_add_ops_fromq();
    void matrix_remove_op(str opid);
    void matrix_add_hint(ds_entry *dse, ptr<vec<oid_hint> > oh);

    void wrap_perform_optimization();
    void perform_optimization(CLOSURE);
    void desc_avail(ht_entry * dse, ptr<vec<str > > r);
    void cost_per_block(os_entry * ose);
    bool pressure_from_computation();
    void pick_block_alloc(ptr<opt_result> res, CLOSURE);
    void pick_xdisk_op(ptr<opt_result> res);
    void pick_computation();
    void pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb, CLOSURE);
    void get_descriptors_cb(descriptors_cb cb1, str s, ptr<vec<dot_descriptor> > descs, bool end);
    void get_chunks_cb(str opid, unsigned int plugin, str s, ptr<desc_result> res);
    void cancel_from_net(dot_desc desc, ptr<vec<nw_status> > status);

    /*functions to implement policies to compare against*/
    void othertypes_notify_new_ops(int mode);
    
    /*functions to implement random policy*/
    void random_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb);
    void random_pick_xdisk_op(ptr<opt_result> res);

    /*functions to implement bfs policy*/
    void bfs_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb);
    void bfs_pick_xdisk_op(ptr<opt_result> res);

    void allstats_pick_op_descs(callback<void, str, ptr<opt_result> >::ref cb);
    void allstats_pick_xdisk_op(ptr<opt_result> res);
    bool allstats_only_hash();
#ifdef TIME_SERIES
    void dump_time_series();
#endif
};


#endif /* _XFER_NET_H_ */
