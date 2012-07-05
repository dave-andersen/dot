/* This function allocates memory that the caller must free.
 * Designed as a C source code interface to the C++/libasync-using
 * rabin polynomial chunker */

#ifdef __cplusplus
extern "C" {
#endif
    
unsigned int *chunk_boundaries(const unsigned char *data, size_t size,
			       unsigned int *nchunks);
#ifdef __cplusplus
}
#endif
