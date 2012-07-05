/*
 * Copyright (c) 2005-2008 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_ce.h"

#define TEST_OVERHEAD 1
static double encryption_time = 0;
static double decryption_time = 0;
static double digest_time = 0;

/* CE - Cache */

static ptr<suio> temp_chunk_buffer; // The encrypted chunk received from the network is temporarily buffered here...

static ihash<const dot_oid, eoid_cache_entry, &eoid_cache_entry::eoid, &eoid_cache_entry::hlink> eoidCache;

static ihash<const dot_oid, oidcache_entry, &oidcache_entry::oid, &oidcache_entry::hlink> oidCache;

static ihash<const dot_desc, edesc_cache_entry, &edesc_cache_entry::ed_id, &edesc_cache_entry::hlink> edescCache;

static ihash<const dot_desc, dd_cache_entry, &dd_cache_entry::dd_id, &dd_cache_entry::hlink> descCache;

static ihash<const dot_sId, esid_cache_entry, &esid_cache_entry::id, &esid_cache_entry::hlink> tempCache;

eoid_cache_entry::eoid_cache_entry(const dot_oid oid, vec<dot_descriptor> dv)
    :eoid(oid), edv(dv)
{
    eoidCache.insert(this);
}

eoid_cache_entry::~eoid_cache_entry()
{
    eoidCache.remove(this);
}

oidcache_entry::oidcache_entry(const dot_oid oid, dot_oid eoid)
    :oid(oid), eoid(eoid)
{
    oidCache.insert(this);
}

oidcache_entry::~oidcache_entry()
{
    oidCache.remove(this);
}

edesc_cache_entry::edesc_cache_entry(const dot_desc e_desc_id, dot_descriptor desc)
    :ed_id(e_desc_id), dd(desc)
{
    edescCache.insert(this);
}

edesc_cache_entry::~edesc_cache_entry()
{
    edescCache.remove(this);
}

dd_cache_entry::dd_cache_entry(const dot_desc desc_id, dot_descriptor edesc)
    :dd_id(desc_id), ed(edesc)
{
    descCache.insert(this);
}

dd_cache_entry::~dd_cache_entry()
{
    descCache.remove(this);
}

esid_cache_entry::esid_cache_entry(const dot_sId sid)
    :id(sid)
{
    tempCache.insert(this);

    EVP_MD_CTX_init(&ehash);
    EVP_DigestInit(&ehash, EVP_sha1());
}

esid_cache_entry::~esid_cache_entry()
{
    tempCache.remove(this);
}


/* Storage Part of CE Plugin */

void 
storagePlugin_ce::set_more_plugins(vec<storagePlugin *> splist)
{
    if (splist.size() > 2) {
        fatal << "storagePlugin_ce::set_more_plugins: CE plugin can have at most two child plugins\n";
    }
    child_sp = splist;
}

bool
storagePlugin_ce::configure(str s, str pluginClass)
{
    if (pluginClass == "storage") {
        unencrypted_child_sp = NULL;
        encrypted_child_sp = NULL;

        vec<str> enc_list;
	static rxx comma(",");
	split(&enc_list, comma, s);
	
        if (enc_list.size() != child_sp.size()) {
            warn << "storagePlugin_ce::configure: Incorrect conf string - size mismatch\n";
            dwarn(DEBUG_CE) << "enc_list.size() = " << enc_list.size() << "; child_sp.size() = " << child_sp.size() << "\n";
            return false;
        }
        for (u_int i = 0; i < enc_list.size(); i++) {
            if (enc_list[i] == "u") {
                unencrypted_child_sp = child_sp[i];
            }
            else if (enc_list[i] == "e") {
                encrypted_child_sp = child_sp[i];
            }
	    else {
		warn << "storagePlugin_ce::configure: Incorrect conf string: " << enc_list[i] << "\n";
	    }

        }
        assert(unencrypted_child_sp);
    }
    else if (pluginClass == "xfer") {
        return true;
    }
    else {
        warn << "storagePlugin_ce can be configured only as storage or xfer plugin\n";
        return false;
    }
    return true;
}

bool
storagePlugin_ce::init(dot_sId id)
{ 
    bool result = unencrypted_child_sp->init(id);
    if (encrypted_child_sp) {
        result &= encrypted_child_sp->init(id);
    }
    if (result) {
        esid_cache_entry *esce = tempCache[id];
        if (!esce) {
            esce = New esid_cache_entry(id);
        }
    }

    return result; 
}

