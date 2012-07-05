/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtcd.h"
#include "stllike.h"
#include "gtc_ext_interface.h"
#include "xferPlugin.h"
#include "rxx.h"

list<client, &client::link> clientlist;
static unsigned int numclients = 0;
static struct timeval start, end;
static unsigned int pending_write_bytes = 0;
bool pending_signal = false;
bool sequential_mode = false;
bool sequential_pending = 0;
connectionCache *connCache_ptr;

#ifdef TIME_SERIES
extern double chunk_start;
#endif

bool
pressure_from_xfer()
{
    if (sequential_mode) {
	if (sequential_pending)
	    return true;
	else
	    return false;
    }
    if (pending_write_bytes > 0) {
	dwarn(DEBUG_OPT&DEBUG_L1) << "pressure_from_xfer:: "
				  << pending_write_bytes << "\n";
	return true;
    }
    else {
	dwarn(DEBUG_OPT&DEBUG_L1) << "pressure_from_xfer:: NONE\n";
	return false;
    }
}

bool
pressure_from_client()
{
    if (!pressure) 
	return false;

    //works for one client only
    client *obj = clientlist.first;
    if (!obj) {
	DPRINTF(DEBUG_OPT&DEBUG_L1, "pressure_from_client:: No client connected\n");
	return(false);
    }
	
    ref<axprt_unix> x = obj->x;
    assert(x);
    int bytes = x->outlen();
    if (bytes > CLIENT_OUTSTANDING_THRESHOLD) {
	DPRINTF(DEBUG_OPT&DEBUG_L1, "pressure_from_client:: Bytes are %d\n", bytes);
	return(true);
    }

    //checking in xfer table
    return (pressure_from_xfer());
}

bool
pressure_from_network()
{
    return(connCache_ptr->pressure_from_network());
}

int
return_metadata_index(str module, str key, metadata *md)
{
    size_t size = md->list.size();
    for (size_t i = 0; i < size; i++)
        if ((module && md->list[i].module == module) &&
	    (!key || md->list[i].key == key))
	    return(i);
    
    return(-1);
}


xferData::xferData() 
    : id(0), xmode(XFER_SEQUENTIAL), descs(NULL), descs_count(0),
      descs_xfered(0), descs_start(0), starting_offset(0), 
      buf_offset(0), fetching(false), xcb(NULL),
      err(NULL), hints(NULL)
{
}

bool
xferData::descriptors_verify()
{
    if (!desc_verify)
	return false;
    
    EVP_MD_CTX hash;
    EVP_MD_CTX_init(&hash);
    EVP_DigestInit(&hash, EVP_sha1());
    
    //Hash for descriptor list
    for (size_t i = 0; i < descs->size(); i++) {
	str desc_buf = strbuf() << (*descs)[i].id << " "
				<< (*descs)[i].length;
	EVP_DigestUpdate(&hash, desc_buf, desc_buf.len());
    }
    
    unsigned int diglen;
    unsigned char digest[EVP_MAX_MD_SIZE];
    EVP_DigestFinal(&hash, digest, &diglen);

    strbuf name;
    name << hexdump(digest, diglen);

    dwarn(DEBUG_CLIENT) << "Descriptor hash recvd is " << desc_verify <<"\n";
    return (desc_verify == name);
}

static int chunk_fetch_count;  // A hack for performance analysis.

