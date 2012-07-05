/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

/*
 * Data structures for xdisk and bdb interface
 */

%#include "gtc_prot.h"

typedef hyper dot_time;

enum xfer_op { 
	DISK_LIST, 
	DISK_STAT, 
	DISK_RLIST, 
	DISK_HASH, 
	DISK_FAKEHASH, 
	DISK_CHIT,
	SET_XFER 
};

enum xfer_unit { 
	UNIT_TIME, 
	UNIT_CPU, 
	UNIT_NW 
};

enum db_entry { 
	INFO_CID, 
	INFO_CID_CHUNK,
	INFO_OID_DESC, 
	INFO_OID, 
	INFO_OP 
};

struct shadow_stat {
   unsigned int stsize;    
   dot_time statime;   
   dot_time stmtime;   
   dot_time stctime;   
};

struct stat_info {
    string name<>;
    shadow_stat s;
};

struct op_bdb_info {
   db_entry type;	
   string path<>;
   xfer_op oper;
   stat_info buf;
   dot_time time;
};

enum evict_status {
    EVICT_UNSAFE,		
    EVICT_SAFE
}; 	

struct offset_info {
    string path<>;
    int offset;
    int fd;
    evict_status st;
};

struct cid_bdb_info {
   db_entry type;	
   dot_descriptor desc;
   offset_info info;
};

struct cid_chunk_bdb_info {
   db_entry type;	
   dot_descriptor desc;
   dot_data buf;
};


struct oid_desc_bdb_info {
   db_entry type;	
   dot_oid_md  oid;
   dot_descriptor descriptors<>;	
};

struct oid_bdb_info {
   db_entry type;	
   dot_oid_md  oid;
   offset_info info;
};
