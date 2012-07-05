/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_portable.h"

#define PORTABLE_CHECK_SEC    5
#define PORTABLE_MOUNT_PATH   "/mnt/flash/.dot/pscache"

desc_request::desc_request(chunk_cb cb, dot_descriptor dd)
    : cb(cb), desc_id(dd.id), length(dd.length)
{
}

desc_request::~desc_request()
{
}

xferPlugin_portable::xferPlugin_portable(gtcd *m, xferPlugin *next_xp)
{
    assert(m);
    if (next_xp)
        fatal << __PRETTY_FUNCTION__ << " next_xp is not NULL\n"
              << "Make sure that this storage plugin comes last\n";

    prev_cache = false;
    ps_check = delaycb(PORTABLE_CHECK_SEC, 0,
                       wrap(this, &xferPlugin_portable::check_device));
}

void
xferPlugin_portable::check_descs(desc_request *d)
{
    char cache_path[PATH_MAX];
    str s = NULL;
    int ret;

    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_MD_CTX desc_hash;
    unsigned int diglen;
    //strbuf chunkname;

    cache_path[0] = '\0';
    strcat(cache_path, PORTABLE_MOUNT_PATH);
    strcat(cache_path, "/");
    str ss = strbuf() << d->desc_id;
    strcat(cache_path, ss);

    struct stat sb;
    if (stat(cache_path, &sb) != -1) {
        // Data found. Read and return
        ref<suio> data = New refcounted<suio>;
        int fd = open(cache_path, O_RDONLY);
        if (fd == -1) {
            s = "Unable to open portable device";
	    return;
        }
        ret = data->input(fd, d->length);
	close(fd);
	
        if (ret == -1 || (unsigned int) ret != d->length) {
            s = "Unable to read entire descriptor";
	    return;
        }

	EVP_MD_CTX_init(&desc_hash);
	EVP_DigestInit(&desc_hash, EVP_sha1());
	char *sbuf = New char[d->length];
	data->copyout(sbuf, d->length);
	EVP_DigestUpdate(&desc_hash, sbuf, d->length);
	EVP_DigestFinal(&desc_hash, digest, &diglen);
	// chunkname << hexdump(digest, diglen);
        dot_oid chunkname;
        chunkname.set((char *)digest, diglen);
	//str verify = chunkname;
	//if (verify.cmp(d->desc_id) != 0) {
        if (d->desc_id != chunkname) {
	    warn << "Hashes not equal on portable storage device.\n";
	    delete[] sbuf;
	    return;
	}

	ref<dot_descriptor> dd = New refcounted<dot_descriptor>;
	dd->id = d->desc_id;
	dd->length = d->length;
	// Copy data back
	data = New refcounted<suio>;
	data->copy(sbuf, d->length);
	ref<desc_result> dr = 
	    New refcounted<desc_result> (dd, data, false);
	(*d->cb)(NULL, dr);

        desc_request_cache.remove(d);
	delete[] sbuf;
        delete d;
    }
}

void
xferPlugin_portable::check_device()
{
    struct stat sb;
    if (-1 == stat(PORTABLE_MOUNT_PATH, &sb)) {
        prev_cache = false;
        // Nothing found
        ps_check = delaycb(PORTABLE_CHECK_SEC, 0,
                           wrap(this,&xferPlugin_portable::check_device));
        return;
    }
    
    // Device found. Were we looking at it earlier or should we just
    // run through and check the whole thing?
    if (prev_cache) {
        if (sb_cached.st_dev == sb.st_dev && sb_cached.st_ino == sb.st_ino) {
            return;
            ps_check = delaycb(PORTABLE_CHECK_SEC, 0,
                               wrap(this,&xferPlugin_portable::check_device));

        }
    }

    warn << "New portable device with DOT cache discovered\n";

    sb_cached.st_dev = sb.st_dev;
    sb_cached.st_ino = sb.st_ino;
    prev_cache = true;

    // Look at portable storage device and figure out if it has the
    // data we need    
    desc_request_cache.traverse(wrap(this, &xferPlugin_portable::check_descs));

    ps_check = delaycb(PORTABLE_CHECK_SEC, 0,
                       wrap(this,&xferPlugin_portable::check_device));
}

/** PUBLIC **/

void
xferPlugin_portable::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
				     descriptors_cb cb, ptr<closure_t>)
{
    (*cb)("Error: PSP called for xp_get_descriptors.", NULL, false);
}

void
xferPlugin_portable::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                               chunk_cb cb, ptr<closure_t>)
{
    desc_request *dr = New desc_request(cb, *d);
    desc_request_cache.insert(dr);
}

void
xferPlugin_portable::xp_get_chunks(ref< vec<dot_descriptor> > dv, 
			        ref<hv_vec > hints, chunk_cb cb, ptr<closure_t>)
{
    for (unsigned int i = 0; i < dv->size(); i++) {
        desc_request *dr = New desc_request(cb, (*dv)[i]);
        desc_request_cache.insert(dr);
    }
    if (prev_cache) {
	desc_request_cache.traverse(wrap(this, &xferPlugin_portable::check_descs));
    }
}

void
xferPlugin_portable::cancel_chunk(ref<dot_descriptor> dd, cancel_cb cb,
				  ptr<closure_t>)
{
    desc_request *d = desc_request_cache[dd->id];
    if (d) {
        desc_request_cache.remove(d);
        delete d;
    }
}

void
xferPlugin_portable::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb,
				   ptr<closure_t>)
{
    desc_request *d;

    for (unsigned int i = 0; i < dv->size(); i++) {
        d = desc_request_cache[(*dv)[i].id];
        warn << "cancel for " << (*dv)[i].id << "\n";
        if (d != NULL) {
            desc_request_cache.remove(d);
            delete d;
        }
    }
}

void 
xferPlugin_portable::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
}

void 
xferPlugin_portable::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
}

void
xferPlugin_portable::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
				     bitmap_cb cb, ptr<closure_t>)
{
    (*cb)("Error: PSP called for get_bitmap.", NULL);
}
