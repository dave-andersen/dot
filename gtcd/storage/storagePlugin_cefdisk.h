/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_CEFDISK_H_
#define _STORAGEPLUGIN_CEFDISK_H_

#include "storagePlugin.h"
#include "gtcd.h"
#include "storagePlugin_ce.h"

template<class T>
T *get_plugin(str plg, T *next_plg);

class gtcd;
class storagePlugin_ce;

class storagePlugin_cefdisk : public storagePlugin {
private:
    storagePlugin_ce *sp;
public:
    storagePlugin_cefdisk(gtcd *m, storagePlugin *next_sp) 
        { assert(!next_sp); }
    ~storagePlugin_cefdisk() { }

    bool configure(str s, str pluginClass);

    bool init(dot_sId id)
        { return true; }
    void put_chunk(dot_sId id, ref<dot_descriptor> d,
                   const char *buf, int len, cbs cb, CLOSURE);
    void commit_object(dot_sId id, commit_cb cb, CLOSURE);
    bool release_object(ref<dot_oid> oid)
        { return true; }

    void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                    bool retain, cbs cb, CLOSURE);
    bool release_ichunk(ref<dot_descriptor> d)
        { return true; }

    void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, CLOSURE);
    void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb, CLOSURE);
    void sp_notify_descriptors(ref<dot_oid_md> oid,
			    ptr<vec<dot_descriptor> > descs);
    void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, CLOSURE);
    void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    int get_chunk_refcount(dot_descriptor *d);
    void inc_chunk_refcount(dot_descriptor *d)
        { }
    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE);
};

#endif /* _STORAGEPLUGIN_CEFDISK_H_ */
