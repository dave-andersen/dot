/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_disk.h"

desc_result::desc_result(ref<dot_descriptor> d, ptr<suio> s, bool copy)
  : desc(d)
{
    if (copy) {
        // We need to make a copy as the storage plugin could decide to
        // page this chunk out to disk underneath us
        data = New refcounted<suio>;
        data->copyu(s);
    }
    else {
        data = s;
    }
}

desc_result::~desc_result()
{
}

chunk_data::chunk_data(const str &hash, suio *dat)
    :hash(hash) 
{
    data.copyu(dat);
}

struct oid_cache_entry {
    const dot_oid oid;
    ihash_entry<oid_cache_entry> hlink;
    ref<vec<dot_descriptor> > dv;
    unsigned int refcount;

    oid_cache_entry (const dot_oid o, ref<vec<dot_descriptor> > dv);
    ~oid_cache_entry ();
};

static ihash<const dot_oid, oid_cache_entry,
             &oid_cache_entry::oid, &oid_cache_entry::hlink, do_hash> oidCache;

oid_cache_entry::oid_cache_entry(const dot_oid o, ref<vec<dot_descriptor> > dv)
    : oid(o), dv(dv), refcount(1)
{
    oidCache.insert(this);
}

oid_cache_entry::~oid_cache_entry()
{
    oidCache.remove(this);
}

static ihash<const dot_sId, sid_cache_entry, &sid_cache_entry::id, 
	     &sid_cache_entry::hlink> tempCache;

sid_cache_entry::sid_cache_entry(const dot_sId sid)
    : id(sid), dv(New refcounted<vec<dot_descriptor> >)
{
    tempCache.insert(this);

    EVP_MD_CTX_init(&hash);
    EVP_DigestInit(&hash, EVP_sha1());

    EVP_MD_CTX_init(&desc_hash);
    EVP_DigestInit(&desc_hash, EVP_sha1());
}

sid_cache_entry::~sid_cache_entry()
{
    tempCache.remove(this);
}

storagePlugin_disk::storagePlugin_disk(gtcd *m, storagePlugin *next_sp)
{
    if (next_sp)
        fatal << __PRETTY_FUNCTION__ << " next_sp is not NULL\n"
              << "Make sure that this storage plugin comes last\n";

    //cache setup
    dbenv = new DbEnv(0);
    dbenv->set_errpfx("Disk Storage Plugin");
    
    // a min of 20 KB shared memory buffer pool cachesize,
    dbenv->set_cachesize(0, 20 * 1024, 0);

    str cachepath = get_dottmpdir() << "/dcache";
    if (mkdir(cachepath, S_IRWXU) < 0 && errno != EEXIST)
        fatal("Could not create cache directory: %s: %m\n", cachepath.cstr());

    (void)dbenv->set_data_dir(cachepath);

    // Open the environment with full transactional support.
    dbenv->open(cachepath, DB_CREATE | DB_INIT_MPOOL | DB_PRIVATE, 0);

    filesDb = new Db(dbenv, 0);
    if (filesDb->open(NULL,
		      "chunkcache.db",
		      NULL,
		      DB_HASH,
		      DB_CREATE,
		      0) < 0) {
	warn << "Error opening\n";
    }
    
    // We are ok at this point. The database exists
    chunk_cache = New chunkCache(cachepath, filesDb);
}

bool
storagePlugin_disk::init(dot_sId id)
{
    sid_cache_entry *sce = tempCache[id];
    if (sce) {
        warn("storagePlugin_disk received duplicate ID: %d\n", id);
        return false;
    }
    sce = New sid_cache_entry(id);
    return true;
}

void
storagePlugin_disk::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb, ptr<closure_t>)
{
    sid_cache_entry *sce = tempCache[id];
    ptr<vec<unsigned int> > iv;

    if (!sce) {
        (*cb)("Incorrect transfer ID");
        return;
    }

    // Hash for whole object
    EVP_DigestUpdate(&sce->hash, buf, len);

    //Hash for descriptor list
    str desc_buf = strbuf() << d->id << " " << d->length;
    dwarn(DEBUG_STORAGE) << "desc data " << desc_buf << "\n";
    EVP_DigestUpdate(&sce->desc_hash, desc_buf, desc_buf.len());
    
    struct offset_info info;
    extract_offset_info(d, &info);
        
    chunk *ck = chunk_cache->getChunk(d->id); /* actually d */
    if (!ck) {
	ck = chunk_cache->new_chunk(d->id, buf, len, info);
	warnx << "A0A " << d->id << " " << d->length << " " << info.path << "\n";
    }
    else {
	dwarn(DEBUG_STORAGE) << "Cache hit " << d->id << " " << info.path << "\n";
	warnx << "A1A " << d->id << " " << d->length << " " << info.path << "\n";
	chunk_cache->increment_refcount(d->id, buf, len, info);
    }

    // XXX: sce->dv->push_back(ck->desc);
    sce->dv->push_back(*d);

    (*cb)(NULL);
}