void
gtcd::get_data(svccb *sbp)
{
    gtc_get_data_arg *arg = sbp->Xtmpl getarg<gtc_get_data_arg>();
    gtc_get_data_res res(false);

    ptr<xferData> pdp = xferTable[*arg];
    if (!pdp) {
        *res.errmsg = strbuf() << "unknown transfer id: " << *arg;
        warn << *res.errmsg << "\n";
        sbp->replyref(res);
        return;
    }

    if (pending_signal && (pending_write_bytes <= 0 ||
			   (sequential_mode && sequential_pending <= 0))) {
	dwarn(DEBUG_OPT&DEBUG_L1) << "Calling from gtcd\n";
	if (opt_cb)
	    (*opt_cb)();
	if (aiod_cb)
	    (*aiod_cb)();
	pending_signal = false;
    }
    
    if ((pdp->buf.resid() > 0) 
	|| (pdp->xmode == XFER_SEQUENTIAL
	    && (*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE)) {
	transfer_data(sbp, *arg);
	return;
    }

    if (pdp->descs_xfered == pdp->descs->size()) {
	res.set_ok(true);
	res.resok->end = true;
	res.resok->count = 0;
	res.resok->offset = 0;
	res.resok->data.setsize(0);
	sbp->replyref(res);
	xferTable.remove(*arg);
	return;
    }

    if (pdp->xmode == XFER_OUT_OF_ORDER) {
	for (size_t i = pdp->descs_start; i < pdp->descs->size(); i++) {
	    if ((*pdp->descs_status)[i] == DESC_ON_STORAGE) {
		transfer_data(sbp, *arg);
		return;
	    }
	}
    }

    // Set fetch callback and start fetch if not already started
    pdp->xcb = wrap(this, &gtcd::transfer_data, sbp, *arg);
    if (!pdp->fetching) {
	pdp->fetching = true;
	delaycb(0, 0, wrap(this, &gtcd::fetch_data, *arg));
    }
}

void
gtcd::fetch_data(dot_xferId xferId)
{
    bool missing = false;
    
    //warnx << "xferId == " << xferId << "\n";
    ptr<xferData> pdp = xferTable[xferId];
    ref<vec<dot_descriptor> > missing_descs = 
        New refcounted<vec<dot_descriptor> >;

    warn << "Have to fetch " << pdp->descs_status->size() << " blocks\n";
    for (size_t i = 0; i < pdp->descs_status->size(); i++) {
        if (sp->get_chunk_refcount(&(*pdp->descs)[i]) >= 0) {
	    sp->inc_chunk_refcount(&(*pdp->descs)[i]);
            (*pdp->descs_status)[i] = DESC_ON_STORAGE;
	    pending_write_bytes += (*pdp->descs)[i].length;
	    pending_signal = true;
        }
        else {
            missing = true;
            missing_descs->push_back((*pdp->descs)[i]);
            (*pdp->descs_status)[i] = DESC_REQUESTED;
        }
    }

    // This code is actually never called yet because fetch_data is
    // only called once. This is only here right now in case we ever
    // rate limit the amount of data fetched
    if (pdp->xcb) {

	if ((pdp->xmode == XFER_SEQUENTIAL) 
	    && (*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE) {
	    dwarn(DEBUG_CLIENT) << "fetch_data Have a sequential block\n";
	    sequential_pending = 1;
	    xfer_cb xcb = pdp->xcb;
	    pdp->xcb = NULL;
	    (*xcb)();
	}
	else if (pdp->xmode == XFER_OUT_OF_ORDER) {
	    for (size_t i = 0; i < pdp->descs->size(); i++) {
		if ((*pdp->descs_status)[i] == DESC_ON_STORAGE) {
		    xfer_cb xcb = pdp->xcb;
		    pdp->xcb = NULL;
		    (*xcb)();
		    break;
		}
	    }
	}
    }

    if (missing) {
        // For each descriptor, call into storage plugin stack
        //    Get_get_chunk_md (GGCMD)
        //
//         for (size_t j = 0; j < missing_descs->size(); j++)
//             for (size_t i = 0; i < (*missing_descs)[j].md.list.size(); i++)
//                 warn << "  " << (*missing_descs)[j].md.list[i].module << "."
//                      << (*missing_descs)[j].md.list[i].key << " = "
//                      << (*missing_descs)[j].md.list[i].val << "\n";
      
      //convert pdp->hints to per chunk hints
	ref<hv_vec> vechints = New refcounted<hv_vec > ;
	vechints->setsize(missing_descs->size()); 

	for (size_t i = 0; i < missing_descs->size(); i++) {
	    (*vechints)[i] = New refcounted<vec<oid_hint > >(*(pdp->hints));
	}
      
	xp->xp_get_chunks(missing_descs, vechints,
		       wrap(this, &gtcd::xp_fetch_data_cb, xferId));
    }
}

void
gtcd::xp_fetch_data_cb(dot_xferId xferId, str s, ptr<desc_result> res)
{
    dwarn(DEBUG_CLIENT) << "xferId fetch == " << xferId << " "
			<< res->desc->id << "\n";
    
    ptr<xferData> pdp = xferTable[xferId];
    if (!pdp) {
        // This can happen when we get multiple errors and we removed
        // pdp from the xfer table after passing the first error back
        // to the application.
        warn <<"Callback for invalid xferId \n";
        return;
    }

    if (s || !res->data || res->data->resid() == 0) {
        if (s) {
            pdp->err = s;
        }
        else {
            pdp->err = "Unable to fetch data from the xfer plugin";
        } 
        if (pdp->xcb) {
            xfer_cb xcb = pdp->xcb;
            pdp->xcb = NULL;
            (*xcb)();
        }
        return;
    }

    // Find out where this chunk belongs
    unsigned int chunks_put = 0;
    dot_descriptor res_desc = *(res->desc);

    ptr<vec<unsigned int> > vv = (*pdp->descs_hash[res_desc.id]);
    if (vv) {
        for (size_t j = 0; j < vv->size(); j++) {
            unsigned int i = (*vv)[j];
            if ((*pdp->descs_status)[i] != DESC_ON_STORAGE &&
                (*pdp->descs_status)[i] != DESC_DONE) {
                (*pdp->descs_status)[i] = DESC_ON_STORAGE;
                if (!chunks_put) {
                    sp->put_ichunk(res->desc, res->data, true,
                                   wrap(this, &gtcd::put_sp_cb));
                } else {
                    sp->inc_chunk_refcount(&res_desc);
                }
                chunks_put++;
		dwarn(DEBUG_CLIENT) << "Putting " << i << " in storage\n";
            }
        }
    }

    pending_write_bytes += chunks_put * res_desc.length;
    pending_signal = true;
    
    chunk_fetch_count++;

    if ((pdp->xcb && pdp->xmode == XFER_OUT_OF_ORDER && chunks_put) ||
	(pdp->xcb && pdp->xmode == XFER_SEQUENTIAL
	    && ((*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE))) {
	sequential_pending = 1;
	dwarn(DEBUG_CLIENT) << "fetch_data_cb sequential pending now\n";
	xfer_cb xcb = pdp->xcb;
	pdp->xcb = NULL;
	dwarn(DEBUG_CLIENT) << "Calling back to gcp\n";
	(*xcb)();
    }
    else {
	if (pdp->xmode == XFER_SEQUENTIAL
	    && ((*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE)) {
	    sequential_pending = 1;
	    dwarn(DEBUG_CLIENT) << "fetch_data_cb sequential pending now wo call back\n";
	}	    
	if (!pdp->xcb)
	    dwarn(DEBUG_CLIENT) << "No call back\n";
    }
}

void
gtcd::transfer_data(svccb *sbp, dot_xferId xferId)
{
    ptr<xferData> pdp = xferTable[xferId];

    if (pdp->err) {
        actual_transfer_data(sbp, xferId);
        return;
    }

    if (pdp->xmode == XFER_SEQUENTIAL) {
	// Now, check whether we have enough data in the buf?
	if (pdp->buf.resid() < SEND_SIZE
	    && pdp->descs_xfered != pdp->descs->size()) {
	    if ((*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE) {
		// Move contents in from the sp
		pdp->descs_count++;
		sp->get_chunk(New refcounted<dot_descriptor> 
			      ((*pdp->descs)[pdp->descs_count-1]), 
			      wrap(this, &gtcd::get_chunk_cb, sbp, xferId,
				   pdp->descs_count-1, -1));
		return;
	    }
	}
	actual_transfer_data(sbp, xferId);
    }
    else if (pdp->xmode == XFER_OUT_OF_ORDER) {
	if (pdp->buf.resid() > 0) {
	    // We have data that we need to empty first
	    actual_transfer_data(sbp, xferId);
	} 
	else {
	    long offset = pdp->starting_offset;
	    size_t pdpds = pdp->descs->size();
	    // Find a chunk from the sp and send that over
            bool all_done = true;
	    for (size_t i = pdp->descs_start; i < pdpds; i++) {
                if (all_done && (*pdp->descs_status)[i] == DESC_DONE) {
                    pdp->descs_start++;
		    pdp->starting_offset += (*pdp->descs)[i].length;
                } else {
                    all_done = false;
                }
		if ((*pdp->descs_status)[i] == DESC_ON_STORAGE) {
		    // Move contents in from the sp
		    sp->get_chunk(New refcounted<dot_descriptor> 
				  ((*pdp->descs)[i]), 
				  wrap(this, &gtcd::get_chunk_cb, sbp, 
				       xferId, i, offset));
		    return;
		}
		offset += (*pdp->descs)[i].length;
	    }
	}
    }
}

void
gtcd::get_chunk_cb(svccb *sbp, dot_xferId xferId, unsigned int desc_no, 
		   long offset, str s, ptr<desc_result> res)
{
    ptr<xferData> pdp = xferTable[xferId];

    if (s) {
        pdp->err = s;
        actual_transfer_data(sbp, xferId);
        return;
    }

    // As we always get data from the storage plugin, we should be
    // able to just insert this into an array and then write it out.
    pdp->buf.copyu(res->data);
    (*pdp->descs_status)[desc_no] = DESC_DONE;
    //sp->release_ichunk(res->desc);
    pdp->descs_xfered++;

    
    if (offset >= 0) {
	pdp->buf_offset = offset;
    }

    // Now, if we don't have enough data in the buffer, can we add
    // some more? No matter what the xfer mode is, we can only add the
    // next sequential chunk
    if (pdp->buf.resid() < SEND_SIZE
        && pdp->descs_xfered != pdp->descs->size()
	&& ((desc_no+1) < pdp->descs->size())) {
        if ((*pdp->descs_status)[desc_no+1] == DESC_ON_STORAGE) {
            // Move contents in from the sp
	    if (pdp->xmode == XFER_SEQUENTIAL) {
		assert(pdp->descs_count == (desc_no + 1));
		pdp->descs_count++;
	    }
	    sp->get_chunk(New refcounted<dot_descriptor> 
                          ((*pdp->descs)[desc_no+1]), 
                          wrap(this, &gtcd::get_chunk_cb, sbp, xferId,
			       desc_no+1, -1));
            return;
        }
    }
    actual_transfer_data(sbp, xferId);
    if ((*pdp->descs_status)[pdp->descs_count] == DESC_ON_STORAGE) {
	dwarn(DEBUG_CLIENT) << "get_chunk_cb sequential set " << pdp->descs_count << "\n";
	sequential_pending = 1;
    }
    else {
	dwarn(DEBUG_CLIENT) << "get_chunk_cb sequential reset " << pdp->descs_count << "\n";
	sequential_pending = 0;
    }
}

void
gtcd::actual_transfer_data(svccb *sbp, dot_xferId xferId)
{

    ptr<xferData> pdp = xferTable[xferId];
    gtc_get_data_res res(true);

    if (pdp->err) {
	res.set_ok(false);
        *res.errmsg = pdp->err;
        warn << "actual_transfer_data:: " << *res.errmsg << "\n";
        sbp->replyref(res);
        xferTable.remove(xferId);
        return;
    }

    size_t send_bytes;
    send_bytes = min(pdp->buf.resid(), SEND_SIZE);
    dwarn(DEBUG_CLIENT) << "Sending to client " << send_bytes << " bytes\n";
    res.resok->count = send_bytes;
    res.resok->offset = pdp->buf_offset;
    res.resok->data.setsize(send_bytes);
    pdp->buf_offset += send_bytes;
    pdp->buf.copyout(res.resok->data.base(), send_bytes);
    pdp->buf.rembytes(send_bytes);
    pending_write_bytes -= send_bytes;
    res.resok->end = false; /* set to true in one case below */

    if (pdp->buf.resid() <= SEND_SIZE &&
	pdp->descs_xfered == pdp->descs->size()) {
	// XXX - Insert a low-water mark here such that if its hit and
	// only we are not currently fetching more data, get more data
	warn << "had to fetch " << chunk_fetch_count
	     << " blocks from remote end\n";
	res.resok->end = true;

	gettimeofday(&end, NULL);

	float time_taken = timeval_diff(&start, &end);
	if (time_taken > 0) 
	    fprintf(stderr, "time for gtcd data start-finish == %.4f\n",
		    time_taken);
	else {
	    fprintf(stderr, "time for gtcd data start-finish == %.4f\n",
		    time_taken);
	    fprintf(stderr, "times are == %u %u %u %u\n",
		    (unsigned int)start.tv_sec, (unsigned int)start.tv_usec,
		    (unsigned int)end.tv_sec, (unsigned int)end.tv_usec);
	}
	chunk_fetch_count = 0;
	//so that data is in SET for sharing
	//for (size_t i = 0; i < pdp->descs->size(); i++) {
	//sp->release_ichunk(New refcounted<dot_descriptor> ((*pdp->descs)[i]));
	//}
	xferTable.remove(xferId);
    }

    sbp->replyref(res);
}


void 
gtcd::get_init_cb(svccb *sbp, ref<dot_oid_md> oid, bool last_try, 
                  dot_xferId id, str s, ptr<vec<dot_descriptor> > descs, 
                  bool end)
{
    gtc_get_init_res res(false);

    if (s) {
	if (!last_try) {
	    /* Storage plugin didn't have descriptors;  get from net */
	    ref<xferData> pdp = xferTable[id];
	    warn << "gtcd::get_init_cb: No. of oid_md metadata entries = " << oid->md.list.size() << "\n";

	    xp->xp_get_descriptors(oid, pdp->hints,
				   wrap(this, &gtcd::get_init_cb, sbp, oid, true, 
					id));
	    return;
	}
	else {
	    warn << "gtcd::get_init_cb: Error " << s << "\n";
	    xferTable.remove(id);
	    res.set_ok(false);
	    *res.errmsg = s;
	    sbp->replyref(res);
	    return;
	}
    }
    
    ref<xferData> pdp = xferTable[id];
    if (!pdp->descs) {
	pdp->descs = descs;
    }
    else {
	*pdp->descs += *descs;
    }
    
    if (end) {
	chunk_fetch_count = 0;
	res.set_ok(true);
	*res.id = id;
	pdp->descs_status = New refcounted<vec<desc_status> >;
	pdp->descs_status->setsize(pdp->descs->size());  
	for (size_t i = 0; i < pdp->descs->size(); i++) {
	    (*pdp->descs_status)[i] = DESC_UNKNOWN;
            if (!pdp->descs_hash[(*pdp->descs)[i].id]) {
                ref<vec<unsigned int> > vv = New refcounted<vec<unsigned int> >;
                pdp->descs_hash.insert((*pdp->descs)[i].id, vv);
            }
            (*pdp->descs_hash[(*pdp->descs)[i].id])->push_back(i);
	}

	if (pdp->descriptors_verify()) 
	    warn << "Descriptors verify...proceeding\n";
	else
	    warn << "Descriptors don't verify ...moving on\n";
	
	//collected all the descriptors so notify the transfer plugins of it
	//incase they do not know
	xp->xp_notify_descriptors(oid, pdp->descs);
	
	//the descriptors came from xp so let the sp know about it
	if (last_try)
	    sp->sp_notify_descriptors(oid, pdp->descs);
	
	sbp->replyref(res);
    } 
}

tamed void
gtcd::get_init(svccb *sbp)
{
    ptr<dot_oid_md> oid;

    tvars {
        ptr<xferData> pdp;
        str errmsg;
        ptr<dot_oid_md> oidmd;
    }

    {
    gtc_get_init_arg *arg = sbp->Xtmpl getarg<gtc_get_init_arg>();
    gtc_get_init_res res(false);

    dot_oid oid_id = arg->oid.id;

    str err;
    if (oid_id.size() == 0)
        err = "Received invalid OID for GET";
    if (arg->hints.size() == 0)
	err = "No Hints provided for GET";
    if (arg->xmode != XFER_SEQUENTIAL && arg->xmode != XFER_OUT_OF_ORDER)
        err = "Invalid Transfer mode";

    if (err) {
        warn << err << "\n";
	*res.errmsg = err;
        sbp->replyref(res);
        return;	
    }

    gettimeofday(&start, NULL);
    ref<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;
    hints->setsize(arg->hints.size());

    for (size_t i = 0; i < arg->hints.size() ;i++) {
        // warn << "gtcd::get_init - Hint at pos " << i << " found\n";
        (*hints)[i] = (arg->hints[i]);
    }

    warn << "Received GET for OID = " << oid_id << "\n";
#ifdef TIME_SERIES
    chunk_start = return_time(SECONDS);
#endif
    oid = New refcounted<dot_oid_md> (arg->oid);
    
    pdp = New refcounted<xferData>;
    xferTable.insert(xferCounter, pdp);
    
    pdp->xmode = arg->xmode;
    pdp->id = xferCounter++;
    pdp->hints = hints;
    int i = return_metadata_index("DISK", "desc_hash", &(oid->md));
    if (i < 0) {
	warn << "OID does not have descriptor hash\n";
	pdp->desc_verify = NULL;
    }
    else 
	pdp->desc_verify = oid->md.list[i].val;
    }
    
    if (pdp->xmode == XFER_SEQUENTIAL) {
	dwarn(DEBUG_CLIENT) << "Setting sequential mode\n";
	sequential_mode = true;
    }
    
    twait { sp->get_descriptors_init(oid, mkevent (errmsg, oidmd)); }

    sp->sp_get_descriptors(oidmd, wrap(this, &gtcd::get_init_cb, sbp, oidmd,
				    false, pdp->id));
}

void
gtcd::put_commit_cb(svccb *sbp, str s, ptr<dot_oid_md> oid)
{
    gtc_put_commit_res res(false);

    if (s) {
        warn << "Error in put_commit - " << s << "\n";
        *res.errmsg = s;
        sbp->replyref(res);
        return;
    } 

    dwarn(DEBUG_CLIENT) << "Plugin says that the oid is " << oid->id << "\n";
    for (size_t i = 0; i < oid->md.list.size(); i++)
        warn << "  " << oid->md.list[i].module << "."
                     << oid->md.list[i].key << " = "
                     << oid->md.list[i].val << "\n";
    res.set_ok(true);
    res.resok->oid = *oid;
    ref<vec<oid_hint> > hint = New refcounted<vec<oid_hint> >;
    sep->get_default_hint(hint);
    res.resok->hints.setsize(hint->size());
    for (size_t i = 0; i < hint->size(); i++) {
	res.resok->hints[i] = (*hint)[i];
    }
    sbp->replyref(res);
}

void
gtcd::put_commit(svccb *sbp)
{
    gtc_put_commit_arg *arg = sbp->Xtmpl getarg<gtc_put_commit_arg>();
    gtc_put_commit_res res(false);

    ptr<xferData> pdp = xferTable[*arg];
    if (!pdp) {
        *res.errmsg = strbuf() << "unknown xferID " << *arg;
        sbp->replyref(res);
        return;
    }

    xferTable.remove(*arg);

    cp->commit_object(pdp->sid, wrap(this, &gtcd::put_commit_cb, sbp));
}

void
gtcd::put_sp_cb(str s)
{
    if (s)
        warn << "Message from put_ichunk is " << s << " \n";
}

void
gtcd::put_data_cb(svccb *sbp, str s)
{
    gtc_put_data_res res(false);

    if (s) {
        warn << "Message from put_data is " << s << " \n";
        *res.errmsg = s;
    } else {
	res.set_ok(true);
    }
    
    sbp->replyref(res);
}

void
gtcd::put_data(svccb *sbp)
{
    gtc_put_data_arg *arg = sbp->Xtmpl getarg<gtc_put_data_arg>();
    gtc_put_data_res res(false);
    
    ptr<xferData> pdp = xferTable[arg->id];
    if (!pdp) {
        *res.errmsg = strbuf() << "unknown xferID " << arg->id;
        sbp->replyref(res);
        return;
    }

    assert (arg->data.size() == arg->count);    
    cp->put_object(pdp->sid, arg->data.base(), arg->data.size(), 
                   wrap(this, &gtcd::put_data_cb, sbp));
}

void
gtcd::put_init(svccb *sbp, bool init_with_path)
{
    //warnx << "gtcd:: put_path_init called\n";
    
    ref<xferData> pdp = New refcounted<xferData>;
    xferTable.insert(xferCounter, pdp);

    gtc_put_init_res res(true);
    *res.id = xferCounter++;
    pdp->id = *res.id;
    ptr<metadata_entry > e = NULL;

    if (init_with_path) {
	e = New refcounted<metadata_entry >;
	gtc_put_init_arg *arg = sbp->Xtmpl getarg<gtc_put_init_arg>();
	unsigned int i = return_metadata_index("LOCAL", NULL, arg);
	if (i >= 0)
	    *e = arg->list[i];
	else
	    fatal << "No metadata for put with path\n";
	
	dwarn(DEBUG_CLIENT) << "gtcd::put_init: Sending metadata "
                            << e->module << " " << e->key << " o ->"
                            << e->val << "e\n";
    }
    
    cp->init(&pdp->sid, e);
    sbp->replyref(res);
}

void
gtcd::put_fd_read_cb(ref<putfd_state> st, str s)
{
    if (s) {
        gtc_put_commit_res res(false);
        warn << "Message from put_chunk is " << s << " \n";
        *res.errmsg = s;
        st->sbp->replyref(res);
        return;
    }

    st->pending--;
    put_fd_main(st);
}

void
gtcd::put_fd_read(ref<putfd_state> st)
{
    if (st->sbp->getsrv()->xprt()->ateof()) {
        warn << "put_fd_read(): client is gone...stopping read from FD\n";
	fdcb(st->fd, selread, NULL);
        st->sbp->ignore();
        return;
    }

    char inbuf[CHUNK_SIZE];
    int nbytes = read(st->fd, inbuf, CHUNK_SIZE);
    
    if (nbytes == -1) {
        gtc_put_commit_res res(false);
        str s = strbuf() << "Could not read from input file descriptor\n";
        *res.errmsg = s;
        st->sbp->replyref(res);
    }
    else if (nbytes == 0) {
	fdcb(st->fd, selread, NULL);
	close(st->fd);
        st->fd = -1;
        put_fd_main(st);
    }
    else {
        st->pending++;
        cp->put_object(st->sid, inbuf, nbytes,
                       wrap(this, &gtcd::put_fd_read_cb, st));
    }
}

void
gtcd::put_fd_main(ref<putfd_state> st)
{
    bool more = false;

    if (st->fd != -1) {
        fdcb(st->fd, selread, wrap(this, &gtcd::put_fd_read, st));
	more = true;
	//	warnx << " [reading]";
    }

    if (!more && st->pending <= 0) {
	//warnx << "s_cb_s:  DONE!\n";
        cp->commit_object(st->sid, wrap(this, &gtcd::put_commit_cb, st->sbp));
    }
}

void
gtcd::put_fd(svccb *sbp, bool put_with_path)
{
    dwarn(DEBUG_CLIENT) << "put_fd called\n";
    
    axprt_unix *x = static_cast<axprt_unix *>(sbp->getsrv()->xprt().get());
    int fd = x->recvfd();
    if (fd < 0) {
        gtc_put_commit_res res(false);
        *res.errmsg = strbuf() << "Could not receive FD from client\n";
        warn << *res.errmsg;
        sbp->replyref(res);
        return;
    }

    ref<putfd_state> st = New refcounted<putfd_state>;

    ptr<metadata_entry > e = NULL;

    if (put_with_path) {
	e = New refcounted<metadata_entry>;
	gtc_put_init_arg *arg = sbp->Xtmpl getarg<gtc_put_init_arg>();
	unsigned int i = return_metadata_index("LOCAL", NULL, arg);
	if (i >= 0)
	    *e = arg->list[i];
	else
	    fatal << "No metadata for put with path\n";
	
	/*
	  attach fd to metadata --> no longer done since gtcd has too
	  many open fds and it is not clear who should keep track of
	  closing them when it runs out of fds. so we now close fd
	  
	*/
	e->key = strbuf() << e->key << "-1";
    
	dwarn(DEBUG_CLIENT) << "gtcd::put_fd: Sending metadata "
                            << e->module << " " << e->key << " o ->"
                            << e->val << "e\n";
    }
    
    cp->init(&st->sid, e);
    st->sbp = sbp;
    st->fd = fd;
    st->pending = 0;

    put_fd_main(st);
}

void
gtcd::abort()
{
    for (client *p = clientlist.first; p; p = clientlist.next(p))
        if (p->x->ateof()) {
            delete p;
            break;
        }

    warn("Deleting client connection (%d clients left)\n", numclients);
}

tamed void
gtcd::serve_descriptors(ptr<dot_oid_md> oidmd, descriptors_cb cb)
{
    sp->sp_get_descriptors(oidmd, cb);
}

tamed void
gtcd::serve_chunk(ref<dot_descriptor> d, chunk_cb cb)
{
    sp->get_chunk(d, cb);
}

tamed void 
gtcd::serve_bitmap(ref<dot_oid_md> oid, bitmap_cb cb)
{
    sp->sp_get_bitmap(oid, cb);
}

void
gtcd::dispatch(svccb *sbp)
{
     if (!sbp) {
        abort();
        return;
    }

    switch(sbp->proc()) {
    case GTC_PROC_PUT_INIT:
        put_init(sbp, false); /* without path */
        break;
    case GTC_PROC_PUT_PATH_INIT:
        put_init(sbp, true); /* with path */
        break;
    case GTC_PROC_PUT_DATA:
        put_data(sbp);
        break;
    case GTC_PROC_PUT_COMMIT:
        put_commit(sbp);
        break;
    case GTC_PROC_PUT_FD:
        put_fd(sbp, false); /* without path */
        break;
    case GTC_PROC_PUT_PATH_FD:
        put_fd(sbp, true); /* with path */
        break;
    case GTC_PROC_GET_INIT:
        get_init(sbp);
        break;
    case GTC_PROC_GET_DATA:
	get_data(sbp);
        break;
    default:
        sbp->reject(PROC_UNAVAIL);
        break;
    }
}

client::client(int fd, const sockaddr_un &sun, asrv_cb cb)
    : x(axprt_unix::alloc(fd, MAX_PKTSIZE)),
      c(asrv::alloc(x, gtc_program_1, cb))
{
    clientlist.insert_head (this);
    numclients++;

#ifdef HAVE_GETPEEREID
    if (getpeereid (fd, &uid, &gid) < 0) {
        warn ("getpeereid: %m\n");
        // XXX: What do we want to do if we don't know the client?
        //close (fd);
        //delete sa;
        //return;
    }
#endif /* HAVE_GETPEEREID */
    
    warn("Accepted connection from uid=%d, gid=%d\n", uid, gid);
}

client::~client ()
{
    warn("Connection closed for uid=%d, gid=%d\n", uid, gid);
    clientlist.remove (this);
    numclients--;
}
