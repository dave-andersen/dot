bin_PROGRAMS = plcmd plcmd_daemon
noinst_HEADERS = plcmd.h
CFLAGS += -g
AM_LDFLAGS = -g

plcmd_SOURCES = plcmd.cc
plcmd_LDADD = $(LIBGTC) $(LDADD)

plcmd_daemon_SOURCES = plcmd_daemon.cc
plcmd_daemon_LDADD = $(LIBGTC) $(LDADD)

CLEANFILES = core *.core *~ 
