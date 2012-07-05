/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "storagePlugin_sset.h"
#include "parseopt.h"

static ihash<const dot_sId, net_cache_entry, &net_cache_entry::id, &net_cache_entry::hlink> tempCache;

int odht_port = DEFAULT_DHT_PORT;
str odht_ip = NULL;

net_cache_entry::net_cache_entry(const dot_sId sid, gtcd *min)
    : id(sid), m(min), slist(New refcounted<ordered_descriptor_list>),
    list(NULL), hint(NULL), shingles_done(0), oidstatus(NULL),
    oid_done(false)
{
    tempCache.insert(this);
}

net_cache_entry::~net_cache_entry()
{
    warn << "Delete for oid " << oid << "\n";
    tempCache.remove(this);
}

void
net_cache_entry::net_insert()
{
    if (!hint) {
	hint = New refcounted<vec<oid_hint> >;
	m->sep->get_default_hint(hint);
    }
    
    warn << debug_sep
	 << "net_cache_entry::net_insert: came to insert all shingles for "
	 << oid << "\n";
    
    // Output items in priority_queue using top()
    // and use pop() to get to next item until
    // priority_queue is empty
    shingles_done = 0;
    oid_done = false;
    if (!list) {
	list = New refcounted<vec<dot_desc> >;
	while (!slist->empty()) {
	    dot_desc ds = slist->top();
	    list->push_back(ds);
	    slist->pop();
	    ref<dht_rpc> dht = New refcounted<odht_rpc>(odht_ip, odht_port, m);
	    status.push_back(dht);
	}
    }

    unsigned int size = list->size();
    for (unsigned int i = 0; i < size; i++) {
	dot_desc ds = (*list)[i];
	dwarn(DEBUG_SET) << "Inserting shingle " << shingles_done << " " << ds << "\n";
	put_fp_to_oid(status[i], ds, oid, wrap(this, &net_cache_entry::put_fp_to_oid_done));
	shingles_done++;
    }

    dwarn(DEBUG_SET) << "Inserting object id " << oid << "\n";
    if (!oidstatus)
	oidstatus = New refcounted<odht_rpc>(odht_ip, odht_port, m);
    put_oid_source(oidstatus, oid, (*hint)[0],
		   wrap(this, &net_cache_entry::put_oid_source_done));

    dwarn(DEBUG_SET) << "Inserted " << shingles_done << " shingles\n" << debug_sep;
}

void
net_cache_entry::put_fp_to_oid_done(str err)
{
    shingles_done--;

    if (err)
	warn << "Shingle status:: err\n";
    else
	dwarn(DEBUG_SET) << "Shingle status:: success\n";
        
    if (shingles_done <= 0 && oid_done) {
	
	dwarn(DEBUG_SET) << "All shingle and oid calls returned \n";
		
	//now i kill myself, since the refs to dht_rpc objects go away,
	//they should be garbage collected too
	//delete this;
	//refresh the put
	delaycb((int)(0.75*OPENDHT_TTL), 0,
		wrap(this, &net_cache_entry::net_insert));
    }
}

void
net_cache_entry::put_oid_source_done(str err)
{
    oid_done = true;

    if (err)
	warn << "Oid status:: err\n";
    else
	dwarn(DEBUG_SET) << "Oid status:: success\n";
    
    if (shingles_done <= 0 && oid_done) {
	
	warn << "All shingle and oid calls returned \n";
	
	//now i kill myself, since the refs to dht_rpc objects go away,
	//they should be garbage collected too
	//delete this;
	//refresh the put
	delaycb((int)(0.75*OPENDHT_TTL), 0,
		wrap(this, &net_cache_entry::net_insert));
    }
}

bool 
storagePlugin_sset::init(dot_sId id)
{
    warn << "storagePlugin_sset:: DHT plugin initiated\n";
    
    net_cache_entry *sce = tempCache[id];
    if (sce) {
	warn("storagePlugin_sset received duplicate ID: %d\n", id);
	sp->init(id);
	return (false);
    }

    sce = New net_cache_entry(id, m);

    return(sp->init(id));
}


tamed void
storagePlugin_sset::put_chunk(dot_sId id, ref<dot_descriptor> d,
                              const char *buf, int len, cbs cb)
{
    tvars { str err; str err1; net_cache_entry *sce; }
  
    //warn << "storagePlugin_sset::put_chunk: called\n";
    
    sce = tempCache[id];
    if (!sce) {
	err1 = "Incorrect transfer ID";
	warn << err1 << "\n";
    }
    else {
	//Maintain NUM_SHINGLES ordered hashes
	int size_q = sce->slist->size();
	
	//warn << "storagePlugin_sset::put_chunk: accumulated " << size_q << " shingles\n";
	if (size_q > NUM_SHINGLES - 1) {
	    //warn << "pushing " << d->id << " of length " << d->length << "\n";
	    sce->slist->push(d->id);
	    //warn << "popping " << sce->slist->top() << "\n";
	    sce->slist->pop();
	}
	else {
	    //warn << "pushing " << d->id << " of length " << d->length << "\n";
	    sce->slist->push(d->id);
	}
	err1 = NULL;
    }
  
    twait {
	sp->put_chunk(id, d, buf, len, mkevent (err));
    }

    if (err)
	warn << "storagePlugin_sset::put_chunk: Error message from child: "
	     << err << "\n";
    
    (*cb)(err1);
}

