/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_XSET_H_
#define _XFER_XSET_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"
#include "se_transfer.h"
#include "params.h"
#include "rxx.h"

#include "xferPlugin_opt.h"

typedef callback<void, ref< vec<dot_descriptor> >, ref<hv_vec> >::ref update_cb;

struct hint_cache {
    oid_hint hint;
    str name;
    ihash_entry<hint_cache> hlink;
    
    hint_cache(oid_hint, str);
    ~hint_cache();
};

struct chunk_cache_entry {
    const dot_desc cid;
    ihash_entry<chunk_cache_entry> hlink;
    
    ihash<const str, hint_cache, &hint_cache::name, &hint_cache::hlink> hints_hash;
    
    chunk_cache_entry (const dot_desc o);
    ~chunk_cache_entry();
};

class oid_info {
    
public:
    
    dot_oid oid;
    cbs cb;
    ptr<vec<dot_descriptor> > descs;
    gtcd *m;
    ptr<dht_rpc> dht;
    ptr<vec<oid_hint> > hints;
    ptr<bitvec> bv;

    ihash_entry<oid_info> hlink;
        
    oid_info(const dot_oid &, cbs cb, ptr<vec<dot_descriptor> > descs, gtcd *m);
    ~oid_info() { }
    void get_oid_sources_done(str err, ptr<vec<bamboo_value> > results);
    void get_descriptors_cb(str s, ptr<vec<dot_descriptor> > descsin, bool end);
    
} ;

class src_info {
public:
    str key;
    dot_oid oid;
    double time;
    bool inprogress;
    ptr<bitvec> bmp;
    oid_hint hint;
    ptr<vec<oid_hint> > hints_arg;
    ptr<dot_oid_md> oid_arg;
    ihash_entry<src_info> hlink;
    src_info(oid_hint, dot_oid, unsigned int);
    ~src_info();
} ;

typedef ihash<const str, src_info, &src_info::key, &src_info::hlink> src_hash;

struct oid_netcache_entry {
    
    const dot_oid oid;
    ref<ordered_descriptor_list> slist;

    int shingles_done;
    int oids_done;
    int oid_insert_done;

    update_cb cb;
    gtcd *m;
    
    //for partial sources
    bool next_event;
    unsigned int ident_count;
    unsigned int sim_count;
    src_hash ident_srcs;
    src_hash sim_srcs;
    
    ptr<vec<dot_descriptor> > self_descs;
    ihash_entry<oid_netcache_entry> hlink;

    std::vector< ref<dht_rpc> > status ;
    ihash<const dot_oid, oid_info, &oid_info::oid, &oid_info::hlink, do_hash> oidstatus;
    ptr<dht_rpc> oidinsert_status;
    
    oid_netcache_entry (const dot_oid o, update_cb, gtcd *m);
    ~oid_netcache_entry();
    void net_lookup();
    void net_lookup_refresh();
    void net_insert_refresh();
    void get_fp_oids_done(str err, ptr<vec<bamboo_value> > results);
    void net_lookup_oid_done(dot_oid oid, str err);
    void put_oid_source_done(str err);
    void pick_sources(dot_oid);
    void get_bitmap_cb(src_info *src, str err, ptr<bitvec > bmp);
    void get_bitmap_refresh();
private:
    void get_bitmap_refresh_sources(src_hash *srcs);
};

//-------------------------------------------------------------

class xferPlugin_xset : public xferPlugin {
    
private:
    gtcd *m;
    xferPlugin *xp;

    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb, CLOSURE);
    void get_hints_chunk_cache(dot_desc cid, ref<vec<oid_hint > > hintsin);
        
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

    static bool insert_chunk_cache(dot_desc cid, ptr<vec<oid_hint> > srcdata,
				   ref<vec<oid_hint> > new_hints);
    void xp_dump_statistics() { xp->xp_dump_statistics(); }
    
    xferPlugin_xset(gtcd *m, xferPlugin *next_xp);
    ~xferPlugin_xset(); 
};

#endif /* _XFER_XSET_H_ */
