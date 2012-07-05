/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include <stdlib.h>
#include <sys/types.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

#include "async.h"
#include "rabin_fprint.h"

#define PAGE_SIZE 4096

typedef struct buf_entry
{
  char buffer[PAGE_SIZE];
  struct buf_entry *next;
  unsigned cursor;
  unsigned size;
} buf_entry;

static rabinChunker *myChunker = NULL;

void chunk_file (char *filename, unsigned char* buf)
{  
  int ffd = open (filename, O_RDONLY);

  if (ffd > 0)
  {
    int count;
//      printf ("ffd = %d\n", ffd);
    printf ("*****%s*****\n", filename);
      
    if (myChunker == NULL)
      myChunker = new rabinChunker (New chunkCache("/home/isruser/.dot/dcache"));
    while ((count = read (ffd, buf, PAGE_SIZE)) > 0)
    {
//	printf ("chunking 1024 bytes\n");
      myChunker->chunk_data (buf, count);
//	printf ("chunker returned\n");
    }
//      printf ("stopping chunker\n");
    myChunker->stop ();
    close (ffd);

    ref<vec<dot_descriptor> > chunks = myChunker->get_dv();
      
    for (unsigned i=0; i< chunks->size(); i++) {
      warn << (*chunks)[i].desc << "\t" <<  (*chunks)[i].length << "\n";
    }
    delete myChunker;
    myChunker = NULL;
  }
}

int main(int argc, char *argv[])
{
  if (argc == 1)
  {
    printf ("usage: %s <filename>\n", argv[0]);
    return -1;
  }

  int fd = open (argv[1], O_RDONLY);
  char filename[1024];
  int len = 0;
  unsigned char*buf = new unsigned char[PAGE_SIZE];

  while (read (fd, filename+len, 1) == 1)
  {
    // remove whitespace from the beginning of filenames
    if (!((len == 0) && ((filename[len] == ' ') || 
			 (filename[len] == '\t'))))
    {
      if (filename[len] == '\n') // new line
      {
	filename[len] = '\0';
//      printf ("filename = %s\n", filename);
	chunk_file (filename, buf);
	len = -1; // read in a new filename
      }
      len++;
    }
  }
  filename[len] = '\0';
  chunk_file (filename, buf);
  delete buf;
  close (fd);  
  return 0;
}
