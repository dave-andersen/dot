/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "parseopt.h"
#include "rxx.h"
#include "params.h"

bool
parse_config(str file, vec<str> *sp_list, vec<str> *xp_list,
	     vec<str> *sep_list, vec<str> *cp_list);
bool
parse_paramfile(str file);
   
