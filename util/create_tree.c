#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <limits.h>

#define KILOBYTE 1024

unsigned maxdepth=4;

unsigned subdirs_max=10;
unsigned subdirs_min=0;

unsigned files_max=10;
unsigned files_min=1;

unsigned filesize_max=1*1024; // in KB
unsigned filesize_min=1; // in KB

int randomseed = 424242;
int urandom_fd = -1;

int fillbuf_rand(unsigned buf[], unsigned num)
{
  unsigned u;

  for(u=0; u<num; u++)
    buf[u] = rand();

  return 0;
}

unsigned uniform_rand(unsigned min, unsigned max)
{
  if (min == max)
      return min;
  return (min + (unsigned) (max * (rand() / (RAND_MAX + 1.0))));
}

void generate_file(char *name, unsigned filesize)
{
    char buf[KILOBYTE];
    unsigned b;
    int fd;

    //open
    fd = open(name, O_WRONLY | O_CREAT | O_EXCL, 0644);
    if(fd < 0) {
      printf("ERROR: unable to open file <%s>\n", name);
      exit(1);
    }

    // write
    for(b=0; b<filesize; b++) {
      // get random block
#if 0
      if(read(urandom_fd, buf, KILOBYTE) != KILOBYTE) {
	printf("ERROR: unable to read random file\n");
	exit(1);
      }
#else
      fillbuf_rand((unsigned*)buf, KILOBYTE/sizeof(unsigned));
#endif

      // write it
      if(write(fd, buf, KILOBYTE) != KILOBYTE) {
	printf("ERROR: unable to write file <%s>\n", name);
	exit(1);
      }
    }

    //close
    close(fd);
}

int populatedir(int depth)
{
  unsigned u;

  unsigned num_subdirs;
  unsigned num_files;

  char name[128];

  // check for recursion end
  if(depth < maxdepth) {
    char wd_name[PATH_MAX];

    // get the cmd
    if(getcwd(wd_name, PATH_MAX) == NULL) {
      printf("ERROR: unable to getcwd()\n");
      exit(1);
    }

    // populate subdirs
    num_subdirs = uniform_rand(subdirs_min, subdirs_max);
    for(u=0; u<num_subdirs; u++) {
      // form directory name
      sprintf(name, "dir%u_%u", depth, u);
      printf("INFO: creating directory <%s>\n", name);

      // create directory
      if(mkdir(name, 0775) != 0) {
	printf("ERROR: unable to mkdir <%s>\n", name);
	exit(1);
      }

      // descend
      if(chdir(name) != 0) {
	printf("ERROR: unable to chdir <%s>\n", name);
	exit(1);
      }
      
      // call recursive
      populatedir(depth+1);

      // pop
      if(chdir(wd_name) != 0) {
	printf("ERROR: unable to chdir <%s>\n", wd_name);
	exit(1);
      }
    }
  }

  // populate files
  num_files = uniform_rand(files_min, files_max);
  for(u=0; u<num_files; u++) {
    unsigned filesize;
 
    // determine file size
    filesize = uniform_rand(filesize_min, filesize_max); // in KB

    // form file name
    sprintf(name, "file%u_%u", depth, u);
    printf("INFO: creating file <%s> of %u KB\n", name, filesize);

    generate_file(name, filesize);
  }

  return 0;
}

void usage(const char *progname)
{
  printf("usage: %s [options]\n", progname);
  printf("\t--maxdepth <num>\n");
  printf("\t--subdirs_max <num>\n");
  printf("\t--subdirs_min <num>\n");
  printf("\t--files_max <num>\n");
  printf("\t--files_min <num>\n");
  printf("\t--filesize_max <kb>\n");
  printf("\t--filesize_min <kb>\n");
  printf("\t--seed <int>\n");
  exit(0);
}

int main(int argc, char *argv[])
{
  int i;

  // parse command line
  for(i=1; i<argc; i++) {
    if((strcmp(argv[i], "--maxdepth")==0) && (i+1<argc)) {
      maxdepth = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--subdirs_max")==0) && (i+1<argc)) {
      subdirs_max = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--subdirs_min")==0) && (i+1<argc)) {
      subdirs_min = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--files_max")==0) && (i+1<argc)) {
      files_max = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--files_min")==0) && (i+1<argc)) {
      files_min = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--filesize_max")==0) && (i+1<argc)) {
      filesize_max = strtoul(argv[++i], NULL, 0);
    } else if((strcmp(argv[i], "--filesize_min")==0) && (i+1<argc)) {
      filesize_min = strtoul(argv[++i], NULL, 0);
    } else if((strcmp("--seed", argv[i])==0) && (i+1<argc)) {
      randomseed=atoi(argv[++i]);
    } else {
      usage(argv[0]);
    }
  }

  // ensure reproducibility
  srand(randomseed);

  // open dev urandom
  urandom_fd = open("/dev/urandom", O_RDONLY);
  if(urandom_fd < 0) {
    printf("ERROR: unable to open file </dev/urandom>\n");
    exit(1);
  }

  // call populate
  populatedir(0);

  // close dev urandom
  close(urandom_fd);

  return 0;
}
