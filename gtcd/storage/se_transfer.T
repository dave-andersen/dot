#include "async.h"
#include "arpc.h"
#include "bigint.h"
#include "storagePlugin.h"
#include "se_transfer.h"
#include "gtcd.h"

void
put_oid_source(dht_rpc *dht, dot_oid oid, oid_hint hint, cbs cb)
{
    rpc_bytes<1024> value;

    //warn << "put_oid_source reached " << oid << " " <<
    //oid.size() << "\n";
    
    {
	hint_res result;
	if (parse_hint(hint.name, "gtc", &result) < 0)
	    fatal << "No hints to put_oid_source\n";
	
	oid_hint_odht hint1;
	hint1.protocol = result.hint.protocol; /* Unused. Should be a URI */
	hint1.priority = result.hint.priority; /* Unused */
	hint1.weight = result.hint.weight; /* Unused */
	hint1.port = result.hint.port ;
	hint1.hostname = result.hint.hostname;
	hint1.appnum = APPDOT_VERSION;
	
	odht_val res(true);
	res.oid_info->protocol = hint1.protocol;
	res.oid_info->priority = hint1.priority;
	res.oid_info->weight = hint1.weight;
	res.oid_info->port = hint1.port;
	res.oid_info->hostname = hint1.hostname;
	res.oid_info->appnum = hint1.appnum;
	
	xdr2bytes(value, res);
    }

    dht->put(oid.base(), oid.size(), value.base(), value.size(), cb);
}

void
put_fp_to_oid(dht_rpc *dht, dot_desc cid, dot_oid oid, cbs cb)
{
    rpc_bytes<1024> value;
        
    //warn << "put_fp_to_oid reached " << cid << " " <<
    //cid.size() << "\n";

    oid_info_odht val1;
    
    val1.oid = oid;
    val1.appnum = APPDOT_VERSION;
    
    odht_val res(false);
    res.cid_info->oid = val1.oid;
    res.cid_info->appnum = val1.appnum;
    
    xdr2bytes(value, res);

    dht->put(cid.base(), cid.size(), value.base(), value.size(), cb);
}

void
get_fp_oids(dht_rpc *dht, dot_desc cid, dht_get_cb cb)
{
    //warn << "get_fingerprint_sources called " << cid << " " <<
    //cid.size() << "\n";
    
    dht->get(cid.base(), cid.size(), ODHT_MAXVALS_RET, cb);
}

void
get_oid_sources(dht_rpc *dht, dot_oid oid, dht_get_cb cb)
{
    //warn << "get_oid_sources called " << oid << " " <<
    //oid.size() << "\n";
    
    dht->get(oid.base(), oid.size(), ODHT_MAXVALS_RET, cb);
}

/***********************BDB FUNCS*******************************/
/*cache*/
void
extract_offset_info(ref<dot_descriptor> d, struct offset_info *info)
{
    metadata_entry e;
    int found = return_metadata_index("LOCAL", NULL, &(d->md));

    info->fd = -1;
    info->offset = -1;

    if (found >= 0)
	e = (d->md.list)[found];
    else {
	dwarn(DEBUG_OPT) << "No metadata for descriptor\n";
	info->st = EVICT_UNSAFE;
        return;
    }

    str n = e.key;
    const char *old_ptr = n.cstr();
    const char *ptr = strstr(old_ptr, ":");
    if (ptr) {
        info->path = str(old_ptr, ptr-old_ptr);
    } 
    else 
        warnx << "Error in disk info\n";
    
    info->fd = atoi(ptr+1);
    info->offset = atoi(e.val.cstr());
    info->st = EVICT_SAFE;
    
    dwarn(DEBUG_OPT) << "Metadata found " << info->path << " | " << info->fd
	  << " | " << info->offset << " | " << info->st << "\n";
    //warnx << "---------------------------BEFORE\n";
    //for (unsigned int i = 0; i < d->md.list.size(); i++) {
    //warnx << "Metadata " << i << " " << d->md.list[i].module << "\n";
    //}
    //warnx << "---------------------------BEFORE\n";
    
    //pop the metadata entry from d
    vec <metadata_entry> tmp;
    //num elements to pop_back
    int count = d->md.list.size() - found - 1;
    while (count > 0) {
        e = d->md.list.pop_back();
        tmp.push_back(e);
        count--;
    }
    //pop the entry with local info
    d->md.list.pop_back();
    //push back the rest
    for (int i = tmp.size() - 1; i >= 0; i--) {
        e = tmp[i];
        d->md.list.push_back(e);
    }

    //warnx << "---------------------------AFTER\n";
    //for (unsigned int i = 0; i < d->md.list.size(); i++) {
    //warnx << "Metadata " << i << " " << d->md.list[i].module << "\n";
    //}
    //warnx << "---------------------------AFTER\n";
}


