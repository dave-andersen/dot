/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _GTC_PROT_STRBUF_H_
#define _GTC_PROT_STRBUF_H_

inline const strbuf &
strbuf_cat (const strbuf &sb, dot_oid oid)
{
  strbuf s;
  s << hexdump(oid.base(), oid.size());
  return strbuf_cat (sb, s);
}

#endif /* _GTC_PROT_STRBUF_H_ */
