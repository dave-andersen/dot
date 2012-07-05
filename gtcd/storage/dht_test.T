#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include "dht.h"

#if 0
class dht_test {
public:
    odht_rpc dht;
    void start(CLOSURE);
    void more_rude_test(CLOSURE);
    /*dht_test() : dht("12.108.127.136", 5852) {*/
    dht_test() : dht("127.0.0.1", 5852) {
	start();
    }
};

tamed void
dht_test::more_rude_test()
{
    tvars {
	char *key;
	char *bigval;
	int keylen;
	str err;
	int i;
	ptr<vec<bamboo_value> > results;
	unsigned int biglen;
    }

    key = "01234567";
    keylen = 20;
    bigval = "VVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVALUE";

    warn << "Starting rude tests\n";
    
    biglen = strlen(bigval) + 1;
    i = 1;
    warn << "i: " << i << "\n";
    for (i = 0; i < 3; i++) {
	twait {
	    dht.put(key, keylen, bigval, biglen, mkevent (err));
	}
	warn << "Dht put done\n";
	twait {
	    dht.get(key, keylen, 255, mkevent (err, results));
	}
	warn << "Results size: " << results->size() << "\n";
	if (results->size() != 1) {
	    warn << "INCORRECT RESULT COUNT " << results->size()  << "\n";
	    exit(0);
	}
	for (unsigned int j = 0; j < results->size(); j++) {
#if 0
	    unsigned int len = min(biglen, (unsigned int)((*results)[i].size()));
	    if (memcmp((*results)[i].base(), bigval, len)) {
		warn << "INCORRECT VALUE RETURN\n";
		exit(0);
	    }
#endif
	    }
    }

    warn << "All rude tests passed\n";
    exit(0);
}

tamed void
dht_test::start()
{
#if 1
    tvars {
	str err;
	ptr<vec<bamboo_value> >results;
    }
    
    twait { dht.put("K1", 3, "Value1", 7, mkevent (err)); }

    if (err)
	warn << "PUT: Err: " << err << "\n";

    twait { dht.put("K1", 3, "Value2", 7, mkevent (err)); }
    if (err)
	warn << "PUT2: Err: " << err << "\n";

    twait { dht.get("K1", 3, 255, mkevent (err, results)); }

    if (err)
	warn << "GET: Err: " << err << "\n";
    else {
	for (unsigned int i = 0; i < results->size(); i++) {
	    char foo[256];
	    sprintf(foo, "%10.10s", (*results)[i].base());
	    warn << "  " << i << ": " << foo << "\n";
	}
	warn << "\n";
    }
#endif
    more_rude_test();
}

#endif

int
main()
{
    //vNew dht_test;
    amain();
}

