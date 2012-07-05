lib_LTLIBRARIES = libxferPlugin.la

INCLUDES = -I$(srcdir)/../storage -I$(srcdir)/../chunker \
           -I../storage -I../chunker

noinst_HEADERS = xferPlugin_all.h xferPlugin_xgtc.h xferPlugin_mpath.h \
		 xferPlugin_portable.h xferPlugin_xset.h xferPlugin_msrc.h \
		 xferPlugin_xnoop.h xferPlugin_opt.h xferPlugin_xdisk.h \
		 xferPlugin_decompress.h 

libxferPlugin_la_SOURCES = xferPlugin_xgtc.cc xferPlugin_mpath.cc \
                           xferPlugin_gtc_prot.C xferPlugin_portable.cc \
			   xferPlugin_xset.cc xferPlugin_msrc.cc xferPlugin_xnoop.cc\
			   xferPlugin_decompress.cc \
			   xferPlugin_opt.cc xferPlugin_aux.cc xferPlugin_xdisk.cc

libxferPlugin_la_LIBADD =  ../prot/libgtcprot.la

#noinst_PROGRAMS = match_test
#match_test_SOURCES = match_test.cc
#match_test_LDADD = $(LDADD) /usr/local/lib/libitimer.so

SUFFIXES = .T .C .cc .x .h

.x.h:
	-$(RPCC) -h $< || rm -f $@
.x.C:
	-$(RPCC) -c $< || rm -f $@

.T.cc:
	-$(TAME) -o $@ $< || rm -f $@

xferPlugin_gtc_prot.C: $(srcdir)/xferPlugin_gtc_prot.x
xferPlugin_gtc_prot.h: $(srcdir)/xferPlugin_gtc_prot.x
xferPlugin_gtc_prot.o: xferPlugin_gtc_prot.h
xferPlugin_gtc_prot.lo: xferPlugin_gtc_prot.h

xferPlugin_xgtc.o: xferPlugin_gtc_prot.h
xferPlugin_xgtc.lo: xferPlugin_gtc_prot.h
xferPlugin_mpath.o: xferPlugin_gtc_prot.h
xferPlugin_mpath.lo: xferPlugin_gtc_prot.h

dist-hook:
	cd $(distdir) && rm -f xferPlugin_gtc_prot.C xferPugin_gtc_prot.h

EXTRA_DIST = xferPlugin_gtc_prot.x
CLEANFILES = core *.core *~ xferPlugin_gtc_prot.h xferPlugin_gtc_prot.C \
	xferPlugin_msrc.cc xferPlugin_xnoop.cc xferPlugin_xdisk.cc \
	xferPlugin_decompress.cc \
	xferPlugin_xset.cc xferPlugin_opt.cc xferPlugin_aux.cc xferPlugin_xgtc.cc
MAINTAINERCLEANFILES = Makefile.in
