/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtcd.h"
#include "chunk_cache.h"
#include "params.h"


chunk::chunk(const dot_desc hash, const char *buf, unsigned int length, struct offset_info i) 
    : hash(hash), length(length), data(New refcounted<suio>),
      refcount(1), status(CHUNK_IN_MEM)
{
    dwarn(DEBUG_STORAGE) << "chunkCache.c::chunk Creating " << hash << "\n";
    info = i;
    data->copy(buf, length);
}

chunk::chunk(const dot_desc hash, ref<suio> indata, struct offset_info i) 
    : hash(hash), refcount(1), status(CHUNK_IN_MEM)
{
    dwarn(DEBUG_STORAGE) << "chunkCache.c::chunk Creating 1 " << hash << "\n";
    info = i;
    length = indata->resid();
    data = indata;
}

chunk::~chunk() 
{
    dwarn(DEBUG_STORAGE) << "chunkCache.c::chunk Deleting " << hash << "\n";
}

chunkCache::chunkCache(const str cache_path, Db *filesDb)
    : cache_path(cache_path), mem_footprint(0), ptrDb(filesDb)
{
    purger = delaycb(CHUNK_PURGER_SEC, CHUNK_PURGER_NSEC, wrap(this, &chunkCache::purge_chunks));
    syncer = NULL;
}

void
chunkCache::purge_cb(chunk *ck)
{
    if (ck->refcount == 0) {
	dwarn(DEBUG_STORAGE) << "chunkCache::purge_cb: begin purge\n";
        if (ck->status == CHUNK_IN_MEM || ck->status == CHUNK_IN_MEM_ON_DISK) {
            dwarn(DEBUG_STORAGE) << "about to remove from mem "<< ck->hash << "\n";
            mem_lru.remove(ck);
            mem_footprint -= ck->data->resid();
            ck->data = NULL;

	    if (ck->info.st == EVICT_UNSAFE) {
		chunk_cache.remove(ck);
		delete ck;
	    }
	    else if (ck->info.st == EVICT_SAFE) {
		assert(ck->status == CHUNK_IN_MEM);
		ck->status = CHUNK_AS_OFFSET;
	    }
        } 
        if (ck->status == CHUNK_IN_MEM_ON_DISK || ck->status == CHUNK_ON_DISK) {
            unlink_chunk(ck->hash);
	    assert(ck->info.st == EVICT_UNSAFE);
	    chunk_cache.remove(ck);
	    delete ck;
        }
    }
}

void
chunkCache::purge_chunks()
{
    chunk_cache.traverse(wrap(this, &chunkCache::purge_cb));
    purger = delaycb(CHUNK_PURGER_SEC, CHUNK_PURGER_NSEC, wrap(this, &chunkCache::purge_chunks));
}

void
chunkCache::cache_pressure_cb(chunk *ck)
{
    if (mem_footprint <= CHUNKS_LOW_WATER) {
        return;
    }

    dwarn(DEBUG_STORAGE) << "chunkCache::cache_pressure_cb: responding to pressure\n";
    if (ck->refcount == 0) {
        if (ck->status == CHUNK_IN_MEM) {
            
            mem_lru.remove(ck);
	    mem_footprint -= ck->data->resid();
            ck->data = NULL;
	    
	    if (ck->info.st == EVICT_UNSAFE) {
		chunk_cache.remove(ck);
		delete ck;
	    }
	    else if (ck->info.st == EVICT_SAFE) {
		dwarn(DEBUG_STORAGE) << "chunkCache::cache_pressure_cb: ref 0 Moving to offset mode " << ck->hash << "\n";
		ck->status = CHUNK_AS_OFFSET;
	    }
	    
	    return;
        } 
        else if (ck->status == CHUNK_IN_MEM_ON_DISK) {
            // This needs to cleaned up by the purger. So we leave enough
            // state around
            mem_lru.remove(ck);

            mem_footprint -= ck->data->resid();
            ck->data = NULL;
            ck->status = CHUNK_ON_DISK;
	    assert(ck->info.st == EVICT_UNSAFE);
	    return;
        }
        else {
            fatal << "remove_zero_refcount: Unknown state for chunk\n";
        }
    }
    
    if (ck->status == CHUNK_IN_MEM) {
        // write it out to disk
        mem_lru.remove(ck);
	
	if (ck->info.st == EVICT_UNSAFE) {
	    write_chunk(ck->hash, ck->data);
	    ck->status = CHUNK_ON_DISK;
	}
	else if (ck->info.st == EVICT_SAFE) {
	    dwarn(DEBUG_STORAGE) << "chunkCache::cache_pressure_cb: Moving to offset mode " << ck->hash << "\n";
	    ck->status = CHUNK_AS_OFFSET;
	}
	
	mem_footprint -= ck->data->resid();
	ck->data = NULL;
    }
    else if (ck->status == CHUNK_IN_MEM_ON_DISK) {
        mem_lru.remove(ck);
        ck->status = CHUNK_ON_DISK;
        mem_footprint -= ck->data->resid();
        ck->data = NULL;
	assert(ck->info.st == EVICT_UNSAFE);
    }
    else {
        fatal << "remove_zero_refcount: Unknown state for chunk\n";
    }
}

