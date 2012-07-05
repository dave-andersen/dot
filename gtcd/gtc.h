/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _GTC_H_
#define _GTC_H_ 1

#include "async.h"
#include "arpc.h"
#include "gtc_prot.h"
#include "params.h"

#include <openssl/evp.h>

#define MAX_OPEN_FDS 1000
#define SEND_SIZE      ((size_t)(MAX_PKTSIZE - 0x1000))

typedef callback<void, str, ptr<dot_oid_md>, ptr<vec<oid_hint> > >::ref put_client_cb;

struct fd_struct {
    str fname;
    int fd;

    ihash_entry<fd_struct> hlink;
    tailq_entry<fd_struct> tlink;

    fd_struct (str name);
    ~fd_struct ();
};

int get_new_fd(str s);
bool return_fd(str s);

class put_client_base {
public:
    ref<aclnt> gtc_c;
    put_client_cb cb;
    put_client_base(ref<aclnt> gtc, put_client_cb cb) :
      gtc_c(gtc), cb(cb) {}
    virtual ~put_client_base() {};
    void put_end(ref<gtc_put_commit_res> res, clnt_stat err);
};

class put_client: public put_client_base {
    dot_xferId xferId;
    unsigned int pendingRPCs;

    /* Reading file stuff--move out of put_client?? */
    suio io_in;
    int in_fd;
    char inbuf[SEND_SIZE]; // per-object??

    void send_file();
    void set_callback_state();
    void read_file_data();
    void put_start(ref<gtc_put_init_res> res, clnt_stat err);
    void put_data_cb(ref<gtc_put_data_res> res, clnt_stat err);
    
public:
    put_client(int in_fd, ref<aclnt> gtc, put_client_cb cb);
    put_client(int in_fd, str file, ref<aclnt> gtc, put_client_cb cb);
    ~put_client();
};

class put_client_fd : public put_client_base {
    int in_fd;

public:
    put_client_fd(int in_fd, ref<aclnt> gtc, put_client_cb cb);
    put_client_fd(int in_fd, str file, ref<aclnt> gtc, put_client_cb cb);
    ~put_client_fd();
};

class put_client_suio : public put_client_base {
    dot_xferId xferId;
    unsigned int pendingRPCs;

    /* Reading file stuff--move out of put_client?? */
    ptr<suio > buf;
    char inbuf[SEND_SIZE]; // per-object??

    void put_start(ref<gtc_put_init_res> res, clnt_stat err);
    void put_data();
    void put_data_cb(ref<gtc_put_data_res> res, clnt_stat err);
    
public:
    put_client_suio(ptr<suio > buf, ref<aclnt> gtc, put_client_cb cb);
    ~put_client_suio();
};

class get_client {
    dot_oid_md oid;
    int out_fd;
    ref<aclnt> gtc_c;
    cbs cb;

    dot_xferId xferId;
    ptr<suio > buf;

    str final_name;

    void get_descs(str res, ref<gtc_get_init_res> res2, clnt_stat err);
    void get_start(ref<gtc_get_init_res> res, clnt_stat err);
    void get_data(ref<gtc_get_data_res> res, clnt_stat err);

    void finish(str err);

public:
    get_client(dot_oid_md oid, ref<vec<oid_hint> > hints, int out_fd, str n,
	       ref<aclnt> gtc, cbs cb);
    get_client(dot_oid_md oid, ref<vec<oid_hint> > hints, ptr<suio > in, 
			   ref<aclnt> gtc, cbs cb);
    ~get_client();
};

#endif /* _GTC_H_ */
