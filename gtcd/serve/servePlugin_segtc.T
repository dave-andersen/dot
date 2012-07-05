/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "servePlugin_segtc.h"
#include "parseopt.h"

#define DEFAULT_PORT           12000

static ihash<const dot_desc, stat_entry, &stat_entry::cid, &stat_entry::hlink, dd_hash> statCache;
static int total_bytes = 0;

stat_entry::stat_entry(const dot_desc o)
    : cid(o)
{
    count = 0;
    //warn << "stat_entry::stat_entry: Creating stat_entry for " << cid << "\n";
    statCache.insert(this);
}

stat_entry::~stat_entry()
{
    statCache.remove(this);
}

servePlugin_segtc::servePlugin_segtc(gtcd *_m, servePlugin* next_sep)
    : m(_m), parent(NULL), idle_time_start(-1), prev_qlen(0), prev_chunk_size(0), start_time(-1)
{
    assert(m);
    if (next_sep)
        fatal << __PRETTY_FUNCTION__ << " next_sep is not NULL\n"
              << "Make sure that this server plugin comes last\n";
    
    //delaycb(5, 0, wrap(this, &servePlugin_segtc::dump_statcache));
}

void
servePlugin_segtc::dump_statcache()
{
    warn << "Dumping statCache\n" << debug_sep;
    stat_entry *se = statCache.first();
    while (se != NULL) {
	warn << se->cid << " " << se->count << "\n";
	se = statCache.next(se);
    }
    //warn << "Total bytes thus far are " << total_bytes << "\n";
    //warn << debug_sep;
    
    delaycb(5, 0, wrap(this, &servePlugin_segtc::dump_statcache));
}

bool
servePlugin_segtc::configure(str s, str pluginClass)
{
    int port_num;
    if (!s || s == "")
        port_num = DEFAULT_PORT;
    else if (!convertint(s, &port_num)) {
        warn << "Cannot parse port number: " << s << "\n";
        return false;
    }

    dwarn(DEBUG_INIT|DEBUG_SERVE_GTC) << "servePlugin_segtc starting on port "
				      << port_num << "\n";
    serve_gtc_listen_port = port_num;
   
    sock = inetsocket(SOCK_STREAM, serve_gtc_listen_port);
    if (sock < 0)
        fatal("serve_gtc inetsocket: %m\n");

    close_on_exec(sock);
    make_async(sock);

    listen(sock, 150);
    fdcb(sock, selread, wrap(this, &servePlugin_segtc::accept_connection, sock));

    return true;
}

servePlugin_segtc::~servePlugin_segtc()
{
    warn << "servePlugin_segtc destructor\n";
}

void
servePlugin_segtc::dispatch(xferGtcConn *helper, svccb *sbp)
{
    if (!sbp) {
        warnx("servePlugin_segtc: dispatch(): client closed connection\n");
        subconnlist.remove(helper);
        return;
    }

    switch(sbp->proc()) {
    case XFERGTC_PROC_GET_CHUNK:
        remote_get_chunk(helper, sbp);
        break;
    case XFERGTC_PROC_GET_DESCRIPTORS:
	remote_get_descriptors(sbp);
	break;
    case XFERGTC_PROC_GET_BITMAP:
	remote_get_bitmap(sbp);
	break;
    default:
        sbp->reject(PROC_UNAVAIL);
        break;
    }
}

void
servePlugin_segtc::accept_connection(int s)
{
    struct sockaddr_in sin;
    socklen_t sinlen = sizeof(sin);
    bzero(&sin, sizeof(sin));
    
    int cs = accept(sock, (struct sockaddr *) &sin, &sinlen);
    if (cs < 0) {
        if (errno != EAGAIN)
            warn << "gtc accept failed; errno = " << errno << "\n";
        return;
    }
    tcp_nodelay(cs);
    make_async(cs);
    close_on_exec(cs);

    xferGtcConn *c = New xferGtcConn(cs, sin, this);
    c->bandwidth = 1;
    subconnlist.insert_head(c);
}

xferGtcConn::xferGtcConn(int fd, const sockaddr_in &sin, servePlugin_segtc *parent)
    : x(axprt_stream::alloc(fd, MAX_PKTSIZE)),
      c(asrv::alloc(x, xfergtc_program_1, wrap(parent, &servePlugin_segtc::dispatch, 
                                               this)))
{
    ipaddr = sin.sin_addr;
    tcpport = ntohs (sin.sin_port);
    
    warn("serveGtc: Accepted connection from %s:%d\n", inet_ntoa(ipaddr), tcpport);
}

