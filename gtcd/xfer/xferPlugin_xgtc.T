/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "xferPlugin_xgtc.h"
#include "parseopt.h"

/* Mac OS X ugly hack - adapt to missing header definition.  Poo. */
#ifndef HOST_NAME_MAX
#define HOST_NAME_MAX MAXHOSTNAMELEN
#endif


flow_ctrl_entry::flow_ctrl_entry(oid_hint hint, dot_descriptor d, chunk_cb cb)
    :hint_str(hint.name), hint(hint)
{
    desc_entry *de = New desc_entry(d, cb);
    pending_hash.insert(de);
    pending_queue.insert_tail(de);
    bytes_desired = 0;
    bytes_outstanding = 0;
    last_qlen_uptime = return_time(SECONDS);
    start_time = return_time(SECONDS);
    rtt = 0;

    desc_entry *curr_entry = pending_queue.first;
    for (int i = 0; i < (int) NUM_ALLOWED_REQS && curr_entry; i++,
	     curr_entry = pending_queue.next(curr_entry)) {
        bytes_desired += (curr_entry->d).length;
    }
    
    if (!flow_control)
       bytes_desired = NUM_ALLOWED_REQS * CHUNK_SIZE;
}

static struct timeval start;

xferPlugin_xgtc::xferPlugin_xgtc(gtcd *_m, xferPlugin *next_xp)
    : m(_m)
{
    assert(m);
    if (next_xp)
        fatal << __PRETTY_FUNCTION__ << " next_xp is not NULL\n"
              << "Make sure that this storage plugin comes last\n";
}

bool
xferPlugin_xgtc::configure(str s, str pluginClass)
{
    return true;
}

tamed void
xferPlugin_xgtc::xp_get_descriptors(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			        descriptors_cb cb)
{
    tvars {
	hint_res result;
	rpc_info i;
	rconn_entry *conn;
    }
    
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::xp_get_descriptors: called with oid " << oid->id << "\n";
    if (parse_hint((*hints)[0].name, "gtc", &result) < 0)
	fatal << "No hints to get descriptors from\n";

    i.ip = result.hint.hostname;
    i.port = result.hint.port;
    i.stream = AXPRT_STREAM;
    i.program = &xfergtc_program_1;
    i.canq = false;

    twait {
	m->rpcCache->connect(i, mkevent(conn));
    }

    if (!conn) {
	(*cb)("could not connect to remote host", NULL, true);
        return;
    }

    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::xp_get_descriptors: calling get_descriptors_int with oid " << oid->id << "\n";
    gettimeofday(&start, NULL);
    get_descriptors_int(oid, 0, cb, conn);
}

void xferPlugin_xgtc::get_descriptors_int(ref<dot_oid_md> oid, int offset, 
                                         descriptors_cb cb, rconn_entry *conn)
{
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_descriptors_int: called with oid " << oid->id << "\n";
    xfergtc_get_descriptors_arg darg;
    ref<xfergtc_get_descriptors_res> dres = 
        New refcounted<xfergtc_get_descriptors_res>;
    darg.oid = *oid;
    darg.offset = offset;
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_descriptors_int: calling XFERGTC_PROC_GET_DESCRIPTORS with oid " << oid->id << "\n";
    conn->clnt->call(XFERGTC_PROC_GET_DESCRIPTORS, &darg, dres, 
		     wrap(this, &xferPlugin_xgtc::get_desc_internal_cb, cb, oid, conn, 
			  dres));
}

void
xferPlugin_xgtc::get_desc_internal_cb(descriptors_cb cb, ref<dot_oid_md> oid,
                                     rconn_entry *conn,
                                     ref<xfergtc_get_descriptors_res> res, 
                                     clnt_stat err)
{
    if (err) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ << " XFERGTC_PROC_GET_DESCRIPTORS RPC failure: " 
           << err << "\n";
	conn->release(false);
	(*cb)(sb, NULL, true);
        return;
    }
    if (!res->ok) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ <<" XFERGTC_PROC_GET_DESCRIPTORS returned:\n`" 
           << *res->errmsg << "'\n";
	conn->release(false);
        (*cb)(sb, NULL, true);
        return;
    }
    
    ptr<vec<dot_descriptor> > descptr = New refcounted<vec<dot_descriptor> >;
    descptr->setsize(res->resok->count);

    for (unsigned int i = 0; i < res->resok->count ;i++) {
        (*descptr)[i] = res->resok->descriptors[i];
	// warn << res->resok->descriptors[i].desc << " " << i << "\n";
    }

    if (!res->resok->end) {
	get_descriptors_int(oid, res->resok->count + res->resok->offset, cb,
                            conn);
    }
    else {
	struct timeval tv;
	gettimeofday(&tv, NULL);
	printf("Time to get descs - %.4f\n", timeval_diff(&start, &tv));
	conn->release(false);
    }
    (*cb)(NULL, descptr, res->resok->end);
}