tamed void
storagePlugin_ce::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb)
{
    tvars { 
        str err;
        esid_cache_entry *esce;
        int outlen1, outlen2, encrypted_size;
        metadata_entry me;
        metadata_entry clen_md;
        unsigned char *ciphertext;
        dot_descriptor ed;
        str descriptor_id;
        str val_str;
        double now, cost;
    }

    twait {
        unencrypted_child_sp->put_chunk(id, d, buf, len, mkevent(err));
    }
    if (err) {
        warn("storagePlugin_ce::put_chunk: Error message from child: %s\n",
             err.cstr());
        (*cb)(err);
        return;
    }
    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::put_chunk: Child returned successfully.\n";

        esce = tempCache[id];
        if (!esce) {
            warn << "storagePlugin_ce::put_chunk: dot_sId " << id << " not found in local cache\n";
            err = "dot_sId not found in local cache";
            (*cb)(err);
            return;
        }

        /* Generate random IV */
        unsigned char iv[EVP_MAX_IV_LENGTH];
        for (int k = 0; k < EVP_MAX_IV_LENGTH; k++) {
            iv[k] = (unsigned char)rand() % 255;
        }

        /* Encrypt the chunk with it's descriptor
         * Add the descriptor to the tempCache entry */
        EVP_CIPHER_CTX ctx;
        descriptor_id = strbuf() << d->id;

#if TEST_OVERHEAD
        now = return_time(SECONDS);
#endif
        //Bug-fix - Need a deterministic IV here
        //Using 0 - Suggested by Adrian
        EVP_EncryptInit(&ctx, EVP_aes_256_cbc(), (unsigned char *)descriptor_id.cstr(), NULL);
        ciphertext = New (unsigned char[len + EVP_CIPHER_CTX_block_size(&ctx)]);
        EVP_EncryptUpdate(&ctx, ciphertext, &outlen1, (unsigned char *)buf, len); 
        EVP_EncryptFinal(&ctx, ciphertext + outlen1, &outlen2);
#if TEST_OVERHEAD
        cost = return_time(SECONDS) - now;
        encryption_time += cost;
#endif
        encrypted_size = outlen1 + outlen2;

        /* Add IV to the metadata */
        me.module = "ENCRYPT";
        me.key = "iv";
        val_str = armor64((char *)iv, EVP_MAX_IV_LENGTH);
        assert(armor64len((unsigned char *)val_str.cstr()) == val_str.len());
        me.val = val_str;

        /* Add chunk length to the metadata */
        clen_md.module = "ENCRYPT";
        clen_md.key = "chunk_len";
        clen_md.val = strbuf() << d->length;

        /* Get the digest of the encrypted chunk (edescriptor)
         * Add the edescriptor to the tempCache entry */
        unsigned int ed_diglen;
        unsigned char ed_digest[EVP_MAX_MD_SIZE];
        EVP_MD_CTX ed_hash;
#if TEST_OVERHEAD
        now = return_time(SECONDS);
#endif
        EVP_MD_CTX_init(&ed_hash);
        EVP_DigestInit(&ed_hash, EVP_sha1());
        EVP_DigestUpdate(&ed_hash, ciphertext, encrypted_size);
        EVP_DigestFinal(&ed_hash, ed_digest, &ed_diglen);
#if TEST_OVERHEAD
        cost = return_time(SECONDS) - now;
        digest_time += cost;
#endif
        ed.id.set((char *)ed_digest, ed_diglen);
        ed.length = encrypted_size;
        ed.md.list.push_back(me);
        ed.md.list.push_back(clen_md);
        esce->dv.push_back(*d);
        esce->edv.push_back(ed);

#if TEST_OVERHEAD
        now = return_time(SECONDS);
#endif
        /* Update the message digest context in the tempCache entry */
        EVP_DigestUpdate(&(esce->ehash), ciphertext, encrypted_size);
#if TEST_OVERHEAD
        cost = return_time(SECONDS) - now;
        digest_time += cost;
#endif

        twait {
            if (encrypted_child_sp)
                encrypted_child_sp->put_chunk(id, New refcounted<dot_descriptor> (ed), (char *)ciphertext, encrypted_size, mkevent(err));
        }

        delete ciphertext;
        (*cb)(err);
        return;
    }
}

