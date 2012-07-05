/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include <openssl/evp.h>
#include "chunkAlg_fixed.h"

chunkAlg_fixed::chunkAlg_fixed()
    : _bytes_left(0)
{
}

chunkAlg_fixed::~chunkAlg_fixed()
{
}

void
chunkAlg_fixed::stop()
{
    _bytes_left = 0;
}

ptr<vec<unsigned int> >
chunkAlg_fixed::chunk_data (const unsigned char *in_data, size_t size)
{
    ptr<vec<unsigned int> > iv = NULL;

    _bytes_left += size;
    if (_bytes_left >= CHUNK_SIZE) {
        iv = new refcounted<vec<unsigned int> >;
    }

    while (_bytes_left >= CHUNK_SIZE) {
        iv->push_back(CHUNK_SIZE);
        _bytes_left -= CHUNK_SIZE;
    }
    return iv;
}

ptr<vec<unsigned int> >
chunkAlg_fixed::chunk_data (suio *in_data)
{
    // We don't do anything with the data
    return chunk_data(NULL, in_data->resid());
}
