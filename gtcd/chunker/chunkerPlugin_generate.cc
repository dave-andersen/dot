/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "chunkerPlugin_generate.h"
#include <openssl/evp.h>

struct cgid_cache_entry {
    const dot_sId id;
    suio data;

    ihash_entry<cgid_cache_entry> hlink;

    cgid_cache_entry (const dot_sId id);
    ~cgid_cache_entry ();
};

static ihash<const dot_sId, cgid_cache_entry, &cgid_cache_entry::id,
	     &cgid_cache_entry::hlink> tempCache;

void 
chunkerPlugin_generate::get_pseudo_data(str hash_val, char *buf, int size)
{
    ctx.reset();
    ctx.setkey(hash_val, hash_val.len());
      
    for (int i = 0; i < size ; i++) {
      	u_char c = ctx.getbyte();
	buf[i] = c;
    }
}

void
chunkerPlugin_generate::name_chunk(dot_sId id_in, const char *buf, size_t len)
{
    cgid_cache_entry *sce = tempCache[id_in];
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_MD_CTX desc_hash;
    unsigned int diglen;
    strbuf chunkname;

    EVP_MD_CTX_init(&desc_hash);
    EVP_DigestInit(&desc_hash, EVP_sha1());
    EVP_DigestUpdate(&desc_hash, buf, len);
    EVP_DigestFinal(&desc_hash, digest, &diglen);
    chunkname << hexdump(digest, diglen);

    ref<dot_descriptor> dd = New refcounted<dot_descriptor>();
    dd->id = chunkname;
    dd->length = len;

    sp->put_chunk(sce->id, dd, buf, len, cb_null);
}

void
chunkerPlugin_generate::commit_object(dot_sId id, commit_cb cb)
{
    warn <<"chunkerPlugin_generate::commit_object called\n";

    cgid_cache_entry *sce = tempCache[id];
    if (!sce) {
        (*cb)("Incorrect transfer ID", NULL);
        return;
    }

    //interpret the data as lines of hash and size
    if(sce->data.resid() <= 0) {
      warn << "No data accumulated\n";
      (*cb)("No data accumulated",NULL);
      return;
    }
    
    //read the file data into buf
    char *sbuf = New char[sce->data.resid()+1];
    bzero(sbuf, sce->data.resid());
    sce->data.copyout(sbuf, sce->data.resid());
    sbuf[sce->data.resid()] = '\0';

    //warn << "File is \n";
    //warn << sbuf <<"\n";

    char *line, *element, *brkt, *brkb;

    for (line = strtok_r(sbuf, "\n", &brkt);  
	 line; line = strtok_r(NULL, "\n", &brkt)) {
	
	//warn << "Line is " << line <<"\n";
	
	//char *temp = New char[strlen(line)+1];
	//memcpy(temp, line, strlen(line)+1];
	//warn << "dup --> " << temp <<"\n";

	int count = 0;
	str hash_val;
	unsigned int size = 0;

	for (element = strtok_r(line, " ", &brkb);
	     element; element = strtok_r(NULL, " ", &brkb)) {
	    
	    if (count == 0) {
		str t(element, strlen(element));
		hash_val = t;
		warn << "Hash is " << hash_val <<"\n";
	    }
	    else if (count == 1) {
		size = atoi(element);
		warn << "Size is " << size <<"\n";
	    }
	    else {
		warn << element <<"\n";
		fatal << "chunkerPlugin_generate::commit_object: More than 2 tokens in line ...check \n";
	    }
	    
	    count++;
	}
	
	if(size <= 0)
	    fatal << "chunkerPlugin_generate::commit_object: didn't get chunk size\n";
	
	char inbuf[size];
	bzero(inbuf, sizeof(inbuf));
	
	get_pseudo_data(hash_val, inbuf, size);
	
	name_chunk(id, inbuf, size);
    }
    
    delete[] sbuf;
    
    return sp->commit_object(id, cb);
}

bool
chunkerPlugin_generate::init(dot_sId *id_out, ptr<metadata_entry > mde)
{
  warn << "chunkerPlugin_generate::init called\n";

    dot_sId curr = id_next;
  
    while(tempCache[++id_next] && id_next != curr);

    cgid_cache_entry *sce = tempCache[id_next];
    if (sce) {
        warn("Unable to find free slots\n");
        return false;
    }
    sce = New cgid_cache_entry(id_next);
    *id_out = id_next;

    sp->init(id_next);

    return true;
}

void
chunkerPlugin_generate::put_object(dot_sId id, const void *buf, size_t len, cbs cb)
{
  warn << "chunkerPlugin_generate::put_object called\n";

    cgid_cache_entry *sce = tempCache[id];

    if (!sce) {
        (*cb)("Incorrect transfer ID");
        return;
    }

    sce->data.copy(buf, len);

    (*cb)(NULL);
}

cgid_cache_entry::cgid_cache_entry(const dot_sId sid) : id(sid)
{
    tempCache.insert(this);

}

cgid_cache_entry::~cgid_cache_entry()
{
    tempCache.remove(this);
}