bool
delete_from_cache(Db *filesDb, const char *key, unsigned int keylen)
{
    Dbc *cursorp = NULL;
    // Get a cursor
    filesDb->cursor(NULL, &cursorp, 0);
    if (cursorp == NULL)
	return false;
    
    Dbt k((char *)key, keylen);
    Dbt d;
    
    int ret;
    ret = cursorp->get(&k, &d, DB_SET);
    if (ret != 0 ||
	ret == DB_NOTFOUND) {
	cursorp->close(); 
	return false;
    }
    
    cursorp->del(0);
    cursorp->close();
    //warnx << "delete_from_cache: for " << key << "\n";
    return true;
}

bool
get_from_cache(Db *filesDb, const char *key, unsigned int keylen,
	       ptr<vec<ptr<Dbt > > > dvec)
{
    fatal << "shld not come here doesnt work\n";
    
    Dbc *cursorp = NULL;
    // Get a cursor
    filesDb->cursor(NULL, &cursorp, 0);
    if (cursorp == NULL) 
	return false;
    
    Dbt k((char *)key, keylen);
    int ret;

    ptr<Dbt > d = New refcounted<Dbt >;
    ret = cursorp->get(&k, d, DB_SET);
    if (ret != 0 ||
	ret == DB_NOTFOUND) {
	cursorp->close(); 
	return false;
    }
    
    dvec->push_back(d);
    while (1) {
	d = New refcounted<Dbt >;
	ret = cursorp->get(&k, d, DB_NEXT_DUP);
	if (ret != 0 ||
	    ret == DB_NOTFOUND) {
	    cursorp->close();
	    return true;
	}
	
	dvec->push_back(d);
    }

    cursorp->close();
    return true;
}

bool
get_unique_from_cache(Db *filesDb, const char *key, unsigned int keylen,
		      ptr<Dbt > d)
{
    Dbc *cursorp = NULL;
    // Get a cursor
    filesDb->cursor(NULL, &cursorp, 0);
    if (cursorp == NULL) {
	return false;
    }

    Dbt k((char *)key, keylen);
    int ret;
    
    ret = cursorp->get(&k, d, DB_SET);
    cursorp->close(); 

    if (ret != 0 ||
	ret == DB_NOTFOUND) {
	return false;
    }
    return true;
}

bool
put_in_cache(Db *filesDb, const char *key, unsigned int keylen,
	     const char *value, unsigned int vallen, bool unique)
{
    Dbc *cursorp = NULL;
    // Get a cursor
    filesDb->cursor(NULL, &cursorp, 0);
    if (cursorp == NULL)
	return false;
	
    Dbt k((char *)key, keylen);
    Dbt d1;
    
    if (unique) {
	dwarn(DEBUG_OPT) << "put_in_cache: checking for " << key << "\n";
	int ret = cursorp->get(&k, &d1, DB_SET);
	//get successful
	if (ret == 0) {
	    //warnx << "put_in_cache: hit for " << key << "\n";
	    cursorp->close(); 
	    return true;
	}
    }

    //if (unique)
    //warnx << "put_in_cache " << key << " not found\n";
        
    Dbt d((char *)value, vallen);
    int ret;

    if ((ret = cursorp->put(&k, &d, DB_KEYLAST)) < 0) {
	fatal << "Problems in put\n";
    }

    dwarn(DEBUG_OPT) << "put_in_cache " << key << " successful\n";
    cursorp->close();

    return true;
}
