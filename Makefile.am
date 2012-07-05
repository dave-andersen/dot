$(PROGRAMS): $(LDEPS)

if USE_MILTER
FILTER = mailfilter
else
FILTER =
endif

BUILT_SOURCES=gtcd/prot/libgtcprot.la
gtcd/prot/libgtcprot.la:
	cd gtcd/prot && ${MAKE}

DIST_SUBDIRS = util gtcd gcp cdht test misc/plcmd
SUBDIRS = $(DIST_SUBDIRS) # $(FILTER)
# Filter disabled for now

CLEANFILES = core *.core *~
DISTCLEANFILES = autom4te*.cache config.status config.log

MAINTAINERCLEANFILES = aclocal.m4 install-sh mkinstalldirs \
	missing configure config.guess config.sub config.h.in \
	ltconfig ltmain.sh COPYING INSTALL Makefile.in stamp-h.in
