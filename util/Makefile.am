noinst_LTLIBRARIES = libdotutil.la

noinst_HEADERS = util.h connection_cache.h

libdotutil_la_SOURCES = util.cc connection_cache.cc const.cc hints.cc

SUFFIXES = .T .C .cc .x .h

.x.h:
	-$(RPCC) -h $< || rm -f $@
.x.C:
	-$(RPCC) -c $< || rm -f $@

.T.cc:
	-$(TAME) -o $@ $< || rm -f $@


CLEANFILES = core *.core *~ connection_cache.cc

EXTRA_DIST = dbparse.pl
