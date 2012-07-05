#include <sys/types.h>

#define PLCMD_DEFAULT_PORT 8932

#define PLCMD_MAGIC 785461736
#define PLCMD_SIG_SIZE 128

#define PLCMD_PASS_XXX 5923523

#define PLCMD_TYPE_CMD 0
#define PLCMD_TYPE_ACK 1

#define PLCMD_MAJOR_VERS 1
#define PLCMD_MINOR_VERS 1

#define PLCMD_MAX_CMD_LEN 511

struct plcmd_wire {
    u_int32_t magic; /* Must be PLCMD_MAGIC */
    u_int16_t vers_major;
    u_int16_t vers_minor;
    u_int32_t type;
    u_int32_t pass;  /* Quick filtering of bogus stuff without crypto cost */
    u_int32_t id;    /* make idempotent */
    u_int32_t siglen;
    u_int32_t cmdlen;
    u_char sig[PLCMD_SIG_SIZE];
    /* rest is cmd */
};