tamed void
storagePlugin_ce::commit_object(dot_sId id, commit_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> oid;
        ptr<dot_oid_md> eoid;
        esid_cache_entry *esce;
        double now, cost;
    }

    twait {
        unencrypted_child_sp->commit_object(id, mkevent(err, oid));
    }

    if (err) {
        warn("storagePlugin_ce::commit_object: Error message from child: %s\n",
             err.cstr());
        return;
    }
    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: Child returned successfully.\n";

        esce = tempCache[id];
        if (!esce) {
            warn << "storagePlugin_ce::commit_object: The dot_sId " << id << " not found in local cache\n";
            err = "Incorrect dot_sId";
            (*cb)(err, oid);
            return;
        }
        else {

            /* Update edescCache */
            for (int i = 0; i < (int)esce->dv.size(); i++) {

                /* Get the IV from metadata */
                str iv_str;
                for (u_int j = 0; j < esce->edv[i].md.list.size(); j++) {
                    metadata_entry &e = esce->edv[i].md.list[j];
                    if (e.module == "ENCRYPT" && e.key == "iv") {
                        iv_str = dearmor64(e.val.cstr(), e.val.len());
                        break;
                    }
                }

                /* Encrypt the original descriptor with oid
                 * and store it as metadata in edescriptor */
                str ptext_str = strbuf() << esce->dv[i].id;
                EVP_CIPHER_CTX desc_ctx;
                int desc_outlen1, desc_outlen2;
                str oid_id = strbuf() << oid->id;
#if TEST_OVERHEAD
        now = return_time(SECONDS);
#endif
                EVP_EncryptInit(&desc_ctx, EVP_aes_256_cbc(), (unsigned char *)oid_id.cstr(), (unsigned char *)iv_str.cstr());
                unsigned char *desc_ctext = New (unsigned char[EVP_MAX_MD_SIZE + EVP_CIPHER_CTX_block_size(&desc_ctx)]);
                EVP_EncryptUpdate(&desc_ctx, desc_ctext, &desc_outlen1, (unsigned char *)ptext_str.cstr(), ptext_str.len());
                EVP_EncryptFinal(&desc_ctx, desc_ctext + desc_outlen1, &desc_outlen2);
#if TEST_OVERHEAD
        cost = return_time(SECONDS) - now;
        encryption_time += cost;
#endif
                int ciphertext_size = desc_outlen1 + desc_outlen2;

                /* Add the encrypted key (original descriptor) to the metadata */
                metadata_entry me;
                me.module = "ENCRYPT";
                me.key = "key";
                str md_val(armor64((char *)desc_ctext, ciphertext_size)); 
                me.val = md_val;
                esce->edv[i].md.list.push_back(me);

                edesc_cache_entry *edce = edescCache[esce->edv[i].id];
                if (edce) {
                    dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: duplicate descriptor " << esce->edv[i].id << " - updating it\n";
                    edce->dd = esce->dv[i];
                    edce->ed = esce->edv[i];
                }
                else {
                    dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: new descriptor " << esce->edv[i].id << "\n";
                    edce = New edesc_cache_entry(esce->edv[i].id, esce->dv[i]);
                    edce->ed = esce->edv[i];
                }

                delete desc_ctext;
            }

            /* Update eoidCache */
            dot_oid eoid_id;
            unsigned char eoid_digest[EVP_MAX_MD_SIZE];
            unsigned int eoid_diglen;
            EVP_DigestFinal(&(esce->ehash), eoid_digest, &eoid_diglen);
            eoid_id.set((char *)eoid_digest, eoid_diglen);
            esce->eoid = eoid_id;
            eoid_cache_entry *eoce = eoidCache[eoid_id];
            if (eoce) {
                dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: duplicate eoid - updating it\n";
                eoce->edv = esce->edv;
            }
            else {
                eoce = New eoid_cache_entry(eoid_id, esce->edv);
            }
            eoce->oid = oid->id;
            dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: added " << eoid_id << " to eoidCache\n";

            /* Update oidCache */
            oidcache_entry *oce = oidCache[oid->id];
            if (oce) {
                dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object: duplicate oid - updating it\n";
                oce->eoid = eoid_id;
            }
            else {
                oce = New oidcache_entry(oid->id, eoid_id);
            }

            /* Add eoid metadata to the original oid */
            metadata_entry eoid_md;
            eoid_md.module = "ENCRYPT";
            eoid_md.key = "eOID";
            str eoid_val(armor64((char *)eoid_digest, eoid_diglen));
            assert(armor64len((unsigned char *)eoid_val.cstr()) == eoid_val.len());
            eoid_md.val = eoid_val;
            oid->md.list.push_back(eoid_md);

        }
        twait {
            if (encrypted_child_sp)
                encrypted_child_sp->commit_object(id, mkevent(err, eoid));
        }

#if TEST_OVERHEAD
        printf("storagePlugin_ce::commit_object:\n");
        printf("Encryption time = %f\n", encryption_time);
        printf("Decryption time = %f\n", decryption_time);
        printf("Digest time = %f\n", digest_time);
        encryption_time = 0;
        decryption_time = 0;
        digest_time = 0;
#endif

        delete esce;
        (*cb)(err, oid);
        return;
    }

}

/* Called by cefdisk
 * Returns eOID which moves up the encrypted chain */

void 
storagePlugin_ce::commit_object_fake(dot_sId id, commit_cb cb)
{
    dwarn(DEBUG_CE) << "storagePlugin_ce::commit_object_fake: called\n";
    ptr<dot_oid_md> oid;
    str err;
    esid_cache_entry *esce = tempCache[id];
    if (!esce) {
        err = "Incorrect dot_sId";
    }
    else {
        oid = New refcounted<dot_oid_md> ();
        oid->id = esce->eoid;
    }

    (*cb)(err, oid);
}

/* Called by cefdisk
 * Makes appropriate descriptor conversion and returns the refcount */
