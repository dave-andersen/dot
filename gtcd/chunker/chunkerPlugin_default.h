/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _CHUNKERPLUGIN_DEFAULT_H_
#define _CHUNKERPLUGIN_DEFAULT_H_

#include "chunkerPlugin.h"
#include "gtcd.h"

class chunkerPlugin_default : public chunkerPlugin {
private:
    storagePlugin *sp;
    dot_sId id_next;
    str chunk_algo;
    void name_chunk(dot_sId id_in, const char *buf, size_t len);
    void name_chunks(dot_sId id_in, ref<vec<unsigned int> > iv,
                     const char *buf, size_t len);
public:
    chunkerPlugin_default(gtcd *_m, chunkerPlugin *next_cp) : sp(_m->sp)
	{ assert(!next_cp); }
    bool configure(str s, str pluginClass)
	{ chunk_algo = s; return true; }
    void set_storage_plugin(storagePlugin *prt)
	{ sp = prt; }
    
    bool init(dot_sId *id_out, ptr<metadata_entry > mde);
    
    void commit_object(dot_sId id, commit_cb cb);

    bool release_object(ref<dot_oid> oid) {
	return sp->release_object(oid);
    }
    
    void put_object(dot_sId id, const void *buf, size_t len, cbs cb);
};

#endif /* _CHUNKERPLUGIN_DEFAULT_H_ */
