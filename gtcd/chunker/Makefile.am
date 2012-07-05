$(PROGRAMS): $(LDEPS)

#noinst_PROGRAMS = chunk
noinst_LTLIBRARIES = libchunk.la

noinst_HEADERS =  chunkAlg_fixed.h chunkerPlugin_default.h \
		  chunkerPlugin_all.h chunkerPlugin_generate.h

#chunk_SOURCES = chunk.C fingerprint.C plain_chunker.cc
#chunk_LDADD = $(LDADD)

libchunk_la_SOURCES = chunkAlg_fixed.cc chunkerPlugin_default.cc \
		      chunkerPlugin_generate.cc

dist-hook:
	cd $(distdir)

EXTRA_DIST =
CLEANFILES = core *.core *~
MAINTAINERCLEANFILES = Makefile.in