void
xferPlugin_xgtc::xp_get_chunks(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints,
			   chunk_cb cb, ptr<closure_t>)
{
  
  dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::xp_get_chunks called\n";

  // When we want to send chunks in the reverse order from the
  // request, we actually need 'int i' and NOT 'unsigned int i'
  //for (int i = dv->size()-1; i >= 0; i--) {
  vec<oid_hint> hv;
  for (int i = 0; i < (int)hints->size(); i++) {
      flow_ctrl_entry *fc;
      oid_hint hint = (oid_hint)((*(*hints)[i])[0]);
      fc = flow_control_cache[hint.name];
      if (!fc) {
          fc = New flow_ctrl_entry(hint, (*dv)[i], cb);
          flow_control_cache.insert(fc);
	  hv.push_back(fc->hint);
      }
      else {
          desc_entry *de = New desc_entry((*dv)[i], cb);
          fc->pending_hash.insert(de);
          fc->pending_queue.insert_tail(de);
      }
      dwarn(DEBUG_XFER_GTC) << "GET CHUNK " << (*dv)[i].id << "\n";
  }

  bytes_rcvd = 0;
  delaycb(1, 0, wrap(this, &xferPlugin_xgtc::dump_xput));
  
  for (int i = 0; i < (int)hv.size(); i++) {
      get_more_chunks_int(hv[i], true, 1.0e+30); //3rd parameter - a large value
  }
}

long long
xferPlugin_xgtc::get_qspace(str hname)
{
    flow_ctrl_entry *fc = flow_control_cache[hname];
    if (!fc)
	return -1;

    long long rem = fc->bytes_desired - fc->bytes_outstanding;
    if (rem < 0)
	rem = 0;
    if (rem == 0 &&
	!fc->pending_queue.first)
	rem = -1;
    
    return(rem);
}

void
xferPlugin_xgtc::get_more_chunks_int(oid_hint hint, bool bw_token, double rtt)
{
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_more_chunks_int called\n";
    bool max_request = false;
    flow_ctrl_entry *fc = flow_control_cache[hint.name];

    while ((fc->bytes_outstanding < fc->bytes_desired ||
	    fc->bytes_desired <= 0) && fc->pending_queue.first) {

        // Pop the first element from the pending_queue
        desc_entry *de = fc->pending_queue.remove(fc->pending_queue.first);
        fc->pending_hash.remove(de);
        // Insert it into the issue_queue
        fc->issue_queue.insert_tail(de);
        fc->issue_hash.insert(de);

        dot_descriptor desc = de->d;
        ref<dot_descriptor> d = New refcounted<dot_descriptor> ;
        d->id = desc.id;
        d->length = desc.length;
        d->md = desc.md;
        fc->bytes_outstanding += desc.length;

	dwarn(DEBUG_XFER_GTC) << "Outstanding is " << fc->bytes_outstanding << "\n";
        
        if (fc->bytes_outstanding >= fc->bytes_desired) {
            max_request = bw_token;
        }
        
        ref<vec<oid_hint> > hv = New refcounted<vec<oid_hint> > ();
        hv->push_back(hint);
        get_chunk(d, max_request, rtt, hv, de->cb);
        fc->chunk_reqtime.push_back(return_time(SECONDS));
    }
}

