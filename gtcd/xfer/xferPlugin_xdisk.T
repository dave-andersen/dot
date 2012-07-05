/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_xdisk.h"

extern opt_matrix mat;
ptr<vec<str> > ignore_str;
extern unsigned int pressure_aiod;

extern bool abort_flag;

#ifdef TIME_SERIES
extern int xdisk_raw_time_bytes;
#endif

struct stat_info
get_shadow_stat(struct item_info ip)
{
    struct stat_info op;

    op.name = ip.name;
    op.s.stsize = ip.s.st_size;
    op.s.statime = ip.s.st_atime;
    op.s.stmtime = ip.s.st_mtime;
    op.s.stctime = ip.s.st_ctime;

    return(op);
}

bool
check_op_in_cache(Db *filesDb, str key, struct item_info s)
{
    ptr <Dbt> d = New refcounted<Dbt >;
    
    if (!get_unique_from_cache(filesDb, key, key.len(), d)) {
	//warnx << "check_op_in_cache: MISS for " << key << "\n";
	return false;
    }

    //warnx << "check_op_in_cache: HIT for " << key << "\n";
    
    rpc_bytes<> value;
    value.set((char *)d->get_data(), d->get_size());
    
    op_bdb_info o;
    bytes2xdr(o, value);
    if (o.type != INFO_OP) {
	return false;
    }

    if (s.s.st_mtime > o.time) {
	//warnx << "check_op_in_cache: HITBUTSTALE for " << key << "\n";
	//delete the stale entry
	delete_from_cache(filesDb, key, key.len());
	return false;
    }

    //warnx << "check_op_in_cache: HITVALID for " << key << "\n";
    return true;
}

/*
 * This function modifies the input path string to avoid creating
 * lots of str objects.  It stores pointers to the start of each
 * path component in the path_parts vec.
 */
static void
split_path(char *path, vec<const char *> *path_parts)
{
    if (*path == '/')
	path_parts->push_back("/");
    
    char *line, *brkt;
    for (line = strtok_r(path, "/", &brkt);  
         line;
	 line = strtok_r(NULL, "/", &brkt)) {
	path_parts->push_back(line);
    }
}

double
dir_match(vec<const char *> *p1, vec<const char *> *p2)
{
    double dist = 0;
    size_t s1 = p1->size();
    size_t s2 = p2->size();
    size_t max_len = max(s1, s2);
    vec<const char *> *sm;
    vec<const char *> *lg;
    if (s1 > s2) {
	sm = p2; lg = p1;
    }
    else {
	sm = p1; lg = p2;
    }

    //leftmost match
    unsigned int lmatch = 0;
    int nrdist = -1;
    double ldist = 0;
    for (size_t i = 0; i < sm->size(); i++) {
	if (strcmp((*sm)[i], (*lg)[i]) != 0) {
	    nrdist = i;
	    break;
	}
	else 
	    lmatch++;
    }
    
    ldist = ((double)lmatch)/max_len;
    dist = ldist*ldist;
    
    //new right match
    //give credit for attempt to reconverge
    unsigned int nrmatch = 0;
    double denom;
    double redist;
    if (nrdist >= 0) {
	unsigned int d = s2-nrdist; //num tokens in tp that are not matched
	denom = d*(d+1)/(double)2;

	DPRINTF(DEBUG_XDISK, "denom %f d %d nrdist %d\n", denom, d, nrdist);

	int j = s1-1;
	for (int i = s2-1; i >= nrdist; i--) {
	    if (strcmp((*p2)[i], (*p1)[j]) == 0) {
		nrmatch += (i+1-nrdist);
		DPRINTF(DEBUG_XDISK, "nrmatch %d j %d\n", nrmatch, j);
		j--;
		if (j < nrdist) break;
	    }
	    else if (nrmatch)
		break;
	}
    }
    
    if (nrmatch) {
	double quot = (double)nrmatch/(double)denom;
	redist = pow(ldist,(2-quot));
	DPRINTF(DEBUG_XDISK, "quot %f, redist %f\n", quot, redist);
	if (redist > dist)
	    dist = redist;
    }

    //rightmost match
    unsigned int rmatch = 0;
    double rdist = 0;
    unsigned int j = lg->size()-1;
    for (int i = sm->size()-1; i >= 0; i--) {
	if (strcmp((*sm)[i], (*lg)[j]) != 0)
	    break;
	else {
	    rmatch++;
	    j--;
	}
    }
    rdist = ((double)rmatch)/max_len;

    if (rdist > dist)
	dist = rdist;

    unsigned int mmatch = 0;
    double mdist = 0;
    {
	int *L = new int[(s1+1)*(s2+1)];
	bzero(L, sizeof(int)*(s1+1)*(s2+1));
	int z = 0;
	int len = -1;
	
	for (size_t i = 0; i < s1; i++) {
	    for (size_t j = 0; j < s2; j++) {
		if ((*p1)[i] == (*p2)[j]) {
		    
		    L[(i+1)*(s2+1)+j+1] = L[i*(s2+1)+j] + 1;
		    
		    if (L[(i+1)*(s2+1)+j+1] >= z) 
			z = L[(i+1)*(s2+1)+j+1];
		    
		    if (L[(i+1)*(s2+1)+j+1] == z) 
			len = z;
		}
	    }
	}
	
	delete[] L;
	mmatch = z;
    }
    
    mdist = ((double)mmatch)/max_len;
    mdist = mdist*mdist;
    
    if (mdist > dist)
	dist = mdist;
    
    return(dist);
}

bool
inline suffix_match(str c, str t, str suf)
{
    const char *ptr;
    if ((ptr = strstr(c, suf))) {
	if (!strncasecmp(c, t, (ptr - c.cstr())))
	    return true;
    }
    return false;
}

bool
inline prefix_match(str c, str t, str pre)
{
    const char *ptr;
    if ((ptr = strstr(c, pre))) {
	if (!strcasecmp(ptr, t))
	    return true;
    }
    return false; 
}

double
inline fuzzy_name_match(str c, str t, str c_type, str t_type,
			name_property np)
{
    if (c == t) 
	return 1;

    //not an exact name match ..see if backup file match
    if ((np.s_tilda && suffix_match(c, t, "~")) ||
	(np.s_bak && suffix_match(c, t, ".bak")) ||
	(np.p_hash && prefix_match(c, t, "#")))
	return(0.7);
    
    if (c_type != "NONE" &&  t_type != "NONE" &&
	!strcasecmp(c_type, t_type))
	return(0.5);
    
    return(0.1);
}

double
inline fuzzy_size_match(int c, int t)
{
    if (c == t)
	return 1;

    double perc = abs(t-c)/((double)t);
    if (perc > 0.1)
	return(0.1);

    //0.9 = m(0.01) + c
    //0.5 = m(0.1) + c
    double p = -4.45*perc + 0.95;
    return(p);
}

double
inline time_match(int c, int t)
{
    if (c == t)
	return 1;

    double perc = abs(t-c)/((double)t);
    if (perc > 10)
	return(0.7);
    
    //0.9 = m(0.01) + c;
    //0.7 = m(10) + c;
    double p = -0.02*perc + 0.9;
    return(p);
}

