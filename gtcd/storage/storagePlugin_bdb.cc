/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_bdb.h"

storagePlugin_bdb::storagePlugin_bdb(storagePlugin *next_sp)
{
    if (next_sp)
        fatal << __PRETTY_FUNCTION__ << " next_sp is not NULL\n"
              << "Make sure that this storage plugin comes last\n";

    dbenv = new DbEnv(0);
    // dbenv->set_error_stream(&err_stream);
    dbenv->set_errpfx("BDB Storage Plugin");
    
    // 10 MB shared memory buffer pool cachesize,
    dbenv->set_cachesize(0, 10 * 1024 * 1024, 0);
    
    (void)dbenv->set_data_dir(DB_HOME_PATH);
    
    // Open the environment with full transactional support.
    dbenv->open(DB_HOME_PATH, 
		DB_CREATE | DB_INIT_LOCK | DB_INIT_LOG | DB_INIT_MPOOL
		| DB_INIT_TXN, 0);

    filesDb = new Db(dbenv, 0);
    filesDb->set_pagesize(32*1024);
    filesDb->open(NULL,
		  "filelist.db",
		  NULL,
		  DB_HASH,
		  DB_CREATE,
		  0);

    hash_check = delaycb(BDB_CHECK_SEC, 0,
			 wrap(this, &storagePlugin_bdb::check_files));


}

storagePlugin_bdb::~storagePlugin_bdb()
{
    filesDb->close(0);
    dbenv->close(0);
}

void
storagePlugin_bdb::check_files()
{
    Dbc *cursorp = NULL;

    filesDb->cursor(NULL, &cursorp, 0); 

    Dbt key, data;
    int ret;

    // Iterate over the database, retrieving each record in turn.
    while ((ret = cursorp->get(&key, &data, DB_NEXT)) == 0) {
        // Do interesting things with the Dbts here.
	ret = *(int *) data.get_data();
	printf("%s, %d\n", (char *)key.get_data(), ret);
    }

    if (cursorp != NULL) 
	cursorp->close(); 
    
    // Re-enable check
    hash_check = delaycb(BDB_CHECK_SEC, 0,
			 wrap(this, &storagePlugin_bdb::check_files));

}

bool
storagePlugin_bdb::init(dot_sId id)
{
    return false;
}

void
storagePlugin_bdb::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb, ptr<closure_t>)
{
    // Do nothing
}

void
storagePlugin_bdb::commit_object(dot_sId id, commit_cb cb, ptr<closure_t>) 
{
    // Do nothing
}

bool
storagePlugin_bdb::release_object(ref<dot_oid> oid)
{
    return false;
}

// The buffers passed to put_ichunk now belong to it
void
storagePlugin_bdb::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                           bool retain, cbs cb, ptr<closure_t>)
{
    // Do nothing
}

void
storagePlugin_bdb::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, ptr<closure_t>)
{
    strbuf sb;
    sb << "Error:" << __PRETTY_FUNCTION__ << " should not be called";
    (*cb)(sb, NULL);
}

void
storagePlugin_bdb::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb,
                                    ptr<closure_t>)
{
    strbuf sb;
    sb << "Error:" << __PRETTY_FUNCTION__ << " should not be called";
    (*cb)(sb, NULL, false);
}

void
storagePlugin_bdb::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, ptr<closure_t>)
{
    strbuf sb;
    sb << "Error:" << __PRETTY_FUNCTION__ << " should not be called";
    (*cb)(sb, NULL);
}

void
storagePlugin_bdb::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb,
                               ptr<closure_t>)
{
    for (unsigned int i = 0; i < dv->size(); i++) {
	ref<dot_descriptor> dd = New refcounted<dot_descriptor>((*dv)[i]);
        get_chunk(dd, cb);
    }
}

void
storagePlugin_bdb::get_chunk(ref<dot_descriptor> d, chunk_cb cb,
                              ptr<closure_t>)
{
    ptr<suio> chunkData = NULL;

    if (NULL == chunkData) {
        // warn << "Cannot find " << d->id << "\n";
        // (*cb)("Chunk not in database", NULL);
        return;
    }
    else {
        // warn << chunkData->resid();
    }
    ref<desc_result> res = New refcounted<desc_result> (d, chunkData, true);
    (*cb)(NULL, res);
}

int
storagePlugin_bdb::get_chunk_refcount(dot_descriptor *d)
{
    fatal << __PRETTY_FUNCTION__  << " should not be called\n";
    return -1;
}

void
storagePlugin_bdb::inc_chunk_refcount(dot_descriptor *d)
{
    fatal << __PRETTY_FUNCTION__  << " should not be called\n";
}

bool
storagePlugin_bdb::release_ichunk(ref<dot_descriptor> d)
{
    fatal << __PRETTY_FUNCTION__  << " should not be called\n";
    return false;
}

void 
storagePlugin_bdb::sp_notify_descriptors(ref<dot_oid_md> oid,
				       ptr<vec<dot_descriptor> > descs)
{
    // Do nothing for now
}

void
storagePlugin_bdb::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb,
			      ptr<closure_t>)
{
    strbuf sb;
    sb << "Error:" << __PRETTY_FUNCTION__ << " should not be called";
    (*cb)(sb, NULL);
}

