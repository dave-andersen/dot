/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _CHUNKERPLUGIN_GENERATE_H_
#define _CHUNKERPLUGIN_GENERATE_H_

#include "chunkerPlugin.h"
#include "arc4.h"
#include "gtcd.h"

class storagePlugin_generate;

class chunkerPlugin_generate : public chunkerPlugin {
private:
    dot_sId id_next;
    storagePlugin *sp;
    void name_chunk(dot_sId id_in, const char *buf, size_t len);
    void get_pseudo_data(str hash_val, char *buf, int size);
    arc4 ctx;

public:
    chunkerPlugin_generate(gtcd *_m, chunkerPlugin *next_cp) : sp(_m->sp)
	{ assert(!next_cp); }
    bool configure(str s, str pluginClass) { return true; }
    void set_storage_plugin(storagePlugin *prt)
	{ sp = prt; }
        
    bool init(dot_sId *id_out, ptr<metadata_entry > mde);
    
    void commit_object(dot_sId id, commit_cb cb);

    bool release_object(ref<dot_oid> oid) {
	return true;
    }
    
    void put_object(dot_sId id, const void *buf, size_t len, cbs cb);
};

#endif /* _CHUNKERPLUGIN_GENERATE_H_ */
