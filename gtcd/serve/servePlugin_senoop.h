/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _SERVE_SENOOP_H_
#define _SERVE_SENOOP_H_

#include "servePlugin.h"
#include "gtcd.h"

class servePlugin_senoop : public servePlugin {
  
private:
    gtcd *m;
    vec<servePlugin*> seplugins;
    servePlugin* parent;

public:
    bool configure(str s, str pluginClass) { return true; }
    void set_more_plugins(vec<servePlugin*> seplist) {
	seplugins = seplist;
    }
    void set_parent(servePlugin* prt) {
	parent = prt;
    }
    
    void serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb,
			   CLOSURE);
    void serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE);
    void serve_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE);
    void get_default_hint(ref<vec<oid_hint> > hint);
    
    servePlugin_senoop(gtcd *m, servePlugin* next_sep)
	: m(m), parent(NULL)
        { assert(m); if (next_sep) seplugins.push_back(next_sep); }
    ~servePlugin_senoop() { }
};


#endif /* _SERVE_SENOOP_H_ */
