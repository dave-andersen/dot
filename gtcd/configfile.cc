/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "configfile.h"

bool
parse_config(str file, vec<str> *sp_list, vec<str> *xp_list,
	     vec<str> *sep_list, vec<str> *cp_list)
{
    assert(sp_list);
    assert(xp_list);
    assert(sep_list);
    assert(cp_list);

    if (!file) {
        file = CONFDIR "/gtcd.conf";
        warn("No config file specified...using %s\n", file.cstr());
    }

    parseargs pa(file);
    int line;
    vec<str> av;
    vec<str> *cur = NULL;
    bool errors = false;

    while (pa.getline(&av, &line)) {
        if (!strcasecmp(av[0], "[storage]")) {
            if (sp_list->size() > 0) {
                errors = true;
                warn << file << ":" << line << ": Duplicate [storage] section\n";
            }
            else {
                cur = sp_list;
            }
        }
        else if (!strcasecmp(av[0], "[transfer]")) {
            if (xp_list->size() > 0) {
                errors = true;
                warn << file << ":" << line << ": Duplicate [transfer] section\n";
            }
            else {
                cur = xp_list;
            }
        }
	else if (!strcasecmp(av[0], "[server]")) {
            if (sep_list->size() > 0) {
                errors = true;
                warn << file << ":" << line << ": Duplicate [server] section\n";
            }
            else {
                cur = sep_list;
            }
        }
	else if (!strcasecmp(av[0], "[chunker]")) {
            if (cp_list->size() > 0) {
                errors = true;
                warn << file << ":" << line << ": Duplicate [chunker] section\n";
            }
            else {
                cur = cp_list;
            }
        }
        else {
            if (!cur) {
                errors = true;
                warn << file << ":" << line << ": Not inside a plugin section\n";
            }
            else {
                cur->push_back(av.pop_front());
                if (av.size()) {
		    //for plg_list
		    cur->push_back(av.pop_front());
		    //for conf
                    cur->push_back(join(" ", av));
		}
                else {
		    //for plg_list and conf
                    cur->push_back("");
		    cur->push_back("");
		}
	    }
	}
    }

    if (sp_list->size() <= 0) {
        warn << file << ": Missing [storage] section\n";
        errors = true;
    }
    if (xp_list->size() <= 0) {
        warn << file << ": Missing [transfer] section\n";
        errors = true;
    }
    if (sep_list->size() <= 0) {
        warn << file << ": Missing [server] section\n";
        errors = true;
    }
    if (cp_list->size() <= 0) {
        warn << file << ": Missing [chunker] section\n";
        errors = true;
    }

    if (errors)
        warn << "Errors processing file: " << file << "\n";

    return errors;
}

unsigned int CHUNK_SIZE = 16384;


//SET params
int NUM_SHINGLES = 30;
unsigned int DEFAULT_DHT_PORT = 5852;
int REFRESH_OID_LOOKUP = 10;
int REFRESH_BITMAP = 50*1000000; //nanoseconds for delaycb
unsigned int MAX_PEERS_ALBT = 80; //as per BT
/* scale bitmap refresh to limit overhead
  to one bitmap exchange in 50ms */
int REFRESH_BITMAP_ALBT = 2;
unsigned int NUM_ALLOWED_REQS = 1; //boot strap value for flow control
unsigned int NUM_ALLOWED_SRCS = MAX_PEERS_ALBT;

//opt params
int LARGE_COST = 999999; //huge cost
int THRESH_CHANGE = 10;
int MIN_BLOCKS = 50; 
str AIOD_PATH = NULL; 
str NEW_ROOT = "/";
double ALPHA = 0.2;
int XDISK_CACHE_SIZE = 10485760;
double DIR_STAT_COST = 0.001;
double CHUNK_READ_HASH_COST = 0.001;
double ADJ_WT = 5; //tolerates one hash p value to be ~0.1
double CACHE_CHECK_COST = 0;
int CLIENT_OUTSTANDING_THRESHOLD = 0;
unsigned int AIOD_READ_SIZE = 0x10000;
bool pressure = true;
callback<void>::ptr opt_cb = NULL;
callback<void>::ptr aiod_cb = NULL;

