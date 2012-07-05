/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "servePlugin_compress.h"

void 
servePlugin_compress::get_default_hint(ref<vec<oid_hint> > hint)
{
    //dwarn(DEBUG_SERVE_NOOP) << "servePlugin_compress::get_default_hint: called\n";
    for (unsigned int i = 0; i < seplugins.size(); i++) {
        seplugins[i]->get_default_hint(hint);
    }
}

tamed void
servePlugin_compress::serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb)
{
    if (parent)
	parent->serve_descriptors(oidmd, cb);
    else
	m->serve_descriptors(oidmd, cb);
}

tamed void
servePlugin_compress::serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    if (parent)	
	parent->serve_bitmap(oid, cb);
    else
	m->serve_bitmap(oid, cb);
}

tamed void
servePlugin_compress::serve_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    tvars {
        str err;
        ptr<desc_result> dres;
    }

    twait {
        if (parent)
	    parent->serve_chunk(d, mkevent (err, dres));
	else
	    m->serve_chunk(d, mkevent (err, dres));
    }
   
   
    bool comp_flag = false;
    for(int i = 0; i < (int)d->md.list.size(); i++) {
        metadata_entry &e = d->md.list[i];
	if(e.module == "COMPRESS") {
	    if(e.key == "compress" && e.val == "gzip")
	    comp_flag = true;
	}
    }

    if(comp_flag) {
	metadata_entry e;
	e.module = "COMPRESS";
	e.key = "compressed";
	e.val = "gzip";
	dres->desc->md.list.push_back(e);

	uLong ucomp_len = (uLong)d->length;
	Bytef *uncompressed_data = New (Bytef[ucomp_len]);
	long buffer_offset = 0;
	for(int i = 0; i < (int)dres->data->iovcnt(); i++) {
	    const iovec &buf_struct = dres->data->iov()[i];
	    memcpy(uncompressed_data + buffer_offset,buf_struct.iov_base, buf_struct.iov_len);
	    buffer_offset += buf_struct.iov_len;
	}
	    
	uLong comp_len = compressBound(ucomp_len);
	Bytef *compressed_data = New (Bytef[comp_len]);
	int compress_result = compress(compressed_data, (uLongf *)&comp_len, uncompressed_data, ucomp_len);
	if(compress_result != Z_OK) {
	    fatal << "Compression of data failed!\n";
	}
	//warn << "Uncompressed Length = " << ucomp_len << "\tCompressed Length = " << comp_len << "\n";
	dres->data->rembytes(ucomp_len);
	dres->data->copy(compressed_data, comp_len);

	delete compressed_data;
	delete uncompressed_data;
    }
    
    (*cb)(err, dres);
}
