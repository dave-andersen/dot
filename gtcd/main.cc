/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtcd.h"
#include "chunker/chunkerPlugin_all.h"
#include "xfer/xferPlugin_all.h"
#include "storage/storagePlugin_all.h"
#include "serve/servePlugin_all.h"
#include "configfile.h"

static str gtcd_listen_sock;
gtcd *gtcdp;
qhash<str, sPluginNew_cb> sPluginTab;
qhash<str, xPluginNew_cb> xPluginTab;
qhash<str, sePluginNew_cb> sePluginTab;
qhash<str, cPluginNew_cb> cPluginTab;

qhash<str, Plugin*> Plugin_instantiated;
extern connectionCache *connCache_ptr;

str 
parse_plgname(str plugin_instance)
{
    const char *c;
    if ((c = strchr(plugin_instance, ':')) != NULL) {
	return str(plugin_instance, c - plugin_instance);
    }
    return plugin_instance; 
}

template<class T>
T *
get_plugin(str plg, T *next_plg)
{
    T *p = NULL;
    if (Plugin_instantiated[plg]) {
        p = dynamic_cast<T *>(*(Plugin_instantiated[plg]));
        if (!p) {
            fatal << "Plugin " << plg << " already instantiated but can't be used as this plugin-type\n";
        }
        else {
            p->set_next_plugin(next_plg);
            return p;
        }
    }

    /* Else - parse plg and check if it appears in any of the tables
     * If so, call the corresponding cb with gtcdp and next_plg, 
     * and set p to that object
     * update the corresponding instantiated table
     * else - fatal error
     * *************************************************/
    str plugin = parse_plgname(plg);

#define p_equals(Tab,Type) \
    if (Tab[plugin]) { \
	p = dynamic_cast<T *>((*Tab[plugin])(gtcdp, (Type *)next_plg)); \
    } // end p_equals macro
    
    p_equals(sPluginTab, storagePlugin)
    else p_equals(xPluginTab, xferPlugin)
    else p_equals(sePluginTab, servePlugin)
    else p_equals(cPluginTab, chunkerPlugin)
	;

    if (p) {
        warn << "Plugin not instantiated - returning new plugin: " << plg << "\n";
        p->set_next_plugin(next_plg);
        Plugin_instantiated.insert(plg, p);
        return p;
    }

    fatal << "Incorrect plugin name " << plg << ": could not instantiate a new plugin\n";
    return p;
}

static void
cleanup()
{
    warn << "gtcd exiting...\n";
    gtcdp->xp->xp_dump_statistics();
    if (gtcd_listen_sock) {
        unlink(gtcd_listen_sock);
    }
    exit(0);
}

static void
accept_connection(int fd)
{
    struct sockaddr_un sun;
    socklen_t sunlen = sizeof(sun);
    bzero(&sun, sizeof(sun));

    int cs = accept(fd, (struct sockaddr *) &sun, &sunlen);
    if (fd < 0) {
        if (errno != EAGAIN)
            warn << "accept; errno = " << errno << "\n";
        return;
    }

    vNew client(cs, sun, wrap(gtcdp, &gtcd::dispatch));
}

static void
gtcd_start(bool background)
{
    mode_t m = umask(0);

    if (!gtcd_listen_sock)
        gtcd_listen_sock = get_gtcd_socket();

    int fd = unixsocket(gtcd_listen_sock);
    if (fd < 0 && errno == EADDRINUSE) {
        /* XXX - This is a slightly race-prone way of cleaning up after a
         * server bails without unlinking the socket.  If we can't connect
         * to the socket, it's dead and should be unlinked and rebound.
         * Two daemons could do this simultaneously, however. */
        int xfd = unixsocket_connect(gtcd_listen_sock);
        if (xfd < 0) {
            unlink(gtcd_listen_sock);
            fd = unixsocket(gtcd_listen_sock);
        }
        else {
            warn << "closing the socket\n";
            close (xfd);
            errno = EADDRINUSE;
        }
    }
    if (fd < 0)
        fatal ("%s: %m\n", gtcd_listen_sock.cstr ());

    close_on_exec(fd);
    make_async(fd);

    umask(m);

    listen(fd, 150);

    if (background)
        daemonize();

    warn << progname << " (DOT Generic Transfer Client) version "
        << VERSION << ", pid " << getpid() << "\n";

    fdcb(fd, selread, wrap(accept_connection, fd));
}

template <class T>
static void
print_plugin(const str &s, T *cb)
{
    warnx << s << " ";
}

template <class T>
static void 
print_plugin_tab(const char *name, qhash<str, T> &tab)
{
    warnx << "Available " << name << " Plugins: ";
    tab.traverse(wrap(print_plugin<T>));
    warnx << "\n";
}

static void
print_plugins()
{
    print_plugin_tab("Storage",  sPluginTab);
    print_plugin_tab("Transfer", xPluginTab);
    print_plugin_tab("Server",   sePluginTab);
    print_plugin_tab("Chunker",  cPluginTab);
}

static void
usage()
{
    fprintf(stderr, "usage:  gtcd [-h] [-f configfile] [-p gtcd_listen_sock] [-v paramfile]\n");
}

