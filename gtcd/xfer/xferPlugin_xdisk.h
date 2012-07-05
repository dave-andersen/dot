/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _XFER_XDISK_H_
#define _XFER_XDISK_H_

#include "xferPlugin.h"
#include "../chunker/chunkerPlugin_default.h"
#include "gtcd.h"
#include "xferPlugin_gtc_prot.h"
#include "xferPlugin_opt.h"

#include <sys/types.h>
#include <dirent.h>
#include <math.h>
#include "aiod.h"

class xferPlugin_xdisk;

class stat_op : public os_entry {
private:
    struct item_info stat_buf;
    xferPlugin_xdisk *xp;
    vec<const char *> *spl_path;
    char *sp_ptr;
    
public:
    void perform_op(CLOSURE);
    double get_cost();
    float get_benefit(ht_entry *);
    double get_xfer_cost(ht_entry *);
    bool is_chit_op() { return false; }
    void dump_info() { warnx << "DISK_STAT: " << path << "\n"; }
    stat_op(str, str p, struct item_info s, xferPlugin_xdisk *ptr);
    ~stat_op();
};

struct name_property {
    bool s_tilda;
    bool s_bak;
    bool p_hash;
};

class hash_op : public os_entry {
private:
    struct item_info stat_buf;
    xferPlugin_xdisk *xp;
    name_property np;
    vec<const char *> *spl_path;
    char *sp_ptr;
    
public:
    void perform_op(CLOSURE);
    double get_cost();
    float get_benefit(ht_entry *);
    double get_xfer_cost(ht_entry *);
    bool is_chit_op() { return false; }
    void dump_info() {
	warnx << "DISK_HASH: " << path << "/" <<
	    stat_buf.name << " size: " << stat_buf.s.st_size << "\n"; }
    hash_op(str, str p, struct item_info s, xferPlugin_xdisk *ptr);
    ~hash_op();
};

class chit_op : public os_entry {
private:
    ptr<vec<struct offset_info > > inf;
    int length;
    xferPlugin_xdisk *xp;
    
public:
    void perform_op(CLOSURE);
    double get_cost();
    float get_benefit(ht_entry *);
    double get_xfer_cost(ht_entry *);
    bool is_chit_op() { return true; }
    void dump_info() {
	warnx << "DISK_CHIT: " << desc << "\n";
    }
    chit_op(str, dot_desc p, ptr<vec<struct offset_info > > inf,
	    int len, xferPlugin_xdisk *ptr);
    ~chit_op();
};

//iohandlers
typedef callback<void, bool, str >::ref cb_bool;
typedef callback<void, int >::ref cb_int;

class ioh {
    
public:
    dot_sId sid;
    int fd;
    int pending;
    
    virtual ~ioh() {};
    virtual void opendir(str path, cbs cb, CLOSURE) = 0;
    virtual void readdir(struct dirent *,cb_bool cb, CLOSURE) = 0;
    virtual void closedir(cbs cb, CLOSURE) = 0;
    virtual void stat(str name, struct stat *res, cbs cb, CLOSURE) = 0;
    virtual void open(str name, mode_t mode, cbs cb, CLOSURE) = 0;
    virtual void read(ptr<suio> io_in, int size, cb_int cb, CLOSURE) = 0;
    virtual void close(cbs cb, CLOSURE) = 0;
    virtual void seek(int offset, cbs cb, CLOSURE) = 0;
};

class sioh : public ioh {
    
private:
    DIR *fp;
        
public:
    sioh() { pending = 0; }
    ~sioh() { }
    virtual void opendir(str path, cbs cb, CLOSURE);
    virtual void readdir(struct dirent *, cb_bool cb, CLOSURE);
    virtual void closedir(cbs cb, CLOSURE);
    virtual void stat(str name, struct stat *res, cbs cb, CLOSURE);
    virtual void open(str name, mode_t mode, cbs cb, CLOSURE);
    virtual void read(ptr<suio> io_in, int size, cb_int cb, CLOSURE);
    virtual void close(cbs cb, CLOSURE);
    virtual void seek(int offset, cbs cb, CLOSURE);
};