bool
xferPlugin_xgtc::get_more_chunks_int(oid_hint hint, ref<dot_descriptor> d, size_t offset,
				     bool bw_token)
{
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_more_chunks_int_2 called\n";
    bool max_request = false;
    flow_ctrl_entry *fc = flow_control_cache[hint.name];
    //fc->bytes_outstanding += (d->length - offset);
    
    if (fc->bytes_outstanding >= fc->bytes_desired) {
	max_request = bw_token;
    }
        
    fc->chunk_reqtime.push_back(return_time(SECONDS));
    return(max_request);
}


tamed void
xferPlugin_xgtc::get_chunk(ref<dot_descriptor> d, bool max_request, double rtt, ref<vec<oid_hint> > hints,
			  callback<void, str, ptr<desc_result> >::ptr cb)
{
    tvars {
	hint_res result;
	rpc_info i;
	rconn_entry *conn;
    }
    
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_chunk called " << d->id << "\n";
    if (parse_hint((*hints)[0].name, "gtc", &result) < 0)
	fatal << "No hints to get chunk from\n";
    
    i.ip = result.hint.hostname;
    i.port = result.hint.port;
    i.stream = AXPRT_STREAM;
    i.program = &xfergtc_program_1;
    i.canq = true;

    twait {
	m->rpcCache->connect(i, mkevent(conn));
    }

    if (!conn) {
	(*cb)("could not connect to remote host", NULL);
        return;
    }
    
    ref<suio> data = New refcounted<suio>;
    get_chunk_int(d, max_request, rtt, cb, 0, data, conn, (*hints)[0]);
}