tamed void
storagePlugin_sset::commit_object(dot_sId id, commit_cb cb)
{
    tvars {
        str err;
        ptr<dot_oid_md> oid;
	net_cache_entry *sce;
    }

    //warn << "storagePlugin_sset::commit_object: called\n";
    
    twait {
        sp->commit_object(id, mkevent (err, oid));
    }

    if (err)
	warn << "storagePlugin_sset::commit_object: Error message from child: "
	     << err << "\n";
    
    //do something with shingles now
    sce = tempCache[id];
    if (!sce) {
	warn << "Incorrect transfer ID \n";
	err = "Incorrect transfer ID";
    }
    else {
	//set the oid
	//warn("OID is %s\n", oid->id.cstr());
	sce->oid = oid->id;
	delaycb(0, 0, wrap(sce, &net_cache_entry::net_insert));
    }
    
    //warn << "storagePlugin_sset::commit_object: making callback\n";
    (*cb)(err, oid);
}

tamed void
storagePlugin_sset::get_descriptors_init(ref<dot_oid_md> oid, oid_cb cb)
{
    //warnx << "storagePlugin_sset::get_descriptors_init: called\n";

    tvars {
	str err;
	ptr<dot_oid_md> o;
    }
  
    twait {
      sp->get_descriptors_init(oid, mkevent (err, o));
    }
  
    if (err) {
	warnx << "storagePlugin_sset::get_descriptors_init: Error message from child: "
	     << err << "\n";
    }
    else {
	//warnx << "storagePlugin_sset::get_descriptors_init: Child returned successfully.\n";
	metadata_entry e;
	e.module = "NET";
	e.key = "oid++_key0";
	e.val = "oid++_val0";
	o->md.list.push_back(e);
    }
    
    (*cb)(err, o);
}

tamed void
storagePlugin_sset::sp_get_descriptors(ref<dot_oid_md> oid, descriptors_cb cb)
{
    sp->sp_get_descriptors(oid, cb);
}

tamed void
storagePlugin_sset::put_ichunk(ref<dot_descriptor> d, ref<suio> uiop,
                               bool retain, cbs cb)
{
    sp->put_ichunk(d, uiop, retain, cb);
}

tamed void
storagePlugin_sset::get_chunk_init(ref<dot_descriptor> d, descriptor_cb cb)
{
    tvars {
        str err;
        ptr<dot_descriptor> desc;
    }

    twait {
        sp->get_chunk_init(d, mkevent (err, desc));
    }
    
    if (err) {
        warn << "storagePlugin_sset::get_chunk_init: Error message from child: "
	     << err << "\n";
    }
    else {
        warn << "storagePlugin_sset::get_chunk_init: Child returned successfully.\n";
        metadata_entry e;
        e.module = "NET";
        e.key = "dl++_key0";
        e.val = "dl++_val0";
        desc->md.list.push_back(e);
    }

    (*cb)(err, desc);
}

tamed void
storagePlugin_sset::get_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    sp->get_chunk(d, cb);
}

tamed void
storagePlugin_sset::sp_get_chunks(ref< vec<dot_descriptor> > dv, chunk_cb cb)
{
    sp->sp_get_chunks(dv, cb);
}

bool
storagePlugin_sset::configure(str s, str pluginClass)
{
    int portnum;
    str addr;
    char *hn = NULL;
    char *name = NULL;
    
    if (s && s != "") {
	name = strdup(s.cstr());
	if ((hn = strchr(name, ' '))) {
	    *hn++ = '\0';
	    addr.setbuf(name, strlen(name));
	    portnum = atoi(hn);
	    
	    odht_port = portnum;
	    odht_ip = addr;
	    
	    warn << "Setting " << odht_port << " " << odht_ip << "\n";
	    return true;
	}
    }

    assert(!odht_ip);
    odht_ip = get_odht_ip();
    if (!odht_ip) {
	fatal << "No odht rendezvous point\n";
    }
    warn << "Setting " << odht_port << " " << odht_ip << "\n";
    return true;
}

void 
storagePlugin_sset::sp_notify_descriptors(ref<dot_oid_md> oid,
				      ptr<vec<dot_descriptor> > descs)
{
    //warn << "storagePlugin_sset::sp_notify_descriptors:: called\n";
    sp->sp_notify_descriptors(oid, descs);
}

tamed void
storagePlugin_sset::sp_get_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    sp->sp_get_bitmap(oid, cb);
}


//TODOBINDU
/*
1. print elements of priority queue without popping -- not necessary
3. if total blocks are less than num_shingles 
4. insert into dht when file is received in get. right now it inserts into dht only when put is called on a file
6. also send port to contact at in put message -- done
7. if same oid is put again, i will put in dht again...since no oid is known -- sheerly transferid based
8. check for errors during insert when to delete sce
10. check references to string in constructor
12. i am using char arrays everywhere is that ok... for example how can i use oid_info directly - xdr2bytes etc


2. what happens if two chunks have the same keys right now
they get inserted into priority queue as separate elements and thus get inserted into the DHT too ****
5. change chunking to rabin ***
9. look at vec and not vector

opendht

11. share same connection to all rpc calls

*/