bool
inline check_ignore_str(str op)
{
    for (size_t i = 0; i < ignore_str->size(); i++) {
	if (strstr(op, (*ignore_str)[i]))
	    return true;
    }

    return false;
}

os_entry *
create_statop(str path, struct item_info st, xferPlugin_xdisk *xp)
{
    str op_name = strbuf() << path << ":" << DISK_STAT;
    
    os_entry *ose = mat.op_store[op_name];
    //this is a new op
    if (!ose) {
	if (check_ignore_str(op_name) ||
	    check_op_in_cache(xp->filesDb, op_name, st))
	    return(NULL);

	dwarn(DEBUG_XDISK) << "Stat op op_name -->" << op_name << "\n";
	
	ose  = New stat_op(op_name, path, st, xp);
	
	mat.pending_q.insert_tail(ose);
    }
    
    return(ose);
}

os_entry *
create_hashop(str path, struct item_info st, xferPlugin_xdisk *xp)
{
    if (st.s.st_size <= 0) {
	//warnx << "create_hashop:: Nothing useful\n";
	return(NULL);
    }
    str op_name = strbuf() << path << st.name << ":" << DISK_HASH;
    //warnx << "Path is " << path << " " << op_name << "\n";
    
    os_entry *ose = mat.op_store[op_name];
    //this is a new op
    if (!ose) {
	if (check_ignore_str(op_name) ||
	    check_op_in_cache(xp->filesDb, op_name, st))
	    return NULL;
	
	ose  = New hash_op(op_name, path, st, xp);
	
	mat.pending_q.insert_tail(ose);
    }
    
    return(ose);
}

os_entry *
create_chitop(dot_desc d, ptr<vec<struct offset_info > > oi,
	      int len, xferPlugin_xdisk *xp)
{
    str op_name = strbuf() << d << ":" << DISK_CHIT;
    //warnx << "key is " << d << " " << op_name << "\n";
    
    os_entry *ose = mat.op_store[op_name];
    //this is a new op
    if (!ose) {
	ose  = New chit_op(op_name, d, oi, len, xp);
	mat.pending_q.insert_tail(ose);
    }
    
    return(ose);
}

double
update_cost(double prev, double cur)
{
    double new_val = prev + ALPHA * (cur - prev);
    return(new_val);
}

stat_op::stat_op(str i, str p, struct item_info s,
		 xferPlugin_xdisk *ptr)
{
    id = i;
    
    //opt variables
    op_cost = DIR_STAT_COST;
    //DPRINTF(DEBUG_XDISK, "Stat get_cost is %f\n", DIR_STAT_COST);
    sum_p = 0;
    sum_cp = 0;
    cpb = LARGE_COST; //cost per block
    it_num = -1;
    success = 0;
    time = -1;

    type = DISK_STAT;
    path = p;
    
    //keep a split path around
    spl_path = New vec<const char *>;
    sp_ptr = strdup(p);
    split_path(sp_ptr, spl_path);
        
    stat_buf = s;
    xp = ptr;
        
    dwarn(DEBUG_XDISK) << "stat_op::stat_op: Creating entry for " << p <<
	" " << id << "\n";
}

stat_op::~stat_op()
{
    free(sp_ptr);
    spl_path->clear();
    delete spl_path;
    //warnx << "stat_op::stat_op: Deleting entry for " << id << "\n";
}

tamed void
stat_op::perform_op()
{
    tvars {
	str err;
	ptr<vec<struct item_info> > stats;
	double now;
	double cost;
	double prev;
    }

    now = return_time(SECONDS);
    stats = New refcounted<vec<struct item_info> >;
    twait {
	xp->perform_stat(path, stats, mkevent (err));
    }

    if (err) {
	(*(xp->pending_cb))(err, NULL);
	return;
    }
    cost = return_time(SECONDS) - now;
    if (cost < 0) {
	warnx << "Woah, cost is negative\n";
	cost = 0;
    }
    
    prev = DIR_STAT_COST;
    DIR_STAT_COST = update_cost(prev, cost);
    time = cost;
    
    DPRINTF(DEBUG_OPT, "Accumulating stat cost %f to prev %f to get %f\n", cost, prev, DIR_STAT_COST);
    
    //add more ops
    for (size_t i = 0; i < stats->size(); i++) {
	//warnx << (*stats)[i].name << " " << (*stats)[i].s.st_size << "\n";
	if (S_ISDIR((*stats)[i].s.st_mode)) {
	    str p = strbuf() << path << (*stats)[i].name << "/";
	    create_statop(p, (*stats)[i], xp);
	}
	else {
	    create_hashop(path, (*stats)[i], xp);
	}
    }

    //cache the fact that op is performed
    {
	rpc_bytes<> value;
	op_bdb_info o;
	o.type = INFO_OP;
	o.path = path;
	o.oper = DISK_STAT;
	//item_info --> stat_info
	o.buf = get_shadow_stat(stat_buf);
	double t = get_cur_time();
	o.time = (dot_time) t;
	//fprintf(stderr, "****************%f\n", t);
	//warnx << o.time << "\n";
	xdr2bytes(value, o);
	put_in_cache(xp->filesDb, id, id.len(),
		     value.base(), value.size(), true);

	//ptr<Dbt > d = New refcounted<Dbt >;
	//if (get_unique_from_cache(xp->filesDb, id.cstr(), id.len(), d))
	//  warnx << "Everything good\n";
    }
    
    (*(xp->pending_cb))(err, NULL);
}

double
stat_op::get_cost()
{
    op_cost = DIR_STAT_COST;
    //DPRINTF(DEBUG_XDISK, "Stat get_cost is %f\n", DIR_STAT_COST);
    return(op_cost);
}

float
stat_op::get_benefit(ht_entry *hte)
{
    double p_t = 0;
    double p = 0;

    if (hte->key == "CACHE_HIT") 
	return (0);
    
    size_t size = hte->hints->size();
    ptr<vec<xdisk_hint> > temp = hte->hints;
    ptr<vec<vec<const char *> *> > temp_hints = hte->spl_hints;
    
    for (size_t i = 0; i < size; i++) {
	p = dir_match(spl_path, (*temp_hints)[i]);
	DPRINTF(DEBUG_XDISK, "%s ", (*temp)[i].target_dir.cstr());
	p_t = max(p, p_t);
    }
    
    DPRINTF(DEBUG_XDISK, "  %s prob is %.2f\n",path.cstr(), p);

    return(p_t);
}

double
stat_op::get_xfer_cost(ht_entry *hte)
{
    return(CHUNK_READ_HASH_COST);
}

