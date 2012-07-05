#                                               -*- Autoconf -*-
# Process this file with autoconf to produce a configure script.

AC_PREREQ(2.59)
AC_INIT([dot],[0.2])
AC_CONFIG_SRCDIR([config.h.in])
AC_CONFIG_HEADER([config.h])
AM_INIT_AUTOMAKE

AC_CANONICAL_HOST

# Checks for programs.
AC_PROG_CC
AC_PROG_CPP
AC_PROG_CXX
SFS_WFLAGS
SFS_PATH_CPP
AC_PROG_INSTALL
AC_PROG_LN_S
AM_PROG_CC_C_O

dnl Checks for typedefs, structures, and compiler characteristics.
SFS_CHECK_TYPE(ssize_t)

# Checks for libraries.
AM_DISABLE_SHARED
AC_PROG_LIBTOOL
AM_CONDITIONAL(STATIC, test "$enable_shared" != yes)

SFS_SFS

SFS_SLEEPYCAT(4.0 4.1 4.2 4.3 4.4 4.5 4.6, yes)
DBCXX_LIB=`echo $DB_LIB | sed 's/libdb/libdb_cxx/'`
LDADD="$LDADD $DB_LIB $DBCXX_LIB"

AC_CHECK_LIB(z, compress, LDADD="$LDADD -lz")

AC_CHECK_LIB(db_cxx, db_create, LDADD="$LDADD")

AC_CHECK_FUNCS(getpeereid)
AC_CHECK_LIB(rpc, xdrmem_create, LDADD="$LDADD -lrpc")

PKG_CHECK_MODULES(OPENSSL, openssl, )
CPPFLAGS="$CPPFLAGS $OPENSSL_CFLAGS"
LDADD="$LDADD $OPENSSL_LIBS"

AX_PATH_MILTER([8.12],[
],[
  AC_MSG_NOTICE([libmilter not found; not building mailfilter dir])
])
AM_CONDITIONAL(USE_MILTER, test x"$MILTER_LIBS" != x)

# Add DOT libraries to LDADD by default.
CPPFLAGS="$CPPFLAGS -I"'$(top_srcdir)'
for lib in util gtcd; do
    CPPFLAGS="$CPPFLAGS -I"'$(top_srcdir)'"/$lib"
done
for lib in gtcd/prot; do
    CPPFLAGS="$CPPFLAGS -I"'$(top_builddir)'"/$lib"
done
AC_SUBST(LIBDOTUTIL)
LIBDOTUTIL='$(top_builddir)/util/libdotutil.la'
AC_SUBST(LIBGTC)
LIBGTC='$(top_builddir)/gtcd/libgtc.la'

CPPFLAGS="$CPPFLAGS -DCONFDIR="'\"$(sysconfdir)\"'  #"

LDADD="$LDADD "'$(LIBDOTUTIL)'
LDEPS="$LDEPS "'$(LIBDOTUTIL)'

new_LDFLAGS=
for flag in $LDFLAGS; do
    if test x"$flag" = x-static; then
        LIBAPM=
        new_LDFLAGS="$new_LDFLAGS -all-static"
    else
        new_LDFLAGS=" $flag"
    fi
done
LDFLAGS="$new_LDFLAGS"

SFS_CFLAGS

AC_CONFIG_FILES([Makefile
                 util/Makefile
		 gtcd/prot/Makefile
		 gtcd/xfer/Makefile
                 gtcd/chunker/Makefile
		 gtcd/storage/Makefile
		 gtcd/serve/Makefile
                 gtcd/Makefile
		 misc/plcmd/Makefile
		 gcp/Makefile
		 cdht/Makefile
		 test/Makefile])
dnl Mailfilter is disabled for dist
dnl		 mailfilter/Makefile])
AC_OUTPUT
