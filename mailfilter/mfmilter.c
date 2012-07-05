#include <sys/types.h>
#include <sys/stat.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sysexits.h>
#include <unistd.h>
#include <pwd.h>
#include <assert.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <sys/time.h>

#include <openssl/evp.h>
#include <openssl/hmac.h>

#include "libmilter/mfapi.h"
#include "fingerprint_c.h"

#ifndef bool
# define bool   int
# define TRUE   1
# define FALSE  0
#endif /* ! bool */

int debug = 0;

#define TARGET_USER "mailnull"
#define SPOOLDIR "/var/spool/mfmilter"
#define OUTPUTDIR "output"
#define TEMPDIR   "tmp"
#define HMAC_KEY  "jk12#(jfng09t;1jgle09ja.,m13103hjag3;93jt13la81q"

/* Initial amounts of buffer */
#define BUF_INIT_SIZE   65536

struct charbuf
{
    char *buf;
    unsigned int max;
    unsigned int cur;
};

struct mlfiPriv
{
    char    *mlfi_fname;
    char    *mlfi_connectfrom;
    _SOCK_ADDR mlfi_connectaddr;
    char    *mlfi_helofrom;
    FILE    *mlfi_fp;
    struct charbuf databuf;
    unsigned int headerlen; /* within the databuf */
};

#define MLFIPRIV        ((struct mlfiPriv *) smfi_getpriv(ctx))

extern sfsistat         mlfi_cleanup(SMFICTX *, bool);
extern void smfTestMessage(char* mfile);

void
charbuf_free(struct charbuf *b)
{
    if (b->buf) {
	free(b->buf);
	b->buf = NULL;
    }
}

void
charbuf_reset(struct charbuf *b)
{
    b->cur = 0;
}

int
charbuf_init(struct charbuf *b, int siz)
{
    b->buf = malloc(siz);
    b->cur = 0;
    if (!b->buf) {
	return -1;
    }
    b->max = siz;
    return 0;
}

int
charbuf_append(struct charbuf *b, char *dat, int len)
{
    char *newb;
    if (debug) fprintf(stderr, "charbuf_append\n");
    
    assert(dat != NULL);
    assert(b->buf != NULL);
    
    if (len + b->cur >= b->max) {
	if (debug) fprintf(stderr, "Reallocing charbuf\n");
	newb = realloc(b->buf, b->max * 2);
	if (!newb) {
	    return -1;
	}
	b->buf = newb;
	b->max *= 2;
    }
    if (debug) fprintf(stderr, "charbuf_append bcopy cur: %d max %d len: %d dat: %p buf: %p\n",
	    b->cur, b->max, len, dat, b->buf);
    bcopy(dat, b->buf + b->cur, len);
    b->cur += len;
    if (debug) fprintf(stderr, "charbuf_append done\n");
    return 0;
}
	    