hash_op::hash_op(str i, str p, struct item_info s, xferPlugin_xdisk *ptr)
{
    id = i;
    
    unsigned int num_chunks = 0;
    num_chunks = s.s.st_size/CHUNK_SIZE;
    if (s.s.st_size % CHUNK_SIZE != 0)
	num_chunks++;
    op_cost = (num_chunks * CHUNK_READ_HASH_COST);
    //DPRINTF(DEBUG_XDISK, "Hash get_cost per chunk is %f\n", CHUNK_READ_HASH_COST);
    sum_p = 0;
    sum_cp = 0;
    cpb = LARGE_COST; //cost per block
    it_num = -1;
    success = 0;
    time = -1;

    type = DISK_HASH;
    path = p;
    //keep a split path around
    spl_path = New vec<const char *>;
    sp_ptr = strdup(p);
    split_path(sp_ptr, spl_path);
    
    stat_buf = s;
    //extract the type of the file
    const char *f = NULL;
    f = strrchr(stat_buf.name, '.');
    if (f)
	stat_buf.file_type = f;
    else
	stat_buf.file_type = "NONE";

    //extract prefix and suffix info
    if (strstr(stat_buf.name, "~"))
	np.s_tilda = true;
    else
	np.s_tilda = false;
    if (strstr(stat_buf.name, ".bak"))
	np.s_bak = true;
    else
	np.s_bak = false;
    if (strstr(stat_buf.name, "#"))
	np.p_hash = true;
    else
	np.p_hash = false;
    
    xp = ptr;
    
    //warnx << "hash_op::hash_op: Creating entry for " << p <<
    //" name " << stat_buf.name << " size " << stat_buf.s.st_size << " id " << id << "\n";
}

hash_op::~hash_op()
{
    free(sp_ptr);
    spl_path->clear();
    delete spl_path;
    //warnx << "hash_op::hash_op: Deleting entry for " << id << "\n";
}

double
hash_op::get_cost()
{
    unsigned int num_chunks = 0;
    num_chunks = stat_buf.s.st_size/CHUNK_SIZE;
    if (stat_buf.s.st_size % CHUNK_SIZE != 0)
	num_chunks++;
    op_cost = (num_chunks * CHUNK_READ_HASH_COST);
    
    //DPRINTF(DEBUG_XDISK, "Hash get_cost per chunk is %f\n", CHUNK_READ_HASH_COST);
    return(op_cost);
}

float
hash_op::get_benefit(ht_entry *hte)
{
    double p = 0;
    double p_nm = 0;
    double p_sm = 0;
    double p_pc = 0;
    double p_tm = 0;
    double p_sc = 0;
    double p_t = 0;

    if (hte->key == "CACHE_HIT") 
	return (0);

    DPRINTF(DEBUG_XDISK, "****\n");
    size_t size = hte->hints->size();
    ptr<vec<xdisk_hint> > temp = hte->hints;
    ptr<vec<vec<const char *> *> > temp_hints = hte->spl_hints;
    
    for (size_t i = 0; i < size; i++) {

	p_nm = fuzzy_name_match(stat_buf.name, (*temp)[i].name,
				stat_buf.file_type, (*temp)[i].file_type, np);
	
	p_sm = fuzzy_size_match(stat_buf.s.st_size,
				(*temp)[i].size);
	
	p_pc = dir_match(spl_path, (*temp_hints)[i]);

	p_tm = time_match(stat_buf.s.st_mtime, (*temp)[i].modtime);

	if ((*temp)[i].size > 0) {
	    size_t size = min((unsigned int)(stat_buf.s.st_size), (*temp)[i].size);
	    if (size == (*temp)[i].size)
		p_sc = 1;
	    else {
		unsigned int chunks_desired = (*temp)[i].size/CHUNK_SIZE;
		if ((*temp)[i].size%CHUNK_SIZE != 0)
		    chunks_desired++;
		unsigned int chunks_possible = size/CHUNK_SIZE;
		if (size%CHUNK_SIZE != 0)
		    chunks_possible++;
		p_sc = (double) chunks_possible/(double)chunks_desired;
	    }
	}
    
	p = p_nm * p_sm * p_pc * p_tm * p_sc;
	    
	p_t = max(p, p_t);
	
	DPRINTF(DEBUG_XDISK, "%s %s %s p %f || p_nm %f || p_sm %f || p_pc %f || p_tm %f || p_sc %f\n",
		(*temp)[i].target_dir.cstr(), (*temp)[i].name.cstr(), id.cstr(), p, p_nm, p_sm, p_pc, p_tm, p_sc);
    }

    DPRINTF(DEBUG_XDISK, "hasp_op::get_benefit: %s prob is %f\n",path.cstr(), p_t);
    DPRINTF(DEBUG_XDISK, "****\n");
    
    assert(p_t <= 1);
    return(p_t);
}

double
hash_op::get_xfer_cost(ht_entry *hte)
{
    assert(0);
    return(0);
}

tamed void
hash_op::perform_op()
{
    tvars {
	str err;
	str file;
	double now;
	double cost;
	double prev;
	double per_chunk;
	unsigned int num_chunks;
    }
        
    file = strbuf() << path << stat_buf.name;

    now = return_time(SECONDS);
    twait {
	xp->perform_hash(file, mkevent (err));
    }
    if (err) {
	(*(xp->pending_cb))(err, NULL);
	return;
    }
    
    cost = return_time(SECONDS) - now;
    if (cost < 0) {
	warnx << "Woah!  hash_opt::perform_op cost is negative\n";
	cost = 0;
    }
	    
    num_chunks = 0;
    num_chunks = stat_buf.s.st_size/CHUNK_SIZE;
    if (stat_buf.s.st_size % CHUNK_SIZE != 0)
	num_chunks++;
    per_chunk = cost/num_chunks;
    prev = CHUNK_READ_HASH_COST;
    CHUNK_READ_HASH_COST = update_cost(prev, per_chunk);
    time = cost;
    //fprintf(stderr, "Accumulating hash cost %f (%f, %d) with prev %f to get cur %f\n", per_chunk,
    //    cost, num_chunks, prev, CHUNK_READ_HASH_COST);
   
    //cache the fact that op is performed
    {
	rpc_bytes<> value;
	op_bdb_info o;
	o.type = INFO_OP;
	o.path = path;
	o.oper = DISK_HASH;
	o.buf = get_shadow_stat(stat_buf);
	o.time = (unsigned int )get_cur_time();
	xdr2bytes(value, o);
	put_in_cache(xp->filesDb, id, id.len(),
		     value.base(), value.size(), true);
    }
    
    (*(xp->pending_cb))(err, NULL);
}

chit_op::chit_op(str i, dot_desc d, ptr<vec<struct offset_info > > oi,
		 int len, xferPlugin_xdisk *ptr)
{
    id = i;
    
    op_cost = CACHE_CHECK_COST;
    sum_p = 0;
    sum_cp = 0;
    cpb = LARGE_COST; //cost per block
    it_num = -1;
    success = 0;
    time = -1;

    type = DISK_CHIT;
    desc = d;
    inf = oi;
    length = len;
    xp = ptr;
    
    //warnx << "chit_op::chit_op: Creating entry for " << d <<
    //" and id " << id << " and len " << len << "\n";
}

chit_op::~chit_op()
{
    //warnx << "chit_op::chit_op: Deleting entry for " << id << "\n";
}

double
chit_op::get_cost()
{
    op_cost = CACHE_CHECK_COST;
    return(op_cost);
}

float
chit_op::get_benefit(ht_entry *hte)
{
    double p = 0;
    if (mat.desc_store[desc])
        p = 0.95;
    
    return(p);
}

double
chit_op::get_xfer_cost(ht_entry *hte)
{
    return(CHUNK_READ_HASH_COST);
}

