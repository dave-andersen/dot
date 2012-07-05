$(PROGRAMS): $(LDEPS) $(LIBGTC)

bin_PROGRAMS = cdht_server
noinst_HEADERS = cdht_server.h

cdht_server_SOURCES = cdht_server.cc
cdht_server_LDADD = $(LIBGTC) $(LDADD)

cdht_server.o: ../gtcd/prot/gtc_prot.h ../gtcd/prot/odht_prot.h
