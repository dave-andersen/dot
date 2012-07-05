#define MAX_STRING_SIZE	4096
#define MAX_BUFFER_SIZE	32768

#define MAX_PARSE_TXT_DEFAULT	1048576

#include <stdarg.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>

char ErrBuf[MAX_STRING_SIZE + 1];

static char *EnvelopeFrom = "EnvelopeFrom";
static char *EnvelopeRcpt = "EnvelopeRcpt";

void smfError(int code, const char *fmt, ...) {
    va_list ap;

    va_start(ap, fmt);
    vsnprintf(ErrBuf, sizeof(ErrBuf), fmt, ap);
    va_end(ap);
    fprintf(stderr, "%s\n", ErrBuf);
    if (code > 0)
	exit(code);
}

void smfTestMessage(char* mfile) {
    char *p, *p2, *buf, *headerf = NULL, *headerv = NULL, *hdrs[2], *lasts;
    char *conn = "127.0.0.1"; /* by default, if "Connection" header was not specified */
    FILE *fp = NULL;
    SMFICTX *ctx = NULL;
    int fd, i, len;

    if (!(buf = (char*) malloc(MAX_BUFFER_SIZE)) || !(ctx = (SMFICTX*) malloc(MAX_BUFFER_SIZE)))
	smfError(1, "smfTestMessage: memory exhausted");
    if ((fd = open(mfile, O_RDONLY)) == -1 || !(fp = fdopen(fd, "r")))
	smfError(1, "smfTestMessage: message file %s is inaccessible.", mfile);
    while (fgets(buf, MAX_STRING_SIZE, fp)) {
	for (i = 0; *(buf + i); i++) {
	    if (*(buf + i) == '\n' || (*(buf + i) == '\r' && *(buf + i + 1) == '\n')) {
		*(buf + i) = 0;
		break;
	    }
	}
	if (!strncasecmp(buf, "Connection:", 11)) {
	    if (strtok_r(buf, ": \t", &lasts) && (p = strtok_r(NULL, "", &lasts))) {
		while (*p && (*p == ' ' || *p == '\t'))
		    p++;
		conn = strdup(p);
	    }
	    else
		smfError(1, "smfTestMessage: malformed message string \"%s\"", buf);
	    continue;
	}
	else
	if (!strncasecmp(buf, EnvelopeFrom, strlen(EnvelopeFrom)) &&
	    *(buf + strlen(EnvelopeFrom)) == ':') {
	    if ((p = strtok_r(buf, ": \t", &lasts)) && (p2 = strtok_r(NULL, "", &lasts))) {
		while (*p2 && (*p2 == ' ' || *p2 == '\t'))
		    p2++;
		hdrs[0] = p2;
	    }
	    else
		smfError(1, "smfTestMessage: malformed message string \"%s\"", buf);
	    break;
	}
	else
	if (!strncmp(buf, "From ", 5)) {
	    hdrs[0] = strdup(buf + 5);
	    break;
	}
	else {
	    hdrs[0]  = "<nobody@localhost>";
	    fseek(fp, 0, SEEK_SET);
	    break;
	}
    }
    hdrs[1] = NULL;
    if (mlfi_connect(ctx, conn, NULL) != SMFIS_CONTINUE ||
	mlfi_envfrom(ctx, hdrs) != SMFIS_CONTINUE) {
	mlfi_close(ctx);
	return;
    }
    while (fgets(buf, MAX_STRING_SIZE, fp)) {
	for (i = 0; *(buf + i); i++)
	    if (*(buf + i) == '\n' || *(buf + i) == '\r') {
		*(buf + i) = 0;
		break;
	    }
	if (*buf == '\0') { /* end of headers */
	    if (headerf && headerv) {
		if (mlfi_header(ctx, headerf, headerv) != SMFIS_CONTINUE) {
		    mlfi_close(ctx);
		    return;
		}
		free(headerf);
		free(headerv);
		headerf = NULL;
		headerv = NULL;
	    }
	    if (mlfi_eoh(ctx) != SMFIS_CONTINUE) {
		mlfi_close(ctx);
		return;
	    }
	    break;
	}
	else {
	    if (*buf == ' ' || *buf == '\t') {
		if (headerf && headerv) {
		    len = strlen(headerv);
		    headerv = realloc(headerv, len + strlen(buf) + 2);
		    *(headerv + len) = '\n';
		    strcpy(headerv + len + 1, buf);
		}
		else
		    smfError(1, "smfTestMessage: malformed message header \"%s\"", buf);
	    }
	    else {
		if ((p = strtok_r(buf, ": \t", &lasts))) {
		    if (headerf && headerv) {
			if (!strncmp(headerf, EnvelopeRcpt, strlen(EnvelopeRcpt))) {
			    hdrs[0] = headerv;
			    if (mlfi_envrcpt(ctx, hdrs) != SMFIS_CONTINUE) {
				mlfi_close(ctx);
				return;
			    }
			}
			else {
			    if (mlfi_header(ctx, headerf, headerv) != SMFIS_CONTINUE) {
				mlfi_close(ctx);
				return;
			    }
			}
			free(headerf);
			free(headerv);
			headerf = NULL;
			headerv = NULL;
		    }
		    headerf = strdup(p);
		    if ((p2 = strtok_r(NULL, "", &lasts))) {
			while (*p2 && (*p2 == ' ' || *p2 == '\t'))
			    p2++;
		    }
		    else
			p2 = p + strlen(p);
		    headerv = strdup(p2);
		}
		else
		    smfError(1, "smfTestMessage: malformed message header \"%s\"", buf);
	    }
	}
    }
    fflush(fp);
    while ((len = read(fd, buf, MAX_BUFFER_SIZE)) > 0) {
	if (mlfi_body(ctx, (unsigned char *) buf, len) != SMFIS_CONTINUE) {
	    mlfi_close(ctx);
	    return;
	}
    }
    mlfi_eom(ctx);
    mlfi_close(ctx);
    close(fd);
}


