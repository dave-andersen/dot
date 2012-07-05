/*
 * Copyright (c) 2001-2003 Regents of the University of California.
 * All rights reserved.
 *
 * See the file ODHT_LICENSE included in this distribution for details.
 */

%#define APPLICATION    "DOT"
%#define CLIENT_LIBRARY "sfs-arpc"
%#define OPENDHT_TTL 5*60
%#define APPDOT_VERSION 1
%#define ODHT_MAXVALS_RET 500 /* approx corresponding to ~16KB of data, each val being 32 bytes */
%#include "gtc_prot.h"

enum bamboo_stat {
  BAMBOO_OK = 0,
  BAMBOO_CAP = 1,
  BAMBOO_AGAIN = 2
};


typedef opaque bamboo_key[20];
typedef opaque bamboo_value<1024>; /* may be increased to 8192 eventually */
typedef opaque bamboo_placemark<100>;

struct bamboo_put_args {
  string application<255>;
  string client_library<255>;
  bamboo_key key;
  bamboo_value value;
  int ttl_sec;
};

struct bamboo_get_args {
  string application<255>;
  string client_library<255>;
  bamboo_key key;
  int maxvals;
  bamboo_placemark placemark;
};

struct bamboo_get_res {
    bamboo_value values<>;
    bamboo_placemark placemark;
};

struct oid_info_odht {
    dot_oid oid;        
    int appnum;         
};

struct oid_hint_odht {
    unsigned int protocol; /* Unused. Should be a URI */
    unsigned int priority; /* Unused */
    unsigned int weight; /* Unused */
    unsigned int port;
    string hostname<>;
    int appnum;
};

union odht_val switch (bool ok) {
 case false:
   oid_info_odht cid_info;      
 case true:
   oid_hint_odht oid_info;
};


program BAMBOO_DHT_GATEWAY_PROGRAM {
	version BAMBOO_DHT_GATEWAY_VERSION {
		void 
		BAMBOO_DHT_PROC_NULL (void) = 1;

	        bamboo_stat
		BAMBOO_DHT_PROC_PUT (bamboo_put_args) = 2;

                bamboo_get_res
		BAMBOO_DHT_PROC_GET (bamboo_get_args) = 3;
	} = 2;
} = 708655600;
