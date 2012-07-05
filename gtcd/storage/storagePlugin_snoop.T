/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_snoop.h"

tamed void
storagePlugin_snoop::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb)
{
    tvars { str err; }

    {
        metadata_entry e;
        e.module = "NOOP";
        e.key = "dl_key0";
        e.val = "dl_val0";
        d->md.list.push_back(e);
    }

    twait {
        sp->put_chunk(id, d, buf, len, mkevent (err));
    }
    if (err)
        warn("storagePlugin_snoop::put_chunk: Error message from child: %s\n",
             err.cstr());
//  else
//       warn("storagePlugin_snoop::put_chunk: Child returned successfully.\n");
    (*cb)(err);
}

tamed void
storagePlugin_snoop::commit_object(dot_sId id, commit_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> oid;
    }

    twait {
        sp->commit_object(id, mkevent (err, oid));
    }

    if (err)
        warn("storagePlugin_snoop::commit_object: Error message from child: %s\n",
             err.cstr());
    else {
        warn("storagePlugin_snoop::commit_object: Child returned successfully.\n");
        metadata_entry e;
        e.module = "NOOP";
        e.key = "oid_key0";
        e.val = "oid_val0";
        oid->md.list.push_back(e);
    }

    (*cb)(err, oid);
}

tamed void
storagePlugin_snoop::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                               bool retain, cbs cb)
{
    tvars { str err; }
    
    twait {
        sp->put_ichunk(d, uiop, retain, mkevent (err));
    }
    /* Do something with return value if necessary */
    (*cb)(err);
}

tamed void
storagePlugin_snoop::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> o;
    }

    twait {
        sp->get_descriptors_init(oid, mkevent (err, o));
    }
    
    if (err)
        warn("storagePlugin_snoop::get_descriptors_init: Error message from child: %s\n",
             err.cstr());
    else {
        warn("storagePlugin_snoop::get_descriptors_init: Child returned successfully.\n");
        metadata_entry e;
        e.module = "NOOP";
        e.key = "oid++_key0";
        e.val = "oid++_val0";
        o->md.list.push_back(e);
    }

    (*cb)(err, o);
}

tamed void
storagePlugin_snoop::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb)
{
    tvars {
        str err;
        ptr< vec<dot_descriptor> > descs;
        bool end;
    }

    twait {
        sp->sp_get_descriptors(oid, mkevent (err, descs, end));
    }
    /* Do something with return values if necessary */
    (*cb)(err, descs, end);
}

tamed void
storagePlugin_snoop::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb)
{
    tvars {
        str err;
        ptr<dot_descriptor> desc;
    }

    twait {
        sp->get_chunk_init(d, mkevent (err, desc));
    }
    
    if (err)
        warn("storagePlugin_snoop::get_chunk_init: Error message from child: %s\n",
             err.cstr());
    else {
        warn("storagePlugin_snoop::get_chunk_init: Child returned successfully.\n");
        metadata_entry e;
        e.module = "NOOP";
        e.key = "dl++_key0";
        e.val = "dl++_val0";
        desc->md.list.push_back(e);
    }

    (*cb)(err, desc);
}

tamed void
storagePlugin_snoop::get_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    tvars {
        str err;
        ptr<desc_result> dres;
    }
    
    twait {
        sp->get_chunk(d, mkevent (err, dres));
    }
    /* Do something with return values if necessary */
    (*cb)(err, dres);
}

tamed void
storagePlugin_snoop::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb)
{
    tvars {
        str err;
        ptr<desc_result> dres;
    }
    
    twait {
        sp->sp_get_chunks(dv, mkevent (err, dres));
    }
    /* Do something with return values if necessary */
    (*cb)(err, dres);
}

void 
storagePlugin_snoop::sp_notify_descriptors(ref<dot_oid_md> oid,
				       ptr<vec<dot_descriptor> > descs)
{
    sp->sp_notify_descriptors(oid, descs);
}

tamed void 
storagePlugin_snoop::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    tvars {
        str err;
        ptr<bitvec> bmp;
    }

    twait {
        sp->sp_get_bitmap(oid, mkevent (err, bmp));
    }
    
    /* Do something with return values if necessary */
    (*cb)(err, bmp);
}