sfsistat
mlfi_connect(SMFICTX *ctx, char *hostname, _SOCK_ADDR *hostaddr)
{
    struct mlfiPriv *priv;
    char *ident;
    
    /* allocate some private memory */
    priv = malloc(sizeof *priv);
    if (priv == NULL)
    {
	/* can't accept this message right now */
	return SMFIS_TEMPFAIL;
    }
    bzero(priv, sizeof *priv);
    
    if (charbuf_init(&priv->databuf, BUF_INIT_SIZE) == -1) {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    
    /* save the private data */
    smfi_setpriv(ctx, priv);

    if (hostaddr == NULL) {
	fprintf(stderr, "null connect host\n");
    } else {
	priv->mlfi_connectaddr = *hostaddr;
    }
    
    ident = smfi_getsymval(ctx, "_");
    if (ident == NULL)
	ident = hostname;
    if (ident == NULL)
	ident = "???";
    if ((priv->mlfi_connectfrom = strdup(ident)) == NULL)
    {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    
    /* continue processing */
    return SMFIS_CONTINUE;
}

sfsistat
mlfi_helo(SMFICTX *ctx, char *helohost)
{
    size_t len;
    char *tls;
    char *buf;
    struct mlfiPriv *priv = MLFIPRIV;
    
    tls = smfi_getsymval(ctx, "{tls_version}");
    if (tls == NULL)
	tls = "No TLS";
    if (helohost == NULL)
	helohost = "???";
    len = strlen(tls) + strlen(helohost) + 3;
    if ((buf = (char*) malloc(len)) == NULL)
    {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    snprintf(buf, len, "%s, %s", helohost, tls);
    if (priv->mlfi_helofrom != NULL)
	free(priv->mlfi_helofrom);
    priv->mlfi_helofrom = buf;
    
    /* continue processing */
    return SMFIS_CONTINUE;
}

void
printhash_int(FILE *fp, char *dat, unsigned int datlen, int printlen)
{
    unsigned char md[EVP_MAX_MD_SIZE];
    unsigned int mdsize;
    unsigned int i;

    HMAC(EVP_sha1(), HMAC_KEY, strlen(HMAC_KEY),
	 (unsigned char *) dat, datlen, md, &mdsize);

    for (i = 0; i < mdsize; i++) {
	fprintf(fp, "%2.2x", md[i]);
    }
    if (printlen) fprintf(fp, " %u", datlen);
}

void
printlinehash(FILE *fp, char *dat, unsigned int datlen, char *label)
{
    fprintf(fp, "%s ", label);
    printhash_int(fp, dat, datlen, 1);
    fprintf(fp, "\n");
}

void
printhash(FILE *fp, char *dat, int printlen)
{
    printhash_int(fp, dat, strlen(dat), printlen);
}


void
log_hashed_addr(FILE *fp, char *name, char *addr)
{
    char *rat;
    char *addr_dup;

    fprintf(fp, "%s ", name);
    addr_dup = strdup(addr);
    
    rat = strrchr(addr_dup, '@');
    if (rat) {
	*rat = '\0';
    }

    printhash(fp, addr_dup, 0);
    if (rat) {
	rat++;
	fprintf(fp, " @ ");
	printhash(fp, rat, 0);
    }
    free(addr_dup);
    fprintf(fp, "\n");
}


sfsistat
mlfi_envfrom(SMFICTX *ctx, char **argv)
{
    int argc = 0;
    struct mlfiPriv *priv = MLFIPRIV;
    char tmpfilename[64];
    struct timeval tv;
    struct sockaddr_in *sain;
    char connfrom[INET6_ADDRSTRLEN + INET_ADDRSTRLEN];
    
    char *mailaddr = smfi_getsymval(ctx, "{mail_addr}");
    if (mailaddr == NULL)
	mailaddr = argv[0];
    
    /* open a file to store this message */
    
    gettimeofday(&tv, NULL);
    sprintf(tmpfilename, "%s/%ld.%6.6ld",
	    TEMPDIR, tv.tv_sec, tv.tv_usec);
    if ((priv->mlfi_fname = strdup(tmpfilename)) == NULL)
    {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    
    if ((priv->mlfi_fp = fopen(priv->mlfi_fname, "w+")) == NULL)
    {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    
    /* count the arguments */
    char **p = argv;
    while (*p++ != NULL)
	++argc;
    
    /* log the connection information we stored earlier: */
    /* A vague sense of privacy */
    sain = (struct sockaddr_in *)&priv->mlfi_connectaddr;
    sain->sin_addr.s_addr &= htonl(0xffffff00);

    inet_ntop(AF_INET, &sain->sin_addr, connfrom, sizeof(connfrom));
    
    if (fprintf(priv->mlfi_fp, "CONNECT %s\n", connfrom) == EOF) {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }

    /* log the sender */
    log_hashed_addr(priv->mlfi_fp, "FROM", mailaddr);
    
    /* continue processing */
    return SMFIS_CONTINUE;
}

sfsistat
mlfi_envrcpt(ctx, argv)
    SMFICTX *ctx;
    char **argv;
{
    struct mlfiPriv *priv = MLFIPRIV;
    
    char *rcptaddr = smfi_getsymval(ctx, "{rcpt_addr}");
    if (rcptaddr == NULL)
	rcptaddr = argv[0];
    
    log_hashed_addr(priv->mlfi_fp, "RCPT", rcptaddr);

    return SMFIS_CONTINUE;
}

sfsistat
mlfi_header(SMFICTX *ctx, char *headerf, char *headerv)
{
    if (headerf) {
	if (charbuf_append(&MLFIPRIV->databuf, headerf, strlen(headerf))) {
	    (void) mlfi_cleanup(ctx, FALSE);
	    return SMFIS_TEMPFAIL;
	}
	if (charbuf_append(&MLFIPRIV->databuf, ": ", 2)) {
	    (void) mlfi_cleanup(ctx, FALSE);
	    return SMFIS_TEMPFAIL;
	}
	if (headerv) {
	    if (charbuf_append(&MLFIPRIV->databuf, headerv, strlen(headerv))) {
		(void) mlfi_cleanup(ctx, FALSE);
		return SMFIS_TEMPFAIL;
	    }
	}
	if (charbuf_append(&MLFIPRIV->databuf, "\n", 1)) {
	    (void) mlfi_cleanup(ctx, FALSE);
	    return SMFIS_TEMPFAIL;
	}
    }

    /* continue processing */
    return SMFIS_CONTINUE;
}

sfsistat
mlfi_eoh(SMFICTX *ctx)
{
    
    if (debug) fprintf(stderr, "eoh start\n");
    MLFIPRIV->headerlen = MLFIPRIV->databuf.cur;

    /* append the blank line between the header and the body */
    if (charbuf_append(&MLFIPRIV->databuf, "\n", 1)) {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }

    return SMFIS_CONTINUE;
}

sfsistat
mlfi_body(SMFICTX *ctx, unsigned char *bodyp, size_t bodylen)
{
    if (debug) fprintf(stderr, "mlfi_body\n");
    
    if (charbuf_append(&MLFIPRIV->databuf, (char *) bodyp, bodylen)) {
	(void) mlfi_cleanup(ctx, FALSE);
	return SMFIS_TEMPFAIL;
    }
    
    /* continue processing */
    return SMFIS_CONTINUE;
}

sfsistat
mlfi_eom(SMFICTX *ctx)
{
    bool ok = TRUE;
    unsigned int i;
    unsigned int bytes, body_offset;
    int starts[2];

    if (debug) fprintf(stderr, "mlfi_eom\n");

    body_offset = MLFIPRIV->headerlen + 1;

    printlinehash(MLFIPRIV->mlfi_fp, MLFIPRIV->databuf.buf,
		  MLFIPRIV->headerlen, "HEADER");

    printlinehash(MLFIPRIV->mlfi_fp,
		  MLFIPRIV->databuf.buf + body_offset,
		  MLFIPRIV->databuf.cur - body_offset, "BODY");

    printlinehash(MLFIPRIV->mlfi_fp, MLFIPRIV->databuf.buf,
		  MLFIPRIV->databuf.cur, "WHOLE");

    starts[0] = 0;
    starts[1] = body_offset;

#define STATIC_BLOCKSIZE 16534

    for (i = 0; i < 2; i++) {
	fprintf(MLFIPRIV->mlfi_fp, (i == 0 ? "STATIC_WHOLE_CHUNKS\n" :
				    "STATIC_BODY_CHUNKS\n"));
	for (bytes = starts[i];
	     bytes < MLFIPRIV->databuf.cur;
	     bytes += STATIC_BLOCKSIZE) {
	    int nbytes;
	    nbytes = STATIC_BLOCKSIZE;
	    if (bytes + nbytes > MLFIPRIV->databuf.cur) {
		nbytes = MLFIPRIV->databuf.cur - bytes;
	    }
	    printhash_int(MLFIPRIV->mlfi_fp, MLFIPRIV->databuf.buf + bytes,
			  nbytes, 1);
	    fprintf(MLFIPRIV->mlfi_fp, "\n");
	}
    }
    
    for (i = 0; i < 2; i++) {
	unsigned int *rab;
	unsigned int j, nchunks, off;

	fprintf(MLFIPRIV->mlfi_fp, (i == 0 ? "RABIN_WHOLE_CHUNKS\n" :
				    "RABIN_BODY_CHUNKS\n"));

	off = starts[i];
	nchunks = 0;
	rab = chunk_boundaries((unsigned char *) MLFIPRIV->databuf.buf + off,
			       MLFIPRIV->databuf.cur - off,
			       &nchunks);
	for (j = 0; j < nchunks; j++) {
	    printhash_int(MLFIPRIV->mlfi_fp, MLFIPRIV->databuf.buf + off,
			  rab[j], 1);
	    fprintf(MLFIPRIV->mlfi_fp, "\n");
	    off += rab[j];
	}
	if (off < MLFIPRIV->databuf.cur) {
	    printhash_int(MLFIPRIV->mlfi_fp, MLFIPRIV->databuf.buf + off,
			  MLFIPRIV->databuf.cur - off, 1);
	    fprintf(MLFIPRIV->mlfi_fp, "\n");
	}

	if (rab) free(rab);
    }
    return mlfi_cleanup(ctx, ok);
}

sfsistat
mlfi_abort(SMFICTX *ctx)
{
    return mlfi_cleanup(ctx, FALSE);
}

sfsistat
mlfi_cleanup(ctx, ok)
         SMFICTX *ctx;
         bool ok;
{
        sfsistat rstat = SMFIS_CONTINUE;
        struct mlfiPriv *priv = MLFIPRIV;
        //char *p;
        //char host[512];
        //char hbuf[1024];

	if (debug) fprintf(stderr, "mlfi_cleanup.\n");
        if (priv == NULL)
                return rstat;

        /* close the archive file */
        if (priv->mlfi_fp != NULL && fclose(priv->mlfi_fp) == EOF)
        {
                /* failed; we have to wait until later */
                fprintf(stderr, "Couldn't close archive file %s: %s\n",
                        priv->mlfi_fname, strerror(errno));
                rstat = SMFIS_TEMPFAIL;
                (void) unlink(priv->mlfi_fname);
        }
        else if (!ok)
        {
                /* message was aborted -- delete the archive file */
                fprintf(stderr, "Message aborted.  Removing %s\n",
                        priv->mlfi_fname);
                rstat = SMFIS_TEMPFAIL;
                (void) unlink(priv->mlfi_fname);
        }
	else if (priv->mlfi_fp != NULL) {
	    char outname[64];
	    char *rslash;

	    rslash = strrchr(priv->mlfi_fname, '/');
	    if (!rslash) {
		rslash = priv->mlfi_fname;
	    } else {
		rslash++;
	    }
	    sprintf(outname, "%s/%s",
		    OUTPUTDIR, rslash);
	    rename(priv->mlfi_fname, outname);
	}

        /* release private memory */
        if (priv->mlfi_fname != NULL)
                free(priv->mlfi_fname);

	charbuf_reset(&priv->databuf);
	
        /* return status */
        return rstat;
}

sfsistat
mlfi_close(ctx)
         SMFICTX *ctx;
{
        struct mlfiPriv *priv = MLFIPRIV;

        if (priv == NULL)
                return SMFIS_CONTINUE;
        if (priv->mlfi_connectfrom != NULL)
                free(priv->mlfi_connectfrom);
        if (priv->mlfi_helofrom != NULL)
                free(priv->mlfi_helofrom);
	charbuf_free(&priv->databuf);

        free(priv);
        smfi_setpriv(ctx, NULL);
        return SMFIS_CONTINUE;
}

struct smfiDesc smfilter =
{
        "StatsFilter", /* filter name */
        SMFI_VERSION,   /* version code -- do not change */
        SMFIF_ADDHDRS|SMFIF_ADDRCPT,
                        /* flags */
        mlfi_connect,   /* connection info filter */
        mlfi_helo,      /* SMTP HELO command filter */
        mlfi_envfrom,   /* envelope sender filter */
        mlfi_envrcpt,   /* envelope recipient filter */
        mlfi_header,    /* header filter */
        mlfi_eoh,       /* end of header */
        mlfi_body,      /* body block filter */
        mlfi_eom,       /* end of message */
        mlfi_abort,     /* message aborted */
        mlfi_close,     /* connection cleanup */
};

static void
usage(prog)
     char *prog;
{
        fprintf(stderr,
                "Usage: %s -p socket-addr [-t timeout]\n"
                "Usage: %s -f file\n",
                prog, prog);
}

int
main(argc, argv)
         int argc;
         char **argv;
{
        bool setconn = FALSE;
        int c;
        const char *args = "p:t:hf:";
        char *msgfile = NULL;
        extern char *optarg;
	int did_chroot = 0;

	if (geteuid() == 0) {
	        struct passwd *userent;
	    
		if ((TARGET_USER != NULL) && ((userent = getpwnam(TARGET_USER)) == 0)) {
		        perror("could not setuid");
			exit(EX_SOFTWARE);
		}
		did_chroot = 1;
		chroot(SPOOLDIR);
		if (userent) {
		        setuid(userent->pw_uid);
			seteuid(userent->pw_uid);
		}
	}

        /* Process command line options */
        while ((c = getopt(argc, argv, args)) != -1)
        {
                switch (c)
                {
                  case 'p':
                        if (optarg == NULL || *optarg == '\0')
                        {
                                (void) fprintf(stderr, "Illegal conn: %s\n",
                                               optarg);
                                exit(EX_USAGE);
                        }
                        if (smfi_setconn(optarg) == MI_FAILURE)
                        {
                                (void) fprintf(stderr,
                                               "smfi_setconn failed\n");
                                exit(EX_SOFTWARE);
                        }

                        /*
                        **  If we're using a local socket, make sure it
                        **  doesn't already exist.  Don't ever run this
                        **  code as root!!
                        */

                        if (strncasecmp(optarg, "unix:", 5) == 0)
                                unlink(optarg + 5);
                        else if (strncasecmp(optarg, "local:", 6) == 0)
                                unlink(optarg + 6);
                        setconn = TRUE;
                        break;

                  case 't':
                        if (optarg == NULL || *optarg == '\0')
                        {
                                (void) fprintf(stderr, "Illegal timeout: %s\n",
                                               optarg);
                                exit(EX_USAGE);
                        }
                        if (smfi_settimeout(atoi(optarg)) == MI_FAILURE)
                        {
                                (void) fprintf(stderr,
                                               "smfi_settimeout failed\n");
                                exit(EX_SOFTWARE);
                        }
                        break;
	          case 'f':
		        msgfile = strdup(optarg);
		        break;
                  case 'h':
                  default:
                        usage(argv[0]);
                        exit(EX_USAGE);
                }
        }

	if (msgfile) {
	    fprintf(stdout, "--\n");
	    printf("Starting %s version %s\n", argv[0], "0.1");
	    smfTestMessage(msgfile);
	    fprintf(stdout, "--\n");
	    return 0;
	}

	if (!did_chroot) {
		chdir(SPOOLDIR);
	}

        if (!setconn)
        {
                fprintf(stderr, "%s: Missing required -p argument\n", argv[0]);
                usage(argv[0]);
                exit(EX_USAGE);
        }
        if (smfi_register(smfilter) == MI_FAILURE)
        {
                fprintf(stderr, "smfi_register failed\n");
                exit(EX_UNAVAILABLE);
        }
        return smfi_main();
}

#include "testMessage.c"
/* eof */