static void
help()
{
    usage();
    fprintf(stderr,
	    "    -h .......... help (this message)\n"
	    "    -f file ..... configuration file\n"
	    "    -v file ..... parameter file\n"
	    "    -p listen ... listen socket (default /tmp/dot-$USER/gtcd.sock)\n"
	    "    -D <level> .. debug / do not daemonize\n"
	    "\n");
    print_plugins();
}

template <class T, class U>
T *plumb(vec<str> *p_list, U *p_tab, str pluginClass)
{
    T *p = NULL;
    ref<vec<T *> > pc = New refcounted<vec<T *> >;
    qhash<str, T *> p_ptr;
    
    while (p_list->size()) {
        str conf = p_list->pop_back();
        str plg_list = p_list->pop_back();
        str plugin = p_list->pop_back();
	vec<T *> pvec;

        dwarn(DEBUG_INIT) << "Adding Plugin: " << plugin
                  << " chained to "
                  << plg_list << " with params " << conf << "\n";
        
        //if (!(*p_tab)[plugin]) {
        str plg_name = parse_plgname(plugin);
        if (!sPluginTab[plg_name] && !xPluginTab[plg_name] && !sePluginTab[plg_name] && !cPluginTab[plg_name]) {
            warn("plugin (%s) does not exist\n", plugin.cstr());
            print_plugins();
            exit(-1);
        }

        if (plg_list == "" || plg_list == "null") {
            dwarn(DEBUG_INIT) << "Passing NULL\n";
            p = NULL;
        }
        else {
	    static rxx comma(",");
	    vec<str> plgs;

	    split(&plgs, comma, plg_list);
	    for (unsigned i = 0; i < plgs.size(); i++) {
		str plg = plgs[i];
		if (!p_ptr[plg]) {
		    warn << "Plugin " << plg << " not instantiated - creating a new one\n";
		    p = get_plugin<T> (plg, NULL);
		    p_ptr.insert(plg, p);
		}
		else {
		    p = (*p_ptr[plg]);
		    dwarn(DEBUG_INIT) << "passing " << plg << "\n";
		}
		
		pvec.push_back(p);
	    }
        }

        if (pvec.size() > 1) {
            p = get_plugin<T> (plugin, NULL);
            p->set_more_plugins(pvec);
            for (unsigned int i = 0; i < pvec.size(); i++) {
                pvec[i]->set_parent(p);
            }
        }
        else {
            T *ptemp = get_plugin<T> (plugin, p);
            if (p)
                p->set_parent(ptemp);
            p = ptemp;
        }

        if (!p->configure(conf, pluginClass))
            fatal("Plugin (%s) configuration failed\n", plugin.cstr());
    }
    return p;
}

static void
instantiate_plugins(str configfile)
{
    vec<str> sp_list, xp_list, cp_list, sep_list;

    if (parse_config(configfile, &sp_list, &xp_list, &sep_list, &cp_list))
        fatal << "Cannot parse config file\n";

#define CONFIG(P, PT, PLIST, NAME) \
    gtcdp->set_##P(plumb<P>(&PLIST,&PT,NAME));
    /* calls gtcdp->set_storagePlugin, etc. */

    CONFIG(storagePlugin, sPluginTab,  sp_list,  "storage");
    CONFIG(xferPlugin,    xPluginTab,  xp_list,  "xfer");
    CONFIG(chunkerPlugin, cPluginTab,  cp_list,  "chunker");
    CONFIG(servePlugin,   sePluginTab, sep_list, "serve");
}

/* needed for xdisk*/
chunkerPlugin *
instantiate_chunker_plugin(vec<str> p)
{
    return plumb<chunkerPlugin>(&p, &cPluginTab, "chunker");
}

int
main(int argc, char * argv[])
{
    storagePlugin_maker _spm; // populate sPluginTab
    xferPlugin_maker _xpm;    // populate xPluginTab
    servePlugin_maker _sepm;    // populate sePluginTab
    chunkerPlugin_maker _cepm;    // populate cPluginTab

    char ch;
    bool background = true;
    str configfile;
    str paramfile;

    setprogname(argv[0]);

    while ((ch = getopt(argc, argv, "D:hp:f:v:")) != -1)
        switch(ch) {
	case 'D':
	    background = false;
	    if (set_debug(optarg))
		exit(-1);
	    break;
        case 'p':
            gtcd_listen_sock = optarg;
            break;
        case 'f':
            configfile = optarg;
            break;
	case 'v':
	    paramfile = optarg;
	    break;
	case 'h':
	    help();
	    exit(0);
	default:
	    usage();
	    exit(-1);
	}

    gtcd_start(background);

    /* Configure the graph of plugins */
    gtcdp = New gtcd();

    warn << "********DOT will use " << get_dottmpdir() << "***********\n";
    parse_paramfile(paramfile);
    instantiate_plugins(configfile);

    gtcdp->connCache = New connectionCache();
    gtcdp->rpcCache  = New rpcconnCache(gtcdp->connCache);
    connCache_ptr = gtcdp->connCache;
    
    sigcb (SIGTERM, wrap (cleanup));
    sigcb (SIGINT, wrap (cleanup));

    amain();
}