int
storagePlugin_ce::get_chunk_refcount_fake(dot_descriptor *d)
{
    edesc_cache_entry *edce = edescCache[d->id];
    if (edce)
        return get_chunk_refcount(&edce->dd);
    return -1;
}

bool 
storagePlugin_ce::release_object(ref<dot_oid> oid)
{ 
    bool result = unencrypted_child_sp->release_object(oid);
    if (result) {
        /* Release oidCache entry */
        oidcache_entry *oce = oidCache[*oid];
        if (oce) {
            dot_oid eoid = oce->eoid;
            /* Release eoidCache entry */
            eoid_cache_entry *eoce = eoidCache[eoid];
            if (eoce) {
                for (int i = 0; i < (int)eoce->edv.size(); i++) {
                    dot_descriptor &ed = eoce->edv[i];
                    /* Release edescCache entry */
                    edesc_cache_entry *edce = edescCache[ed.id];
                    if (edce) {
                        dot_descriptor &d = edce->dd;
                        /* Release descCache entry */
                        dd_cache_entry *ddce = descCache[d.id];
                        if (ddce) {
                            delete ddce;
                        }
                        delete edce;
                    }
                }
                delete eoce;
            }
            delete oce;
        }
    }

    return result;
}


tamed void
storagePlugin_ce::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                               bool retain, cbs cb)
{
    tvars { 
        str err; 
        dd_cache_entry *ddce;
        dot_descriptor ed;
    }


    dwarn(DEBUG_CE) << "storagePlugin_ce::put_ichunk: called\n";

    twait {
        unencrypted_child_sp->put_ichunk(d, uiop, retain, mkevent(err));
    }

    if (err) {
        warn << "storagePlugin_ce::put_ichunk: child returned error: " << err << "\n";
        (*cb)(err);
        return;
    }

    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::put_ichunk: checking CE cache\n";
        ddce = descCache[d->id];
        if (!ddce) {
            warn << "storagePlugin_ce::put_ichunk: Descriptor " << d->id << " not found in local cache\n";
            err = "descriptor not found in local cache";
            (*cb)(err);
            return;
        }
        else {
            ed = ddce->ed;
        }
#if TEST_OVERHEAD
        printf("storagePlugin_ce::put_ichunk:\n");
        printf("Encryption time = %f\n", encryption_time);
        printf("Decryption time = %f\n", decryption_time);
        printf("Digest time = %f\n", digest_time);
#endif
        twait {
            if (encrypted_child_sp) {
                assert(temp_chunk_buffer);
                encrypted_child_sp->put_ichunk(New refcounted<dot_descriptor>(ed), temp_chunk_buffer, retain, mkevent (err));
            }
        }
        temp_chunk_buffer = NULL;
        (*cb)(err);
        return;
    }

}

bool 
storagePlugin_ce::release_ichunk(ref<dot_descriptor> d)
{
    bool result = unencrypted_child_sp->release_ichunk(d);
    if (result) {
        dd_cache_entry *ddce = descCache[d->id];
        if (ddce) {
            dot_descriptor &ed = ddce->ed;
            edesc_cache_entry *edce = edescCache[ed.id];
            if (edce) {
                delete edce;
            }
            delete ddce;
        }
    }

    return result;
}

tamed void
storagePlugin_ce::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> o;
        metadata ce_md;
    }

    for (int i = 0; i < (int)oid->md.list.size(); i++) {
        metadata_entry &me = oid->md.list[i];
        if (me.module == "ENCRYPT") {
            ce_md.list.push_back(me);
        }
    }

    twait {
        unencrypted_child_sp->get_descriptors_init(oid, mkevent (err, o));
    }
    
    if (err)
        warn("storagePlugin_ce::get_descriptors_init: Error message from child: %s\n",
             err.cstr());
    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors_init: Child returned successfully.\n";
        if (o) {
            for (int i = 0; i < (int)ce_md.list.size(); i++) {
                o->md.list.push_back(ce_md.list[i]);
            }
        }
    }

    (*cb)(err, o);
}

tamed void
storagePlugin_ce::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb)
{
    tvars {
        str err;
        ptr< vec<dot_descriptor> > descs;
        bool end(true);
        eoid_cache_entry *eoce;
    }

    /* No need to get descriptors from sp
     * Check if the oid is present in the eoidCache
     * and return the descriptors */

    dwarn(DEBUG_CE) << "storagePlugin_ce::sp_get_descriptors: called\n";
    eoce = eoidCache[oid->id];
    if (eoce) {
        descs = New refcounted<vec<dot_descriptor> > (eoce->edv);
        err = NULL;
        dwarn(DEBUG_CE) << "storagePlugin_ce::sp_get_descriptors: eoid " << oid->id << " found in local cache\n";
        dwarn(DEBUG_CE) << "storagePlugin_ce::sp_get_descriptors: sending " << descs->size() << " descriptors\n";
        (*cb)(err, descs, end);
        return;
    }

    dwarn(DEBUG_CE) << "storagePlugin_ce::sp_get_descriptors: Unable to lookup OID " << oid->id << " in local cache\n";
    twait {
        unencrypted_child_sp->sp_get_descriptors(oid, mkevent (err, descs, end));
    }

    (*cb)(err, descs, end);
}

