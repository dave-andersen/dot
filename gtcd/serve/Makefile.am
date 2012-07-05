lib_LTLIBRARIES = libservePlugin.la

INCLUDES = -I$(srcdir)/../storage -I$(srcdir)/../chunker -I$(srcdir)/../xfer \
           -I../storage -I../chunker -I../xfer

noinst_HEADERS = servePlugin_all.h servePlugin_segtc.h servePlugin_senoop.h servePlugin_compress.h

libservePlugin_la_SOURCES = servePlugin_segtc.cc servePlugin_senoop.cc servePlugin_compress.cc

libservePlugin_la_LIBADD =  ../prot/libgtcprot.la

SUFFIXES = .T .C .cc .x .h

.x.h:
	-$(RPCC) -h $< || rm -f $@
.x.C:
	-$(RPCC) -c $< || rm -f $@

.T.cc:
	-$(TAME) -o $@ $< || rm -f $@

CLEANFILES = core *.core *~ servePlugin_senoop.cc servePlugin_segtc.cc servePlugin_compress.cc
MAINTAINERCLEANFILES = Makefile.in
