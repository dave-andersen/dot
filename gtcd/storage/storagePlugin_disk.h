/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_DISK_H_
#define _STORAGEPLUGIN_DISK_H_

#include "storagePlugin.h"
#include "gtcd.h"

#include "chunk_cache.h"
#include <openssl/evp.h>

struct chunk_data {
    const str hash;
    suio data;
    ihash_entry<chunk_data> hlink;

    chunk_data(const str &hash, suio *data);
};

struct sid_cache_entry {
    const dot_sId id;
    ref<vec<dot_descriptor> > dv;
    EVP_MD_CTX hash;
    EVP_MD_CTX desc_hash;
    
    ihash_entry<sid_cache_entry> hlink;

    sid_cache_entry (const dot_sId id);
    ~sid_cache_entry ();
};

class storagePlugin_disk : public storagePlugin {

private:
    dot_sId id;
    chunkCache *chunk_cache;
    DbEnv *dbenv;
    Db *filesDb;
    
    bool release_chunk(ref<dot_descriptor> d);

public:
    storagePlugin_disk(gtcd *m, storagePlugin *next_sp);
    ~storagePlugin_disk() { delete chunk_cache; }

    bool configure(str s, str pluginClass) { return true; };

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
    int get_chunk_refcount(dot_descriptor *d);
    void inc_chunk_refcount(dot_descriptor *d);
    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE);
};

#endif /* _STORAGEPLUGIN_DISK_H_ */
