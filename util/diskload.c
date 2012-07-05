#define _LARGEFILE64_SOURCE

#include <stdio.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>

#include <signal.h>

#include <string.h>

#define KILOBYTE 1024

#define LINEARSEEK 0
#define RANDOMSEEK 1

int exit_main_loop = 0;

char *filename = NULL;
int blocksize = 4;
int seektype = LINEARSEEK; 
int sleeptime = 0;
int randomseed = 42;
unsigned long long loops = 0;

void usage(char *progname)
{
  printf("usage: %s <options>\n", progname);
  printf("\twhere options can be:\n");
  printf("\t--file <file>\n");
  printf("\t--sleep <ms>\n");
  printf("\t--bs <kb>\n");
  printf("\t--seed <int>\n");
  printf("\t--seek <kb>\n");
  printf("\t--random\n");
  printf("\t--linear\n");
  printf("\t--writeonly\n");

  /* my understanding
     if the seek type is linear...we seek to a position given by --seek and read 1 --bs blocksize at a time
     --> this is a bulk read type of load
     my $DISK_CMD = "diskload --file /dev/sda4 --sleep 0 --bs 4 --seed 1 --seek 10485760 --linear";
     blocksize shouldn't matter
     
     if the seek type is random, we pick a random offset and read 1 block and then seek again
     --> this is a seek type of workload
     my $DISK_CMD = "diskload --file /dev/sda4 --sleep 0 --bs 4 --seed 1 --random";
     smaller the block size better...u seek more often

     with sleep 0 - seek is less intense because seek does 130
     iterations/second vs linear's 18000 iterations/second (4KB) so
     seek causes less buffer cache contention and hence write is not
     affected that much

     linear - sleep 5 150 its/sec sleep 1 300 its/sec

     write
     ./diskload --writeonly --file /tmp/crap --bs 4 --sleep 10

     write loads are more powerful than read loads since fc4's io
     scheduler schedules all write operations before reads and
     dwindles the read in face of a huge write and hence it is
     difficult to stress write operations with reads. But another
     write operation certainly contends with the ongoing write.

  */
  
  exit(1);
}

// return a new seek position
off64_t get_new_pos(int seektype, off64_t last_pos, off64_t fd_size)
{
  off64_t newpos = -1;

  // some of the math here is a little sloppy.  
  // it's fine as long as fd_size is big

  if(seektype == LINEARSEEK) {
    if(last_pos > (fd_size - 2 * blocksize * KILOBYTE))
      newpos = 0;  // wrap around
    else 
      newpos = last_pos + blocksize * KILOBYTE;
  } else if(seektype == RANDOMSEEK) {
    off64_t blocks;
    off64_t newblock;
    blocks = fd_size / (blocksize * KILOBYTE);
    newblock = (1 + (off64_t) ((double)blocks * (rand() / (RAND_MAX + 1.0))));
    newpos = newblock * blocksize * KILOBYTE;
  } else {
    printf("ERROR: bad seek type\n");
    exit(9);
  }

  return newpos;
}

double
return_time()
{
  struct timeval tv;

  gettimeofday(&tv, 0);
  return (1.0*(tv.tv_sec + tv.tv_usec/1000000.0));
}


void writeonly_mode()
{
    char *wrbuf = NULL;
    int fd;
    double fsize = 0;
    double two_gb = 1*KILOBYTE*KILOBYTE; //KB
    
    wrbuf = malloc(blocksize*KILOBYTE);
    if (wrbuf==NULL) {
	printf("ERROR: unable to allocate %d kb buffer\n", blocksize);
	exit(1);
    }
    memset(wrbuf, 0xa, blocksize*KILOBYTE);
    
    // open the file
    fd = open(filename, O_RDWR | O_TRUNC | O_CREAT, S_IRWXU);
    if (fd < 0) {
        printf("ERROR: unable to open 2 <%s>\n", filename);
	exit(2);
    }
    
    while (!exit_main_loop) {
	ssize_t rresult;

	//write
	double start = return_time();
	rresult = write(fd, wrbuf, blocksize*KILOBYTE);
	if (rresult != blocksize*KILOBYTE) {
	  printf("ERROR: unable to write %d\n", rresult);
	    exit(5);
	}
	double end = return_time() - start;
	
	double xput = (blocksize*KILOBYTE*8)/end;
	printf("Wrote in %f seconds at xput %f\n", end, xput);
	
	fsize += blocksize;
	
	if (fsize > two_gb) {
	    close(fd);
	    fd = open(filename, O_RDWR | O_TRUNC | O_CREAT, S_IRWXU);
	    if (fd < 0) {
	        printf("ERROR: unable to open 1 <%s>\n", filename);
		exit(2);
	    }
	    printf("Opening new file\n");
	    fsize = 0;
	}

	if(sleeptime != 0)
	    usleep(sleeptime * 1000);
	
	++loops;
    }

    close(fd);
}