//dot cache params
//set for a file size of 1GB
unsigned int MAX_CHUNKS_MEM_FOOTPRINT = 1153433600; //1100MB
unsigned int CHUNKS_HIGH_WATER = ((size_t)((double)MAX_CHUNKS_MEM_FOOTPRINT));
unsigned int CHUNKS_LOW_WATER  = ((size_t)((double)MAX_CHUNKS_MEM_FOOTPRINT));
int CHUNK_PURGER_SEC = 1200;
int CHUNK_PURGER_NSEC = 000;

bool simulate = false;
bool flow_control = true;
int flow_control_scheme = 0;

bool
parse_paramfile(str file)
{
    if (!file) {
        warn << "No parameter file specified!\n";
        return false;
    }

    parseargs pa(file);
    int line;
    vec<str> av;

    warnx << "----------------------------------------------------\n";
    warnx << "----------------------------------------------------\n";
    
    while (pa.getline(&av, &line)) {

	if (!strcasecmp(av[0], "CHUNK_SIZE")) {
	    CHUNK_SIZE = atoi(av[2]);
	    warnx << "Chunk is " << CHUNK_SIZE << "\n";
	    continue;
	}

	if (!strcasecmp(av[0], "NUM_SHINGLES")) {
	    NUM_SHINGLES = atoi(av[2]);
	    warnx << "Shingles are " << NUM_SHINGLES << "\n";
	    continue;
	}
	if (!strcasecmp(av[0], "DEFAULT_DHT_PORT")) {
	    DEFAULT_DHT_PORT = atoi(av[2]);
	    warnx << "Dht port is " << DEFAULT_DHT_PORT << "\n";
	    continue;
	}
	
	if (!strcasecmp(av[0], "NUM_ALLOWED_REQS")) {
	    NUM_ALLOWED_REQS = atoi(av[2]);
	    warnx << "Reqs are " << NUM_ALLOWED_REQS << "\n";
	    continue;
	}
	if (!strcasecmp(av[0], "NUM_ALLOWED_SRCS")) {
	    NUM_ALLOWED_SRCS = atoi(av[2]);
	    warnx << "Srcs are " << NUM_ALLOWED_SRCS <<"\n";
	    continue;
	}
	
	if (!strcasecmp(av[0], "REFRESH_OID_LOOKUP")) {
	    REFRESH_OID_LOOKUP = atoi(av[2]);
	    warnx << "Lookup oid " << REFRESH_OID_LOOKUP << " seconds\n";
	    continue;
	}
	if (!strcasecmp(av[0], "REFRESH_BITMAP")) {
	    REFRESH_BITMAP = atoi(av[2]);
	    warnx << "Bitmap " << REFRESH_BITMAP << " seconds\n";
	    continue;
	}
	if (!strcasecmp(av[0], "MAX_PEERS_ALBT")) {
	    MAX_PEERS_ALBT = atoi(av[2]);
	    warnx << "Max sources are " << MAX_PEERS_ALBT << "\n";
	    continue;
	}
	if (!strcasecmp(av[0], "REFRESH_BITMAP_ALBT")) {
	    REFRESH_BITMAP_ALBT = atoi(av[2]);
	    warnx << "Refresh bitmap " << REFRESH_BITMAP_ALBT << " seconds\n";
	    continue;
	}
	
	if (!strcasecmp(av[0], "THRESH_CHANGE")) {
	    THRESH_CHANGE = atoi(av[2]);
	    warnx << "Threshold change " << THRESH_CHANGE << " %\n";
	    continue;
	}
	if (!strcasecmp(av[0], "MIN_BLOCKS")) {
	    MIN_BLOCKS = atoi(av[2]);
	    if (MIN_BLOCKS <= 0)
		MIN_BLOCKS = ALL_BLOCKS;
	    warnx << "Min blocks to net are " << MIN_BLOCKS <<"\n";
	    continue;
	}

	if (!strcasecmp(av[0], "AIOD_PATH")) {
	    AIOD_PATH = av[2];
	    warnx << "Aiod path is " << AIOD_PATH << "\n";
	    continue;
	}
	if (!strcasecmp(av[0], "NEW_ROOT")) {
	    NEW_ROOT = av[2];
	    warnx << "New root is " << NEW_ROOT << "\n";
	    continue;
	}

	if (!strcasecmp(av[0], "ALPHA")) {
	    ALPHA = atof(av[2]);
	    fprintf(stderr, "Alpha is set to %f seconds\n", ALPHA);
	    continue;
	}
	if (!strcasecmp(av[0], "XDISK_CACHE_SIZE")) {
	    XDISK_CACHE_SIZE = atoi(av[2]);
	    warnx << "Xdisk cache size " << XDISK_CACHE_SIZE << " bytes\n";
	    continue;
	}
	if (!strcasecmp(av[0], "DIR_STAT_COST")) {
	    DIR_STAT_COST = atof(av[2]);
	    fprintf(stderr, "Statting cost %f seconds\n", DIR_STAT_COST);
	    continue;
	}
	if (!strcasecmp(av[0], "CHUNK_READ_HASH_COST")) {
	    CHUNK_READ_HASH_COST = atof(av[2]);
	    fprintf(stderr, "Per chunk hash cost %f seconds\n", CHUNK_READ_HASH_COST);
	    continue;
	}
	if (!strcasecmp(av[0], "ADJ_WT")) {
	    ADJ_WT = atof(av[2]);
	    fprintf(stderr, "Weight adjustment for stat cost %f\n", ADJ_WT);
	    continue;
	}
	if (!strcasecmp(av[0], "CACHE_CHECK_COST")) {
	    CACHE_CHECK_COST = atof(av[2]);
	    fprintf(stderr, "Cache check cost %f seconds\n", CACHE_CHECK_COST);
	    continue;
	}
	
	if (!strcasecmp(av[0], "MAX_CHUNKS_MEM_FOOTPRINT")) {
	    MAX_CHUNKS_MEM_FOOTPRINT = atoi(av[2]);
	    warnx << "DOT cache size " << MAX_CHUNKS_MEM_FOOTPRINT << " bytes\n";
	    continue;
	}
	if (!strcasecmp(av[0], "CHUNKS_HIGH_WATER")) {
	    CHUNKS_HIGH_WATER = atoi(av[2]);
	    CHUNKS_HIGH_WATER = ((size_t)(((double)MAX_CHUNKS_MEM_FOOTPRINT * CHUNKS_HIGH_WATER)/100));
	    warnx << "DOT cache high " << CHUNKS_HIGH_WATER << " bytes\n";
	    continue;
	}
	if (!strcasecmp(av[0], "CHUNKS_LOW_WATER")) {
	    CHUNKS_LOW_WATER = atoi(av[2]);
	    CHUNKS_LOW_WATER = ((size_t)(((double)MAX_CHUNKS_MEM_FOOTPRINT * CHUNKS_LOW_WATER)/100));
	    warnx << "DOT cache low " << CHUNKS_LOW_WATER << " bytes\n";
	    continue;
	}

	if (!strcasecmp(av[0], "CHUNK_PURGER_SEC")) {
	    CHUNK_PURGER_SEC = atoi(av[2]);
	    warnx << "Chunk purge at " << CHUNK_PURGER_SEC << " seconds\n";
	    continue;
	}
	if (!strcasecmp(av[0], "CHUNK_PURGER_NSEC")) {
	    CHUNK_PURGER_NSEC = atoi(av[2]);
	    warnx << "Chunk purge at " << CHUNK_PURGER_NSEC << " nanoseconds\n";
	    continue;
	}

	if (!strcasecmp(av[0], "SIMULATE")) {
	    if (atoi(av[2]) > 0) {
		simulate = true;
		warnx << "Simulation is enabled\n";
	    }
	    continue;
	}
    
	if (!strcasecmp(av[0], "PRESSURE")) {
	    if (atoi(av[2]) <= 0) {
		pressure = false;
		warnx << "Pressure response is disabled\n";
	    }
	    continue;
	}

	if (!strcasecmp(av[0], "FLOW_CONTROL")) {
	    if (atoi(av[2]) <= 0) {
		flow_control = false;
		warnx << "Flow control is disabled\n";
	    }
	    continue;
	}

	if (!strcasecmp(av[0], "FLOW_CONTROL_SCHEME")) {
	    int scheme = atoi(av[2]);
	    flow_control_scheme = scheme;
	    warnx << "Using flow control scheme " << scheme << "\n";
	    continue;
	}
	
    }

    warnx << "----------------------------------------------------\n";
    warnx << "----------------------------------------------------\n";
    
    return true;
}
