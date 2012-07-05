/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtc.h"
#include "gtcd.h"

put_client::put_client(int in_fd, ref<aclnt> gtc, put_client_cb cb)
    : put_client_base(gtc, cb), in_fd(in_fd)
{
    pendingRPCs = 0;
 
    ref<gtc_put_init_res> res = New refcounted<gtc_put_init_res>;

    gtc_c->call(GTC_PROC_PUT_INIT, NULL, res,
                wrap(this, &put_client::put_start, res));
}

put_client::put_client(int in_fd, str file, ref<aclnt> gtc, put_client_cb cb)
    : put_client_base(gtc, cb), in_fd(in_fd)
{
    pendingRPCs = 0;

    metadata_entry e;
    e.module = "LOCAL";
    e.key = strbuf() << file << ":-1"; 
    gtc_put_init_arg arg;
    arg.list.push_back(e);

    ref<gtc_put_init_res> res = New refcounted<gtc_put_init_res>;

    gtc_c->call(GTC_PROC_PUT_PATH_INIT, &arg, res,
                wrap(this, &put_client::put_start, res));
}

void
put_client::put_start(ref<gtc_put_init_res> res, clnt_stat err)
{
    str errstr;

    const str fname = "put_start(): GTC_PROC_PUT_INIT";
    if (err)
	errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
	errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
	(*cb)(errstr, NULL, NULL);
        delete this;
	return;
    }

    xferId = *res->id;
    dwarn(DEBUG_CLIENT) << "Put started " << xferId << "\n";

    set_callback_state();
}

void
put_client::set_callback_state()
{
    bool more = false;
    //    warnx << "s_cb_s: ";
    if (in_fd != -1) {
	fdcb(in_fd, selread, wrap(this, &put_client::read_file_data));
	more = true;
	//	warnx << " [reading]";
    }
    else if (in_fd != -1)
	fdcb(in_fd, selread, NULL);

    if (!more && pendingRPCs <= 0) {
	//warnx << "s_cb_s:  DONE!\n";

        gtc_put_commit_arg arg = xferId;
        ref<gtc_put_commit_res> res = New refcounted<gtc_put_commit_res>;
        gtc_c->call(GTC_PROC_PUT_COMMIT, &arg, res,
                    wrap(static_cast<put_client_base *>(this), &put_client_base::put_end, res));
    }
}

void
put_client::read_file_data()
{
    int rc = io_in.input(in_fd, SEND_SIZE);

    if (rc == -1) {
	strbuf sb;
	sb.fmt("read_file_data failed read: %m\n");
	(*cb)(sb, NULL, NULL);
        delete this;
	return;
    }
    
    if (rc == 0) {
	//warn("Finished reading input file data\n");
	fdcb(in_fd, selread, NULL);
	close(in_fd);
	in_fd = -1;

	set_callback_state();
	return;
    }

    int nbytes = io_in.resid();
    rc = io_in.copyout(inbuf, nbytes);
    assert(rc == nbytes);
    io_in.rembytes(rc);

    /* Send data */
    gtc_put_data_arg arg;
    ref<gtc_put_data_res> res = New refcounted<gtc_put_data_res>;

    arg.id = xferId;
    arg.offset = 0;
    arg.count = nbytes;
    arg.data.set(inbuf, nbytes);

    pendingRPCs++;
    gtc_c->call(GTC_PROC_PUT_DATA, &arg, res,
                wrap(this, &put_client::put_data_cb, res));
}

void
put_client::put_data_cb(ref<gtc_put_data_res> res, clnt_stat err)
{
    str errstr;

    const str fname = "put_data_cb(): GTC_PROC_PUT_DATA";
    if (err)
	errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
        errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
	(*cb)(errstr, NULL, NULL);
        delete this;
	return;
    }

    pendingRPCs--;
    set_callback_state();
}

void
put_client_base::put_end(ref<gtc_put_commit_res> res, clnt_stat err)
{
    str errstr;

    const str fname = "put_end(): GTC_PROC_PUT_COMMIT";
    if (err)
        errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
	errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
	(*cb)(errstr, NULL, NULL);
        delete this;
	return;
    }

    ref<dot_oid_md> oid = New refcounted<dot_oid_md> (res->resok->oid);
    ptr<vec<oid_hint> > hints = New refcounted<vec<oid_hint> >;
    hints->setsize(res->resok->hints.size());

    for (unsigned int i = 0; i < res->resok->hints.size() ;i++) {
	// warn << "Hint at pos " << i << " found\n";
        (*hints)[i] = res->resok->hints[i];
    }
    // strbuf out = strbuf() << *oid << "\n";
    // out.tosuio()->output(STDOUT_FILENO);
    dwarn(DEBUG_CLIENT) << "Put committed\n";

    (*cb) (NULL, oid, hints);
    delete this;
}