void 
servePlugin_segtc::get_default_hint(ref<vec<oid_hint> > hint)
{
    str hostname;
    const str comp = "10"; //used in parsing default_hint in gtc plugin for emulab
    unsigned int port;
    
    port = serve_gtc_listen_port;

    // XXX: Make more robust by fixing addr. selection heuristic
    // or by sending multiple addresses as multiple hints
    vec<in_addr> av;
    if (myipaddrs (&av)) {
        for (in_addr *ap = av.base(); ap < av.lim(); ap++) {
            if (ap->s_addr != htonl (INADDR_LOOPBACK)
		&& ap->s_addr != htonl (0)) {
                char s[64];
                if (inet_ntop(AF_INET, ap, s, sizeof(s))) {
#ifdef EMULAB
		    //warn << "servePlugin_segtc::get_default_hint:: current is "
		    // << s <<"\n";
		    char *hn;
		    
		    if ((hn = strchr(s, '.'))) {
			str temp(s, (hn-s));

			
			//warn << "servePlugin_segtc::get_default_hint:: temp is "
			//   << temp <<"\n";
			
			if (temp == comp) {
			    hostname = str(s);
			    //  warn << "servePlugin_segtc::get_default_hint:: hint "
			    // << hostname <<"\n";
			    break;
			}
		    }
#else
		    hostname = str(s);
		    break;
#endif
                }
            }
        }
    }
    else 
	fatal << "servePlugin_segtc::get_default_hint: Could not obtain IP addresses\n";

    dwarn(DEBUG_SERVE_GTC) << "Hints: hostname:port is " << hostname << ":"
    			   << port << "\n";
    
    oid_hint h;
    h.name = strbuf() << "gtc://" << hostname << ":" << port;
    hint->push_back(h);
}

tamed void
servePlugin_segtc::remote_get_descriptors(svccb *sbp)
{
    tvars {
	xfergtc_get_descriptors_arg *arg;
	ptr<dot_oid_md> oid;
	str s;
	ptr<vec<dot_descriptor> > descs;
	bool end;
	unsigned int offset;
    }
    
    arg = sbp->Xtmpl getarg<xfergtc_get_descriptors_arg>();
    oid = New refcounted<dot_oid_md> (arg->oid);
    offset = arg->offset;

    if (oid->id.size() < 1) {
	xfergtc_get_descriptors_res res(false);
        *res.errmsg = "Received invalid OID for GET_DESCRIPTORS";
        warn << *res.errmsg << "\n";
        sbp->replyref(res);
        return;
    }

    dwarn(DEBUG_SERVE_GTC) << "GET_DESCRIPTORS w/ OID " << oid->id << " offset "
			  << offset << "\n";
    twait {
	serve_descriptors(oid, mkevent(s, descs, end));
    }
    
    xfergtc_get_descriptors_res res(false);
    /* XXX - we're ignoring end right now b/c storage always gives us
       everything */
    if (s) {
        *res.errmsg = s;
        sbp->replyref(res);
        return;
    }
    
    if (offset > 0 && offset >= descs->size()) {
        *res.errmsg = "Too large offset for GET_DESCRIPTORS";
        warn << *res.errmsg << "\n";
        sbp->replyref(res);
        return;
    }

    res.set_ok(true);
    // Determine how many descriptors to send,
    // assuming that all descriptors are the same size
    unsigned int maxsize = SEND_SIZE;
    // XXX - Figure out a way to get the size of a descriptor. The
    // number below is a kludge!
    unsigned int maxd = 0; // outstanding descs.
    unsigned int filled_size = 0;
    for (size_t i = offset; i < descs->size() ; i++) {
        dot_descriptor &d = (*descs)[i];
        filled_size += d.id.size();
        for (size_t j = 0; j < d.md.list.size(); j++) {
            metadata_entry &me = d.md.list[j];
            filled_size += (me.module.len() + me.key.len() + me.val.len());
        }
        filled_size += sizeof(unsigned int);
        if (1.5 * filled_size > maxsize) {
            break;
        }
        maxd ++;
    }
    unsigned int numd = min((unsigned int)(descs->size() - offset), maxd);
    
    /* warn("With a max size of %d, the max descs sent as %d, "
       "the number sent == %d, and size of desc == %d\n",
       maxsize, maxd, numd, descs[0].size()); */
    if (descs->size() - offset <= maxd) {
	res.resok->end = true;
    }
    else {
	res.resok->end = false;
    }
    res.resok->offset = offset;
    res.resok->descriptors.setsize(numd);
    
    for (unsigned int i = offset; i < offset + numd ; i++) {
	res.resok->descriptors[i-offset] = (*descs)[i];
	//warn("Set descriptor at position %d, offset %d to %s\n", i, 
	//     offset, 
	//     res.resok->descriptors[i-offset].desc.cstr());
    }

    res.resok->count = numd;
    sbp->replyref(res);
}

