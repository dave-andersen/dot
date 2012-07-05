#ifndef _DEBUG_H_
#define _DEBUG_H_

#include "err.h"

#include <stdio.h>  /* for perror */
#define DEBUG 1 /* XXX - should set in Makefile */
#ifdef DEBUG
extern unsigned int debug;
#define DPRINTF(level, fmt, args...) \
        do { if (debug & (level)) fprintf(stderr, fmt , ##args ); } while(0)
#define DEBUG_PERROR(errmsg) \
        do { if (debug & DEBUG_ERRS) perror(errmsg); } while(0)
#define DEBUGDO(level, args) do { if (debug & (level)) { args } } while(0)
#else
#define DPRINTF(args...)
#define DEBUG_PERROR(args...)
#define DEBUGDO(args...)
#endif

/*
 * The format of this should be obvious.  Please add some explanatory
 * text if you add a debugging value.  This text will show up in
 * -d list
 *
 * XXX - DEBUG_CLIENT is weird.  The define must be shared between
 * the client libraries and the client app...
 */
#define DEBUG_NONE      0x00	// DBTEXT:  No debugging
#define DEBUG_ERRS      0x01	// DBTEXT:  Verbose error reporting
#define DEBUG_INIT      0x02	// DBTEXT:  Debug initialization
#define DEBUG_SOCKETS   0x04    // DBTEXT:  Debug socket operations
#define DEBUG_PROCESSES 0x08	// DBTEXT:  Debug processes (fork/reap/etc)
#define DEBUG_SET       0x10    // DBTEXT:  Debug SET operation
#define DEBUG_XDISK     0x40    // DBTEXT:  Debug Xdisk operation
#define DEBUG_OPT       0x80    // DBTEXT:  Debug optimization ops
#define DEBUG_XFER_GTC  0x100   // DBTEXT:  Debug default xfer plugin
#define DEBUG_STORAGE   0x200   // DBTEXT:  Debug storage plugin
#define DEBUG_CLIENT    0x400   // DBTEXT:  Debug the client interface

#define DEBUG_ALL  0xffffffff

int set_debug(char *arg);  /* Returns 0 on success, -1 on failure */

class debugobj : public warnobj {
public:
    int dlevel;
    const char *prefix;
    bool dotime;
    debugobj(int dlevel = DEBUG_ERRS) : warnobj(debug & dlevel ? 0 : 1),
	dlevel(dlevel) {}
    
};

template<class T> inline const debugobj &
operator<< (const debugobj &sb, const T &a)
{
    if (debug & sb.dlevel)
	strbuf_cat (sb, a);
    return sb;
}

inline const debugobj &
operator<< (const debugobj &sb, const str &s)
{
    if (debug & sb.dlevel) {
	suio_print(sb.tosuio(), s);
    }

    return sb;
}


#define dwarn(lvl) debugobj(lvl)
const str debug_sep = "--------------------------------\n";

#endif /* _DEBUG_H_ */
