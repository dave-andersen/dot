/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _CHUNKERPLUGIN_H_
#define _CHUNKERPLUGIN_H_

#include "plugin.h"
#include "storagePlugin.h"
#include "params.h"

static void
ig_str (str)
{
}
static callback<void, str>::ref cb_null (gwrap (ig_str));

class chunkerPlugin : virtual public Plugin {
public:
    virtual bool configure(str s, str pluginClass) = 0;
    virtual void set_more_plugins(vec<chunkerPlugin*> cplist) { };
    virtual void set_parent(chunkerPlugin* prt) { };
    virtual void set_next_plugin(chunkerPlugin* next_plg) { };
    virtual void set_storage_plugin(storagePlugin *prt) = 0;
    
    virtual bool init(dot_sId *id_out, ptr<metadata_entry > e) = 0;
    virtual void put_object(dot_sId id_in, const void *buf, size_t len, cbs cb) = 0;
    /* callback:  errstring, null if no error */
    virtual void commit_object(dot_sId id_in, commit_cb cb) = 0;
    virtual bool release_object(ref<dot_oid> id_in) = 0;

    virtual ~chunkerPlugin() {}
};

#endif /* _CHUNKERPLUGIN_H_ */
