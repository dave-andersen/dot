$(PROGRAMS): $(LDEPS) $(LIBGTC)

bin_PROGRAMS = gcp
noinst_HEADERS = gcp.h gcp_prot.h debug.h

gcp_SOURCES = gcp.cc gcp_prot.C gcp_put.cc gcp_get.cc debug.cc
gcp_LDADD = $(LIBGTC) $(LDADD)

noinst_PROGRAMS = ftw_test
ftw_test_SOURCES = ftw_test.cc

SUFFIXES = .T .C .cc .x .h

.x.h:
	-$(RPCC) -h $< || rm -f $@
.x.C:
	-$(RPCC) -c $< || rm -f $@
.T.cc:
	-$(TAME) -o $@ $< || rm -f $@

gcp_prot.C: $(srcdir)/gcp_prot.x
gcp_prot.h: $(srcdir)/gcp_prot.x
gcp_prot.o: gcp_prot.h
gcp_prot.lo: gcp_prot.h

gcp.o: ../gtcd/prot/gtc_prot.h gcp_prot.h

dist-hook:
	cd $(distdir) && rm -f gcp_prot.C gcp_prot.h

debug-text.h: debug.h
	perl @top_srcdir@/util/dbparse.pl < @srcdir@/debug.h > debug-text.h
debug.o: debug-text.h debug.cc


EXTRA_DIST = gcp_prot.x
CLEANFILES = core *.core *~ gcp_prot.C gcp_prot.h gcp_put.cc debug-text.h