tamed void
servePlugin_segtc::serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb)
{
    dwarn(DEBUG_SERVE_GTC) << "servePlugin_segtc::serve_descriptors: called\n";
    if (parent)
	parent->serve_descriptors(oidmd, cb);
    else
	m->serve_descriptors(oidmd, cb);
}

tamed void
servePlugin_segtc::remote_get_chunk(xferGtcConn *xgc, svccb *sbp)
{
    tvars {
	int time;
	xfergtc_get_chunk_arg *arg;
	ptr<dot_descriptor> d;
	stat_entry *s;
	str errmsg;
	ptr<desc_result> dres;
    }

    if (simulate) {
	time = (arandom() % LOCAL_DELAY_SIMULATE)*10; //msec
	dwarn(DEBUG_SERVE_GTC) << "Delaying chunk request for " << time << "msec\n";
	time = time * 1000000; //nsec
	twait {
	    delaycb(0, time, mkevent());
	}
    }
    
    arg = sbp->Xtmpl getarg<xfergtc_get_chunk_arg>();
    d = New refcounted<dot_descriptor> (arg->desc);

    s = statCache[d->id];
    if (!s) {
	s = New stat_entry(d->id);
    }
    s->count++;
    total_bytes += d->length;

    twait {
	serve_chunk(d, mkevent(errmsg, dres));
    }
    
    /* flow control stuff
     * update idle time (add to it)
     * set idle_start_time = -1
     */

    double current_time = return_time(SECONDS);
    if (start_time < 0) {
        start_time = current_time;
    }
    if (idle_time_start >= 0) {
        idle_time += (current_time - idle_time_start);
    }

    static double last_rtt1 = 1.0e+30;
    static double last_rtt2 = 1.0e+30;
    static double cur_rtt = 1.0e+30;
    cur_rtt = (double)atof((arg->rtt).cstr());

    /* The flow control metadata */
    metadata_entry wasted_me;
    wasted_me.module = "SEGTC";
    wasted_me.key = "wasted";
    long qlen = (dynamic_cast<axprt_pipe *> ((axprt *) (sbp->getsrv()->xprt())))->outlen();
    double curr_rate;
    if (prev_chunk_size == 0) {
	    curr_rate = xgc->bandwidth;
    }
    else {
	    curr_rate = (prev_qlen+prev_chunk_size-qlen)*8.0 / (1000.0*(current_time - chunk_enqueue_time));
    }
    if (idle_time > 0) {
        if (arg->bw_token) {
            double busy_frac = 1 - idle_time/(current_time-chunk_enqueue_time);
	    if((last_rtt1 + last_rtt2)/2 >= cur_rtt) {
		    xgc->bandwidth *= (2 - busy_frac);
	    }
        }
	if((last_rtt1 + last_rtt2)/2 >= cur_rtt)
		wasted_me.val = strbuf() << (long)(idle_time*xgc->bandwidth*1000/8.0);
	else
		wasted_me.val = strbuf() << 0;
    }
    else {
        double alpha = 0.25;
        xgc->bandwidth = alpha*curr_rate + (1.0-alpha)*xgc->bandwidth;
	xgc->bandwidth = (xgc->bandwidth > 0) ? xgc->bandwidth : 0;
        long report_qlen = (qlen > prev_qlen) ? (qlen - prev_qlen) : 0;
        wasted_me.val = strbuf() << -report_qlen;
    }

    metadata_entry in_front_me;
    in_front_me.module = "SEGTC";
    in_front_me.key = "in_front";
    in_front_me.val = strbuf() << qlen;
    
    int sock_size_len = sizeof(int);
    int rcv_sock_size, snd_sock_size;
    getsockopt(xgc->getwritefd(), SOL_SOCKET, SO_RCVBUF, &rcv_sock_size, (socklen_t *)&sock_size_len);
    getsockopt(xgc->getwritefd(), SOL_SOCKET, SO_SNDBUF, &snd_sock_size, (socklen_t *)&sock_size_len);

    metadata_entry sock_size_me;
    sock_size_me.module = "SEGTC";
    sock_size_me.key = "sock_size";
    sock_size_me.val = strbuf() << snd_sock_size;

    /* For emulab experiments only */

    //str curr_time_str, curr_rate_str, cur_rtt_str;
    char curr_time_str[50], curr_rate_str[50], cur_rtt_str[50];
    sprintf(curr_time_str, "%.5f", current_time - start_time);
    sprintf(curr_rate_str, "%.5f", curr_rate);
    sprintf(cur_rtt_str, "%f", cur_rtt);
    
    dwarn(DEBUG_SERVE_GTC) << "SEGTC  " <<  curr_time_str
			   << " " << qlen << " " << (long)xgc->bandwidth
			   << " " << rcv_sock_size << " " << snd_sock_size << "\n";

    dwarn(DEBUG_SERVE_GTC) << "DBGFC  " << curr_time_str << " " << xgc->get_remote_ip() << ":" << xgc->get_remote_port() << " " << qlen << " " << (long)xgc->bandwidth << " " << curr_rate_str << " " << cur_rtt_str << "\n";

    dwarn(DEBUG_SERVE_GTC) << "DBGGSO  " << curr_time_str << " " << xgc->get_remote_ip() << ":" << xgc->get_remote_port() << " " << qlen << " " << rcv_sock_size << " " << snd_sock_size << "\n";
    
    idle_time_start = -1;
    idle_time = 0;
    prev_qlen = qlen;
    prev_chunk_size = (long)min((dres->data->resid() - (size_t) arg->offset), SEND_SIZE);
    chunk_enqueue_time = current_time;
    last_rtt2 = last_rtt1;
    last_rtt1 = cur_rtt;
    /* End - flow control stuff.... */


    xfergtc_get_chunk_res res(false);

    if (errmsg) {
        warn << "get_chunk from sp failed " << inet_ntoa(((sockaddr_in *)sbp->getsa())->sin_addr) << "  " << errmsg << "\n";
        *res.errmsg = errmsg;
        sbp->replyref(res);
        chunk_reply_followup(sbp);
        return;
    }
    ptr<suio> data = dres->data;
    dwarn(DEBUG_SERVE_GTC) << "Got back buffer of " << data->resid() << "\n";
    
    if (arg->offset >= data->resid()) {
        warn << "Invalid offset\n";
        *res.errmsg = "Invalid offset for get_chunk";
        sbp->replyref(res);
        chunk_reply_followup(sbp);
        return;
    }

    res.set_ok(true);

    size_t num_bytes = min((dres->data->resid() - (size_t) arg->offset), 
                           SEND_SIZE);
    if (num_bytes < dres->data->resid() - arg->offset) {
        res.resok->end = false;
    }
    else {
        res.resok->end = true;
    }

    if (arg->offset > 0) {
        data->rembytes(arg->offset);
    }
    res.resok->offset = arg->offset;
    res.resok->data.setsize(num_bytes);
    dwarn(DEBUG_SERVE_GTC) << "Sending back " << dres->data->resid() << " bytes " << num_bytes << "\n";
    data->copyout(res.resok->data.base(), num_bytes);
    res.resok->md = dres->desc->md;

    res.resok->md.list.push_back(wasted_me);
    res.resok->md.list.push_back(in_front_me);
    res.resok->md.list.push_back(sock_size_me);
    res.resok->bw_token = arg->bw_token;

    sbp->replyref(res);
    chunk_reply_followup(sbp);
}

