#include "async.h"
#include <sys/time.h>

enum time_label { CYCLES, SECONDS, CYC_SEC };

/*
from http://www-unix.mcs.anl.gov/~kazutomo/rdtsc.html
check the #if defined parts
*/

#if defined(__i386__)

static __inline__ unsigned long long rdtsc(void)
{
  unsigned long long int x;
     __asm__ volatile (".byte 0x0f, 0x31" : "=A" (x));
     return x;
}
#elif defined(__x86_64__)

//typedef unsigned long long int unsigned long long;

static __inline__ unsigned long long rdtsc(void)
{
  unsigned hi, lo;
  __asm__ __volatile__ ("rdtsc" : "=a"(lo), "=d"(hi));
  return ( (unsigned long long)lo)|( ((unsigned long long)hi)<<32 );
}

#elif defined(__powerpc__)

typedef unsigned long long int unsigned long long;

static __inline__ unsigned long long rdtsc(void)
{
  unsigned long long int result=0;
  unsigned long int upper, lower,tmp;
  __asm__ volatile(
                "0:                  \n"
                "\tmftbu   %0           \n"
                "\tmftb    %1           \n"
                "\tmftbu   %2           \n"
                "\tcmpw    %2,%0        \n"
                "\tbne     0b         \n"
                : "=r"(upper),"=r"(lower),"=r"(tmp)
                );
  result = upper;
  result = result<<32;
  result = result|lower;

  return(result);
}

#else

#error "No tick counter is available!"

#endif

float timeval_diff(const struct timeval *start, const struct timeval *end);
double get_cur_time();
double return_time(time_label);
void dump_rusage(struct rusage *rs1, struct rusage *rs2);

/* const.cc */
str myusername();
str get_dottmpdir();
str get_gtcd_socket();
str get_odht_ip();

/* hints.cc */
#include "gtc_prot.h"
#include "ihash.h"
#include "rxx.h"

struct hint_res {
    struct xfer_hint hint;         //for protocol gtc
    struct xdisk_hint hint1;       //for protocol disk
    str hint2;                     //for protocol intern
} ;
