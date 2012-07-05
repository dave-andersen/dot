/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _CHUNK_CACHE_H_
#define _CHUNK_CACHE_H_ 1

#include "list.h"
#include "async.h"
#include "ihash.h"
#include "se_transfer.h"

enum chunk_status {
    CHUNK_IN_MEM,
    CHUNK_ON_DISK,
    CHUNK_IN_MEM_ON_DISK,
    CHUNK_AS_OFFSET
};

// Chunks are separate from descriptors because multiple dot_descs might
// point to the same chunk.
struct chunk {
    const dot_desc hash;
    unsigned int length;
    ptr<suio> data;
    int refcount;
    chunk_status status;
    offset_info info;

    ihash_entry<chunk> hlink;
    tailq_entry<chunk> tlink;

    chunk (const dot_desc hash, const char *buf, unsigned int length, struct offset_info i);
    chunk (const dot_desc hash, ref<suio> indata, struct offset_info i);
    ~chunk ();
};

class chunkCache {

private:
    ihash<const dot_desc, chunk, &chunk::hash, &chunk::hlink, dd_hash> chunk_cache;
    // The talk of this list is the most recently used element
    tailq<chunk, &chunk::tlink> mem_lru;
    const str cache_path;
    size_t mem_footprint;
    // Write unwritten blocks to disk in the face of cache pressure
    timecb_t *syncer;
    // Purge chunks whose refcount has hit zero
    timecb_t *purger;
    Db *ptrDb;
    
    void purge_chunks();
    void purge_cb(chunk *ck);
    void sync_chunks();
    void cache_pressure_cb(chunk *ck);

    bool read_chunk(const dot_desc cname);
    bool write_chunk(dot_desc chunkname, ref<suio> data);
    bool unlink_chunk(dot_desc chunkname);
    void check_footprint();
public:
    chunk *getChunk(const dot_desc name);
    chunk *new_chunk(const dot_desc name, const char *buf, unsigned int length, struct offset_info i);
    chunk *new_chunk(const dot_desc name, ref<suio> data, struct offset_info i);
    ptr<suio> get_chunk_data(const dot_desc name);
    void increment_refcount(dot_descriptor *d, struct offset_info i);
    void increment_refcount(const dot_desc name, const char *buf, unsigned int length, struct offset_info i);
    void increment_refcount(const dot_desc name, ref<suio> data, struct offset_info i);
    int get_refcount(dot_descriptor *d);
    bool get_chunk_from_offset(chunk *ck);

    chunkCache(const str cache_path, Db *);
};

#endif /* _CHUNK_CACHE_H_ */