tamed void
chit_op::perform_op()
{
    tvars {
	str err;
	size_t i;
	double now;
	double prev;
    }

    dwarn(DEBUG_XDISK) << "Came to read\n";
    
    now = return_time(SECONDS);
    for (i = 0; i < inf->size(); i++) {
	dwarn(DEBUG_XDISK) << "Performing offset read\n";
	twait {
	    xp->perform_offset_read((*inf)[i].path, (*inf)[i].offset,
				    length, mkevent (err));
	}
	if (!err)
	    break;
    }

    if (!err) {
	now = return_time(SECONDS) - now;
	if (now < 0) {
	    warnx << "Woah! Cost is negative\n";
	    now = 0;
	}
	prev = CHUNK_READ_HASH_COST;
	CHUNK_READ_HASH_COST = update_cost(prev, now);
	time = now;
    }
    else {
       warnx << " Err in cache hit " << err << "\n";
    }

    dwarn(DEBUG_XDISK) << "Calling back\n";
    
    (*(xp->pending_cb))(err, NULL);
}


/*ops*/
xferPlugin_xdisk::xferPlugin_xdisk(gtcd *_m, xferPlugin *next_xp)
    : m(_m), xp(next_xp)
{
    assert(m);
    if (next_xp)
	fatal << __PRETTY_FUNCTION__ << " next_xp is not NULL\n"
	      << "Make sure that this storage plugin comes last\n";

    if (!AIOD_PATH) 
	AIOD_PATH = "aiod";
    AIOD_PATH = find_program(AIOD_PATH);

    if (!AIOD_PATH)
	warnx << "Aiod is not found\n";
    else
	warnx << "Aiod is found at " << AIOD_PATH << "\n";
    
    //aiod_ptr = New aiod (1, 0x10000, 0x10000, false, AIOD_PATH);
    aiod_ptr = New aiod (1, 0x200000, 0x20000, false, AIOD_PATH);
     
    ignore_str = New refcounted<vec<str> >;

    //cache setup
    dbenv = new DbEnv(0);
    dbenv->set_errpfx("Xdisk Transfer Plugin");
    dbenv->set_cachesize(0, XDISK_CACHE_SIZE, 0);

    str cachepath = get_dottmpdir() << "/db";
    if (mkdir(cachepath, S_IRWXU) < 0 && errno != EEXIST)
        fatal("Could not create cache directory: %s: %m\n", cachepath.cstr());

    (void)dbenv->set_data_dir(cachepath);

    //ignore this path in computation
    ignore_str->push_back(get_dottmpdir());
        
    dbenv->open(cachepath, 
		DB_CREATE | DB_INIT_MPOOL | DB_PRIVATE, 0);

    filesDb = new Db(dbenv, 0);
    filesDb->set_pagesize(32*1024);
    if (filesDb->set_flags(0|DB_DUP) < 0) {
	warn << "Error setting flags\n";
    }
    if (filesDb->open(NULL,
     		  "xdisklist.db",
		  NULL,
		  DB_HASH,
		  DB_CREATE,
		      0) < 0) {
	warn << "Error opening\n";
    }
}

void
xferPlugin_xdisk::xp_dump_statistics()
{
    filesDb->close(0);
    dbenv->close(0);
}

bool
xferPlugin_xdisk::configure(str s, str pluginClass)
{
    if (s) {
	char *hn = NULL;
	char *name = strdup(s);
	
	if ((hn = strchr(name, ' '))) {
	    *hn++ = '\0';
	    str temp(name);
	    chunker.push_back(temp);
	    chunker.push_back("");
	    temp = hn;
	    chunker.push_back(temp);
	    warnx << "Setting xdisk plugin with " << chunker[0] << " and "
		  << chunker[2] << "\n";
	}
    }

    if (chunker.size() <= 0) {
	chunker.push_back("default");
	chunker.push_back("");
	chunker.push_back("static");
	warnx << "Setting xdisk plugin with DEFAULT " << chunker[0] << " and "
	      << chunker[2] << "\n";
    }
    cp = instantiate_chunker_plugin(chunker);
    assert(cp);
    cp->set_storage_plugin(this);
    
    return true;
}

//can't use twait in the functions below since the get_descriptors 
// and the get_chunks calls in xferPlugin_gtc etc call back multiple times
// and TAME thinks that the function is overcalled.

tamed void
xferPlugin_xdisk::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, descriptors_cb cb)
{
    //warnx << "xferPlugin_xdisk::get_descriptors: called\n";
    
    //check bdbcache
    {
	ptr<Dbt > d = New refcounted<Dbt >;

	str key = strbuf() << "INFO_OID_DESC:" << oid->id;
	if (!get_unique_from_cache(filesDb, key, key.len(), d)) {
	    (*cb)("Not a cache hit", NULL, true);
	    return;
	}

	warnx << "xferPlugin_xdisk::get_descriptors: CACHEHIT\n";
	
	rpc_bytes<> value;
	value.set((char *)d->get_data(), d->get_size());
    
	oid_desc_bdb_info o;
	bytes2xdr(o, value);
	if (o.type != INFO_OID_DESC) {
	    (*cb)("Not a cache hit", NULL, true);
	    return;
	}

	ptr< vec<dot_descriptor> > descptr = New refcounted<vec<dot_descriptor> >;
	descptr->setsize(o.descriptors.size());
	for (size_t i = 0; i < o.descriptors.size(); i++) {
	    (*descptr)[i] = o.descriptors[i];
	}

	(*cb)(NULL, descptr, true);
	return;
    }
    
    (*cb)("Not a cache hit", NULL, true);
}

tamed void 
xferPlugin_xdisk::get_chunk(ref<dot_descriptor> d, ref<vec<oid_hint> > hints,
                   chunk_cb cb)
{
    fatal << "xferPlugin_xdisk::get_chunk: called\n";
}

tamed void 
xferPlugin_xdisk::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
			     chunk_cb cb)
{
    //warn << "xferPlugin_xdisk::get_chunks: called\n";
    
    hint_res res;
    if (parse_hint((*(*hints)[0])[0].name, "intern", &res) < 0) {
	warn << "xferPlugin_xdisk::get_chunks: Not internal hint\n";
	(*cb)("No hint", NULL);
    }
    
    pending_cb = cb;
    
    os_entry *ose = mat.op_store[res.hint2];
    ose->perform_op();
}

tamed void 
xferPlugin_xdisk::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::cancel_chunk: called\n";
}

tamed void 
xferPlugin_xdisk::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::cancel_chunks: called\n";
}

void 
xferPlugin_xdisk::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    //warnx << "xferPlugin_xdisk::xp_notify_descriptors: called\n";
}

void 
xferPlugin_xdisk::sp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
    //warnx << "xferPlugin_xdisk::sp_notify_descriptors: called\n";
}

void 
xferPlugin_xdisk::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
    warn << "xferPlugin_xdisk::update_hints: called\n";
}

tamed void
xferPlugin_xdisk::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints, bitmap_cb cb)
{
    warn << "xferPlugin_xdisk::get_bitmap: called\n";
}