tamed void
storagePlugin_ce::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb)
{
    tvars {
        str err;
        ptr<dot_descriptor> desc;
    }

    twait {
        unencrypted_child_sp->get_chunk_init(d, mkevent (err, desc));
    }
    
    if (err)
        warn("storagePlugin_ce::get_chunk_init: Error message from child: %s\n",
             err.cstr());

    (*cb)(err, desc);
}

tamed void
storagePlugin_ce::get_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    tvars {
        str err;
        ptr<desc_result> dres;
        edesc_cache_entry *edce;
        ptr<dot_descriptor> dd;
        bool do_encrypt(true);
        double now, cost;
    }
    
    /* Check for the desc in edescCache
     * get the chunk
     * encrypt the chunk with it's own digest
     * change dres appropriately */

    edce = edescCache[d->id];
    if (!edce) {
        do_encrypt = false;
        dd = New refcounted<dot_descriptor> (*d);
    }
    else {
        do_encrypt = true;
        dd = New refcounted<dot_descriptor>(edce->dd);
    }

    twait {
        unencrypted_child_sp->get_chunk(dd, mkevent (err, dres));
    }

    /* Encryption of the chunk here
     * Change the descriptor id
     * Add metadata to the descriptor */
    if (err) {
        warn << "storagePlugin_ce: local cache update error from child : " << err << "\n";
    }
    else {
        if (!do_encrypt) {
            dwarn(DEBUG_CE) << "storagePlugin_ce::get_chunk: The descriptor doesn't have CE-metadata, hence returning the chunk unencrypted\n";
            (*cb)(err, dres);
            return;
        }

        unsigned int data_len = dres->data->resid();
        unsigned char *plaintext = New (unsigned char[data_len]);
	dres->data->copyout(plaintext);
       
        // Encrypt the chunk
        EVP_CIPHER_CTX ctx;
        int outlen1, outlen2;
        str descriptor_id = strbuf() << dd->id;
#if TEST_OVERHEAD
        now = return_time(SECONDS);
#endif
        //Bug-fix - Need a deterministic IV here
        //Using 0 - Suggested by Adrian
        EVP_EncryptInit(&ctx, EVP_aes_256_cbc(), (unsigned char *)descriptor_id.cstr(), NULL);
        unsigned char *ciphertext = New (unsigned char[data_len + EVP_CIPHER_CTX_block_size(&ctx)]);
        EVP_EncryptUpdate(&ctx, ciphertext, &outlen1, plaintext, data_len); 
        EVP_EncryptFinal(&ctx, ciphertext + outlen1, &outlen2);
#if TEST_OVERHEAD
        cost = return_time(SECONDS) - now;
        encryption_time += cost;
#endif
        int ciphertext_size = outlen1 + outlen2;

        dres->data->rembytes(data_len);
        dres->data->copy(ciphertext, ciphertext_size);

        // Create an appropriate descriptor to be returned in dres
        ref<dot_descriptor> dres_desc = New refcounted<dot_descriptor> (edce->ed);
        for (int j = 0; j < (int)dres->desc->md.list.size(); j++) {
            dres_desc->md.list.push_back(dres->desc->md.list[j]);
        }

        dres->desc = dres_desc;

        delete plaintext;
        delete ciphertext;
    }


    (*cb)(err, dres);
}

tamed void
storagePlugin_ce::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb)
{
    /* Is this function called at all? */

    for (int i = 0; i < (int)dv->size(); i++) {
        ref<dot_descriptor> d = New refcounted<dot_descriptor>((*dv)[i]);
        get_chunk(d, cb);
    }
}

void 
storagePlugin_ce::sp_notify_descriptors(ref<dot_oid_md> oid,
				       ptr<vec<dot_descriptor> > descs)
{
    dwarn(DEBUG_CE) << "storagePlugin_ce::sp_notify_descriptors: called\n";
    ref<dot_oid_md> eoid = New refcounted<dot_oid_md> ();
    ref<vec<dot_descriptor> >edv = New refcounted<vec<dot_descriptor> >();
    bool encrypt = false;
    eoid_cache_entry *eoce = NULL;
    oidcache_entry *oce = oidCache[oid->id];
    if (oce) {
        eoid->id = oce->eoid;
        eoce = eoidCache[eoid->id];
        if (eoce)
            encrypt = true;
    }
    for (int i = 0; i < (int)oid->md.list.size(); i++) {
        metadata_entry &me = oid->md.list[i];
        if (me.module == "ENCRYPT") {
            // do not add it to eoid
        }
        else {
            eoid->md.list.push_back(me);
        }
    }

    if (encrypted_child_sp && encrypt)
        encrypted_child_sp->sp_notify_descriptors(eoid, New refcounted<vec<dot_descriptor> > (eoce->edv));
    unencrypted_child_sp->sp_notify_descriptors(oid, descs);
}

