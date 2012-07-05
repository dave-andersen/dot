/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#ifndef _GTC_EXT_INTERFACE_H_
#define _GTC_EXT_INTERFACE_H_

#ifdef __cplusplus
extern "C" {
#endif

extern int dot_read_fn(int fd, void *buf, unsigned int len, int timeout,
		       void *unused_context);
extern int dot_write_fn(int fd, void *buf, unsigned int len, int timeout,
			void *unused_context);

extern int dot_get_data(const char *armored_oid_hints);
extern int dot_put_data();
extern const char *dot_put_data_commit();

#ifdef __cplusplus
}
#endif

#endif /* _GTC_EXT_INTERFACE_H_ */
