/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "servePlugin_senoop.h"

void 
servePlugin_senoop::get_default_hint(ref<vec<oid_hint> > hint)
{
    dwarn(DEBUG_SERVE_NOOP) << "servePlugin_senoop::get_default_hint: called\n";
    for (unsigned int i = 0; i < seplugins.size(); i++) {
        seplugins[i]->get_default_hint(hint);
    }
}

tamed void
servePlugin_senoop::serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb)
{
    tvars {
	str err;
	ptr< vec<dot_descriptor> > descs;
        bool end;
    }
    
    dwarn(DEBUG_SERVE_NOOP) << "servePlugin_senoop::serve_descriptors: called\n";
    twait {
	if (parent)
	    parent->serve_descriptors(oidmd, mkevent(err, descs, end));
	else
	    m->serve_descriptors(oidmd, mkevent(err, descs, end));
    }

    (*cb)(err, descs, end);
}

tamed void
servePlugin_senoop::serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    tvars {
        str err;
        ptr<bitvec> bmp;
    }

    dwarn(DEBUG_SERVE_NOOP) << "servePlugin_senoop::serve_bitmap: called\n";
    
    twait {
	if (parent)	
	    parent->serve_bitmap(oid, mkevent (err, bmp));
	else
	    m->serve_bitmap(oid, mkevent (err, bmp));
    }
    
    (*cb)(err, bmp);
}

tamed void
servePlugin_senoop::serve_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    tvars {
        str err;
        ptr<desc_result> dres;
    }

    dwarn(DEBUG_SERVE_NOOP) << "servePlugin_senoop::serve_chunk: called\n";

    twait {
        if (parent)
	    parent->serve_chunk(d, mkevent (err, dres));
	else
	    m->serve_chunk(d, mkevent (err, dres));
    }
    
    (*cb)(err, dres);
}