tamed void
xferPlugin_xgtc::get_chunk_int(ref<dot_descriptor> d, bool max_request, double rtt, chunk_cb cb, size_t offset,
			      ref<suio> data, rconn_entry *conn, oid_hint hint)
{
    tvars {
        xfergtc_get_chunk_arg arg;
        ref<xfergtc_get_chunk_res> res(New refcounted<xfergtc_get_chunk_res>);
        clnt_stat err;
        flow_ctrl_entry *fc;
	//str arg_rtt_str;
	char arg_rtt_str[50];
    }
    
    dwarn(DEBUG_XFER_GTC) << "get_chunk_int called for " << d->id << " and offset "
			  << offset << " from " << hint.name << "\n";
    
    arg.desc = *d;
    arg.offset = offset;
    arg.bw_token = max_request;
    sprintf(arg_rtt_str, "%.5f", rtt);
    arg.rtt = arg_rtt_str;

    twait {
        conn->clnt->call(XFERGTC_PROC_GET_CHUNK, &arg, res, 
			 mkevent(err));
    }

    dwarn(DEBUG_XFER_GTC) << "get_chunk_cb called for " << d->id << " " << d->length << "\n";
    
    if (err) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ <<" XFERGTC_PROC_GET_CHUNK RPC failure: " 
           << err << " from " << conn->key << "\n";
	conn->release(true);
        (*cb)(sb, NULL);
        return;
    }
    if (!res->ok) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ << " XFERGTC_PROC_GET_CHUNK returned:\n`" 
           << *res->errmsg << "'\n";
	conn->release(true);
        (*cb)(sb, NULL);
        return;
    }

    dwarn(DEBUG_XFER_GTC) << "Returned " << res->resok->data.size() << " bytes\n";
    data->copy(res->resok->data.base(), res->resok->data.size());
    
    /* flow control stuff... */
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_chunk_cb: enter flow control stuff\n";
    fc = flow_control_cache[hint.name];
    if (!fc) {
        fatal << "fc is null!\n";
    }
    long wasted = 0;
    long in_front = 0;
    double alpha = 0.2;
    int sock_size = 0;
    
    double current_rtt = return_time(SECONDS) - fc->chunk_reqtime.pop_front();
    fc->rtt = alpha*(current_rtt) + (1.0-alpha)*(fc->rtt);
    //str rtt_str;
    char rtt_str[50];
    sprintf(rtt_str, "%.5f", fc->rtt);
    for (int i = 0; i < (int)res->resok->md.list.size(); i++) {
        metadata_entry &me = res->resok->md.list[i];
        if (me.module == "SEGTC" && me.key == "wasted") {
            wasted = atoi(me.val);
        }
        else if (me.module == "SEGTC" && me.key == "in_front") {
            in_front = atoi(me.val);
        }
	else if (me.module == "SEGTC" && me.key == "sock_size") {
            sock_size = atoi(me.val);
        }
    }

    long rcvd_chunk_size = res->resok->data.size();
    //str cur_time_str, cur_rtt_str;
    char cur_time_str[50], cur_rtt_str[50];
    sprintf(cur_time_str, "%.5f", return_time(SECONDS)- fc->start_time);
    sprintf(cur_rtt_str, "%.5f", current_rtt);
    fc->bytes_outstanding -= rcvd_chunk_size;
    bytes_rcvd += rcvd_chunk_size;

    if (flow_control) {
	if (flow_control_scheme == 1) {
		/* ABS-A */

		long next_chunk_size = (fc->pending_queue.first) ? ((fc->pending_queue.first)->d).length : 0;
		in_front = (long)max((double)(in_front-rcvd_chunk_size), 0.0);

		if (wasted > 0) {
		    fc->bytes_desired += (long)(0.4 * wasted) + 1;
		}
		else {
		    wasted = (long)min((double)(wasted + rcvd_chunk_size), 0.0);
		    fc->bytes_desired = (long)max((fc->bytes_desired + 0.4 * wasted), (double)next_chunk_size);
		}
		if ((return_time(SECONDS) - fc->last_qlen_uptime) > fc->rtt) {
		    if (in_front < 0) {
			    in_front = 0;
		    }
		    fc->bytes_desired = (long)max((fc->bytes_desired - 0.226 * in_front), (double)next_chunk_size);
		    fc->last_qlen_uptime = return_time(SECONDS);
		}

	}
	else if (flow_control_scheme == 2) {
		/* static small 
		 * 2 chunks
		 */
		fc->bytes_desired = 2*16*1024;
	}
	else if (flow_control_scheme == 3) {
		/* static large 
		 * 200 chunks
		 */
		fc->bytes_desired = 200*16*1024;
	}
	else { //(flow_control_scheme == 0 or some junk value)
		/* getsockopt-based solution */

		int rcv_sock_size;
		int sock_size_len = sizeof(int);
		getsockopt(conn->ce->x->getreadfd(), SOL_SOCKET, SO_RCVBUF, &rcv_sock_size, (socklen_t *)&sock_size_len);
		//fc->bytes_desired = min(sock_size, rcv_sock_size);
		fc->bytes_desired = sock_size;
		dwarn(DEBUG_XFER_GTC) << "Send size " << sock_size << " and recv " << rcv_sock_size << "\n";
	}
    }
    else {
    }


    dwarn(DEBUG_XFER_GTC) << "DBGXGTC " << fc->hint.name << " " <<  cur_time_str << " " << wasted << " "
	    << in_front << " " << fc->bytes_desired << " " << cur_rtt_str << " " << fc->bytes_outstanding << "\n";
    int snd_size, rcv_size;
    int sock_size_len = sizeof(int);
    getsockopt((conn->clnt->xprt())->getreadfd(), SOL_SOCKET, SO_RCVBUF, &rcv_size, (socklen_t *)&sock_size_len);
    getsockopt((conn->clnt->xprt())->getreadfd(), SOL_SOCKET, SO_RCVBUF, &snd_size, (socklen_t *)&sock_size_len);
    dwarn(DEBUG_XFER_GTC) << "GSO " << snd_size << "\t" << rcv_size << "\n";

    
    if (res->resok->end) {
#if 0
	dwarn(DEBUG_XFER_GTC) << "Received data of size " << data->resid() << "\n";
	unsigned char digest[EVP_MAX_MD_SIZE];
	EVP_MD_CTX desc_hash;
	unsigned int diglen;

	EVP_MD_CTX_init(&desc_hash);
	EVP_DigestInit(&desc_hash, EVP_sha1());
	char *sbuf = New char[data->resid()];
	data->copyout(sbuf, data->resid());	
	EVP_DigestUpdate(&desc_hash, sbuf, data->resid());
	EVP_DigestFinal(&desc_hash, digest, &diglen);
	dwarn(DEBUG_XFER_GTC) << "Comparing " << d->id << " and " << hexdump((char *)digest, diglen) <<"\n";
	if (memcmp((char *)digest, d->id.base(), diglen)) {
	    strbuf sb;
	    sb << __PRETTY_FUNCTION__ << " XFERGTC_PROC_GET_CHUNK returned invalid data\n";
	    dwarn(DEBUG_XFER_GTC) << sb;
	    conn->release(true);
	    (*cb)(sb, NULL);
	    return;
	}
#endif
	for (int i = 0; i < (int)res->resok->md.list.size(); i++) {
       	    d->md.list.push_back(res->resok->md.list[i]);
	}
	
        ref<desc_result> dres = New refcounted<desc_result> (d, data, false);
        conn->release(true);
        (*cb)(NULL, dres);
	desc_entry *de = fc->issue_hash[d->id];
	if (de) {
	    fc->issue_hash.remove(de);
	    fc->issue_queue.remove(de);
	}
    }
    else {
	max_request = get_more_chunks_int(hint, d, data->resid(), res->resok->bw_token);
        get_chunk_int(d, max_request, current_rtt, cb, data->resid(), data, conn, hint);
    }

    get_more_chunks_int(hint, res->resok->bw_token, current_rtt);
    
    if (!fc->pending_queue.first && fc->bytes_outstanding == 0) {
        dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_chunk_cb: removing fc from flow_control_cache\n";
        flow_control_cache.remove(fc);
    }
    dwarn(DEBUG_XFER_GTC) << "xferPlugin_xgtc::get_chunk_cb: exit flow control stuff\n";
    /* End - Flow control stuff... */
}

