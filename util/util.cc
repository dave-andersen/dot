#include "util.h"

float
timeval_diff(const struct timeval *start, const struct timeval *end)
{
    float r;

    /* Calculate the second difference*/
    r = (end->tv_sec - start->tv_sec)* 1000000;

    /* Calculate the microsecond difference */
    if (end->tv_usec > start->tv_usec)
        r += (end->tv_usec - start->tv_usec);
    else if (end->tv_usec < start->tv_usec)
        r -= (start->tv_usec - end->tv_usec);

    return (float)r/1000000;
}

double
return_time(time_label label)
{
    double MHZ = 2992.745 ;
    
    switch (label) {
    case CYCLES:
	return((double)rdtsc());
	break;

    case SECONDS:
	return(get_cur_time());
	break;

    case CYC_SEC:
	return(rdtsc()/(MHZ*1000000));
	break;
	
    default:
	return(-1);
	break;
    }
}

double 
get_cur_time()
{
  struct timeval tv;

  gettimeofday(&tv, 0);
  return ((double)tv.tv_sec + (double)tv.tv_usec/1000000.0);
}

void
dump_rusage(struct rusage *rs1, struct rusage *rs2)
{
    double u1 = (1.0*(rs1->ru_utime.tv_sec + rs1->ru_utime.tv_usec/1000000.0));
    double u2 = (1.0*(rs2->ru_utime.tv_sec + rs2->ru_utime.tv_usec/1000000.0));
    fprintf(stderr, "User time used %f %f %f\n", u1, u2, (u2-u1));
    
    double s1 = (1.0*(rs1->ru_stime.tv_sec + rs1->ru_stime.tv_usec/1000000.0));
    double s2 = (1.0*(rs2->ru_stime.tv_sec + rs2->ru_stime.tv_usec/1000000.0));
    fprintf(stderr, "System time used %f %f %f\n", s1, s2, (s2-s1));

    fprintf(stderr, "Maximum resident set size %ld %ld %ld\n", rs1->ru_maxrss,
	    rs2->ru_maxrss, (rs2->ru_maxrss - rs1->ru_maxrss));

    fprintf(stderr, "Integral shared memory size %ld %ld %ld\n", rs1->ru_ixrss,
	    rs2->ru_ixrss, (rs2->ru_ixrss - rs1->ru_ixrss));

    fprintf(stderr, "Integral unshared data size %ld %ld %ld\n", rs1->ru_idrss,
	    rs2->ru_idrss, (rs2->ru_idrss - rs1->ru_idrss));

     fprintf(stderr, "Integral unshared stack size %ld %ld %ld\n", rs1->ru_isrss,
	     rs2->ru_isrss, (rs2->ru_isrss - rs1->ru_isrss));

     fprintf(stderr, "Page reclaims %ld %ld %ld\n", rs1->ru_minflt,
	     rs2->ru_minflt, (rs2->ru_minflt - rs1->ru_minflt));

     fprintf(stderr, "Page faults %ld %ld %ld\n", rs1->ru_majflt,
	     rs2->ru_majflt, (rs2->ru_majflt - rs1->ru_majflt));

     fprintf(stderr, "Swaps %ld %ld %ld\n", rs1->ru_nswap,
	     rs2->ru_nswap, (rs2->ru_nswap - rs1->ru_nswap));

     fprintf(stderr, "Block input operations %ld %ld %ld\n", rs1->ru_inblock,
	     rs2->ru_inblock, (rs2->ru_inblock - rs1->ru_inblock));

     fprintf(stderr, "Block output operations %ld %ld %ld\n", rs1->ru_oublock,
	     rs2->ru_oublock, (rs2->ru_oublock - rs1->ru_oublock));

     fprintf(stderr, "Messages sent %ld %ld %ld\n", rs1->ru_msgsnd,
	     rs2->ru_msgsnd, (rs2->ru_msgsnd - rs1->ru_msgsnd));

     fprintf(stderr, "Messages received %ld %ld %ld\n", rs1->ru_msgrcv,
	     rs2->ru_msgrcv, (rs2->ru_msgrcv - rs1->ru_msgrcv));

     fprintf(stderr, "Signals received %ld %ld %ld\n", rs1->ru_nsignals,
	     rs2->ru_nsignals, (rs2->ru_nsignals - rs1->ru_nsignals));

     fprintf(stderr, "Voluntary context switches %ld %ld %ld\n", rs1->ru_nvcsw,
	     rs2->ru_nvcsw, (rs2->ru_nvcsw - rs1->ru_nvcsw));

     fprintf(stderr, "Involuntary context switches %ld %ld %ld\n", rs1->ru_nivcsw,
	     rs2->ru_nivcsw, (rs2->ru_nivcsw - rs1->ru_nivcsw));

}