tamed void
servePlugin_segtc::serve_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    dwarn(DEBUG_SERVE_GTC) << "servePlugin_segtc::serve_chunk: called for " << d->id << "\n";
    if (parent)
	parent->serve_chunk(d, cb);
    else
	m->serve_chunk(d, cb);
}

void
servePlugin_segtc::chunk_reply_followup(svccb *sbp)
{
    sbp->getsrv()->xprt()->setwcb(wrap(this, &servePlugin_segtc::chunk_write_cb, (dynamic_cast<axprt_pipe *> ((axprt *) (sbp->getsrv()->xprt())))));
}

void
servePlugin_segtc::chunk_write_cb(axprt_pipe *axp)
{
    int outlen = axp->outlen();
    double current_time = return_time(SECONDS);
    if (outlen == 0) {
        idle_time_start = current_time;
    }
    idle_time = 0;
}


tamed void
servePlugin_segtc::remote_get_bitmap(svccb *sbp)
{
    tvars {
	xfergtc_get_bitmap_arg *arg;
	ptr<dot_oid_md> oid;
	unsigned int offset;
	str s;
	ptr<bitvec > bmp;
    }
    
    arg = sbp->Xtmpl getarg<xfergtc_get_bitmap_arg>();
    oid = New refcounted<dot_oid_md> (arg->oid);
    offset = arg->offset;

    if (oid->id.size() == 0) {
	xfergtc_get_bitmap_res res(false);
        *res.errmsg = "Received invalid OID for GET_BITMAP";
        warn << *res.errmsg << "\n";
        sbp->replyref(res);
        bitmap_reply_followup(sbp);
        return;
    }

    dwarn(DEBUG_SERVE_GTC|DEBUG_SET) << "GET_BITMAP w/ OID " << oid->id
				     << " offset " << offset << "\n";

    twait {
	serve_bitmap(oid, mkevent(s, bmp));
    }
        
    /* flow control stuff */
    double current_time = return_time(SECONDS);
    if (idle_time_start >= 0) {
        idle_time += (current_time - idle_time_start);
    }
    idle_time_start = -1;

    xfergtc_get_bitmap_res res(false);
    /* XXX - we're ignoring end right now b/c storage always gives us
       everything */
    if (s) {
        res.set_ok(false);
        *res.errmsg = s;
        sbp->replyref(res);
        bitmap_reply_followup(sbp);
        return;
    }

    ref< bmp_data > bmp_ret = New refcounted< bmp_data >;
    
    convert_from_bitvec(bmp_ret, (unsigned int) bmp->size(), bmp);

    if (offset > 0 && offset >= bmp_ret->size()) {
        *res.errmsg = "Too large offset for GET_BITMAP";
        warn << *res.errmsg << "\n";
        sbp->replyref(res);
        bitmap_reply_followup(sbp);
        return;
    }

    res.set_ok(true);

    /*
     * We're limited in the number of bits we can send back by
     * the RPC max size.  That's a lot, but perhaps not enough
     * for a huge file.  Support an offset that MUST BE A MULTIPLE
     * OF 8.
     */
    unsigned int maxbits = (SEND_SIZE / 2) * 8; /* Conservative */
    unsigned int totalbits = bmp->size() - offset;
    unsigned int sendbits = totalbits;

    if (totalbits > maxbits) {
	sendbits = maxbits;
	res.resok->end = false;
    }
    else {
	res.resok->end = true;
    }
    unsigned int byte_offset = offset / 8;
    unsigned int sendbytes = sendbits / 8;
    if (sendbits % 8)
	sendbytes++;

    res.resok->offset = offset;
    res.resok->bmp.set(bmp_ret->base() + byte_offset, sendbytes);
    res.resok->count = sendbits;
    res.resok->num_descs = bmp->size();
    
    sbp->replyref(res);
    bitmap_reply_followup(sbp);
}