/***************optimizer interface*****************/
void
xferPlugin_xdisk::extract_stat_ops(str path)
{
    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::extract_stat_ops: Extracting " << path << "\n";
    const char *ref = path;
    const char *ptr = strstr(ref, NEW_ROOT);
    bool nrt = false;

    if (ptr == ref) {
	//warnx << "Path " << path << " starts with " << NEW_ROOT << "\n";
	nrt = true;
	ref = ref + NEW_ROOT.len() - 1;
	ptr = ref;
    }
    else {
	warnx << "Path " << path << "does not fall into " << NEW_ROOT << "\n";
	return;
    }
    
    while ((ptr = strstr(ptr, "/")) != NULL) {
	str p(ref, (ptr - ref + 1));
	ptr++;

	struct item_info i;
	stat(p, &(i.s));
	i.name = "";

	if (nrt) 
	    p = strbuf() << NEW_ROOT << p;
	
	//clean the path
	str newname = "";
	char *ptr1 = strdup(p);
	bool lastsl = false;
	if (*ptr1 == '/')
	    newname = "/";
	if (*(ptr1+p.len()-1) == '/')
	    lastsl = true;

	char *line, *brkt;
    	//1. remove two consec slashes
	for (line = strtok_r(ptr1, "/", &brkt);  
         line; line = strtok_r(NULL, "/", &brkt)) {
	    if (newname == "/" || newname == "")
		newname = strbuf() << newname << line;
	    else
		newname = strbuf() << newname << "/" << line;
	}

	if (lastsl) 
	    newname = strbuf() << newname << "/";
	if (newname == "//")
	    newname = "/";

	free(ptr1);
	
	create_statop(newname, i, this);
    }
}

void
extract_ignore_str(str ignore)
{
    dwarn(DEBUG_XDISK) << "Ignoring " << ignore << "\n";
    
    for (size_t i = 0; i < ignore_str->size(); i++) {
	if ((*ignore_str)[i] == ignore)
	    return;
	//see if new ignore string is a
	//child of an existing ignore string
	if (strstr(ignore, (*ignore_str)[i]) == ignore.cstr())
	    return;
	//viceversa
	if (strstr((*ignore_str)[i], ignore) == (*ignore_str)[i].cstr()) {
	    (*ignore_str)[i] = ignore;
	    return;
	}
    }

    ignore_str->push_back(ignore);
}

void
xferPlugin_xdisk::extract_chit_op(dot_descriptor dv)
{
    //dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::extract_chit_ops: called\n";

    ptr <Dbt> d = New refcounted<Dbt >;
    str key = strbuf() << "INFO_CID:" << dv.id;
    
    if (!get_unique_from_cache(filesDb, key, key.len(), d)) {
	return;
    }
    
    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::extract_chit_ops cache hit :) "
		     << dv.id << "\n";
    
    ptr<vec<struct offset_info > > oi = New refcounted<vec<struct offset_info > >;
    cid_bdb_info c;
    rpc_bytes<> value;
    value.set((char *)d->get_data(), d->get_size());
    bytes2xdr(c, value);
    
    if (c.type != INFO_CID) {
	dwarn(DEBUG_XDISK) << "Info is " << c.type << " " << INFO_CID << "\n";
	return;
    }
	
    dwarn(DEBUG_XDISK) << "Info is " << c.info.path << " and " <<
	c.info.offset << "\n";
    
    oi->push_back(c.info);
    
    if (oi->size() <= 0) {
	dwarn(DEBUG_XDISK) << "No info although HIT\n";
	return;
    }
    
    if (dv.id != c.desc.id)
	fatal << "Something wrong here!!\n";
    
    create_chitop(dv.id, oi, c.desc.length, this);
}


void
xferPlugin_xdisk::xp_get_ops(str key, dot_descriptor d)
{
    if (!key) {
	dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::checking for cache op called\n";
	extract_chit_op(d);
	return;
    }
    
    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::checking for other ops called\n";

    ht_entry *hte = mat.hint_store[key];
    if (!hte)
	fatal << "What happened to hints\n";
	
    /* 1. extract
       disk hints from unique hint object to insert new operations */
    size_t hsize =  hte->oidhint->size();
    for (size_t i = 0; i < hsize; i++) {
	hint_res res;
	if (parse_hint((*(hte->oidhint))[i].name, "xdisk", &res) < 0) {
	    //warnx << "xferPlugin_xdisk::update_table: " << i << ":"
	    //    << i << " Not xdisk hint\n";
	    continue;
	}
	hte->hints->push_back(res.hint1);

	vec<const char *> *spl_path = New vec<const char *>;
	char *ptr = strdup(res.hint1.target_dir);
	split_path(ptr, spl_path);
		
	hte->spl_hints->push_back(spl_path);
	hte->sp_ptr->push_back(ptr);
	
	/*extract ignore_strings*/
	extract_ignore_str(res.hint1.ignore_str);
	if (res.hint1.ignore_path != "NONE")
	    extract_ignore_str(res.hint1.ignore_path);
    }

    hsize =  hte->hints->size();
    for (size_t i = 0; i < hsize; i++) {
	/*extract target directory and its various levels
	  to make stat ops out of it*/
	extract_stat_ops((*(hte->hints))[i].target_dir);
    }
}


tamed void
xferPlugin_xdisk::perform_offset_read(str path, int offset, int len, cbs cb)
{
    tvars {
	str err;
	bool async;
	ptr<ioh > handle;
	ptr<suio> new_one;
	int remain;
	int ret;
	ptr<desc_result> res;
	ptr<dot_descriptor> new_dd;
	unsigned int rsize;
    }

    async = true;
    //async = false;

    if (async)
	handle = New refcounted<aioh >(aiod_ptr);
    else
	handle = New refcounted<sioh >;

    twait {
	handle->open(path, O_RDONLY, mkevent (err));
    }

    dwarn(DEBUG_XDISK) << "Performing offset open " << path << "\n";
    
    if (err) {
	(*cb)(err);
	return;
    }
    
    twait {
	handle->seek(offset, mkevent (err));
    }

    dwarn(DEBUG_XDISK) << "Performing offset seek\n";

    if (err) {
	(*cb)(err);
	return;
    }
    
    warn << "xferPlugin_xdisk::perform_offset_read: asking to read " << path 
         << " " << offset << " and length " << len << "\n";

    new_one = New refcounted<suio>;
    remain = len;
    while (remain > 0) {
	rsize = min(AIOD_READ_SIZE, (unsigned int)remain);
	twait {
	    handle->read(new_one, rsize, mkevent (ret));
	}
	
	if (ret < 0)
            break;

	remain = remain - ret;
    } 

    twait {
	 handle->close(mkevent (err));
     }


    dwarn(DEBUG_XDISK) << "Performing offset finished read\n";
    
    if (err) {
	(*cb)(err);
	return;
    }
    
    //check for hash
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_MD_CTX desc_hash;
    unsigned int diglen;

    EVP_MD_CTX_init(&desc_hash);
    EVP_DigestInit(&desc_hash, EVP_sha1());

    for (const iovec *i = new_one->iov(); i < new_one->iovlim(); i++) {
	EVP_DigestUpdate(&desc_hash, i->iov_base, i->iov_len);
    }

    EVP_DigestFinal(&desc_hash, digest, &diglen);
    dot_desc chunkname;
    chunkname.set((char *)digest, diglen);
    
    res = NULL;

    ds_entry *dse = mat.desc_store[chunkname];
    if (dse) { // && dse->status != DELETED) {
	dwarn(DEBUG_XDISK) << "Got a hit ....prepare to transfer "
			 << chunkname << "\n";
	//would like to send the original descriptor came to us
	new_dd = New refcounted<dot_descriptor>(dse->dd);
	res = New refcounted<desc_result> (new_dd, new_one, false);
    }

    if (res){
	(*pending_cb)(NULL, res);
	(*cb)(NULL);
    }
    else {
	warnx << "***Wasted caching " << chunkname << "\n";
        (*cb)("Hash didnt match");
    }
}

