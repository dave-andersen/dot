#include "async.h"

str
myusername()
{
    str u = getenv("USER");
    if (!u)
        u = getlogin();
    return u;
}

str
get_dottmpdir()
{
    str dir = getenv("DOT_TMP_DIR");
    if (!dir) {
        str u = myusername();
        if (!u)
            fatal("Could not determine username\n");

        dir = strbuf() << "/tmp/dot-" << u;
    }

    if ((mkdir(dir.cstr(), 0700)) < 0 && errno != EEXIST)
        fatal("Could not create directory: %s: %m\n", dir.cstr());
    return dir;
}

str
get_gtcd_socket()
{
    str dir = get_dottmpdir();
    return strbuf() << dir << "/gtcd.sock";
}

str
get_odht_ip()
{
    str ip = NULL;
    struct in_addr addr;
    
    if (hostent *hp = gethostbyname("opendht.nyuld.net")) {
	addr = *((struct in_addr *)hp->h_addr);
	ip = strbuf() << inet_ntoa(addr);
	warn << "Opendht has ip " << ip << "\n";
    }
    
    return(ip);
}
