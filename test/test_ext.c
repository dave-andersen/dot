/*  
 *  To compile, use something like this:
 *
 *  g++ -I./gtcd -I/home/kaminsky/Projects/DOT/dot/src/trunk/gtcd
 *    -o test_ext test_ext.c 
 *    ./gtcd/.libs/libcgtc.a
 *    ./gtcd/prot/.libs/libgtcprot.a
 *    ./util/.libs/libdotutil.a
 *    ../sfslite2/libtame/.libs/libtame.a
 *    ../sfslite2/arpc/.libs/libarpc.a
 *    ../sfslite2/async/.libs/libasync.a
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "gtc_ext_interface.h"

static const char *oid;

void
put()
{
    int dot_fd, ret;
    char buf[] = "My test file.\n";

    dot_fd = dot_put_data();
    //dot_fd = dot_put_data((void (*)(const char *, ...))printf);
    if (dot_fd < 0) {
        perror("dot_put_data");
        exit(1);
    }
    
    ret = dot_write_fn(dot_fd, buf, strlen(buf), 0, NULL);
    if (ret < 0) {
        perror("dot_write_fn");
        exit(1);
    }
   
    oid = dot_put_data_commit();
    printf("GOT OID = %s", oid);
}

void
get()
{
    int dot_fd, ret;
    char buf[1024];

    bzero(buf, sizeof(buf));

    dot_fd = dot_get_data(oid);
    if (dot_fd < 0) {
        perror("dot_get_data");
        exit(1);
    }

    do {
        ret = dot_read_fn(dot_fd, buf, sizeof(buf)-1, 0, NULL);
        if (ret < 0) {
            perror("dot_read_fn");
            exit(1);
        }
    } while (ret > 0);
    
    printf("PUT OID SUCCESSFUL\n");
    printf(buf);
}

int
main (int argc, char **argv)
{
    put();
    get();

    return 0;
}
