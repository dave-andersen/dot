/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_PLUGIN_ALL_H_
#define _XFER_PLUGIN_ALL_H_

#include "xferPlugin_xgtc.h"
#include "xferPlugin_portable.h"
#include "xferPlugin_mpath.h"
#include "xferPlugin_xnoop.h"
#include "xferPlugin_decompress.h"
#include "xferPlugin_xset.h"
#include "xferPlugin_msrc.h"
#include "xferPlugin_opt.h"
#include "xferPlugin_xdisk.h"

typedef callback<xferPlugin *, gtcd *, xferPlugin *>::ptr xPluginNew_cb;
extern qhash<str, xPluginNew_cb> xPluginTab;

#define PLUGIN(p) \
    xferPlugin *xp_##p##_maker(gtcd *m, xferPlugin *xp) \
    { return New xferPlugin_##p(m, xp); }

PLUGIN(xgtc)
PLUGIN(portable)
//PLUGIN(mpath)
PLUGIN(xnoop)
PLUGIN(decompress)
//PLUGIN(ce)
PLUGIN(xset)
PLUGIN(msrc)
PLUGIN(opt)
PLUGIN(xdisk)

#undef PLUGIN
#define PLUGIN(p) \
    xPluginTab.insert(#p, wrap(xp_##p##_maker));

class xferPlugin_maker
{
public:
    xferPlugin_maker()
    {
        PLUGIN(xgtc)
        PLUGIN(portable)
        //PLUGIN(mpath)
        PLUGIN(xnoop)
        PLUGIN(decompress)
        //PLUGIN(ce)
        PLUGIN(xset)
        PLUGIN(msrc)
	PLUGIN(opt)
	PLUGIN(xdisk)
    }
};

#undef PLUGIN

#endif  /* _XFER_PLUGIN_ALL_H_ */
