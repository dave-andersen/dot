/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_SSET_H_
#define _STORAGEPLUGIN_SSET_H_

#include "storagePlugin.h"
#include "gtcd.h"
#include "se_transfer.h"

struct net_cache_entry {
    const dot_sId id;
    ihash_entry<net_cache_entry> hlink;
    gtcd *m;
    
    ref<ordered_descriptor_list> slist;
    ptr<vec<dot_desc> > list;
    dot_oid oid;
    ptr<vec<oid_hint> > hint;

    //status
    int shingles_done;
    std::vector< ref<dht_rpc> > status ;
    ptr<dht_rpc> oidstatus;
    bool oid_done;
    
    net_cache_entry (const dot_sId id, gtcd *min);
    ~net_cache_entry ();
    void net_insert();
    void put_fp_to_oid_done(str);
    void put_oid_source_done(str);
};


//----------------------------------------------------
class gtcd;

class storagePlugin_sset : public storagePlugin {
private:
    gtcd *m;
    storagePlugin *sp;
    unsigned int xfer_gtc_listen_port;

public:
    storagePlugin_sset(gtcd *m, storagePlugin *next_sp) : m(m), sp(next_sp)
        { assert(m); assert(sp); }
    ~storagePlugin_sset() { };
    
    bool configure(str s, str pluginClass);

    bool init(dot_sId id);

    void put_chunk(dot_sId id, ref<dot_descriptor> d,
                   const char *buf, int len, cbs cb, CLOSURE);
    void commit_object(dot_sId id, commit_cb cb, CLOSURE);


    bool release_object(ref<dot_oid> oid)
        { return sp->release_object(oid); }


    void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                    bool retain, cbs cb, CLOSURE);


    bool release_ichunk(ref<dot_descriptor> d)
        { return sp->release_ichunk(d); }

    void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, CLOSURE);
    void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb, CLOSURE);
    void sp_notify_descriptors(ref<dot_oid_md> oid,
			    ptr<vec<dot_descriptor> > descs);
    void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, CLOSURE);
    void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);

    
    int get_chunk_refcount(dot_descriptor *d)
        { return sp->get_chunk_refcount(d); }
    void inc_chunk_refcount(dot_descriptor *d)
        { sp->inc_chunk_refcount(d); }


    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE);

    static void get_default_hint(oid_hint *hint);
};

#endif /* _STORAGEPLUGIN_SSET_H_ */