tamed void
servePlugin_segtc::serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    dwarn(DEBUG_SERVE_GTC) << "servePlugin_segtc::serve_bitmap: called\n";
    if (parent)
	parent->serve_bitmap(oid, cb);
    else
	m->serve_bitmap(oid, cb);
}

void
servePlugin_segtc::bitmap_reply_followup(svccb *sbp)
{
    sbp->getsrv()->xprt()->setwcb(wrap(this, &servePlugin_segtc::bitmap_write_cb,
				       (dynamic_cast<axprt_pipe *> ((axprt *) (sbp->getsrv()->xprt())))));
}

void
servePlugin_segtc::bitmap_write_cb(axprt_pipe *axp)
{
    if (axp->outlen() == 0) {
        idle_time_start = return_time(SECONDS);
    }
}

void
convert_from_bitvec(ref<bmp_data> bmp_ret, unsigned int desc_count, ptr<bitvec> bmp)
{
    char *bytes;
    int nbytes = desc_count / 8;
    if (desc_count % 8) nbytes++;

    bmp_ret->setsize(nbytes);
    bytes = bmp_ret->base();
    bzero(bytes, nbytes);
    
    for (unsigned int i = 0; i < desc_count; i++) {
        if ((*bmp)[i])
            bytes[i / 8] |= (1 << ((i % 8) & 0x07));
    }
}
