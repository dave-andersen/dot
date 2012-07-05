#include "async.h"
#include "rabin_fprint.h"

/* This function allocates memory that the caller must free */
extern "C" unsigned int *
chunk_boundaries(const unsigned char *data, size_t size,
		 unsigned int *nchunks)
{
    rabin_fprint c;
    ptr<vec<unsigned int> > b;
    unsigned int *bret;
    
    b = c.chunk_data(data, size);
    
    if (!b) {
	return NULL;
    }
    bret = (unsigned int *)malloc(sizeof(unsigned int) * b->size());
    for (unsigned int i = 0; i < b->size(); i++) {
	bret[i] = (*b)[i];
    }
    *nchunks = b->size();
    return bret;
}
