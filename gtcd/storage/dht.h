#ifndef _DHT_H_
#define _DHT_H_

#include "odht_prot.h"
#include "gtcd.h"

typedef callback<void, str>::ref dht_put_cb;
typedef callback<void, str, ptr<vec<bamboo_value> > >::ref dht_get_cb;

//TYPE2STRUCT(, bamboo_stat);

class dht_rpc {
private:
    const str dht_ip;
    const int dht_port;
    gtcd *m;
   
protected:
    rconn_entry *conn;
    
public:
    dht_rpc(const str dht_ip, const int dht_port, gtcd *m) :
	dht_ip(dht_ip), dht_port(dht_port), m(m), conn(NULL) {
    }
    virtual ~dht_rpc() {}
    
    virtual void get(char *key, int keylen, int maxvals, dht_get_cb cb, CLOSURE);
    virtual void put(char *key, int keylen, char *value, int valuelen, dht_put_cb cb, CLOSURE);
    virtual void connect(rce_cb cb, CLOSURE);
    
    virtual void dht_get_call(char *key, int keylen, int maxvals, dht_get_cb cb, CLOSURE) = 0;
    virtual void dht_put_call(char *key, int keylen, char *value, int valuelen, dht_put_cb cb, CLOSURE) = 0;
};

class odht_rpc : public dht_rpc {
public:
    odht_rpc(const str dht_ip, const int dht_port, gtcd *m) :
	dht_rpc(dht_ip, dht_port, m) {}
    virtual void dht_get_call(char *key, int keylen, int maxvals, dht_get_cb cb, CLOSURE);
    virtual void dht_put_call(char *key, int keylen, char *value, int valuelen, dht_put_cb cb, CLOSURE);
};


#endif /* _DHT_H_ */
