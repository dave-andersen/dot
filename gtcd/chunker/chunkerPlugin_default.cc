/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "chunkerPlugin_default.h"
#include "chunkAlg_fixed.h"
#include "rabin_fprint.h"
#include "fprint.h"
#include <openssl/evp.h>

struct csid_cache_entry {
    const dot_sId id;
    fprint *my_chunker;
    suio data;
    ptr<metadata_entry > mde;
    unsigned int offset;
    
    ihash_entry<csid_cache_entry> hlink;

    csid_cache_entry (const dot_sId id, ptr<metadata_entry > e, str algo);
    ~csid_cache_entry ();
};

static ihash<const dot_sId, csid_cache_entry, &csid_cache_entry::id,
	     &csid_cache_entry::hlink> tempCache;

void
chunkerPlugin_default::commit_object(dot_sId id, commit_cb cb)
{
    csid_cache_entry *sce = tempCache[id];
    if (!sce) {
        (*cb)("Incorrect transfer ID", NULL);
        return;
    }

    sce->my_chunker->stop();
    // Look at remaining data
    if (sce->data.resid() > 0) {
        char *sbuf = New char[sce->data.resid()];
        sce->data.copyout(sbuf, sce->data.resid());
        name_chunk(id, sbuf, sce->data.resid());
        delete[] sbuf;
    }

    // Clean up the csid_cache_entry
    delete sce;
    return sp->commit_object(id, cb);
}

void
chunkerPlugin_default::name_chunk(dot_sId id_in, const char *buf, size_t len)
{
    csid_cache_entry *sce = tempCache[id_in];
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_MD_CTX desc_hash;
    unsigned int diglen;

    EVP_MD_CTX_init(&desc_hash);
    EVP_DigestInit(&desc_hash, EVP_sha1());
    EVP_DigestUpdate(&desc_hash, buf, len);
    EVP_DigestFinal(&desc_hash, digest, &diglen);
    
    str chunkname ((char *)digest, diglen);

    ref<dot_descriptor> dd = New refcounted<dot_descriptor>();
    dd->id = chunkname;
    dd->length = len;
    
    if (sce->mde) {
	assert(sce->mde->module == "LOCAL");
	metadata_entry e;
	e.module = sce->mde->module;
	e.key = sce->mde->key;
	e.val = strbuf() << sce->offset;
	dd->md.list.push_back(e);
	sce->offset +=  len;
        //warnx << "chunkerPlugin_default::name_chunk: Sending metadata for "
	//    << dd->id << " || " << e.module << " " << e.key << " " << e.val << "\n";
    }

    sp->put_chunk(sce->id, dd, buf, len, cb_null);
}

void
chunkerPlugin_default::name_chunks(dot_sId id_in, ref<vec<unsigned int> > iv,
                             const char *buf, size_t len)
{
    csid_cache_entry *sce = tempCache[id_in];

    //BUG FIX -- Bindu
    //needs to be confirmed. the assert failed when two sides were equal
    //when I was running RABIN chunking so I changed > to >=
    assert((*iv)[0] >= sce->data.resid());
    size_t buf_cursor = 0;

    // Special case first hash
    char *sbuf = New char[(*iv)[0]];
    sce->data.copyout(sbuf, sce->data.resid());
    buf_cursor = (*iv)[0] - sce->data.resid();
    memcpy(sbuf + sce->data.resid(), buf, (*iv)[0] - sce->data.resid());
    sce->data.rembytes(sce->data.resid());
    name_chunk(id_in, sbuf, (*iv)[0]);
    delete[] sbuf;

    for (unsigned int i = 1; i < iv->size(); i++) {
        name_chunk(id_in, buf + buf_cursor, (*iv)[i]);
        buf_cursor += (*iv)[i];
    }

    // Data left?
    if (len - buf_cursor > 0) {
        sce->data.copy(buf+buf_cursor, len - buf_cursor);
    }
}


bool
chunkerPlugin_default::init(dot_sId *id_out, ptr<metadata_entry > e)
{
    dot_sId curr = id_next;
  
    while(tempCache[++id_next] && id_next != curr);

    csid_cache_entry *sce = tempCache[id_next];
    if (sce) {
        warn("Unable to find free slots\n");
        return false;
    }
    sce = New csid_cache_entry(id_next, e, chunk_algo);
    *id_out = id_next;

    sp->init(id_next);

    return true;
}

void
chunkerPlugin_default::put_object(dot_sId id, const void *buf, size_t len, cbs cb)
{
    csid_cache_entry *sce = tempCache[id];
    ptr<vec<unsigned int> > iv;

    if (!sce) {
        (*cb)("Incorrect transfer ID");
        return;
    }

    // Assumption is that you can have a maximum of one chunk outstanding
    
    // Hold off on making a copy till as far as possible
    iv = sce->my_chunker->chunk_data((const unsigned char*) buf, len);
    if (iv) {
        name_chunks(id, iv, (const char *) buf, len);
    }
    else {
        sce->data.copy(buf, len);
    }
    (*cb)(NULL);
}

csid_cache_entry::csid_cache_entry(const dot_sId sid, ptr<metadata_entry > e,
				   str algo)
    : id(sid), my_chunker(NULL), mde(e), offset(0)
{
    if (algo == "rabin") {
	my_chunker = New rabin_fprint();
	my_chunker->set_chunk_size(CHUNK_SIZE);
    }
    else if (algo == "static")
	my_chunker = New chunkAlg_fixed();
    else
	fatal << "Unknown chunking algorithm\n";
    
    tempCache.insert(this);
}

csid_cache_entry::~csid_cache_entry()
{
    delete my_chunker;
    tempCache.remove(this);
}

