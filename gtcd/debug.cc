/*
 * Rather boring.  Define the debugging stuff.
 */

#include <stdio.h>
#include <stdlib.h>
#include <ctype.h>
#include <string.h>
#include "debug.h"

unsigned int debug = 0;

struct debug_def {
    int debug_val;
    const char *debug_def;
};

static
struct debug_def debugs[] = {
#include "debug-text.h"
    { 0, NULL } /* End of list marker */
};

int set_debug(char *arg)
{
    int i;
    char *argcopy, *part;
    
    if (!arg || arg[0] == '\0') {
	return -1;
    }

    if (arg[0] == '?' || !strcmp(arg, "list")) {
	fprintf(stderr,
		"Debug values and definitions\n"
		"----------------------------\n");
	for (i = 0;  debugs[i].debug_def != NULL; i++) {
	    fprintf(stderr, "%5d  %s\n", debugs[i].debug_val,
		    debugs[i].debug_def);
	}
	return -1;
    }

    argcopy = strdup(arg);
    
    while ((part = strsep(&argcopy, ",")) != NULL) {
	if (isdigit(part[0])) {
	    debug |= atoi(part);
	}
    }

    free(argcopy);
    return 0;
}