tamed void 
storagePlugin_ce::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    tvars {
        str err;
        ptr<bitvec> bmp;
    }

    twait {
        unencrypted_child_sp->sp_get_bitmap(oid, mkevent (err, bmp));
    }
    
    (*cb)(err, bmp);
}

/**************************************************************************
 * XFER ZONE
 **************************************************************************/

//can't use twait in the functions below since the get_descriptors 
// and the get_chunks calls in xferPlugin_gtc etc call back multiple times
// and TAME thinks that the function is overcalled.
// TAME probably keeps a counter as to how many times a function call was made with in twait
// and hence allows only that many callbacks

tamed void
storagePlugin_ce::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{

    dwarn(DEBUG_CE) << "storagePlugin_ce::xp_get_descriptors: called\n";

    tvars {
        int i;
        bool get_encrypted(false), end;
        str eoid_str, s;
        char eoid_buf[EVP_MAX_MD_SIZE];
        ref<dot_oid_md> eoid(New refcounted<dot_oid_md>());
        ptr<vec<dot_descriptor> > descs;
        double now, cost;
        rendezvous_t<> rv;
        event<str, ptr<vec<dot_descriptor> >, bool>::ptr ev;
    }

    ev = mkevent(rv, s, descs, end);
    ev->set_reuse(true);
    /* Check for the eOID metadata in oid and 
     * send a request for eOID instead of OID */
    for (i = 0; i < (int)oid->md.list.size(); i++) {
        metadata_entry &me = oid->md.list[i];
        if (me.module == "ENCRYPT" && me.key == "eOID") {
            eoid_str = dearmor64((char *)me.val.cstr(), me.val.len());
            if (!eoid_str) {
                fatal << "storagePlugin_ce::xp_get_descriptors: Incorrect length passed to dearmor64\n";
            }
            memcpy(eoid_buf, eoid_str.cstr(), eoid_str.len());
            eoid->id.set((char *)eoid_buf, eoid_str.len());
            get_encrypted = true;
        }
        else {
            eoid->md.list.push_back(me);
        }
    }

    if (get_encrypted) {
        dwarn(DEBUG_CE) << "storagePlugin_ce::xp_get_descriptors: calling get_descriptors for " << eoid->id << "\n";
        xp->xp_get_descriptors(eoid, hints, ev);
    }
    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors: eOID not found in dot_oid_md - getting " << oid->id << "\n";
        xp->xp_get_descriptors(oid, hints, ev);
    }
        
    do {
        twait(rv);

        if (!descs) {
            dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors_cb: descs is a null pointer! Error message from child: " << s << "\n";
            (*cb)(s, descs, end);
            return;
        }
        
        /* For each descriptor received, create back the original descriptor
         * Update the edescCache and descCache with proper entries
         * Send the unencrypted descriptor list back to cb */
        dwarn(DEBUG_CE) << "storagePlugin_ce::xp_get_descriptors: Got back " << descs->size() << " descriptors\n";
        ptr<vec<dot_descriptor> > dv = New refcounted<vec<dot_descriptor> >();
        for (int i = 0; i < (int)descs->size(); i++) {
            dot_descriptor &ed = (*descs)[i];
            dot_descriptor d;
            dd_cache_entry *ddce;
            edesc_cache_entry *edce = edescCache[ed.id];
            if (edce) {
                dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors_cb: Duplicate entry for edescriptor in edescCache\n";
                d = edce->dd;
            }
            else {
                str encrypted_key = "";
                str iv_str =  "";
                int chunk_len = -1;
                for (int j = 0; j < (int)ed.md.list.size(); j++) {
                    metadata_entry &me = ed.md.list[j];
                    if (me.module == "ENCRYPT") {
                        if (me.key == "key") {
                            encrypted_key = dearmor64(me.val.cstr(), me.val.len());
                        }
                        else if (me.key == "iv") {
                            iv_str = dearmor64(me.val.cstr(), me.val.len());
                        }
                        else if (me.key == "chunk_len") {
                            chunk_len = atoi(me.val.cstr());
                        }
                    }
                    d.md.list.push_back(me);
                }

                if (encrypted_key == "" || iv_str == "" || chunk_len < 0) {
                    dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors_cb: CE metadata not found in the received descriptor\n";
                    dv->push_back(ed);
                    continue;
                }
                /* Decrypt the encrypted key to obtain the descriptor of the original chunk
                 * which is also the key with which the chunk is encrypted */
                str oid_str = strbuf() << oid->id;
                int outlen1, outlen2;
                EVP_CIPHER_CTX ctx;
#if TEST_OVERHEAD
                now = return_time(SECONDS);
#endif
                EVP_DecryptInit(&ctx, EVP_aes_256_cbc(), (unsigned char *)oid_str.cstr(), (unsigned char *)iv_str.cstr());
                unsigned char *desc_key = New (unsigned char[encrypted_key.len() + EVP_CIPHER_CTX_block_size(&ctx) + 1]);
                EVP_DecryptUpdate(&ctx, desc_key, &outlen1, (unsigned char *)encrypted_key.cstr(), encrypted_key.len());
                if (!EVP_DecryptFinal(&ctx, desc_key + outlen1, &outlen2)) {
                    warn << "storagePlugin_ce::get_descriptors_cb: Incorrect padding - Decrypt unsuccessful\n";
                }
#if TEST_OVERHEAD
                cost = return_time(SECONDS) - now;
                decryption_time += cost;
#endif
                str unenc_desc_str((char *)desc_key, outlen1 + outlen2);
                str desc_key_bin = hex2bytes(unenc_desc_str);
                d.id.set((char *)desc_key_bin.cstr(), desc_key_bin.len());
                d.length = chunk_len;
                edce = New edesc_cache_entry(ed.id, d);
                edce->ed = ed;
                ddce = descCache[d.id];
                if (ddce) {
                    dwarn(DEBUG_CE) << "storagePlugin_ce::get_descriptors_cb: Duplicate entry for descriptor in descCache\n";
                }
                else {
                    ddce = New dd_cache_entry(d.id, ed);
                    ddce->dd = d;
                }

                delete desc_key;
            }
            dv->push_back(d);

        }
        (*cb)(s, dv, end);
    } while(!end);

    ev->finish();
}