put_client::~put_client()
{
    dwarn(DEBUG_CLIENT) << "Destroying put_client\n";
}

/***********************/

put_client_fd::put_client_fd(int in_fd, ref<aclnt> gtc, put_client_cb cb)
    : put_client_base(gtc, cb), in_fd(in_fd)
{
    axprt_unix *x = static_cast<axprt_unix *>(gtc->xprt().get());
    assert(x);

    int gtc_fd = x->getfd();
    assert(isunixsocket(gtc_fd));

    x->sendfd(in_fd);

    ref<gtc_put_commit_res> res = New refcounted<gtc_put_commit_res>;
    gtc_c->call(GTC_PROC_PUT_FD, NULL, res,
                wrap(static_cast<put_client_base *>(this), &put_client_fd::put_end, res));
}

put_client_fd::put_client_fd(int in_fd, str file, ref<aclnt> gtc, put_client_cb cb)
    : put_client_base(gtc, cb), in_fd(in_fd)
{
    axprt_unix *x = static_cast<axprt_unix *>(gtc->xprt().get());
    assert(x);

    int gtc_fd = x->getfd();
    assert(isunixsocket(gtc_fd));

    //closes the fd by default after sending it
    x->sendfd(in_fd);

    metadata_entry e;
    e.module = "LOCAL";
    e.key = strbuf() << file << ":"; //fd will be attached in gtcd
    gtc_put_init_arg arg;
    arg.list.push_back(e);
        
    ref<gtc_put_commit_res> res = New refcounted<gtc_put_commit_res>;
    gtc_c->call(GTC_PROC_PUT_PATH_FD, &arg, res,
                wrap(static_cast<put_client_base *>(this), &put_client_fd::put_end, res));
}

put_client_fd::~put_client_fd()
{
    dwarn(DEBUG_CLIENT) << "Destroying put_client_fd with "
			<< in_fd << "\n";
}

/***********************/

put_client_suio::put_client_suio(ptr<suio > in, ref<aclnt> gtc, put_client_cb cb)
    : put_client_base(gtc, cb), buf(in)
{
    pendingRPCs = 0;
    
    ref<gtc_put_init_res> res = New refcounted<gtc_put_init_res>;
    
    gtc_c->call(GTC_PROC_PUT_INIT, NULL, res,
                wrap(this, &put_client_suio::put_start, res));
}

void
put_client_suio::put_start(ref<gtc_put_init_res> res, clnt_stat err)
{
    str errstr;

    const str fname = "put_start(): GTC_PROC_PUT_INIT";
    if (err)
	errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
	errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
	(*cb)(errstr, NULL, NULL);
        delete this;
	return;
    }

    xferId = *res->id;
    
    put_data();
}

void
put_client_suio::put_data()
{
    int nbytes = min(buf->resid(), SEND_SIZE);

    if (nbytes == 0) {
	assert(pendingRPCs == 0);
	//finished sending
	gtc_put_commit_arg arg = xferId;
        ref<gtc_put_commit_res> res = New refcounted<gtc_put_commit_res>;
        gtc_c->call(GTC_PROC_PUT_COMMIT, &arg, res,
                    wrap(static_cast<put_client_base *>(this), &put_client_suio::put_end, res));
	return;
    }
    
    int rc = buf->copyout(inbuf, nbytes);
    assert(rc == nbytes);
    buf->rembytes(rc);

    /* Send data */
    gtc_put_data_arg arg;
    ref<gtc_put_data_res> res = New refcounted<gtc_put_data_res>;

    arg.id = xferId;
    arg.offset = 0;
    arg.count = nbytes;
    arg.data.set(inbuf, nbytes);

    pendingRPCs++;
    gtc_c->call(GTC_PROC_PUT_DATA, &arg, res,
                wrap(this, &put_client_suio::put_data_cb, res));
}

void
put_client_suio::put_data_cb(ref<gtc_put_data_res> res, clnt_stat err)
{
    str errstr;
    const str fname = "put_data_cb(): GTC_PROC_PUT_DATA";
    
    if (err)
        errstr = strbuf() << fname << " RPC failure: " << err << "\n";

    else if (!res->ok)
        errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
	(*cb)(errstr, NULL, NULL);
        delete this;
	return;
    }

    pendingRPCs--;
    put_data();
}

put_client_suio::~put_client_suio()
{
    // NOTE: gcp might exit before this prints, so don't worry
    dwarn(DEBUG_CLIENT) << "Destroying put_client_suio\n";
}
