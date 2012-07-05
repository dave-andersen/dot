#include "cdht_server.h"

/* #define UDP_SERV */ /* default is to use TCP */

int debug = 0;
const str debug_sep = "------------------------------------\n";

class key_compare : public binary_function<bamboo_key, bamboo_key, bool> {
public:
    int operator()(const bamboo_key &x, const bamboo_key &y) {
	size_t keylen = std::min(x.size(), y.size());
	/* Mapping memcmp to y > x */
	return (memcmp(x.base(), y.base(), keylen) < 0);
    }
};

list<cdht_svr, &cdht_svr::link> cdhtlist;

multimap<bamboo_key, cdht_put_info, key_compare> keyvalmap;
typedef multimap<bamboo_key, cdht_put_info>::iterator keyvaliter;
typedef multimap<bamboo_key, cdht_put_info>::const_iterator keyvalciter;
typedef pair<keyvalciter, keyvalciter> keyvalrange;

static void
usage()
{
    fprintf(stderr, "usage:  cdht_server [-h] [-d debuglevel] [-p port]\n");
}

static void
help()
{
    usage();
    fprintf(stderr,
	    "       -h ............. help (this message)\n"
	    "       -p <port> ...... port to listen on\n"
	    "       -d <debuglevel>  enable debugging output\n"
	    );
}

int main(int argc, char *argv[])
{
    int port = DEFAULT_CDHT_PORT;
    
    char ch;
    extern char *optarg;
    /*extern int optind;*/
    
    while ((ch = getopt(argc, argv, "hp:d:")) != -1)
	switch (ch) {
	case 'p':
	    port = atoi(optarg);
	    break;
	case 'd':
	    debug = atoi(optarg);
	    break;
	case 'h':
	    help();
	    exit(0);
	default:
	    usage();
	    exit(-1);
	}

    cdht_svr::start_listening(port);

    //cdht_svr::start_listening_dgram(port);

    amain();
}

void cdht_svr::start_listening(int port)
{
    if (debug >= 1) warn << "Listening on port "<< port << "\n";
  
    int fd = inetsocket(SOCK_STREAM, port);
    if (fd < 0)
	fatal("inetsocket: %m\n");

    close_on_exec(fd);
    make_async(fd);
  
    signal(SIGPIPE, SIG_IGN);

    listen(fd, 50);

    fdcb(fd,selread,wrap(accept_connection,fd));
}

void accept_connection(int fd)
{
    int conn_fd;
    struct sockaddr_in client_addr;
    int client_addr_len = sizeof(struct sockaddr_in);

    bzero((char *)&client_addr, sizeof(client_addr));
  
    //warn << "Accepting connection\n";

    conn_fd = accept(fd, (struct sockaddr*) &client_addr, (socklen_t *)&client_addr_len);

    if(conn_fd < 0) {
	warn << "Problem with incoming connection errno " << errno << "\n";
	return;
    }
    
    if (debug >= 2)
	warn << "accepted connection from "
	     << inet_ntoa(client_addr.sin_addr)
	     << " port " << ntohs(client_addr.sin_port) << "\n";
    
    close_on_exec(conn_fd);
    make_async(conn_fd);

    //make a rpc object to understand the call
    vNew cdht_svr(conn_fd, client_addr, bamboo_dht_gateway_program_2);
}


/**
 * @param fd
 *              The socket file descriptor.
 * @param sin
 *              The socket address.
 * @param prog
 *              The RPC program that will be executed.
 */


cdht_svr::cdht_svr(int fd, const sockaddr_in &sin, rpc_program prog) :
#ifdef UDP_SERV
    x(axprt_dgram::alloc(fd)),
#else
    x(axprt_stream::alloc(fd)),
#endif
      c(asrv::alloc(x, prog, wrap(this, &cdht_svr::dispatch)))
{
    cdhtlist.insert_head(this);
    clientip = sin.sin_addr;
    clientport = ntohs(sin.sin_port);
}

/**
 * Execute the appropriate procedure, according to the type of the request.
 * @param sbp
 *              The service callback.
 */