tamed void 
storagePlugin_ce::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb)
{
    dwarn(DEBUG_CE) << "storagePlugin_ce::xp_get_chunks: called\n";
    /* Convert the dv list to edescriptor list and 
     * call get_chunks with the edescriptor list */

    ref< vec<dot_descriptor> > edv = New refcounted<vec<dot_descriptor> >();
    for (int i = 0; i < (int)dv->size(); i++) {
        dd_cache_entry *ddce = descCache[(*dv)[i].id];
        if (!ddce) {
            dwarn(DEBUG_CE) << "storagePlugin_ce::get_chunks: No entry found in descCache for descriptor " << (*dv)[i].id << "\n";
            edv->push_back((*dv)[i]);
        }
        else {
            edv->push_back(ddce->ed);
        }
    }
  
    xp->xp_get_chunks(edv, hints, wrap(this, &storagePlugin_ce::get_chunk_cb, cb)); 
}

void
storagePlugin_ce::get_chunk_cb(chunk_cb cb1, str s, ptr<desc_result> res)
{
    double now, cost;

    dwarn(DEBUG_CE) << "storagePlugin_ce::get_chunk_cb: called\n";
    if (s || !res) {
        (*cb1)(s, res);
        return;
    }

    /* Extract the ciphertext into a buffer */
    unsigned char *ciphertext = New (unsigned char[res->data->resid()]);
    res->data->copyout(ciphertext);

    /* Store the encrypted chunk for further use in put_ichunk */
    temp_chunk_buffer = New refcounted<suio>();
    temp_chunk_buffer->copy(ciphertext, res->data->resid());

    /* Decrypt ciphertext using desc_key as the key
     * output: plaintext */
    edesc_cache_entry *edce = edescCache[res->desc->id];
    if (!edce) {
        dwarn(DEBUG_CE) << "storagePlugin_ce::get_chunk_cb: Could not decrypt the chunk - key not found\n";
        (*cb1)(s, res);
        return;
    }

    EVP_CIPHER_CTX ctx;
    str key_str = strbuf() << edce->dd.id;
    int outlen1, outlen2;
#if TEST_OVERHEAD
    now = return_time(SECONDS);
#endif
    EVP_DecryptInit(&ctx, EVP_aes_256_cbc(), (unsigned char *)key_str.cstr(), NULL);
    unsigned char *plaintext = New (unsigned char[res->data->resid() + EVP_CIPHER_CTX_block_size(&ctx) + 1]);
    EVP_DecryptUpdate(&ctx, plaintext, &outlen1, (unsigned char *)ciphertext, res->data->resid());
    if (!EVP_DecryptFinal(&ctx, plaintext + outlen1, &outlen2)) {
        warn << "storagePlugin_ce::get_chunk_cb: Incorrect padding in encrypted chunk\n";
    }
#if TEST_OVERHEAD
    cost = return_time(SECONDS) - now;
    decryption_time += cost;
#endif
    assert((int)(res->data->resid() + EVP_CIPHER_CTX_block_size(&ctx) + 1) >= outlen1 + outlen2);

    /* Make appropriate modifications to res */
    res->data->rembytes(res->data->resid());
    res->data->copy(plaintext, outlen1 + outlen2);
    res->desc = New refcounted<dot_descriptor> (edce->dd);

    delete ciphertext;
    delete plaintext;
    (*cb1)(s, res);
}

