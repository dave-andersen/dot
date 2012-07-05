/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGEPLUGIN_H_
#define _STORAGEPLUGIN_H_

#include "plugin.h"
#include "gtc_prot.h"
#include "amisc.h"
#include "ihash.h"
#include "tame.h"
#include "bitvec.h"

struct desc_result {
    ref<dot_descriptor> desc;
    ptr<suio> data;

    desc_result(ref<dot_descriptor> d, ptr<suio> s, bool copy);
    ~desc_result();
};

typedef callback<void, str, ptr<dot_oid_md> >::ref commit_cb;
typedef callback<void, str, ptr<dot_oid_md> >::ref oid_cb;
typedef callback<void, str, ptr<dot_descriptor> >::ref descriptor_cb;
typedef callback<void, str, ptr< vec<dot_descriptor> >, bool>::ref descriptors_cb;
typedef callback<void, str, ptr<desc_result> >::ref chunk_cb;
typedef callback<void, str, ptr<bitvec> >::ref bitmap_cb;

class storagePlugin: virtual public Plugin {

public:
    virtual bool configure(str s, str pluginClass) = 0;
    virtual void set_more_plugins(vec<storagePlugin*> splist) { };
    virtual void set_parent(storagePlugin* prt) { };
    virtual void set_next_plugin(storagePlugin* next_plg) { };

    /* SENDER-SIDE INTERFACE */
    virtual bool init(dot_sId id) = 0;
    virtual void put_chunk(dot_sId id, ref<dot_descriptor> d,
                           const char *buf, int len, cbs cb, CLOSURE) = 0;
    /* callback:  errstring, null if no error */
    virtual void commit_object(dot_sId id, commit_cb cb, CLOSURE) = 0;
    virtual bool release_object(ref<dot_oid> oid) = 0;
    /* The xferId is private to that client, so we don't have to worry
     * about clients releasing other clients' data.  It is generated
     * by the chunker and passed in to the storage plugins.*/

    /* CACHING INTERFACE */
    /* Input methods from the GTC if acting as a cache or buffer */
    virtual void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                            bool retain, cbs cb, CLOSURE) = 0;
    virtual bool release_ichunk(ref<dot_descriptor> d) = 0;

    /* RECEIVER-SIDE INTERFACE */
    virtual void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb,
                                      CLOSURE) = 0;
    virtual void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb,
                                 CLOSURE) = 0;
    virtual void sp_notify_descriptors(ref<dot_oid_md> oid,
				    ptr<vec<dot_descriptor> > descs) = 0;
    virtual void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb,
			    CLOSURE) = 0;
    virtual void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb,
                                CLOSURE) = 0;
    virtual void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE) = 0;
    virtual void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb,
                            CLOSURE) = 0;
    virtual int get_chunk_refcount(dot_descriptor *d) = 0;
    virtual void inc_chunk_refcount(dot_descriptor *d) = 0;

    virtual ~storagePlugin() {}
};

#endif /* _STORAGEPLUGIN_H_ */
