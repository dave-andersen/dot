$(PROGRAMS): $(LDEPS)

noinst_PROGRAMS = mfmilter

noinst_HEADERS = fingerprint_c.h testMessage.c

mfmilter_SOURCES = mfmilter.c fingerprint_c.C
mfmilter_LDADD = $(LDADD) $(MILTER_LIBS) $(MILTER_LDFLAGS) $(top_builddir)/gtcd/chunker/libchunk.la
mfmilter_CPPFLAGS = $(MILTER_CPPFLAGS)

CLEANFILES = core *.core *~
