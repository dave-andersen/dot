/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _STORAGE_PLUGIN_ALL_H_
#define _STORAGE_PLUGIN_ALL_H_

#include "storagePlugin_disk.h"
#include "storagePlugin_snoop.h"
#include "storagePlugin_sset.h"
#include "storagePlugin_ce.h"
#include "storagePlugin_cefdisk.h"

typedef callback<storagePlugin *, gtcd *, storagePlugin *>::ptr sPluginNew_cb;
extern qhash<str, sPluginNew_cb> sPluginTab;

#define PLUGIN(p) \
    storagePlugin *sp_##p##_maker(gtcd *m, storagePlugin *sp) \
    { return New storagePlugin_##p(m, sp); }

PLUGIN(disk)
PLUGIN(snoop)    
PLUGIN(ce)
PLUGIN(cefdisk)
PLUGIN(sset)

#undef PLUGIN
#define PLUGIN(p) \
    sPluginTab.insert(#p, wrap(sp_##p##_maker));

class storagePlugin_maker
{
public:
    storagePlugin_maker()
    {
        PLUGIN(disk)
        PLUGIN(snoop)
        PLUGIN(ce)
        PLUGIN(cefdisk)
        PLUGIN(sset)
    }
};

#undef PLUGIN

#endif  /* _STORAGE_PLUGIN_ALL_H_ */