void
storagePlugin_disk::commit_object(dot_sId id, commit_cb cb, ptr<closure_t>) 
{
    sid_cache_entry *sce = tempCache[id];
    if (!sce) {
        (*cb)("Incorrect transfer ID", NULL);
        return;
    }

    //strbuf oidstr;
    unsigned int diglen;
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_DigestFinal(&sce->hash, digest, &diglen);
    dot_oid oo;
    oo.set((char *)digest, diglen);

    // move from tempCache to oidCache. 
    oid_cache_entry *oce = oidCache[oo];

    if (oce) {
        // XXX:  We might have different metadata for the same OID, so
        //       we should probably return the most recent metadata instead.
        // Assuming same descriptor list
        oce->refcount++;
    } 
    else {
        oce = New oid_cache_entry(oo, sce->dv);
    }

    ptr<dot_oid_md> oid = New refcounted<dot_oid_md> ();
    oid->id = oo;

    bzero(digest, sizeof(digest));
    EVP_DigestFinal(&sce->desc_hash, digest, &diglen);
    delete sce;
    metadata_entry e;
    e.module = "DISK";
    e.key = "desc_hash";
    strbuf desc_hash;
    desc_hash << hexdump(digest, diglen);
    e.val = desc_hash;
    oid->md.list.push_back(e);
    
    dwarn(DEBUG_STORAGE) << "storagePlugin_disk::commit_object OID is " << oid->id << "\n";
    dwarn(DEBUG_STORAGE) << "storagePlugin_disk::commit_object descriptor hash is "
			 << desc_hash << "\n";
    (*cb)(NULL, oid);
}

bool
storagePlugin_disk::release_object(ref<dot_oid> oid)
{
    oid_cache_entry *oce = oidCache[*oid];

    if (!oce) {
        warn << "release_object:: Unable to lookup OID " << *oid << "\n";
        return false;
    }

    for (unsigned int i = 0; i < oce->dv->size(); i++) {
	release_chunk(New refcounted<dot_descriptor> ((*oce->dv)[i]));
    }
    // Now remove oid from table if present
    oce->refcount--;
    if (0 == oce->refcount) {
        delete oce;
    }
    return true;
}

// The buffers passed to put_ichunk now belong to it
void
storagePlugin_disk::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                           bool retain, cbs cb, ptr<closure_t>)
{
    // Treating retain as true for now
    // We have a descriptor and the data. Simply write a chunk out
    chunk *ck = chunk_cache->getChunk(d->id);

    struct offset_info(info);
    extract_offset_info(d, &info);
    //this shd be unsafe since the file is not yet written to disk
    //there shd be no local info
    assert(info.st == EVICT_UNSAFE);
    
    if (!ck) {
        ck = chunk_cache->new_chunk(d->id, uiop, info);
	if (ck) {
	    (*cb)(NULL);
	} 
	else {
	    (*cb)("Unable to write chunk");
	}
    } 
    else {
	if (retain) {
	    chunk_cache->increment_refcount(d->id, uiop, info);
	    //ck->refcount++;
	}
    }  
}

void
storagePlugin_disk::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, ptr<closure_t>)
{
    ref<dot_oid_md> new_oid = New refcounted<dot_oid_md>();
    new_oid->id = oid->id;
    (*cb)(NULL, new_oid);
}

void
storagePlugin_disk::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb,
                                    ptr<closure_t>)
{

    oid_cache_entry *oce = oidCache[oid->id];

    if (!oce) {
        warn << "get_descs:: Unable to lookup OID " << oid->id << "\n";
        (*cb)("No OID found", NULL, true);
        return;
    }

    (*cb)(NULL, oce->dv, true);
}

