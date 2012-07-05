#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <sys/time.h>
#include <time.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <arpa/inet.h>

#include <openssl/ssl.h>

#include "plcmd.h"

#include <algorithm>
#include <list>
#include <map>

using namespace std;

void
usage()
{
    fprintf(stderr,
	    "plcmd -n <nodelist> -c <cmdfile>\n"
	    );
}

void
help()
{
    usage();
    fprintf(stderr,
	    "\n"
	    );
}

int
init_socket(int port)
{
    int s;
    struct sockaddr_in sin;

    bzero(&sin, sizeof(sin));
    sin.sin_family = AF_INET;
    sin.sin_port = htons(port);
    sin.sin_addr.s_addr = INADDR_ANY;
#if defined(__FreeBSD__) || defined(__APPLE__)
    sin.sin_len = sizeof(sin); /* BSD/MacOS Only */
#endif

    if ((s = socket(AF_INET, SOCK_DGRAM, 0)) == -1) {
        perror("could not create socket");
        exit(-1);
    }

    if (bind(s, (struct sockaddr *)&sin, sizeof(sin)) == -1) {
        perror("could not bind socket");
        exit(-1);
    }

    return s;
}

int
sign(u_char *dat, int datlen, u_char *sig, u_int *siglen)
{
    EVP_PKEY *key;
    EVP_MD_CTX evp;
    BIO *keybio = BIO_new(BIO_s_file());

    BIO_read_filename(keybio, "key.pem");
    
    key = EVP_PKEY_new();
    if (!PEM_read_bio_PrivateKey(keybio, &key, NULL, NULL)) {
	printf("couldn't read privkey\n");
	exit(-1);
    }

    EVP_SignInit(&evp, EVP_sha1());
    EVP_SignUpdate(&evp, dat, datlen);
    
    int valid = EVP_SignFinal(&evp, sig, siglen, key);
    
    /* Free memory here;  this function leaks */

    return (valid == 1);
}

class node {
public:
    struct in_addr addr;
    unsigned short port;
    struct sockaddr_in sin;
    int sendcount;
    int acked;
    bool operator==(node& n) {
	return (addr.s_addr == n.addr.s_addr) && (port == n.port);
    }
    bool operator <= (node& n) {
	return (addr.s_addr < n.addr.s_addr) ||
	    ((addr.s_addr == n.addr.s_addr) && (port <= n.port));
    }
};

void
read_nodelist(char *filename, list<node> *nodelist)
{
    char buf[128];
    node n;
    FILE *f = fopen(filename, "r");
    while (fgets(buf, sizeof(buf)-1, f) != NULL) {
	char *colon = strchr(buf, ':');
	if (colon) {
	    *colon = '\0';
	    n.port = atoi(colon+1);
	    inet_aton(buf, &(n.addr));
#if 0
	    printf("Added host %s - %d\n",
		   inet_ntoa(n.addr), n.port);
#endif
	    
	    n.sendcount = 0;
	    n.acked = 0;
	    
	    bzero(&n.sin, sizeof(struct sockaddr_in));
	    n.sin.sin_family = AF_INET;
	    n.sin.sin_port = htons(n.port);
	    n.sin.sin_addr = n.addr;
#if defined(__FreeBSD__) || defined(__APPLE__)
	    n.sin.sin_len = sizeof(struct sockaddr_in); /* BSD/MacOS Only */
#endif
	    nodelist->push_back(n);
	}
    }
    fclose(f);
}

int
read_cmdfile(char *fname, char *cmdbuf)
{
    int f;
    f = open(fname, O_RDONLY);
    return read(f, cmdbuf, PLCMD_MAX_CMD_LEN+1);
    cmdbuf[PLCMD_MAX_CMD_LEN] = '\0';
}

int
read_ack(int sock, list<node> *nodelist)
{
    char buf[1500];
    struct sockaddr_in fromaddr;
    socklen_t fromsize = sizeof(fromaddr);

    int nb = recvfrom(sock, buf, sizeof(buf), 0,
		      (struct sockaddr *)&fromaddr, &fromsize);
    if (nb < 0) {
	perror("error on recvfrom");
	return 0;
    }
    if (nb != sizeof(struct plcmd_wire)) {
	fprintf(stderr, "bad sized packet: %d\n", nb);
	return 0;
    }
    
    struct plcmd_wire *plc = (struct plcmd_wire *)buf;
    if (ntohl(plc->magic) != PLCMD_MAGIC) {
	fprintf(stderr, "Bad magic: %u\n", ntohl(plc->magic));
	return 0;
    }
    if (ntohl(plc->pass) != PLCMD_PASS_XXX ||
	ntohl(plc->type) != PLCMD_TYPE_ACK) {
	fprintf(stderr, "Bad pkt contents\n");
	return 0;
    }

    list<node>::iterator i;
#if 0
    fprintf(stderr, "Got ACK from %s:%d\n",
	    inet_ntoa(fromaddr.sin_addr), ntohs(fromaddr.sin_port));
#endif

    for (i = nodelist->begin(); i != nodelist->end(); i++) {
	if (fromaddr.sin_addr.s_addr == i->addr.s_addr &&
	    fromaddr.sin_port == i->sin.sin_port) {
	    i->acked = 1;
#if 0
	    printf("Processing ACK for %s:%d\n",
		   inet_ntoa(fromaddr.sin_addr), ntohs(fromaddr.sin_port));
#endif
	    return 1;
	}
    }
    return 0;
}

