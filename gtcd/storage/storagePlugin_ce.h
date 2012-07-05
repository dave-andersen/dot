/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_ENCRYPT_H_
#define _STORAGEPLUGIN_ENCRYPT_H_

#include "storagePlugin.h"
#include "xferPlugin.h"
#include "../xfer/xferPlugin_gtc_prot.h"
#include "gtcd.h"
#include "storagePlugin_cefdisk.h"

#include <openssl/evp.h>

template<class T>
T *get_plugin(str plg, T *next_plg);


struct eoid_cache_entry {
	const dot_oid eoid;
    dot_oid oid;
	ihash_entry<eoid_cache_entry> hlink;
	vec<dot_descriptor> edv;

	eoid_cache_entry(const dot_oid oid, vec<dot_descriptor> dv);
	~eoid_cache_entry();
};

struct oidcache_entry {
    const dot_oid oid;
    dot_oid eoid;
    ihash_entry<oidcache_entry> hlink;

    oidcache_entry(const dot_oid oid, dot_oid eoid);
    ~oidcache_entry();
};

struct edesc_cache_entry {
	const dot_desc ed_id;
	dot_descriptor dd;
	dot_descriptor ed;
	ihash_entry<edesc_cache_entry> hlink;

	edesc_cache_entry(const dot_desc e_desc_id, dot_descriptor desc);
	~edesc_cache_entry();
};

struct esid_cache_entry {
    const dot_sId id;
    EVP_MD_CTX ehash;
    dot_oid eoid;
    vec<dot_descriptor> dv; 
    vec<dot_descriptor> edv; 

    ihash_entry<esid_cache_entry> hlink;

    esid_cache_entry(const dot_sId sid);
    ~esid_cache_entry();
};

struct dd_cache_entry {
	const dot_desc dd_id;
	dot_descriptor dd;
	dot_descriptor ed;
	ihash_entry<dd_cache_entry> hlink;

	dd_cache_entry(const dot_desc desc_id, dot_descriptor edesc);
	~dd_cache_entry();
};

class gtcd;

class storagePlugin_ce : public storagePlugin, public xferPlugin {
    friend class storagePlugin_cefdisk;
private:
    vec<storagePlugin *> child_sp;
    storagePlugin *encrypted_child_sp;
    storagePlugin *unencrypted_child_sp;

    /* XFER PART */

    gtcd *m;
    xferPlugin *xp;
    
    void get_bitmap_cb(bitmap_cb cb1, str s, ptr<bitvec> bmp);
    void get_chunk_cb(chunk_cb cb1, str s, ptr<desc_result> res);

    /* FOR CEFDISK */

    void commit_object_fake(dot_sId id, commit_cb cb);
    int get_chunk_refcount_fake(dot_descriptor *d);
        
public:
    storagePlugin_ce(gtcd *m, storagePlugin *next_sp)
        { srand(time(0)); }
    ~storagePlugin_ce() { }

    void set_more_plugins(vec<storagePlugin *> splist);
    bool configure(str s, str pluginClass);
    void set_next_plugin(storagePlugin *next_plg)
    {
        warn << "set_next_plugin called for ce\n";
        if(next_plg) {
            child_sp.push_back(next_plg);
        }
    }

    bool init(dot_sId id);
    void put_chunk(dot_sId id, ref<dot_descriptor> d,
                   const char *buf, int len, cbs cb, CLOSURE);
    void commit_object(dot_sId id, commit_cb cb, CLOSURE);
    bool release_object(ref<dot_oid> oid);
    void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                    bool retain, cbs cb, CLOSURE);
    bool release_ichunk(ref<dot_descriptor> d);

    void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, CLOSURE);
    void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb, CLOSURE);
    void sp_notify_descriptors(ref<dot_oid_md> oid,
			    ptr<vec<dot_descriptor> > descs);
    void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, CLOSURE);
    void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    int get_chunk_refcount(dot_descriptor *d)
        { 
            return unencrypted_child_sp->get_chunk_refcount(d);
        }
    void inc_chunk_refcount(dot_descriptor *d)
        { 
            unencrypted_child_sp->inc_chunk_refcount(d);
        }
    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE);


    /* Xfer Zone */

    void set_next_plugin(xferPlugin *next_plg)
       { xp = next_plg; } 
    
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
    
};

#endif /* _STORAGEPLUGIN_ENCRYPT_H_ */
