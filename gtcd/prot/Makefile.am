lib_LTLIBRARIES = libgtcprot.la

noinst_HEADERS = gtc_prot.h odht_prot.h bdb_int.h

libgtcprot_la_SOURCES = gtc_prot.C odht_prot.C bdb_int.C

gtc_prot.h: $(srcdir)/gtc_prot.x
	@rm -f $@
	-$(RPCC) -h $(srcdir)/gtc_prot.x || rm -f $@

gtc_prot.C: $(srcdir)/gtc_prot.x
	@rm -f $@
	-$(RPCC) -c $(srcdir)/gtc_prot.x || rm -f $@

odht_prot.h: $(srcdir)/odht_prot.x
	@rm -f $@
	-$(RPCC) -h $(srcdir)/odht_prot.x || rm -f $@

odht_prot.C: $(srcdir)/odht_prot.x
	@rm -f $@
	-$(RPCC) -c $(srcdir)/odht_prot.x || rm -f $@

bdb_int.h: $(srcdir)/bdb_int.x
	@rm -f $@
	-$(RPCC) -h $(srcdir)/bdb_int.x || rm -f $@

bdb_int.C: $(srcdir)/bdb_int.x
	@rm -f $@
	-$(RPCC) -c $(srcdir)/bdb_int.x || rm -f $@

dist-hook:
	cd $(distdir) && rm -f gtc_prot.h gtc_prot.C odht_prot.h odht_prot.C bdb_int.h bdb_int.C

gtc_prot.o: gtc_prot.h ../gtc_prot_strbuf.h
gtc_prot.lo: gtc_prot.h ../gtc_prot_strbuf.h

odht_prot.o: odht_prot.h
odht_prot.lo: odht_prot.h

bdb_int.o: bdb_int.h
bdb_int.lo: bdb_int.h

EXTRA_DIST = gtc_prot.x odht_prot.x bdb_int.x
CLEANFILES = core *.core *~ gtc_prot.h gtc_prot.C odht_prot.h odht_prot.C bdb_int.h bdb_int.C
MAINTAINERCLEANFILES = Makefile.in
