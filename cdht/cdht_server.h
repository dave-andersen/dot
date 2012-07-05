#ifndef _CDHT_SERVER_H_
#define _CDHT_SERVER_H_

#include <stdio.h>
#include <stdlib.h>
#include <errno.h>
#include <signal.h>

#include <sys/types.h>
#include <sys/socket.h>

#include "odht_prot.h"
#include "async.h"
#include "arpc.h"

#include <iostream>
#include <map>

#define DEFAULT_CDHT_PORT 5852

using namespace std;

void accept_connection(int fd);
void sigpipe();
void debug_mmap();

class cdht_svr {
public:
    static void start_listening(int port); //start listening
    static void start_listening_dgram(int port);
    cdht_svr(int fd, const sockaddr_in &sin, rpc_program prog); //creates rpc server
    ~cdht_svr();
    list_entry<cdht_svr> link;

private:
    void dispatch(svccb *sbp);
    void cdht_put_proc(svccb *sbp);
    void cdht_get_proc(svccb *sbp);

    struct in_addr clientip;
    unsigned int clientport;
    ref<axprt> x;
    ref<asrv> c;
};

//identical member variables to cdht_putoid_arg
class cdht_put_info {
public:
    cdht_put_info(bamboo_key &, bamboo_value &);
    ~cdht_put_info();
    static void debug_mmap();
    static void lookup_key(bamboo_key key, vec<bamboo_value> *values);
    bamboo_key key;
    bamboo_value value;
};

#endif /* _CDHT_SERVER_H_ */
