#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include "dht.h"

tamed void
dht_rpc::connect(rce_cb cb)
{
    rpc_info i;
        
    i.ip = dht_ip;
    i.port = dht_port;
    i.stream = AXPRT_STREAM;
    i.program = &bamboo_dht_gateway_program_2;
    i.canq = false;

    m->rpcCache->connect(i, cb);
}

tamed void
dht_rpc::put(char *key, int keylen, char *value, int valuelen, dht_put_cb cb)
{
    tvars {
	str dht_key;
	str dht_val;
    }

    dht_key.setbuf(key, keylen);
    dht_val.setbuf(value, valuelen);

    twait {
	connect(mkevent(conn));
    }
    if (!conn) {
	warn << "dht_rpc::put could not connect to DHT!\n";
	(*cb)("Could not connect to DHT");
	return;
    }

    dht_put_call((char *)dht_key.cstr(), dht_key.len(), (char *)dht_val.cstr(), dht_val.len(), cb);
}


tamed void
dht_rpc::get(char *key, int keylen, int maxvals, dht_get_cb cb)
{
    tvars {
	str dht_key;
    }

    dht_key.setbuf(key, keylen);
    
    twait {
	connect(mkevent(conn));
    }
    if (!conn) {
	warn << "dht_rpc::get could not connect to DHT!\n";
	(*cb)("Could not connect to DHT", NULL);
	return;
    }

    dht_get_call((char *)dht_key.cstr(), dht_key.len(), maxvals, cb);
}


tamed void
odht_rpc::dht_put_call(char *key, int keylen, char *value, int valuelen, dht_put_cb cb)
{
    tvars {
	clnt_stat err;
	ptr<bamboo_stat> cli_res;
	bamboo_put_args args;
    }
    
    cli_res = New refcounted<bamboo_stat>; /* ugh, should be bamboo_stat */

    args.application = APPLICATION;
    args.client_library = CLIENT_LIBRARY;
    args.ttl_sec = OPENDHT_TTL; /* XXX */
    memcpy(args.key.base(), key, min(keylen, 20));

    //warn << "odht_rpc:: Valuelen: " << min(valuelen, 1024) << "\n";
    args.value.set(value, min(valuelen, 1024));

    //warn << "odht_rpc:: DHT put call blocking\n";
    
    twait {
	conn->clnt->call(BAMBOO_DHT_PROC_PUT, &args, cli_res, mkevent (err));
    }

    if (err) {
	str sb = strbuf() << "odht_rpc::put failed: " << err << "\n";
	warn << sb;
	(*cb)(sb);
	return;
    } else {
	if (*cli_res != BAMBOO_OK) {
	    str sb = strbuf() << "odht_rpc::put failed due to Bamboo error";
	    warn << sb << "\n";
	    (*cb)(sb);
	    return;
	} else {
	    dwarn(DEBUG_SET) << "odht_rpc::put succeeded\n";
	    (*cb)(NULL);
	    return;
	}
    }

    assert(false); /* not reached */
}

tamed void
odht_rpc::dht_get_call(char *key, int keylen, int maxvals, dht_get_cb cb)
{
    tvars {
	clnt_stat err;
	bamboo_get_args args;
	bamboo_get_res cli_res;
	ptr<vec<bamboo_value> > results;
	int rounds;
    }

    rounds = 0;
    args.application = APPLICATION;
    args.client_library = CLIENT_LIBRARY;
    args.maxvals = min(maxvals, ODHT_MAXVALS_RET);
    
    memcpy(args.key.base(), key, min(keylen, 20));

    twait {
	conn->clnt->timedcall(10, BAMBOO_DHT_PROC_GET, &args, &cli_res, mkevent (err));
    }

    if (err) {
	str sb = strbuf() << "odht_rpc::get failed: " << err << "\n";
	warn << sb;
	(*cb)(sb, NULL);
	return;
    }
    
    results = New refcounted<vec<bamboo_value> >;

    while (1) {

	//warn << "odht_rpc::get succeeded.  " << cli_res.values.size() << " values returned\n";
	rounds++;
	
	for (unsigned int i = 0; i < cli_res.values.size(); i++) {
	    results->push_back(cli_res.values[i]);
	}

	if (cli_res.values.size() == 0) {
	    dwarn(DEBUG_SET) << "odht_rpc:: dht_get_call:: No more results\n";
	    break;
	}
	
	//get all the values if placemark is not zero
	if (cli_res.placemark.size() > 0 ) {
            
            dwarn(DEBUG_SET) << "odht_rpc:: Have more stuff\n";

	    bzero(&args, sizeof(struct bamboo_get_args));
            args.application = APPLICATION ;
            args.client_library = CLIENT_LIBRARY ;
	    args.maxvals = min(maxvals, ODHT_MAXVALS_RET);
	    memcpy(args.key.base(), key, min(keylen, 20));
	    args.placemark.setsize(cli_res.placemark.size());
	    memcpy(args.placemark.base(), cli_res.placemark.base(), cli_res.placemark.size());

	    bzero(&cli_res, sizeof(struct bamboo_get_res));

	    twait {
		conn->clnt->timedcall(10, BAMBOO_DHT_PROC_GET, &args, &cli_res, mkevent (err));
	    }
        }
        else {
	    dwarn(DEBUG_SET) << "odht_rpc:: Finished get\n";
	    break;
	}
    }

    warn << "Get succeeded in " << rounds << " rounds and gave "
	 << results->size() << " values\n";

    if (results->size())
	(*cb)(NULL, results);
    else {
	str sb = "odht_rpc::get returned no results\n";
	warn << sb;
	(*cb)(sb, NULL);
    }
}
