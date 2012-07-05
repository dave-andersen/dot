#ifndef _CHUNKER_PLUGIN_ALL_H_
#define _CHUNKER_PLUGIN_ALL_H_

#include "chunkerPlugin.h"
#include "chunkerPlugin_default.h"
#include "chunkerPlugin_generate.h"

typedef callback<chunkerPlugin *, gtcd *, chunkerPlugin *>::ptr cPluginNew_cb;
extern qhash<str, cPluginNew_cb> cPluginTab;

#define PLUGIN(p) \
    chunkerPlugin *cp_##p##_maker(gtcd *m, chunkerPlugin *cp) \
    { return New chunkerPlugin_##p(m, cp); }

PLUGIN(default)
PLUGIN(generate)

#undef PLUGIN
#define PLUGIN(p) \
    cPluginTab.insert(#p, wrap(cp_##p##_maker));

class chunkerPlugin_maker
{
public:
    chunkerPlugin_maker()
    {
        PLUGIN(default)
	PLUGIN(generate)
    }
};

#undef PLUGIN

#endif  /* _CHUNKER_PLUGIN_ALL_H_ */
