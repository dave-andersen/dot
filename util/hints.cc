#include "util.h"

struct ph_cache_entry {
    str id;
    hint_res res;
    ihash_entry<ph_cache_entry> hlink;
    ph_cache_entry(const str i, hint_res r);
    ~ph_cache_entry();
};

static ihash<const str, ph_cache_entry,
    &ph_cache_entry::id, &ph_cache_entry::hlink> parse_hint_cache;

ph_cache_entry::ph_cache_entry(const str i, hint_res r)
    : id(i), res(r)
{
    parse_hint_cache.insert(this);
}

ph_cache_entry::~ph_cache_entry()
{
    parse_hint_cache.remove(this);
}

int 
parse_hint(str hint, str protocol, hint_res *res)
{
    str join = strbuf() << hint << ":" << protocol;
    ph_cache_entry *pce;
    if ((pce = parse_hint_cache[join])) {
	*res = pce->res;
	return 1;
    }
	
    static rxx colon(":");
    vec<str> parts;

    if (!hint || !hint.len()) {
	fatal("woah! parse_hint got a null hint!");
	return -1;
    }
    /* hints:
     * gtc://hostname:port
     * xdisk://name:target_dir:size:time:ignore:ing_path
     * intern://name
     */

    const char *proto_data = strstr(hint, "://");
    if (!proto_data || (protocol != str(hint.cstr(), proto_data-hint.cstr())))
	return -1;
    proto_data += 3; // Skip the '://'

    split(&parts, colon, proto_data);

    if (protocol == "gtc") {
	if (parts.size() < 2) {
	    warn << "Invalid gtc protocol hint: " << proto_data << "\n";
	    return -1;
	}
	
	res->hint.hostname = parts[0];
	/* last component specifies the port */
	res->hint.port = atoi(parts[ parts.size() - 1 ]);
    }
    else if (protocol == "xdisk") {
	if (parts.size() < 5) {
	    warn << "Could not parse xdisk hint: " << proto_data << "\n";
	    return -1;
	}

	res->hint1.name = parts[0];
	res->hint1.target_dir = parts[1];
	res->hint1.size = atoi(parts[2]);
	res->hint1.modtime = atoi(parts[3]);
	res->hint1.ignore_str = parts[4];
	
	if (parts.size() > 5)
	    res->hint1.ignore_path = parts[5];
	else
	    res->hint1.ignore_path = res->hint1.ignore_str;

	const char *f = strrchr(res->hint1.name, '.');
	if (f) 
	    res->hint1.file_type = strbuf() << f;
	else
	    res->hint1.file_type = "NONE";
#if 0
	warnx << "parse_hint:: filename " << res->hint1.name
	      << " type " << res->hint1.file_type
	      << " size " << res->hint1.size
	      << " time " << res->hint1.modtime
	      << " target " << res->hint1.target_dir
	      << " ignoring " << res->hint1.ignore_str
	      << " " << res->hint1.ignore_path << "\n";
#endif
    }
    else if (protocol == "intern") {
	res->hint2 = str(proto_data);
    }
    else { /* Unknown protocol! */
	return -1;
    }

    pce = New ph_cache_entry(join, *res);
    assert(pce);
    return 1;
}

int
make_hint(hint_res ip, str protocol, oid_hint *op)
{
    if (protocol == "gtc") {
	op->name = strbuf() << "gtc://" << ip.hint.hostname << ":" << ip.hint.port;
	return 1;
    }

    if (protocol == "intern") {
	op->name = strbuf() << "intern://" << ip.hint2;
	return 1;
    }
    
    return -1;
}

int 
gtc_hint_to_name(str hint, str *name)
{
    hint_res result;
    if (parse_hint(hint, "gtc", &result) < 0)
	return -1;
    
    *name = strbuf() << result.hint.hostname << ":" << result.hint.port;
    return 0;
}