tamed void 
storagePlugin_ce::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    /* Convert d to edescriptor
     * and call cancel chunk with the edescriptor */

    dd_cache_entry *ddce = descCache[d->id];
    if (!ddce) {
        dwarn(DEBUG_CE) << "storagePlugin_ce::cancel_chunk: No entry found in descCache for descriptor " << d->id << "\n";
        xp->cancel_chunk(d, cb);
    }
    else {
        xp->cancel_chunk(New refcounted<dot_descriptor>(ddce->ed), cb);
    }
}

tamed void 
storagePlugin_ce::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    /* Convert descriptor list to edescriptor list and
     * call cancel_chunks with the edescriptor list */
    ref<vec<dot_descriptor> > edv = New refcounted<vec<dot_descriptor> >();
    for (u_int i = 0; i < dv->size(); i++) {
        dd_cache_entry *ddce = descCache[(*dv)[i].id];
        if (!ddce) {
            dwarn(DEBUG_CE) << "storagePlugin_ce::cancel_chunk: No entry found in descCache for descriptor " << (*dv)[i].id << "\n";
        }
        else {
            edv->push_back(ddce->ed);
        }
    }
    xp->cancel_chunks(edv, cb);
}

void 
storagePlugin_ce::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    dwarn(DEBUG_CE) << "storagePlugin_ce::xp_notify_descriptors: called\n";
    ref<dot_oid_md> eoid = New refcounted<dot_oid_md> ();
    bool encrypt = false;
    
    for (u_int i = 0; i < oid->md.list.size(); i++) {
        metadata_entry &me = oid->md.list[i];
        if (me.module == "ENCRYPT") {
            // Do not add the metadata to eoid
        }
        else {
            eoid->md.list.push_back(me);
        }
    }
    oidcache_entry *oce = oidCache[oid->id];
    if (oce) {
        eoid->id = oce->eoid;
        encrypt = true;
    }

    if (encrypt) {
        ref<vec<dot_descriptor> > edv = New refcounted<vec<dot_descriptor> >();
        if (descs) {
            for (u_int i = 0; i < descs->size(); i++) {
                dd_cache_entry *ddce = descCache[(*descs)[i].id];
                if (ddce) {
                    edv->push_back(ddce->ed);
                }
                else {
                    edv->push_back((*descs)[i]);
                }
            }
        }
        dwarn(DEBUG_CE) << "storagePlugin_ce::xp_notify_descriptors: called with encrypted-OID " << eoid->id << "\n";
        xp->xp_notify_descriptors(eoid, edv);
    }
    else {
        dwarn(DEBUG_CE) << "storagePlugin_ce::xp_notify_descriptors: called with OID " << oid->id << "\n";
        xp->xp_notify_descriptors(oid, descs);
    }
}

void 
storagePlugin_ce::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    ref<vec<dot_descriptor> >edv = New refcounted<vec<dot_descriptor> >();
    for (u_int i = 0; i < dv->size(); i++) {
        dd_cache_entry *ddce = descCache[(*dv)[i].id];
        if (ddce) {
            edv->push_back(ddce->ed);
        }
        else {
            edv->push_back((*dv)[i]);
        }
    }
    xp->update_hints(edv, hints);
}

tamed void
storagePlugin_ce::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    ref<dot_oid_md> eoid = New refcounted<dot_oid_md> ();
    bool get_encrypted = false;

    for (u_int i = 0; i < oid->md.list.size(); i++) {
        metadata_entry &me = oid->md.list[i];
        if (me.module == "ENCRYPT" && me.key == "eOID") {
            dwarn(DEBUG_CE) << "storagePlugin_ce::get_bitmap: CE metadata found in the OID - getting bitmap for eOID\n";
            str eoid_str = dearmor64((char *)me.val.cstr(), me.val.len());
            if (eoid_str == NULL) {
                warn << "storagePlugin_ce::xp_get_bitmap: Incorrect length passed to dearmor64\n";
            }
            char eoid_buf[EVP_MAX_MD_SIZE];
            memcpy(eoid_buf, eoid_str.cstr(), eoid_str.len());
            eoid->id.set((char *)eoid_buf, eoid_str.len());
            get_encrypted = true;
        }
        else {
            eoid->md.list.push_back(me);
        }
    }
    if (get_encrypted) {
        xp->xp_get_bitmap(eoid, hints, wrap(this, &storagePlugin_ce::get_bitmap_cb, cb));
    }
    else {
        xp->xp_get_bitmap(oid, hints, wrap(this, &storagePlugin_ce::get_bitmap_cb, cb));
    }
}

void
storagePlugin_ce::get_bitmap_cb(bitmap_cb cb1, str s, ptr<bitvec> bmp)
{
    (*cb1)(s, bmp);
}

