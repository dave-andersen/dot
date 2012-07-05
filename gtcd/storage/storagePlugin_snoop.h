/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_SNOOP_H_
#define _STORAGEPLUGIN_SNOOP_H_

#include "storagePlugin.h"
#include "gtcd.h"

class gtcd;

class storagePlugin_snoop : public storagePlugin {
private:
    storagePlugin *sp;
public:
    storagePlugin_snoop(gtcd *m, storagePlugin *next_sp) : sp(next_sp)
        { assert(sp); }
    ~storagePlugin_snoop() { }

    bool configure(str s, str pluginClass) { return true; };

    bool init(dot_sId id)
        { return sp->init(id); }
    void put_chunk(dot_sId id, ref<dot_descriptor> d,
                   const char *buf, int len, cbs cb, CLOSURE);
    void commit_object(dot_sId id, commit_cb cb, CLOSURE);
    bool release_object(ref<dot_oid> oid)
        { return sp->release_object(oid); }

    void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                    bool retain, cbs cb, CLOSURE);
    bool release_ichunk(ref<dot_descriptor> d)
        { return sp->release_ichunk(d); }

    void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, CLOSURE);
    void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb, CLOSURE);
    void sp_notify_descriptors(ref<dot_oid_md> oid,
			    ptr<vec<dot_descriptor> > descs);
    void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, CLOSURE);
    void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    int get_chunk_refcount(dot_descriptor *d)
        { return sp->get_chunk_refcount(d); }
    void inc_chunk_refcount(dot_descriptor *d)
        { sp->inc_chunk_refcount(d); }
    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE);
};

#endif /* _STORAGEPLUGIN_SNOOP_H_ */
