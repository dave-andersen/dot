lib_LTLIBRARIES = libstoragePlugin.la libse_transfer.la

noinst_PROGRAMS = dht_test
dht_test_SOURCES = dht_test.cc
dht_test_LDADD = libse_transfer.la ../prot/libgtcprot.la $(LDADD)

noinst_HEADERS = dht.h storagePlugin_all.h storagePlugin_disk.h \
		 chunk_cache.h \
		 storagePlugin_snoop.h storagePlugin_sset.h \
		 storagePlugin_ce.h storagePlugin_cefdisk.h

libse_transfer_la_SOURCES = se_transfer.cc dht.cc
libse_transfer_la_LIBADD = ../prot/libgtcprot.la ../../util/libdotutil.la

libstoragePlugin_la_SOURCES = storagePlugin_disk.cc \
			      chunk_cache.cc storagePlugin_snoop.cc\
			      storagePlugin_sset.cc storagePlugin_ce.cc storagePlugin_cefdisk.cc

libstoragePlugin_la_LIBADD =  ../prot/libgtcprot.la libse_transfer.la

SUFFIXES = .T .C .cc .x .h

.x.h:
	-$(RPCC) -h $< || rm -f $@

.x.C:
	-$(RPCC) -c $< || rm -f $@

.T.cc:
	-$(TAME) -o $@ $< || rm -f $@

CLEANFILES = core *.core *~ \
	storagePlugin_snoop.cc storagePlugin_sset.cc storagePlugin_ce.cc storagePlugin_cefdisk.cc\
	se_transfer.cc dht.cc dht_test.cc
MAINTAINERCLEANFILES = Makefile.in