void
chunkCache::sync_chunks()
{
    mem_lru.traverse(wrap(this, &chunkCache::cache_pressure_cb));
    syncer = NULL;
}

void
chunkCache::check_footprint() 
{
    dwarn(DEBUG_STORAGE) << "chunk cache check_footprint: mem_footprint is " << mem_footprint << "\n";
    if (mem_footprint >= CHUNKS_HIGH_WATER && !syncer) {
	syncer = delaycb(0, 0, wrap(this, &chunkCache::sync_chunks));
    }
        
}

chunk *
chunkCache::getChunk(const dot_desc name) 
{
    return chunk_cache[name];
}


chunk *
chunkCache::new_chunk(const dot_desc name, const char *buf,
		      unsigned int length, struct offset_info i)
{
    chunk *ck = New chunk(name, buf, length, i);
    chunk_cache.insert(ck);
    mem_lru.insert_tail(ck);

    mem_footprint += length;
    check_footprint();

    //warnx << "chunkCache: Inserting " << name << "\n";
    //warnx << "chunkCache Mem " << mem_footprint << " low " << CHUNKS_LOW_WATER
    //  << " high " <<  CHUNKS_HIGH_WATER << "\n";
    
    return ck;
}

chunk *
chunkCache::new_chunk(const dot_desc name, ref<suio> data, struct offset_info i)
{
    chunk *ck = New chunk(name, data, i);
    chunk_cache.insert(ck);
    mem_lru.insert_tail(ck);

    mem_footprint += data->resid();
    check_footprint();
    
    // for debugging only
    // write_chunk(ck->desc.id, ck->data);

    return ck;
}

bool
chunkCache::read_chunk(const dot_desc cname)
{
    //warnx << "about to read in " << cname << "\n";
    
    chunk *ck = chunk_cache[cname];
    
    if (!ck) 
	return false;

    ptr <Dbt> d = New refcounted<Dbt >;
    if (!get_unique_from_cache(ptrDb, cname.base(), cname.size(), d)) {
	fatal << "Data Disappeared " << cname << "\n";
	return false;
    }

    rpc_bytes<> value;
    value.set((char *)d->get_data(), d->get_size());
    
    cid_chunk_bdb_info o;
    bytes2xdr(o, value);
    if (o.type != INFO_CID_CHUNK) {
	return false;
    }

    ref<suio> data = New refcounted<suio>;
    data->copy(o.buf.base(), o.buf.size());
    
    ck->data = data;
    ck->status = CHUNK_IN_MEM_ON_DISK;
    mem_lru.insert_tail(ck);
    
    mem_footprint += ck->length;
    check_footprint();
    return true;
}