tamed void
xferPlugin_xgtc::cancel_chunk(ref<dot_descriptor> d, cancel_cb cb)
{
    tvars {
	ptr<vec<nw_status> > status;
    }

    status = New refcounted<vec<nw_status> >;
    if (cancel_chunk_int(d->id)) {
        status->push_back(CANCELLED);
	dwarn(DEBUG_XFER_GTC) << "CANCEL CHUNK " << d->id << "\n";
    }
    else {
        status->push_back(NOT_CANCELLED);
    }
    (*cb)(status);
}

tamed void
xferPlugin_xgtc::cancel_chunks(ref< vec<dot_descriptor> > dv, cancel_cb cb)
{
    tvars {
	ptr<vec<nw_status> > status;
    }

    status = New refcounted<vec<nw_status> >;

    for (unsigned int i = 0; i < dv->size(); i++) {
        if (cancel_chunk_int(((*dv)[i]).id)) {
            status->push_back(CANCELLED);
	    dwarn(DEBUG_XFER_GTC) << "CANCEL CHUNKS " << (*dv)[i].id << "\n";
        }
        else {
            status->push_back(NOT_CANCELLED);
        }
    }
    
    (*cb)(status);
}

bool
xferPlugin_xgtc::cancel_chunk_int(dot_desc id)
{
    bool cancelled = true;
    flow_ctrl_entry *fc;
    for (fc = flow_control_cache.first(); fc; fc = flow_control_cache.next(fc)){
        desc_entry *de = fc->pending_hash[id];
        if (de) {
            fc->pending_hash.remove(de);
            fc->pending_queue.remove(de);
        }
        else {
            de = fc->issue_hash[id];
            if (de) {
                cancelled &= false;
            }
        }
    }
    return cancelled;
}

void 
xferPlugin_xgtc::xp_notify_descriptors(ref<dot_oid_md> oid, ptr<vec<dot_descriptor> > descs)
{
}

void 
xferPlugin_xgtc::update_hints(ref< vec<dot_descriptor> > dv, ref<hv_vec > hints)
{
}

xferPlugin_xgtc::~xferPlugin_xgtc()
{
    warn << "xferPlugin_xgtc destructor\n";
}

tamed void
xferPlugin_xgtc::xp_get_bitmap(ref<dot_oid_md> oid, ref<vec<oid_hint> > hints,
			   bitmap_cb cb)
{
    tvars {
	hint_res result;
	rpc_info i;
	rconn_entry *conn;
    }
    
    if (parse_hint((*hints)[0].name, "gtc", &result) < 0)
	fatal << "No hints to get bitmap from\n";

    i.ip = result.hint.hostname;
    i.port = result.hint.port;
    i.stream = AXPRT_STREAM;
    i.program = &xfergtc_program_1;
    i.canq = false;

    twait {
	m->rpcCache->connect(i, mkevent(conn));
    }
    
    if (!conn) {
	(*cb)("could not connect to remote host", NULL);
        return;
    }
    
    ref<bitvec> bmp = New refcounted<bitvec>;
    get_bitmap_int(oid, 0, cb, conn, bmp);
}

