/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _CHUNKALG_FIXED_H_
#define _CHUNKALG_FIXED_H_

#include "fprint.h"
#include "params.h"

class chunkAlg_fixed : public fprint {
private:
    unsigned int _bytes_left;

public:
    chunkAlg_fixed();
    ~chunkAlg_fixed();

    void stop();
    ptr<vec<unsigned int> > chunk_data (const unsigned char *data, 
                                        size_t size);
    ptr<vec<unsigned int> > chunk_data (suio *in_data);
    void set_chunk_size (unsigned) { }
};

#endif /* _CHUNKALG_FIXED_H_ */
