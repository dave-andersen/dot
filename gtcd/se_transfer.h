#ifndef _SE_TRANFER_H_
#define _SE_TRANFER_H_

#include "dht.h"
#include <db_cxx.h>
#include "bdb_int.h"
#include "params.h"

/* CDHT or ODHT? */
/*#define USE_CDHT 1 */

class Compare_dot_desc {
public:
    int operator()(const dot_desc &x, const dot_desc &y) {
	str xx = strbuf() << x;
	str yy = strbuf() << y;
	return xx < yy;
    }
};

#include <vector>
#include <queue>
typedef std::priority_queue<dot_desc,std::vector<dot_desc>,Compare_dot_desc> ordered_descriptor_list;

void put_oid_source(dht_rpc *dht, dot_oid oid, oid_hint hint, cbs cb);
void put_fp_to_oid(dht_rpc *dht, dot_desc descriptor, dot_oid oid, cbs cb);
void get_fp_oids(dht_rpc *dht, dot_desc cid,  dht_get_cb cb);
void get_oid_sources(dht_rpc *dht, dot_oid oid, dht_get_cb cb);

bool delete_from_cache(Db *filesDb, const char *key, unsigned int keylen);
bool get_from_cache(Db *filesDb, const char *key, unsigned int keylen,
		    ptr<vec<ptr<Dbt > > > dvec);
bool get_unique_from_cache(Db *filesDb, const char *key, unsigned int keylen,
			   ptr<Dbt > d);
bool put_in_cache(Db *filesDb, const char *key, unsigned int keylen,
		  const char *value, unsigned int vallen, bool unique);

struct stat_info get_shadow_stat(struct item_info ip);
void extract_offset_info(ref<dot_descriptor> d, struct offset_info *info);

#endif /* _SE_TRANFER_H_ */
