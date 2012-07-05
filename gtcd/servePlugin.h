/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _PLUGIN_SERVE_H_
#define _PLUGIN_SERVE_H_

#include "plugin.h"
#include "amisc.h"
#include "gtcd.h"

class servePlugin : virtual public Plugin {

public:
    virtual bool configure(str s, str pluginClass) = 0;
    virtual void set_more_plugins(vec<servePlugin*> seplist) = 0;
    virtual void set_parent(servePlugin* prt) = 0;
    virtual void set_next_plugin(servePlugin* next_plg) { };

    virtual void serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb,
				   CLOSURE) = 0;
    virtual void serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE) = 0;
    virtual void serve_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE) = 0;
    virtual void get_default_hint(ref<vec<oid_hint> > hint) = 0;
    
    virtual ~servePlugin() {}
};

#endif /* _PLUGIN_SERVE_H_ */