bool
chunkCache::write_chunk(dot_desc chunkname, ref<suio> data)
{
    //warnx << "chunkCache: about to write out " << chunkname << "\n";

    chunk *ck = chunk_cache[chunkname];
    if (!ck)
	return false;
    
    cid_chunk_bdb_info c;
    c.type = INFO_CID_CHUNK;
    c.desc.id = ck->hash;
    c.desc.length = ck->length;
    c.buf.setsize(ck->data->resid());
    ck->data->copyout(c.buf.base());
    rpc_bytes<> value;
    xdr2bytes(value, c);
    return(put_in_cache(ptrDb, chunkname.base(), chunkname.size(),
			value.base(), value.size(), true));
}

bool 
chunkCache::unlink_chunk(dot_desc chunkname)
{
    dwarn(DEBUG_STORAGE) << "chunkCache::unlink_chunk " << chunkname << "\n";
    return(delete_from_cache(ptrDb, chunkname.base(), chunkname.size()));
}

ptr<suio>
chunkCache::get_chunk_data(const dot_desc cname)
{
    chunk *ck = chunk_cache[cname];

    if (!ck) {
	dwarn(DEBUG_STORAGE) << "Returning NULL " << cname << "\n";
	return NULL;
    }

    if (ck->status == CHUNK_IN_MEM || ck->status ==  CHUNK_IN_MEM_ON_DISK) {
	dwarn(DEBUG_STORAGE) << "chunkCache::get_chunk_data Giving " << cname << " from mem\n";
        mem_lru.remove(ck);
        mem_lru.insert_tail(ck);
	return ck->data;
    }

    if (ck->status == CHUNK_ON_DISK) {
	dwarn(DEBUG_STORAGE) << "chunkCache::get_chunk_data Giving " << cname << " from disk\n";
	read_chunk(cname);
	return ck->data;
    }
    else if (ck->status == CHUNK_AS_OFFSET) {
	if (get_chunk_from_offset(ck)) {
	    dwarn(DEBUG_STORAGE) << "chunkCache::get_chunk_data Giving " << cname << " from offset\n";
	    return ck->data;
	}
	else {
	    dwarn(DEBUG_STORAGE) << "chunkCache::get_chunk_data Giving " << cname << " from offset FAILED\n";
	    return NULL;
	}
    }
    else {
	dwarn(DEBUG_STORAGE) << "Unknown chunk status\n";
        return NULL;
    }
}

void
chunkCache::increment_refcount(dot_descriptor *d, struct offset_info i)
{
    //warnx << "chunkCache::increment_refcount: from increment " << d->id << "\n";
    
    chunk *ck = getChunk(d->id);
    if (!ck) {
        return;
    }
    
    ck->refcount++;
    
    if (ck->info.st == EVICT_SAFE) {
	//see if i need to change status
	if (i.st == EVICT_UNSAFE ||
	    ck->info.path != i.path) {
	    //warnx << "chunkCache::increment_refcount: making unsafe\n";
	    ck->info.st = EVICT_UNSAFE;
	    //a previous call to get_refcount shd have refreshed this
	    assert(ck->status != CHUNK_AS_OFFSET);
	}
    }
}

void
chunkCache::increment_refcount(const dot_desc name, const char *buf, unsigned int length,
			       struct offset_info i)
{
    //warnx << "chunkCache::increment_refcount:: from put_chunk called " << name << "\n";
    
    chunk *ck = getChunk(name);
    if (!ck) {
        return;
    }

    ck->refcount++;
    
    if (ck->info.st == EVICT_SAFE) {
	//see if i need to change status
	if (i.st == EVICT_UNSAFE ||
	    ck->info.path != i.path) {
	    //warnx << "chunkCache::increment_refcount: making unsafe\n";
	    ck->info.st = EVICT_UNSAFE;
	    if (ck->status == CHUNK_AS_OFFSET) {
		//convert to not have as_offset
		//warnx << "chunkCache::increment_refcount: getting into mem\n";
		ck->data = New refcounted<suio>;
		ck->data->copy(buf, length);
		ck->status = CHUNK_IN_MEM;

		mem_lru.insert_tail(ck);
		
		mem_footprint += length;
		check_footprint();
	    }
	}
    }
}

void
chunkCache::increment_refcount(const dot_desc name, ref<suio> data,
			       struct offset_info i)
{
    //warnx << "chunkCache::increment_refcount:: from put_ichunk called " << name << "\n";
    