tamed void
xferPlugin_xdisk::perform_hash(str path, cbs cb)
{
    tvars {
	str err;
	ptr<dot_oid_md> oid;
    }

    //warn << "Performing chunking of " << path <<"\n";

    twait {
	//get_hash(path, false, mkevent (err, oid));
	get_hash(path, true, mkevent (err, oid));
    }

    if (err) {
	(*cb)(err);
	return;
    }
    
    //cache oid->info mapping
    //dont want it
    if (0) {
	rpc_bytes<> value;
	oid_bdb_info o;
	o.type = INFO_OID;
	o.oid = *(oid);
	o.info.path = path;
	o.info.fd = -1;
	o.info.offset = -1;
	xdr2bytes(value, o);
	dwarn(DEBUG_XDISK) << "Putting oid info\n";
	put_in_cache(filesDb, oid->id.base(), oid->id.size(),
		     value.base(), value.size(), false);
    }
    
    (*cb)(NULL);
}

tamed void
xferPlugin_xdisk::get_hash(str path, bool async, commit_cb cb)
{
    tvars {
	ptr<ioh > handle;
	//ptr to vector of suio ptrs
	ptr<vec<ptr<suio> > > io_in;
	ptr<suio> new_one;
	int rc;
	str err;
	ptr<metadata_entry > mde;
    }
    
    if (async)
	handle = New refcounted<aioh >(aiod_ptr);
    else
	handle = New refcounted<sioh >;

    twait {
	handle->open(path, O_RDONLY, mkevent (err));
    }

    if (err) {
	(*cb)(err, NULL);
	return;
    }

    mde = New refcounted<metadata_entry>;
    mde->module = "LOCAL";
    mde->key = strbuf() << path << ":-1";
        
    cp->init(&handle->sid, mde);
    //buffer between producer and consumer
    io_in = New refcounted<vec<ptr<suio> > >; 

    //warnx << "xferPlugin_xdisk::get_hash: file opened\n";
    
    while (1) {

	new_one = New refcounted<suio>;

	dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::get_hash: asking to read\n";
	
	twait {
	    handle->read(new_one, AIOD_READ_SIZE, mkevent (rc));
	}
	
	if (rc == -1) {
	    str s = "Could not read from input file descriptor\n";
	    (*cb)(s, NULL);
	    return;
	}
	else if (rc == 0) {
	    twait {
		handle->close(mkevent (err));
	    }
	    //warnx << "xferPlugin_xdisk::get_hash: done reading\n";
	    get_hash_done(handle, cb);
	    return;
	}
	else {
	    dwarn(DEBUG_XDISK) << "xferPlugin_xdisk::get_hash: reading new chunk\n";
	    if (io_in->size() <= 0) { //trigger the consumer
		io_in->push_back(new_one);
		signal_chunker(handle, io_in, cb);
	    }
	    else
		io_in->push_back(new_one);
	}
    }
}

void
xferPlugin_xdisk::signal_chunker(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in, commit_cb cb)
{
    //warnx << "xferPlugin_xdisk::signal_chunker: signaling chunker\n";
    delaycb(0, 0, wrap(this, &xferPlugin_xdisk::perform_chunk, handle, io_in, cb));
}

//not tamed because delaycb above cant wrap a tamed function
void
xferPlugin_xdisk::perform_chunk(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in, commit_cb cb)
{
    char inbuf[AIOD_READ_SIZE];
    ptr<suio> new_one = (*io_in)[0];
    size_t nbytes = new_one->resid();

    //warnx << "xferPlugin_xdisk::perform_chunk: chunking\n";
    size_t ncopied = new_one->copyout(inbuf, nbytes);
    assert(ncopied == nbytes);
    new_one->rembytes(ncopied);
    handle->pending++;
    cp->put_object(handle->sid, inbuf, nbytes,
		   wrap(this, &xferPlugin_xdisk::perform_chunk_cb, handle, io_in, cb));
}

void
xferPlugin_xdisk::perform_chunk_cb(ptr<ioh > handle, ptr<vec<ptr<suio> > > io_in,
				   commit_cb cb, str s)
{
    if (s) {
	warn << "Message from put_chunk is " << s << " \n";
	return;
    }

    //warnx << "xferPlugin_xdisk::perform_chunk_cb: chunked\n";
    
    io_in->pop_front();
    handle->pending--;
    
    if (io_in->size() <= 0) 
	get_hash_done(handle, cb);
    else
	perform_chunk(handle, io_in, cb);
}

tamed void
xferPlugin_xdisk::get_hash_done(ptr<ioh > handle, commit_cb cb)
{
    tvars {
	str s;
	ptr<dot_oid_md> oid;
    }
    
    if (handle->fd == -1 && handle->pending <= 0) {

	//warnx << "xferPlugin_xdisk::get_hash_done: to commit\n";
	
	twait {
	    cp->commit_object(handle->sid, mkevent (s, oid));
	}
	    
	if (s) {
	    warn << "Error in put_commit - " << s << "\n";
	    (*cb)(s, NULL);
	    return;
	} 
	
	//warn << "Plugin says that the oid is " << oid->id << "\n";
	//for (size_t i = 0; i < oid->md.list.size(); i++)
	//  warn << "  " << oid->md.list[i].module << "."
	// << oid->md.list[i].key << " = "
	// << oid->md.list[i].val << "\n";
	
	(*cb)(NULL, oid);
    }
}

tamed void
xferPlugin_xdisk::perform_stat(str path, ptr<vec<struct item_info> > stats, cbs cb)
{
    tvars {
        str err;
	ptr<vec<str> > entries;
    }

    //warnx << "perform_stat called\n";
    
    entries = New refcounted<vec<str> >;
    twait {
        //get_list(path, entries, false, mkevent (err));
	get_list(path, entries, true, mkevent (err));
    }

    if (err) {
	(*cb)(err);
	return;
    }
    
    //warnx << "get_list came back\n";
    //for (size_t i = 0; i < entries->size(); i++) {
    //warnx << (*entries)[i] << "\n";
    //}

    for (size_t i = 0; i < entries->size(); i++) {
	struct item_info item;
	item.name = (*entries)[i];
	stats->push_back(item);
    }
    
    twait {
	get_stats(path, stats, true, mkevent (err));
    }

    if (err) {
	(*cb)(err);
	return;
    }
    //warnx << "get_stats came back for " << path << "\n";
    //cache the list in a cache
    //for (size_t i = 0; i < stats->size(); i++) {
    //	warnx << (*stats)[i].name << " " << (*stats)[i].s.st_size << "\n";
    //}

    //return
    if (err)
        (*cb)(err);
    else
        (*cb)(NULL);
}

