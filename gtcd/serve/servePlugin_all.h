/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _SERVE_PLUGIN_ALL_H_
#define _SERVE_PLUGIN_ALL_H_

#include "servePlugin_segtc.h"
#include "servePlugin_senoop.h"
#include "servePlugin_compress.h"

typedef callback<servePlugin *, gtcd *, servePlugin * >::ptr sePluginNew_cb;
extern qhash<str, sePluginNew_cb> sePluginTab;

#define PLUGIN(p) \
    servePlugin *sep_##p##_maker(gtcd *m, servePlugin* sep) \
    { return New servePlugin_##p(m, sep); }

PLUGIN(segtc)
PLUGIN(senoop)
PLUGIN(compress)

#undef PLUGIN
#define PLUGIN(p) \
    sePluginTab.insert(#p, wrap(sep_##p##_maker));

class servePlugin_maker
{
public:
    servePlugin_maker()
    {
        PLUGIN(segtc)
        PLUGIN(senoop)
        PLUGIN(compress)
    }
};

#undef PLUGIN

#endif  /* _SERVE_PLUGIN_ALL_H_ */