void cdht_svr::dispatch(svccb *sbp)
{
    if (!sbp) {
	//warn("dispatch(): client closed connection\n");
	delete this;
	return;
    }

    switch (sbp->proc()) {
    case BAMBOO_DHT_PROC_PUT:
	cdht_put_proc(sbp);
	break;
    
    case BAMBOO_DHT_PROC_GET:
	cdht_get_proc(sbp);
	break;

    default:
	//warn << "requested unavailable procedure\n";
	sbp->reject(PROC_UNAVAIL);
	break;
    }
}


/* The server is destroyed when connection is closed. */
cdht_svr::~cdht_svr()
{
    if (debug >= 2)
	warn("Connection closed from %s:%d\n", inet_ntoa(clientip), clientport);
    
    cdhtlist.remove(this);
}

void cdht_svr::cdht_put_proc(svccb *sbp)
{
    if (debug >= 3)
	warn << "processing put request\n";

    bamboo_put_args *arg1 = sbp->Xtmpl getarg<bamboo_put_args>();
    bamboo_stat res(BAMBOO_OK);

    bamboo_key key = arg1->key;
    bamboo_value value = arg1->value;

    bool isdup = false;

    keyvalrange range = keyvalmap.equal_range(key);

    for (keyvalciter i = range.first; i != range.second; i++) {
	if (!memcmp(i->second.value.base(), value.base(),
		    std::min(i->second.value.size(), value.size()))) {
	    isdup = true;
	    break;
	}
    }

    if (!isdup) {
	if (debug >= 3) warn << "inserting put request\n";
	cdht_put_info item1(key, value);
	keyvalmap.insert(make_pair(key, item1));
    } else {
	if (debug >= 3) warn << "skipping duplicate put request\n";
	/* XXX - if we supported a TTL, update it here */
    }

    sbp->replyref(res);
}

void cdht_svr::cdht_get_proc(svccb *sbp)
{
    bamboo_get_args *arg1;
    bamboo_get_res res;
    bamboo_key key;

    arg1 = sbp->Xtmpl getarg<bamboo_get_args>();
    
    if (debug >= 3)
	warn << debug_sep << "processing get request\n";
    
    key = arg1->key;

    vec<bamboo_value> values;

    //cdht_put_info::debug_mmap();
    cdht_put_info::lookup_key(key, &values);
  
    res.values.setsize(values.size());
    for (unsigned int i = 0; i < values.size(); i++) {
	if (debug >= 3)
	    warn << "Getting values\n";
	res.values[i] = values[i];
    }
  
    sbp->replyref(res);
    
    if (debug >= 3)
	warn << debug_sep;
}

void
cdht_put_info::debug_mmap()
{
    warn << debug_sep << "Values with all keys\n";
    
    for (keyvalciter i = keyvalmap.begin(); i != keyvalmap.end(); i++) {
	warn << "Key: " << i->first.base()
	     << " Value: " << i->second.value.base() << "\n";
    }
}

cdht_put_info::cdht_put_info(bamboo_key &key, bamboo_value &value) :
    key(key), value(value)
{
}

cdht_put_info::~cdht_put_info()
{
}

void
cdht_put_info::lookup_key(const bamboo_key key, vec<bamboo_value> *values)
{
    keyvalrange range = keyvalmap.equal_range(key);

    for (keyvalciter i = range.first; i != range.second; i++) {
	values->push_back(i->second.value);
    }
}

/* Not currently used */

void cdht_svr::start_listening_dgram(int port)
{
    if (debug >= 1) warn << "Listening on UDP port "<< port << "\n";
  
    int fd = inetsocket(SOCK_DGRAM, port);
    if (fd < 0)
	fatal("inetsocket: %m\n");

    close_on_exec(fd);
    make_async(fd);
  
    signal(SIGPIPE, SIG_IGN);

    struct sockaddr_in client_addr;
    bzero((char *)&client_addr, sizeof(client_addr));
  
    vNew cdht_svr(fd, client_addr, bamboo_dht_gateway_program_2);
}