tamed void
xferPlugin_xdisk::get_list(str path, ptr<vec<str> > res, bool async, cbs cb)
{
    tvars {
	ptr<ioh > handle;
	str err;
	bool rem;
	struct dirent entry;
	str name;
    }
    
    if (async)
	handle = New refcounted<aioh >(aiod_ptr);
    else
	handle = New refcounted<sioh >;
    
    twait {
	handle->opendir(path, mkevent (err));
    }

    if (err) {
	(*cb)(err);
	return;
    }

    rem = true;
    while (rem) {
	twait {
	    handle->readdir(&entry, mkevent (rem, err));
	}
	
	if (err) {
	    (*cb)(err);
	    return;
	}

	if (rem) {
	    name = entry.d_name;
	    if (name != "." && name != "..")
		res->push_back(name);
	}
    }

    twait {
	handle->closedir(mkevent (err));
    }
    
    if (err)
        (*cb)(err);
    else
	(*cb)(NULL);
}

tamed void
xferPlugin_xdisk::get_stats(str path, ptr<vec<struct item_info> > res, bool async, cbs cb)
{
    tvars {
	ptr<ioh > handle;
	str err;
	bool err_flag;
	str name;
    }
    
    if (async)
	handle = New refcounted<aioh >(aiod_ptr);
    else
	handle = New refcounted<sioh >;

    err_flag = false;
    
    twait {
	for (size_t i = 0; i < res->size(); i++) {
	    name = strbuf() << path << "/" << (*res)[i].name;
	    handle->stat(name, &((*res)[i].s), mkevent (err));
	    if (err && !err_flag)
		err_flag = true;
	}
    }
    
    if (err_flag)
        (*cb)("Error in Statting");
    else
	(*cb)(NULL);
}

/*************************************/
/* Storage plugin interface */

struct xid_cache_entry {
    const dot_sId id;
    ref<vec<dot_descriptor> > dv;
    EVP_MD_CTX hash;

    ihash_entry<xid_cache_entry> hlink;

    xid_cache_entry (const dot_sId id);
    ~xid_cache_entry ();
};

static ihash<const dot_sId, xid_cache_entry, &xid_cache_entry::id, 
	     &xid_cache_entry::hlink> tempCache;


xid_cache_entry::xid_cache_entry(const dot_sId sid)
    : id(sid), dv(New refcounted<vec<dot_descriptor> >)
{
    tempCache.insert(this);

    EVP_MD_CTX_init(&hash);
    EVP_DigestInit(&hash, EVP_sha1());
}

xid_cache_entry::~xid_cache_entry()
{
    tempCache.remove(this);
}

bool
xferPlugin_xdisk::init(dot_sId id)
{
    //warn << "xferPlugin_xdisk::init called\n";
    
    xid_cache_entry *sce = tempCache[id];
    if (sce) {
        warn("xferPlugin_xdisk received duplicate ID: %d\n", id);
        return false;
    }
    sce = New xid_cache_entry(id);
    return true;
}

void
xferPlugin_xdisk::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb, ptr<closure_t>)
{
    xid_cache_entry *sce = tempCache[id];
    ptr<vec<unsigned int> > iv;
    ptr<desc_result> res = NULL;
    ptr<dot_descriptor> new_dd;
     
    if (!sce) {
        (*cb)("Incorrect transfer ID");
        return;
    }

    // Hash for whole object
    EVP_DigestUpdate(&sce->hash, buf, len);

    //caching cid -> file mapping
    {
	struct offset_info info;
	extract_offset_info(d, &info);
	cid_bdb_info c;
	c.type = INFO_CID;
	c.desc = (*d);
	c.info = info;

	dwarn(DEBUG_XDISK) << "Info is " << c.info.path << " and " <<
	    c.info.offset << "\n";
	
	rpc_bytes<> value;
	xdr2bytes(value, c);
	dwarn(DEBUG_XDISK) << "Putting in cache " << d->id << "\n";
	str key = strbuf() << "INFO_CID:" << d->id;
	put_in_cache(filesDb, key.cstr(), key.len(),
		     value.base(), value.size(), true);
	//put_in_cache(filesDb, d->id.base(), d->id.size(),
    }


    ds_entry *dse = mat.desc_store[d->id];

    ptr<suio> data = New refcounted<suio>;
    data->copy(buf, len);
    if (dse) //would like to send the original descriptor came to us
	new_dd = New refcounted<dot_descriptor>(dse->dd);
    else
	new_dd = New refcounted<dot_descriptor>(*d);
	
    res = New refcounted<desc_result> (new_dd, data, false);
    
    if (dse) {	// && dse->status != DELETED) {
	dwarn(DEBUG_XDISK) << "Got a hit ....prepare to transfer " << d->id << "\n";
	assert(res);
	(*pending_cb)(NULL, res);
    }
    else
	m->sp->put_ichunk(res->desc, res->data, true,
			  wrap(this, &xferPlugin_xdisk::put_sp_cb));
    
    sce->dv->push_back(*d);

#ifdef TIME_SERIES
    xdisk_raw_time_bytes += d->length;
#endif
        
    (*cb)(NULL);
}

void
xferPlugin_xdisk::put_sp_cb(str s)
{
    if (s)
        warn << "Message from put_ichunk is " << s << " \n";
}

void
xferPlugin_xdisk::commit_object(dot_sId id, commit_cb cb, ptr<closure_t>) 
{
    xid_cache_entry *sce = tempCache[id];
    if (!sce) {
        (*cb)("Incorrect transfer ID", NULL);
        return;
    }

    unsigned int diglen;
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_DigestFinal(&sce->hash, digest, &diglen);
    dot_oid oo;
    oo.set((char *)digest, diglen);

    ptr<dot_oid_md> oid = New refcounted<dot_oid_md> ();
    oid->id = oo;
    //warn << "xferPlugin_xdisk::commit_object OID is " << oid->id << "\n";
   
    //cache oid->descs mapping
    {
	rpc_bytes<> value;
	oid_desc_bdb_info od;
	od.type = INFO_OID_DESC;
	od.oid = (*oid);
	od.descriptors.setsize(sce->dv->size());
	for (size_t i = 0; i < sce->dv->size(); i++) {
	    od.descriptors[i] = (*(sce->dv))[i];
	}
	xdr2bytes(value, od);
	dwarn(DEBUG_XDISK) << "Putting desc\n";
	str key = strbuf() << "INFO_OID_DESC:" << oid->id;
	put_in_cache(filesDb, key.cstr(), key.len(),
		     value.base(), value.size(), true);
	//put_in_cache(filesDb, oid->id.base(), oid->id.size(),
	//value.base(), value.size(), false);
    } 

    delete sce;
    (*cb)(NULL, oid);
}

/*************************************/
tamed void
sioh::opendir(str path, cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    fp = ::opendir(path);
    
    //warn << "opendir successful\n";
    
    if (!fp)
	(*cb)("Problem in opening directory");
    else
	(*cb)(NULL);
}

tamed void
sioh::readdir(struct dirent *res, cb_bool cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    dirent *dp = ::readdir(fp);
    
    if (dp) {
	memcpy(res, dp, sizeof(dirent)); 
	(*cb)(true, NULL);
    }
    else
	(*cb)(false, NULL);
}

tamed void
sioh::closedir(cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    ::closedir(fp);
    (*cb)(NULL);
}