int
check_acks(int sock, list<node> *nodelist)
{
    fd_set rset;
    FD_ZERO(&rset);
    FD_SET(sock, &rset);
    struct timeval timeout;
    timeout.tv_sec = 0;
    timeout.tv_usec = 1000;
    int nfds = select(sock+1, &rset, NULL, NULL, &timeout);
    if (nfds == 1) {
	return read_ack(sock, nodelist);
    }
    return 0;
}

int
main(int argc, char **argv)
{
    extern char *optarg;
    extern int optind;
    int ch;
    char cmdbuf[PLCMD_MAX_CMD_LEN+1];
    int cmdbufsize = 0;
    bool cmd_set = false;
    bool nodes_set = true;

    list<node> nodelist;
    
    while ((ch = getopt(argc, argv, "hn:c:")) != -1)
	switch (ch) {
	case 'n':
	    read_nodelist(optarg, &nodelist);
	    nodes_set = true;
	    break;
	case 'c':
	    cmdbufsize = read_cmdfile(optarg, cmdbuf);
	    cmd_set = true;
	    break;
	case 'h':
	    help();
	    exit(0);
	default:
	    usage();
	    exit(-1);
	}
    argc -= optind;
    argv += optind;

    if (!cmd_set || !nodes_set) {
	usage();
	exit(-1);
    }
    
    int s = init_socket(0);

    u_char buf[1500];
    u_char *cmd = (buf + sizeof(struct plcmd_wire));
    struct plcmd_wire *plc = (struct plcmd_wire *)buf;
    plc->magic = htonl(PLCMD_MAGIC);
    plc->pass = htonl(PLCMD_PASS_XXX);
    plc->vers_major = htons(PLCMD_MAJOR_VERS);
    plc->vers_minor = htons(PLCMD_MINOR_VERS);
#if defined(__FreeBSD__) || defined(__APPLE__)
    srandomdev();
#else
    struct timeval tv_rand;
    gettimeofday(&tv_rand, NULL);
    srandom(getpid() + tv_rand.tv_usec);
#endif
    plc->id = random();
    plc->cmdlen = htonl(cmdbufsize);
    memcpy(cmd, cmdbuf, cmdbufsize);
    
    unsigned int siglen = 0;
    sign(cmd, cmdbufsize, plc->sig, &siglen);
    plc->siglen = htonl(siglen);

    int pktsize = sizeof(struct plcmd_wire) + ntohl(plc->cmdlen);

    int n_acks_left = nodelist.size();

    int iters = 0;
    while (++iters < 3 && n_acks_left > 0) {
	list<node>::const_iterator i;
	for (i = nodelist.begin(); i != nodelist.end(); i++) {
	    node n = *i;
	    if (i->acked) {
		continue;
	    }
	    int rc = sendto(s, buf, pktsize, 0, (struct sockaddr *)&(n.sin), sizeof(struct sockaddr_in));
	    if (rc != pktsize) {
		perror("sendto");
	    }
#if 0
	    printf("Sent to %s:%d\n", inet_ntoa(n.sin.sin_addr), ntohs(n.sin.sin_port));
#endif
	    fflush(stdout);
	    n_acks_left -= check_acks(s, &nodelist);
	}
	if (n_acks_left > 0) {
	    sleep(1);
	}
    }
    struct timeval tv_start, tv_now;
    gettimeofday(&tv_start, NULL);
    if (n_acks_left != 0) {
	do {
	    n_acks_left -= check_acks(s, &nodelist);
	    gettimeofday(&tv_now, NULL);
	} while (tv_now.tv_sec - 3 < tv_start.tv_sec && n_acks_left > 0);
    }

    printf("\n\n");
    list<node>::const_iterator i;
    for (i = nodelist.begin(); i != nodelist.end(); i++) {
	printf("%s:%d %d\n",
	       inet_ntoa(i->addr), i->port, i->acked);
    }
    
    exit(0);
}