class aioh : public ioh {
    
private:
    aiod *a;
    ptr<aiofh> fh;
    ptr<aiobuf> buf;
    off_t pos;

public:
    aioh(aiod *ptr) : a(ptr) { pending = 0; pos = 0; }
    ~aioh() { }
    virtual void opendir(str path, cbs cb, CLOSURE);
    virtual void readdir(struct dirent *, cb_bool cb, CLOSURE);
    virtual void closedir(cbs cb, CLOSURE);
    virtual void stat(str name, struct stat *res, cbs cb, CLOSURE);
    virtual void open(str name, mode_t mode, cbs cb, CLOSURE);
    virtual void read(ptr<suio> io_in, int size, cb_int cb, CLOSURE);
    virtual void close(cbs cb, CLOSURE);
    virtual void seek(int offset, cbs cb, CLOSURE);
    virtual void check_pressure(cbv cb, CLOSURE);
};

class xferPlugin_xdisk : public xferPlugin, public storagePlugin {
  
private:
    gtcd *m;
    xferPlugin *xp;
    aiod *aiod_ptr;
    
    DbEnv *dbenv;

    chunkerPlugin *cp;
    storagePlugin *sp;
    vec<str> chunker;
        
public:
    Db *filesDb;
    
    callback<void, str, ptr<desc_result> >::ptr pending_cb;
    
    bool configure(str s, str pluginClass);
    
    /* Calls from the GTC */
    void xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			 descriptors_cb cb, CLOSURE);
    void xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
		    bitmap_cb cb, CLOSURE);
    void xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs);
    void sp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs);
    void xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
		    chunk_cb cb, CLOSURE);
    void cancel_chunk(ref<dot_descriptor> d, cancel_cb cb, CLOSURE);
    void cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb, CLOSURE);

    void update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints);

    /* Optimizer interface */
    void xp_get_ops(str key, dot_descriptor);
        
    xferPlugin_xdisk(gtcd *m, xferPlugin *next_xp);
    ~xferPlugin_xdisk() { }
    void xp_dump_statistics();

    /* Storage interface */
    
    bool init(dot_sId id);
    void put_chunk(dot_sId id, ref<dot_descriptor> d,
                   const char *buf, int len, cbs cb, CLOSURE);
    void commit_object(dot_sId id, commit_cb cb, CLOSURE);
    

    bool release_object(ref<dot_oid> oid) { return true; }
    
    void put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                    bool retain, cbs cb, CLOSURE) { }
    bool release_ichunk(ref<dot_descriptor> d) { return true; }

    void put_sp_cb(str s);
    

    void get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb, CLOSURE) { }
    void sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb, CLOSURE) { }
    //void notify_descriptors(ref<dot_oid_md> oid,
    //                      ptr<vec<dot_descriptor> > descs);
    void sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb, CLOSURE) { }
    void get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb, CLOSURE) { }
    void get_chunk(ref<dot_descriptor> d, chunk_cb cb, CLOSURE) { }
    int get_chunk_refcount(dot_descriptor *d) { return(1); }
        
    void inc_chunk_refcount(dot_descriptor *d) { }
        
    void sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb, CLOSURE) { }

    // private:
    void get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb, CLOSURE);
    void extract_stat_ops(str path);
    void extract_chit_op(dot_descriptor dv);
    void perform_stat(str path, ptr<vec<struct item_info> > stats, cbs cb, CLOSURE);
    void get_list(str path, ptr<vec<str> > res, bool async, cbs cb, CLOSURE);
    void get_stats(str path, ptr<vec<struct item_info> > res, bool async, cbs cb, CLOSURE);
    void perform_hash(str path, cbs cb, CLOSURE);
    void get_hash(str path, bool async, commit_cb cb, CLOSURE);
    void signal_chunker(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in, commit_cb cb);
    void perform_chunk(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in, commit_cb cb);
    void perform_chunk_cb(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in,
			  commit_cb cb, str s);
    void get_hash_done(ptr<ioh > handle, commit_cb cb, CLOSURE);
    void perform_offset_read(str path, int offset, int len, cbs cb, CLOSURE);
};


#endif /* _XFER_NET_H_ */