    chunk *ck = getChunk(name);
    if (!ck) {
        return;
    }

    ck->refcount++;
    
    if (ck->info.st == EVICT_SAFE) {
	//see if i need to change status
	if (i.st == EVICT_UNSAFE ||
	    ck->info.path != i.path) {
	    //warnx << "chunkCache::increment_refcount: making unsafe\n";
	    ck->info.st = EVICT_UNSAFE;
	    if (ck->status == CHUNK_AS_OFFSET) {
		//convert to not have as_offset
		//warnx << "chunkCache::increment_refcount: getting into mem\n";
		ck->data = data;
		ck->status = CHUNK_IN_MEM;

		mem_lru.insert_tail(ck);

		assert (ck->length == data->resid());
		mem_footprint += ck->length;
		check_footprint();
	    }
	}
    }
}

int
chunkCache::get_refcount(dot_descriptor *d)
{
    dwarn(DEBUG_STORAGE) << "chunkCache::get_refcount " << d->id << "\n";
    chunk *ck = getChunk(d->id);
    if (!ck) {
        return -1;
    }

    //assume it is becoming unsafe
    if (ck->info.st == EVICT_SAFE) {
	ck->info.st = EVICT_UNSAFE;
	if (ck->status == CHUNK_AS_OFFSET) {
	    if (!get_chunk_from_offset(ck))
		return -1;
	}
    }

    return (ck->refcount);
}

bool
chunkCache::get_chunk_from_offset(chunk *ck)
{
    dwarn(DEBUG_STORAGE) << "offset called\n";
    ref<suio> data = New refcounted<suio>;
    int fd;
    bool canclose = true;
    
    if (ck->info.fd < 0) {
	fd = open(ck->info.path, O_RDONLY);
	if (fd < 0) {
	    warn("chunkCache Unable to find %s\n", ck->info.path.cstr());
	    chunk_cache.remove(ck);
	    delete ck;
	    return false;
	}
    }
    else {
	canclose = false;
	//warnx << "chunkCache::get_chunk_from_offset : leveraging passed fd\n";
	fd = ck->info.fd;
    }

    int ret;
    if (lseek(fd, ck->info.offset, SEEK_SET) != ck->info.offset) {
	chunk_cache.remove(ck);
	delete ck;
	return false;
    }

    int remain = ck->length;
    while (1) {
	//warnx << "chunkCache::get_chunk_from_offset : reading " << remain << "\n";
	ret = data->input(fd, remain);
	if (ret == remain ||
	    ret < 0)
	    break;
	else
	    remain = remain - ret;
    } 
    
    if (ret == -1) {
	if (errno == EAGAIN) {
	    fatal << "chunkCache: Implement support for EAGAIN\n";
	}
	else {
	    warn << "chunkCache: Error when reading file\n";
	    chunk_cache.remove(ck);
	    delete ck;
	    return false;
	}
    }

    if (canclose)
	close(fd);
    
    //check for hash
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_MD_CTX desc_hash;
    unsigned int diglen;
    EVP_MD_CTX_init(&desc_hash);
    EVP_DigestInit(&desc_hash, EVP_sha1());

    for (const iovec *i = data->iov(); i < data->iovlim(); i++) {
	EVP_DigestUpdate(&desc_hash, i->iov_base, i->iov_len);
    }

    EVP_DigestFinal(&desc_hash, digest, &diglen);

    if (memcmp(ck->hash.base(), digest, diglen)) {
	/* Perhaps we should update the index? */
	chunk_cache.remove(ck);
	delete ck;
	return false;
    }

    ck->data = data;
    ck->status = CHUNK_IN_MEM;
    mem_lru.insert_tail(ck);

    mem_footprint += ck->length;
    check_footprint();
    
    return true;
}

/*TODO

can be optimised
right now this is what happens due to lru

so suppose there is c1 shared by two files
and c2 not shared. when time comes to evict
c1 needs to be written but c2 can be made offset.
currently since c1 is before c2, it gets written.
but may be better thing would be to make c2 offset.

*/