void my_signal_handler(int sig)
{
  exit_main_loop = 1;

  return;
}

int main(int argc, char *argv[])
{
  int i;
  void *old_sig_handler;
  int fd = 0;
  off64_t fd_size = 0;
  off64_t pos = 0;
  char *rdbuf = NULL;
    
  struct timeval start, end;
  unsigned long long startsec, endsec;
  double elapsedtime;

  int writeonly = 0;

  /* Register our signal handler */
  old_sig_handler = signal(SIGINT, my_signal_handler);
  if (old_sig_handler == SIG_ERR) {
    printf("ERROR: unable to register signal handler\n");
    exit(8);
  }

  // parse command line
  for(i=1; i<argc; i++) {
    if(strcmp("--help", argv[i])==0) {
      usage(argv[0]);
    } else if(strcmp("--file", argv[i])==0) {
      if(i+1<argc) filename=argv[++i]; else usage(argv[0]);
    } else if(strcmp("--sleep", argv[i])==0) {
      if(i+1<argc) sleeptime=atoi(argv[++i]); else usage(argv[0]);
    } else if(strcmp("--random", argv[i])==0) {
      seektype=RANDOMSEEK;
    } else if(strcmp("--linear", argv[i])==0) {
      seektype=LINEARSEEK;
    } else if(strcmp("--writeonly", argv[i])==0) {
      writeonly = 1;
    } else if(strcmp("--bs", argv[i])==0) {
      if(i+1<argc) blocksize=atoi(argv[++i]); else usage(argv[0]);
    } else if(strcmp("--seed", argv[i])==0) {
      if(i+1<argc) randomseed=atoi(argv[++i]); else usage(argv[0]);
    } else if(strcmp("--seek", argv[i])==0) {
      int tmpblocks;
      if(i+1<argc) tmpblocks=atoi(argv[++i]); else usage(argv[0]);
      pos = ((off64_t)tmpblocks) * KILOBYTE;
    } else {
      usage(argv[0]);
    }
  }

  // check for errors
  if(filename == NULL)
    usage(argv[0]);

  // ensure reproducibility
  srand(randomseed);

  gettimeofday(&start, NULL);
  if (writeonly) {
      writeonly_mode();
  }
  else {

      // allocate read buffer
      rdbuf = malloc(blocksize*KILOBYTE);
      if(rdbuf==NULL) {
	  printf("ERROR: unable to allocate %d kb buffer\n", blocksize);
	  exit(1);
      }
      
      // open the file
      fd = open(filename, O_RDONLY | O_LARGEFILE);
      if(fd < 0) {
	  printf("ERROR: unable to open <%s>\n", filename);
	  exit(2);
      }
      
      // get fd_size
      fd_size = lseek64(fd, 0, SEEK_END);
      if(fd_size < 0) {
	  printf("ERROR: unable to determine file size of <%s>\n", filename);
	  exit(3);
      }
      
      // continuously seek
      while(!exit_main_loop) {
	  off64_t sresult;
	  ssize_t rresult;
	  
	  // calcuate pos
	  pos = get_new_pos(seektype, pos, fd_size);
	  
	  // seek
	  sresult = lseek64(fd, pos, SEEK_SET);
	  if(sresult != pos) {
	      printf("ERROR: unable to seek\n");
	      exit(4);
	  }
	  
	  // read
	  rresult = read(fd, rdbuf, blocksize*KILOBYTE);
	  if(rresult != blocksize*KILOBYTE) {
	      printf("ERROR: unable to read\n");
	      exit(5);
	  } 
	  // else printf("r %lld\n", pos);
	  
	  // sleep
	  if(sleeptime != 0)
	      usleep(sleeptime * 1000);
	  
	  ++loops;
      }

      // close the file
      close(fd);
  }
  gettimeofday(&end, NULL);
  
  // print stats
  startsec = start.tv_usec + (unsigned long long)start.tv_sec * 1000000;
  endsec = end.tv_usec + (unsigned long long)end.tv_sec * 1000000;
  elapsedtime = (double)(endsec - startsec)/1000000;
  printf("INFO: %lld iterations with blocksize %d KB in %lf seconds.\n", 
	 loops, blocksize, elapsedtime);
  
  // exit
  exit(0);
  
  return 0;
}
