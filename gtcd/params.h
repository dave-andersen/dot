#ifndef _PARAMS_H_
#define _PARAMS_H_

//mode for experiments -- table in the paper
#define noEMULAB
#define noANIMATION
#define noTIME_TRACE
#define noDISK_ONLY
#define noTIME_SERIES

//plugin identities
#define XDISK 1
#define NET 0
#define PORT 2

#define LOCAL_DELAY_SIMULATE 10 
#define MAX_PKTSIZE 0x10400
#define CONN_ENTRY_IDLE_SEC    600 
#define CONN_ENTRY_IDLE_NSEC   000
#define MAX_CONNS_IN_FLIGHT     50000
//something large so that everything is sent to net
#define ALL_BLOCKS 10000000
#define SRC_RECHECK_TIMEOUT    1800 //30mts

extern unsigned int CHUNK_SIZE;

extern int NUM_SHINGLES;
extern unsigned int DEFAULT_DHT_PORT;

extern unsigned int NUM_ALLOWED_REQS; 
extern unsigned int NUM_ALLOWED_SRCS;

extern int REFRESH_OID_LOOKUP;
extern int REFRESH_BITMAP;
extern unsigned int MAX_PEERS_ALBT;
extern int REFRESH_BITMAP_ALBT;

extern int LARGE_COST; //huge cost
extern int THRESH_CHANGE;
extern int MIN_BLOCKS;

//operations
extern str AIOD_PATH;
extern str NEW_ROOT;

extern unsigned int AIOD_READ_SIZE;

extern double ALPHA;
extern int XDISK_CACHE_SIZE;
extern double DIR_STAT_COST;
extern double CHUNK_READ_HASH_COST;
extern double ADJ_WT;
extern double CACHE_CHECK_COST;

extern callback<void>::ptr opt_cb;
extern callback<void>::ptr aiod_cb;

extern int CLIENT_OUTSTANDING_THRESHOLD;

extern unsigned int MAX_CHUNKS_MEM_FOOTPRINT;
extern unsigned int CHUNKS_HIGH_WATER;
extern unsigned int CHUNKS_LOW_WATER;
extern int CHUNK_PURGER_SEC;
extern int CHUNK_PURGER_NSEC;

//experimentation flags
extern bool simulate;
extern bool pressure;
extern bool flow_control;
extern int flow_control_scheme;

#endif