tamed void
sioh::stat(str name, struct stat *res, cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }

    //warn << "Statting " << name << "\n";
    
    struct stat s;
    ::stat(name, &s);
    
    //warn << "stat successful\n";
    
    memcpy(res, &s, sizeof(struct stat));
    (*cb)(NULL);
}

tamed void
sioh::open(str path, mode_t mode, cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    fd = ::open(path, mode);
    
    if (fd == -1)
	(*cb)("Problem in opening file");
    else
	(*cb)(NULL);
}

tamed void
sioh::read(ptr<suio> io_in, int size, cb_int cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    twait {
	fdcb(fd, selread, mkevent ());
    }
    fdcb(fd, selread, NULL);
    int rc = io_in->input(fd, size);
    (*cb)(rc);
}

tamed void
sioh::close(cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    fdcb(fd, selread, NULL);
    ::close(fd);
    fd = -1;

    (*cb)(NULL);
}

tamed void
sioh::seek(int offset, cbs cb)
{
    twait { delaycb(0, 0, mkevent ()); }
    
    if (lseek(fd, offset, SEEK_SET) != offset) {
        (*cb)("Seek failed\n");
    }
    
    (*cb)(NULL);
}

tamed void
aioh::check_pressure(cbv cb)
{
    dwarn(DEBUG_XDISK) << "Asking for permit\n";

    while (pressure_from_client() || pressure_from_network()) {
	pressure_aiod++;
	twait {
	    delaycb(0, 1000000, mkevent ()); //1ms
	}
    }

    dwarn(DEBUG_XDISK) << "Go ahead with op\n";
    if (!abort_flag) 
       (*cb)();
    else 
	warn << "Aborting disk op NOW\n";
}

tamed void
aioh::opendir(str path, cbs cb)
{
    tvars {
	int err;
    }
    
    if ((buf = a->bufalloc(sizeof(dirent))) == NULL) {
	dwarn(DEBUG_XDISK) << "buf not there\n";
	twait {
	    a->bufwait(mkevent ());
	}
	buf = a->bufalloc(sizeof(dirent));
    }

    //check if there is pressure
    twait{
	check_pressure(mkevent ());
    }
    
    twait {
	a->opendir(path, mkevent (fh, err));
    }
    
    if (!fh) {
	warn("opendir: %s\n", strerror(err));
	(*cb)("Problem in opening directory");
    }
    else {
	//warn << "Opendir successful\n";
	(*cb)(NULL);
    }
}

tamed void
aioh::readdir(struct dirent *res, cb_bool cb)
{
    tvars {
	ssize_t len;
	int err;
    }
    
    //check if there is pressure
    twait{
	check_pressure(mkevent());
    }
    
    twait {
	fh->readdir(buf, mkevent (buf, len, err));
    }
    
    if (err) {
	warn("readdir %s\n", strerror (err));
	(*cb)(false, "Problem in reading");
    }
    else {
	//warn << "Readdir successful\n";
	if (len == 0) {
	    (*cb)(false, NULL);
	}
	else {
	    dirent *dp = (dirent *) buf->base();
	    memcpy(res, dp, sizeof(dirent)); 
	    //warn << "Entry --> " << dp->d_name << "\n";
	    (*cb)(true, NULL);
	}
    }
}

tamed void
aioh::closedir(cbs cb)
{
    tvars {
	int err;
    }

    twait {
	fh->closedir(mkevent (err));
    }

    if (err) {
	warn("close %s\n", strerror (err));
	(*cb)("Problem in closing directory");
    }
    else {
	//warn << "Close successful\n";
	(*cb)(NULL);
    }
}

tamed void
aioh::stat(str name, struct stat *res, cbs cb)
{
    tvars {
	int err;
	struct stat *s;
    }

    //check if there is pressure
    twait{
	check_pressure(mkevent());
    }

    //warn << "Statting " << name << "\n";
    twait {
	a->stat(name, mkevent (s, err));
    }

    if (err)
	(*cb)("async stat failed");
    else {
	//warn << "stat successful\n";
	memcpy(res, s, sizeof(struct stat));
	(*cb)(NULL);
    }
}

tamed void
aioh::open(str path, mode_t mode, cbs cb)
{
    tvars {
	int err;
    }

    //check if there is pressure
    twait{
	check_pressure(mkevent());
    }
    
    twait {
	a->open(path, mode, 066, mkevent (fh, err));
    }
    
    if (!fh) {
	fd = -1;
	warn("open: %s\n", strerror(err));
	(*cb)("Problem in opening file");
    }
    else {
	fd = 1; //success
	(*cb)(NULL);
    }
}

tamed void
aioh::read(ptr<suio> io_in, int size, cb_int cb)
{
    tvars {
	ssize_t len;
	int err;
    }

    buf = NULL;
    buf = a->bufalloc(size);
    if (!buf) {
	dwarn(DEBUG_XDISK) << "aioh::read waiting on buf\n";
	twait {
	    a->bufwait(mkevent ());
	}
	buf = a->bufalloc(size);
	if (!buf)
	    fatal << "Failed bufalloc of " << size << "bytes in aioh!\n";
    }

    //check if there is pressure
    twait{
	check_pressure(mkevent());
    }
    
    //warnx << "aioh::read Got buf\n";
    twait {
	fh->read(pos, buf, mkevent (buf, len, err));
    }
    
    if (err) {
	warn("readdir %s\n", strerror (err));
	(*cb)(-1);
    }
    else {
	pos += len;
	io_in->copy(buf->base(), len);
	(*cb)(len);
    }
}

tamed void
aioh::close(cbs cb)
{
    tvars {
	int err;
    }

    twait {
	fh->close(mkevent (err));
    }

    fd = -1;
    
    if (err) {
	warn("close %s\n", strerror (err));
	(*cb)("Problem in closing file");
    }
    else {
	(*cb)(NULL);
    }
}

tamed void
aioh::seek(int offset, cbs cb)
{
    pos = offset;
    (*cb)(NULL);
}

/* TODO
1. aiod->finalize in destructor

2. the deal with updatetime right now statcache gets update from list cache
i could use stat errors to invalidate caches
update time business

3. tamed version for perform_hash that doesnt compile

//   while (1) {
	
// 	twait {
// 	    fdcb(in_fd, selread, mkevent ());
// 	}
	
//        	rc = io_in.input(in_fd, CHUNK_SIZE);
// 	if (rc == -1) {
// 	    (*cb)("Could not read from input file descriptor\n");
// 	    return;
// 	}
// 	else if (rc == 0) {
// 	    fdcb(in_fd, selread, NULL);
// 	    break;
// 	}
// 	else {
// 	    nbytes = io_in.resid();
// 	    rc = io_in.copyout(inbuf, nbytes);
// 	    assert(rc == nbytes);
// 	    io_in.rembytes(rc);

	    
// 	    twait {
// 		m->cp->put_object(id, inbuf, nbytes, mkevent (err));
// 	    }
// 	}
//     }

//     twait {
// 	m->cp->commit_object(id, mkevent (err, oid));
//     }

4. list and stat on a file and not on dir

5. when chunks are shared across files - dicey

6. update_table --> for already existing descriptors if
xdisk hints are repeated, then they are inserted again

broekn BFS--> not putting in cache ops
*/
