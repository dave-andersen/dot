/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_MSRC_H_
#define _XFER_MSRC_H_

#include "xferPlugin.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"

#include "se_transfer.h"
#include "params.h"

// for the pending queue structure
struct descs_msrc {
    const dot_desc desc_name;
    ihash_entry<descs_msrc> hlink;
    
    dot_descriptor dd;
    ref<vec<oid_hint> > oidhint;
        
    int i; // just for debugging purpose - to be removed
    int dups;

    vec<chunk_cb> cb;
    
    descs_msrc (chunk_cb cb, dot_descriptor dot_desc,
		ref<vec<oid_hint> > hints, int i, int dupin);
    descs_msrc (vec<chunk_cb> cb_in, dot_descriptor dot_desc, 
		ref<vec<oid_hint> > oidhints, int i, int dupin);
    ~descs_msrc ();
};


struct src_state {
    
    ihash<const dot_desc, descs_msrc, &descs_msrc::desc_name, &descs_msrc::hlink, dd_hash> desc_request_cache;
    
    str hostname;
    unsigned int port;
    str key;

    unsigned int outstanding_requests;
    unsigned long long allowed_bytes;
    unsigned long long outstanding_bytes;
    unsigned int served_requests;
    unsigned int fetched_bytes;
    bool isdup;
    str hname;
    
    src_state(str key) : key(key){
	char *hn = NULL;
	char *name = NULL;
	
	name = strdup(key);
	if ((hn = strchr(name, ':'))) {
	    *hn++ = '\0';
	    hostname.setbuf(name, strlen(name));
	    port = atoi(hn);
	}
	else
	    fatal << "What sort of key - " << key << "\n";

	oid_hint oh; hint_res h;
	h.hint.hostname = hostname; h.hint.port = port;
	make_hint(h, "gtc", &oh);
	hname = oh.name;
	
	outstanding_requests = 0;
	outstanding_bytes = 0;
	allowed_bytes = 0;
	served_requests = 0;
	fetched_bytes = 0;
	isdup = false;
    }
    ~src_state() {
	warnx << "SRCSTATS@@@@@@@@@@@@@@@@ " << hostname << " " << port
	      << " " << served_requests << " " << fetched_bytes << "\n";
    }
};

struct bin_entry {
    const dot_desc desc_name; 
    ihash_entry<bin_entry> hlink;
    tailq_entry<bin_entry> link;
    bin_entry(dot_desc id) : desc_name(id) { }
    ~bin_entry() { }
};

struct bin {
    void insert(bin_entry *be) {
	hash.insert(be);
	randq.insert_tail(be);
    }
    void remove(bin_entry *be) {
	hash.remove(be);
	randq.remove(be);
    }
    ihash<const dot_desc, bin_entry, &bin_entry::desc_name, &bin_entry::hlink, dd_hash> hash;
    tailq<bin_entry, &bin_entry::link> randq;  //q to keep descs in rand order
};

struct src_view_entry {
    str key;
    ihash_entry<src_view_entry> hlink;
    int rarest_index;
    vec<bin *> bin_vec;
    src_view_entry(str k) : key(k), rarest_index(-1) { }
    ~src_view_entry() { }
};

struct bad_src_entry {
    str key;
    ihash_entry<bad_src_entry> hlink;
    double time_went_bad;
    bad_src_entry(str k, double t) : key(k), time_went_bad(t) { }
    ~bad_src_entry() { }
};

class xferPlugin_msrc : public xferPlugin {
  
private:
    gtcd *m;
    xferPlugin *xp;

    unsigned int num_of_srcs;    
    vec<src_state *> wait_list_src;
    
    // descriptor state
    ihash<const dot_desc, descs_msrc, &descs_msrc::desc_name, &descs_msrc::hlink, dd_hash> hash_pending_desc;
    ihash<const str, src_view_entry, &src_view_entry::key, &src_view_entry::hlink> src_view;
    ihash<const str, bad_src_entry, &bad_src_entry::key, &bad_src_entry::hlink> bad_srcs;

    descs_msrc * check_if_serve(dot_descriptor in);
    void insert_in_src_view(src_view_entry *sve, unsigned int pos, bin_entry *be);
    bin_entry * remove_from_src_view(src_view_entry *sve, unsigned int pos, dot_desc desc_name);
    void create_src_view(descs_msrc *d);
    void update_src_view(descs_msrc *d, ptr<vec<oid_hint> > old_hints, ref<vec<oid_hint> > hints);
    void clean_src_view(descs_msrc *d);
     void send_descs_to_src();
    void try_fillup_src(src_state *ss, ptr<vec<dot_descriptor> > descs_to_get);
    src_state * pick_new_rarest_src(int index);
    int check_srcplugin_exist(str key);
    src_state * add_new_src(str key);
    bool check_src_bad(str key);
    void get_chunks_done(str xp_key, str s, ptr<desc_result> res);
    void print_wait_list();
    void print_src_view();
    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb, CLOSURE);
    void cancel_chunk_cb(ref<dot_descriptor> d, ptr<vec<nw_status> > status);
    nw_status handle_cancel_chunk(dot_descriptor desc, nw_status s);
    void update_allowed_bytes(src_state *ss);
    void delete_source_if_empty(size_t srcidx);
    
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
    void xp_dump_statistics();
    
    xferPlugin_msrc(gtcd *m, xferPlugin *next_xp);
    ~xferPlugin_msrc() { }
};

#endif /* _XFER_NET_H_ */
