/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_cefdisk.h"

bool
storagePlugin_cefdisk::configure(str s, str pluginClass)
{
    sp = dynamic_cast<storagePlugin_ce *>(get_plugin<storagePlugin> (s, sp));
    if(sp) {
        return true;
    }
    return false;
}

tamed void
storagePlugin_cefdisk::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb)
{
    (*cb)(NULL);
}

tamed void
storagePlugin_cefdisk::commit_object(dot_sId id, commit_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> oid;
    }

    twait {
        sp->commit_object_fake(id, mkevent (err, oid));
    }

    if (err)
        warn("storagePlugin_cefdisk::commit_object: Error message from child: %s\n",
             err.cstr());
    else {
        dwarn(DEBUG_CE) << "storagePlugin_cefdisk::commit_object: Child returned successfully.\n";
        metadata_entry e;
        e.module = "CEFDISK";
        e.key = "oid_key0";
        e.val = "oid_val0";
        oid->md.list.push_back(e);
    }

    (*cb)(err, oid);
}

tamed void
storagePlugin_cefdisk::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                               bool retain, cbs cb)
{
    (*cb)(NULL);
}

tamed void
storagePlugin_cefdisk::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb)
{

    ref<dot_oid_md> new_oid = New refcounted<dot_oid_md> ();
    new_oid->id = oid->id;
    (*cb)(NULL, new_oid);
}

tamed void
storagePlugin_cefdisk::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb)
{
    tvars {
        str err;
        ptr< vec<dot_descriptor> > descs;
        bool end(true);
    }

    /*twait {
        sp->sp_get_descriptors_fake(oid, mkevent (err, descs, end));
    }*/
    /* Do something with return values if necessary */
    (*cb)(err, descs, end);
}

tamed void
storagePlugin_cefdisk::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb)
{
    ref<dot_descriptor> new_d = New refcounted<dot_descriptor>();
    new_d->id = d->id;
    new_d->length = d->length;
    (*cb)(NULL, new_d);
}

tamed void
storagePlugin_cefdisk::get_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    /* Do something with return values if necessary */
    (*cb)(NULL, NULL);
}

int
storagePlugin_cefdisk::get_chunk_refcount(dot_descriptor *d)
{ 
    return sp->get_chunk_refcount_fake(d); 
}


tamed void
storagePlugin_cefdisk::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb)
{
    (*cb)(NULL, NULL);
}

void 
storagePlugin_cefdisk::sp_notify_descriptors(ref<dot_oid_md> oid,
				       ptr<vec<dot_descriptor> > descs)
{
}

tamed void 
storagePlugin_cefdisk::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    tvars {
        str err;
        ptr<bitvec> bmp;
    }

    twait {
        //sp->sp_get_bitmap(oid, mkevent (err, bmp));
    }
    
    /* Do something with return values if necessary */
    (*cb)(err, bmp);
}