void
storagePlugin_disk::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, ptr<closure_t>)
{
    ref<dot_descriptor> new_d = New refcounted<dot_descriptor>();
    new_d->id = d->id;
    new_d->length = d->length;
    (*cb)(NULL, new_d);
}

void
storagePlugin_disk::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb,
                               ptr<closure_t>)
{
    for (unsigned int i = 0; i < dv->size(); i++) {
	ref<dot_descriptor> dd = New refcounted<dot_descriptor>((*dv)[i]);
        get_chunk(dd, cb);
    }
}

void
storagePlugin_disk::get_chunk(ref<dot_descriptor> d, chunk_cb cb,
                              ptr<closure_t>)
{
    ptr<suio> chunkData = chunk_cache->get_chunk_data(d->id);
        
    if (NULL == chunkData) {
	//warnx << "Cannot find " << d->id << "\n";
        (*cb)("Chunk not in database", NULL);
        return;
    }
    else {
	//warnx << chunkData->resid() << "\n";
    }
    ref<desc_result> res = New refcounted<desc_result> (d, chunkData, true);
    (*cb)(NULL, res);
}

int
storagePlugin_disk::get_chunk_refcount(dot_descriptor *d)
{
    chunk *ck = chunk_cache->getChunk(d->id);
    if (!ck) {
        return -1;
    }
    return (chunk_cache->get_refcount(d));
    //ck->refcount;
}

void
storagePlugin_disk::inc_chunk_refcount(dot_descriptor *d)
{
    struct offset_info(info);
    ref<dot_descriptor> dd = New refcounted<dot_descriptor>(*d);
    extract_offset_info(dd, &info);
    
    chunk *ck = chunk_cache->getChunk(d->id);
    if (!ck) {
        return;
    }
    chunk_cache->increment_refcount(d, info);
    //ck->refcount++;
}

bool
storagePlugin_disk::release_chunk(ref<dot_descriptor> d)
{
  warnx << "Calling release\n";

    chunk *ck = chunk_cache->getChunk(d->id);

    if (!ck) {
        warn << "unable to find chunk with hash " << d->id << " \n";
        return false;
    } 

    // This will be deleted by the reaper
    ck->refcount--;
    return true;

}

bool
storagePlugin_disk::release_ichunk(ref<dot_descriptor> d)
{
    return release_chunk(d);
}

void 
storagePlugin_disk::sp_notify_descriptors(ref<dot_oid_md> oid,
				       ptr<vec<dot_descriptor> > descs)
{
    //warn << "storagePlugin_disk::notify_descriptors: called\n";
    
    oid_cache_entry *oce = oidCache[oid->id];
    
    if (oce) {
        //fatal << "storagePlugin_disk::notify_descriptors: Should not be there since it was just checked\n";
    } 
    else {
        oce = New oid_cache_entry(oid->id, descs);
    }
}

void
print_bitvec(ptr<bitvec> bmp_ret)
{
    printf("Bitvec is -->\n");

    for (unsigned int j =0; j < bmp_ret->size(); j++)
    {
        if ((*bmp_ret)[j]==1)
            printf("%d --> 1 || ",j);
        else
            printf("%d --> 0 || ", j);
    }

    printf("\n");
}


void
storagePlugin_disk::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb,
			       ptr<closure_t>)
{
    oid_cache_entry *oce = oidCache[oid->id];

    if (!oce) {
        warn << "get_bitmap:: Unable to lookup OID " << oid->id << "\n";
        (*cb)("No OID found", NULL);
        return;
    }

    unsigned int size = oce->dv->size();
    ref<bitvec> bmp = New refcounted<bitvec>(size);
    //clear the bitvector 
    bmp->setrange(0, bmp->size(), 0);

    //warn << "storagePlugin_disk::get_bitmap: created bitvec of size " << bmp->size() << "\n";
    
    for (unsigned int i = 0; i < size; i++) {
	chunk *ck = chunk_cache->getChunk(((*(oce->dv))[i].id)) ;
	if (ck) {
	    dwarn(DEBUG_STORAGE) << "Returning " << ((*(oce->dv))[i].id) << "\n";
	    (*bmp)[i] = 1;
	}
	else
	    assert((*bmp)[i] == 0);
    }

    //print_bitvec(bmp);
    
    (*cb)(NULL, bmp);
}




// XXX - TODO List
// - More efficient implementation
// - Storing data pointers in chunk struct