void xferPlugin_xgtc::get_bitmap_int(ref<dot_oid_md> oid, int offset, 
				    bitmap_cb cb, rconn_entry *conn,
				    ref<bitvec> bmp)
{
    xfergtc_get_bitmap_arg darg;
    ref<xfergtc_get_bitmap_res> dres = 
        New refcounted<xfergtc_get_bitmap_res>;
    darg.oid = *oid;
    darg.offset = offset;

    conn->clnt->call(XFERGTC_PROC_GET_BITMAP, &darg, dres, 
		     wrap(this, &xferPlugin_xgtc::get_bitmap_internal_cb, cb,
			  oid, conn, dres, bmp));
}

void
xferPlugin_xgtc::get_bitmap_internal_cb(bitmap_cb cb, ref<dot_oid_md> oid,
				       rconn_entry *conn,
				       ref<xfergtc_get_bitmap_res> res, 
				       ref<bitvec> bmp, clnt_stat err)
{
    if (err) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ << " XFERGTC_PROC_GET_BITMAP RPC failure: " 
           << err << "\n";
	conn->release(false);
        (*cb)(sb, NULL);
        return;
    }
    
    if (!res->ok) {
        strbuf sb;
        sb << __PRETTY_FUNCTION__ <<" XFERGTC_PROC_GET_BITMAP returned:\n`" 
           << *res->errmsg << "'\n";
	conn->release(false);
        (*cb)(sb, NULL);
        return;
    }

    ref<bitvec> bmp_tmp = New refcounted<bitvec>(res->resok->count);
    // warn << "---------------BEFORE\n";
    //     for (unsigned int i = 0; i < res->resok->bmp.size(); i++) {
    // 	warn << hexdump(&(((res->resok->bmp))[i]), 1) << " " ;
    //     }
    //     warn << "\n";
    //     warn << "---------------BEFORE\n";
    
    ref<bmp_data> bmpref = New refcounted<bmp_data>(res->resok->bmp);
    convert_to_bitvec(bmpref, res->resok->count, bmp_tmp);

    /* XXX - should validate returned offset. */
    bmp->zsetsize(res->resok->count + res->resok->offset);
    for (unsigned int i = 0; i < res->resok->count; i++) {
	(*bmp)[(i + res->resok->offset)] = (int)((*bmp_tmp)[i]);
    }

    if (!res->resok->end) {
	get_bitmap_int(oid, res->resok->count + res->resok->offset, cb,
		       conn, bmp);
    }
    else {
	/*struct timeval tv;
	gettimeofday(&tv, NULL);
	printf("Time to get bitmap - %.4f\n", timeval_diff(&start, &tv)); */
	conn->release(false);
	(*cb)(NULL, bmp);
    }
}

bool
convert_to_bitvec(ref<bmp_data> bmp, int desc_count, ptr<bitvec> bmp_ret)
{
    
    unsigned int dc = static_cast<unsigned int>(desc_count);

    //clear the bitvector
    bmp_ret->zsetsize(desc_count);
    bmp_ret->setrange(0, bmp_ret->size(), 0);

    for (unsigned int i = 0; i < dc; i++) {
        /* unpack and repack the bit string.  This is a little silly,
         * but it's safe. */
        (*bmp_ret)[i] = (bmp->base()[i / 8] & (1 << ((i%8) & 0x07)));
    }

    return true;
}

void 
xferPlugin_xgtc::dump_xput()
{
	//str cur_time, cur_xput;
	char cur_time[50], cur_xput[50];
	sprintf(cur_time, "%.5f", return_time(SECONDS));
	sprintf(cur_xput, "%.5f", (double)bytes_rcvd*8.0/(1024*1024));
	dwarn(DEBUG_XFER_GTC) << "DBGXPUT " << cur_time << " " << cur_xput << "\n";
	bytes_rcvd = 0;
	delaycb(1, 0, wrap(this, &xferPlugin_xgtc::dump_xput));
}

