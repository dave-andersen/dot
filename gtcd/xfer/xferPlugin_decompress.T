/* -*- c++ -*- */
/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_decompress.h"

//can't use twait in the functions below since the get_descriptors 
// and the get_chunks calls in xferPlugin_gtc etc call back multiple times
// and TAME thinks that the function is overcalled.
// TAME probably keeps a counter as to how many times a function call was made with in twait
// and hence allows only that many callbacks

tamed void
xferPlugin_decompress::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    warn << "xferPlugin_decompress::get_descriptors: called\n";

    xp->xp_get_descriptors(oid, hints,
			wrap(this, &xferPlugin_decompress::get_descriptors_cb, cb));
}

void
xferPlugin_decompress::get_descriptors_cb(descriptors_cb cb1, str s, ptr<vec<dot_descriptor> > descs, bool end)
{
    warn << "xferPlugin_decompress:: get_descriptors_cb called\n";
    (*cb1)(s, descs, end);
}

tamed void 
xferPlugin_decompress::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb)
{
    warn << "xferPlugin_decompress::get_chunk: called\n";
    //xp->get_chunk(d, hints, wrap(this, &xferPlugin_decompress::get_chunk_cb, cb));
}

void
xferPlugin_decompress::get_chunk_cb(chunk_cb cb1, str s, ptr<desc_result> res)
{
    if (s || !res) {
        (*cb1)(s, res);
        return;
    }

    bool ucomp_flag = false;
    uLong ucomp_len, comp_len;
    for (size_t i = 0; i < res->desc->md.list.size(); i++) {
	if (res->desc->md.list[i].module == "COMPRESS") {
   	    if (res->desc->md.list[i].key == "compressed" && res->desc->md.list[i].val == "gzip") {
		ucomp_flag = true;
		ucomp_len = (uLong)res->desc->length;
		comp_len = (uLong)res->data->resid();
		break;
	    }
	}
    }

    if (ucomp_flag) {

	Bytef *compressed_data = New (Bytef[comp_len]);
	long buffer_offset = 0;
	for (size_t i = 0; i < res->data->iovcnt(); i++) {
	    const iovec &buf_struct = res->data->iov()[i];
	    memcpy(compressed_data + buffer_offset,buf_struct.iov_base, buf_struct.iov_len);
	    buffer_offset += buf_struct.iov_len;
	}

	Bytef *uncompressed_data = New (Bytef[ucomp_len]);
	int result = uncompress(uncompressed_data, (uLongf *)&ucomp_len, compressed_data, comp_len);
	if (result != Z_OK) {
	    switch(result) {
	    case Z_MEM_ERROR:  warn << "Z_MEM_ERROR! ";  break;
	    case Z_BUF_ERROR:  warn << "Z_BUF_ERROR! ";  break;
	    case Z_DATA_ERROR: warn << "Z_DATA_ERROR! "; break;
	    }
	    
	    fatal << result << ": Uncompress failed\n";
	}
		
	res->data->rembytes(comp_len);
	res->data->copy(uncompressed_data, ucomp_len);

	delete compressed_data;
	delete uncompressed_data;
		
	(*cb1)(s, res);
    }
    else {
	(*cb1)(s, res);
    }
}

tamed void 
xferPlugin_decompress::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb)
{
    warn << "xferPlugin_decompress::get_chunks: called\n";

    for (size_t i = 0; i < dv->size(); i++) {
        metadata_entry e;
	e.module = "COMPRESS";
	e.key = "compress";
	e.val = "gzip";
	(*dv)[i].md.list.push_back(e);
    }
  
    xp->xp_get_chunks(dv, hints, wrap(this, &xferPlugin_decompress::get_chunk_cb, cb)); 
}

tamed void 
xferPlugin_decompress::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    warn << "xferPlugin_decompress::cancel_chunk: called\n";
    xp->cancel_chunk(d, cb);
}

tamed void 
xferPlugin_decompress::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    warn << "xferPlugin_decompress::cancel_chunks: called\n";
    xp->cancel_chunks(dv, cb);
}

void 
xferPlugin_decompress::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    warn << "xferPlugin_decompress::xp_notify_descriptors: called\n";
    xp->xp_notify_descriptors(oid, descs);
}

void 
xferPlugin_decompress::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    warn << "xferPlugin_decompress::update_hints: called\n";
    xp->update_hints(dv, hints);
}

tamed void
xferPlugin_decompress::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    warn << "xferPlugin_decompress::get_bitmap: called\n";
    xp->xp_get_bitmap(oid, hints, wrap(this, &xferPlugin_decompress::get_bitmap_cb, cb));
}

void
xferPlugin_decompress::get_bitmap_cb(bitmap_cb cb1, str s, ptr<bitvec> bmp)
{
    warn << "xferPlugin_decompress:: get_bitmap called\n";
    (*cb1)(s, bmp);
}
