#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <string.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <netinet/in.h>
#include <algorithm>

using namespace std;

#include "plcmd.h"

#include <openssl/evp.h>
#include <openssl/pem.h>

bool verbose = false;

void
usage()
{
    fprintf(stderr,
	    "plcmd_daemon [-dv] [-p port]\n"
	    );
}

void
help()
{
    usage();
    fprintf(stderr,
            "  -p <port> .. run on specified port\n"
	    "  -d  ........ do not daemonize\n"
	    "  -v  ........ verbose output (implies -d)\n"
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

EVP_PKEY *verify_key;

void
setup_key()
{
    BIO *keybio = BIO_new(BIO_s_file());

    BIO_read_filename(keybio, "pubkey.pem");
    
    verify_key = EVP_PKEY_new();
    if (!PEM_read_bio_PUBKEY(keybio, &verify_key, NULL, NULL)) {
	printf("couldn't read pubkey\n");
	exit(-1);
    }
}

int
valid_signature(u_char *sig, int siglen, u_char *dat, int datlen)
{
    EVP_MD_CTX evp;

    EVP_SignInit(&evp, EVP_sha1());
    EVP_SignUpdate(&evp, dat, datlen);

    int valid = EVP_VerifyFinal(&evp, sig, siglen, verify_key);
    return (valid == 1);
}

void
send_ack(int sock, struct plcmd_wire *plc, struct sockaddr_in *src, socklen_t srcsize)
{
    struct plcmd_wire resp;
    bzero(&resp, sizeof(resp));
    resp.type = htonl(PLCMD_TYPE_ACK);
    resp.magic = plc->magic;
    resp.id = plc->id;
    resp.pass = plc->pass;
    sendto(sock, (u_char *)&resp, sizeof(resp), 0, (struct sockaddr *)src, srcsize);
}

/* Global table of recently handled IDs */
#define NRECENT 32
u_int32_t recents[NRECENT];
int most_recent;

bool
handled_recently(u_int32_t id)
{
    for (int i = 0; i < NRECENT; i++) {
	if (recents[i] == id) {
	    return true;
	}
    }
    most_recent++;
    most_recent %= NRECENT;
    recents[most_recent] = id;
    return false;
}

void
handle(int sock, char *buf, unsigned int bufsize, struct sockaddr_in *fromaddr, socklen_t fromsize)
{
    u_char cmdbuf[1500];
    struct plcmd_wire *plc = (struct plcmd_wire *)buf;
    
    int cmdsize = ntohl(plc->cmdlen);
    int siglen = ntohl(plc->siglen);

    if (bufsize < sizeof(struct plcmd_wire))
	return;
    if (ntohl(plc->magic) != PLCMD_MAGIC)
	return;
    if (ntohl(plc->pass) != PLCMD_PASS_XXX)
	return;
    if (siglen != PLCMD_SIG_SIZE) /* XXX - why do we have this field? */
	return;
    if ((cmdsize + sizeof(struct plcmd_wire)) != bufsize)
	return;

    u_int32_t id = plc->id;
    if (handled_recently(id)) {
	return;
    }
    cmdsize = min(cmdsize, (int)(sizeof(cmdbuf)-1));
    memcpy(cmdbuf, (buf + sizeof(struct plcmd_wire)), cmdsize);
    cmdbuf[cmdsize] = 0;

    if (valid_signature(plc->sig, siglen, cmdbuf, ntohl(plc->cmdlen))) {
	send_ack(sock, plc, fromaddr, fromsize);
	if (!strncmp((char *)cmdbuf, "quit_plcmd", 10)) {
	    exit(0);
	}
	if (verbose)
	    printf("CMD: %s\n", cmdbuf);

	pid_t kidpid = fork();
	if (kidpid < 0) {
	    perror("fork failed");
	} else if (kidpid == 0) {
	    system((char *)cmdbuf);
	    exit(0);
	} else {
	    return;
	}
    } else {
	fprintf(stderr, "signature verify failed\n");
    }
}

void
reapkid(int sig)
{
    while (waitpid(0, NULL, WNOHANG) > 0) {
	;
    }
}

int
main(int argc, char **argv)
{
    extern int optind;
    int ch;
    int s;
    char buf[1500];
    bool nodaemon = false;
    int port = PLCMD_DEFAULT_PORT;
    
    while ((ch = getopt(argc, argv, "hdvp:")) != -1)
	switch (ch) {
	case 'v':
	    nodaemon = true;
	    verbose = true;
	    break;
	case 'd':
	    nodaemon = true;
	    break;
	case 'p':
	    port = atoi(optarg);
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
    argv += optind;

    s = init_socket(port);
    setup_key();

    if (!nodaemon) {
	daemon(1, 0);
    }

    signal(SIGCHLD, reapkid);

    while (1) {
	struct sockaddr_in fromaddr;
	socklen_t fromsize = sizeof(fromaddr);
	int nb = recvfrom(s, buf, sizeof(buf)-1, 0,
			  (struct sockaddr *)&fromaddr, &fromsize);
	if (nb < 0) {
	    perror("error on recvfrom");
	} else {
	    handle(s, buf, nb, &fromaddr, fromsize);
	}
	while (waitpid(0, NULL, WNOHANG) > 0) {
	    ;
	}
    }
    
    /* NOEXIT */
}

