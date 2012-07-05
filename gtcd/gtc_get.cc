/*
 * Copyright (c) 2005-2006 Carnegie Mellon University and Intel Corporation.
 * All rights reserved.
 * See the file "LICENSE" for licensing terms.
 */

#include "gtc.h"
#include "debug.h"

unsigned int counter_fds = 0;
ihash<const str, fd_struct, &fd_struct::fname, &fd_struct::hlink> fd_cache;
tailq<fd_struct, &fd_struct::tlink> fds_lru;

fd_struct::fd_struct(str name)
{
    fname = name;
    fd = -1;
    fd_cache.insert(this);
}

fd_struct::~fd_struct()
{
    fd_cache.remove(this);
}

void
close_last_fd()
{
    fd_struct *fds = fds_lru.first;

    //warnx << "Closing fd for " << fds->fname << "\n";
    
    assert(fds->fd >= 0);
    
    fds_lru.remove(fds);
    close(fds->fd);
    counter_fds--;
    
    fds->fd = -1;
}

bool
return_fd(str s)
{
    //warnx << "Returning for " << s << "\n";
    
    fd_struct *fds = fd_cache[s];
    if (!fds)
	fatal << "file not there " << s << "\n";
    
    if (fds->fd >= 0) {
	fds_lru.remove(fds);
	close(fds->fd);
	counter_fds--;
    }
    delete fds;
    return true;
}

int
get_new_fd(str s)
{ 
    fd_struct *fds = fd_cache[s];
    if (fds)
	fatal << "same file name " << s << "\n";

    if (counter_fds >= MAX_OPEN_FDS)
	close_last_fd();
    
    fds = New fd_struct(s);
    int outfd = open(s, O_WRONLY|O_CREAT|O_TRUNC, 0666);
    if (outfd < 0)
	return outfd;
    fds->fd = outfd;
    counter_fds++;
    fds_lru.insert_tail(fds);
    //warnx << "Getting new fd for " << s << " " << outfd << "\n";
    return outfd;
}

int
get_fd(str name)
{
    fd_struct *fds = fd_cache[name];

    if (!fds)
	fatal << "File " << name << " is not there\n";
    
    if (fds->fd >= 0) {
	//warnx << "Returning " << fds->fd << " for " << name << "\n";
	return(fds->fd);
    }

    if (counter_fds >= MAX_OPEN_FDS) 
	close_last_fd(); 	//close some one
        
    int outfd = open(name, O_WRONLY);
    if (outfd < 0) {
        warnx("open %s: %m\n", name.cstr());
        return -1;
    }

    fds->fd = outfd;
    counter_fds++;
    fds_lru.insert_tail(fds);
    
    //warnx << "Returning " << outfd << " for " << name << "\n";
    return outfd;
}

/**********************************************************************/

get_client::get_client(dot_oid_md oid, ref<vec<oid_hint> > hints, int out_fd, 
                       str fn, ref<aclnt> gtc, cbs cb)
    : oid(oid), out_fd(out_fd), gtc_c(gtc), cb(cb)
{
    final_name = fn;
    gtc_get_init_arg fetch_arg;
    fetch_arg.oid = oid;
    fetch_arg.hints.set(hints->base(), hints->size());
    fetch_arg.xmode = XFER_OUT_OF_ORDER;
    //fetch_arg.xmode = XFER_SEQUENTIAL;

    ref<gtc_get_init_res> res = New refcounted<gtc_get_init_res>;
    dwarn(DEBUG_CLIENT) << "gc::gc asking for oid " << oid.id << " with fd " << out_fd << "\n";
    gtc_c->call(GTC_PROC_GET_INIT, &fetch_arg, res,
                wrap(this, &get_client::get_start, res));
}

get_client::get_client(dot_oid_md oid, ref<vec<oid_hint> > hints, ptr<suio> in, 
                       ref<aclnt> gtc, cbs cb)
    : oid(oid), out_fd(-1), gtc_c(gtc), cb(cb), buf(in)
{
    gtc_get_init_arg fetch_arg;
    fetch_arg.oid = oid;
    fetch_arg.hints.set(hints->base(), hints->size());
    fetch_arg.xmode = XFER_SEQUENTIAL;

    ref<gtc_get_init_res> res = New refcounted<gtc_get_init_res>;
    dwarn(DEBUG_CLIENT) << "gc::gc asking for oid " << oid.id << "\n";
    gtc_c->call(GTC_PROC_GET_INIT, &fetch_arg, res,
                wrap(this, &get_client::get_start, res));
}


void
get_client::get_start(ref<gtc_get_init_res> res, clnt_stat err)
{
    str errstr;
    const str fname = "gc::get_start(): GTC_PROC_GET_INIT";
    
    if (err)
	errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
        errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
        finish(errstr);
        return;
    }

    xferId = *res->id; 
    dwarn(DEBUG_CLIENT) << "starting transfer " << xferId << "\n";
    
    gtc_get_data_arg darg = xferId;
    ref<gtc_get_data_res> dres = New refcounted<gtc_get_data_res>;
    gtc_c->call(GTC_PROC_GET_DATA, &darg, dres,
                wrap(this, &get_client::get_data, dres));
}

void
get_client::get_data(ref<gtc_get_data_res> res, clnt_stat err)
{
    str errstr;
    const str fname = "gc::get_data(): GTC_PROC_GET_DATA";
    
    if (err)
	errstr = strbuf() << fname << " RPC failure: " << err << "\n";
    else if (!res->ok)
        errstr = strbuf() << fname << " returned:\n`" << *res->errmsg << "'\n";

    if (errstr) {
        finish(errstr);
        return;
    }

    suio newdat;
    newdat.copy(res->resok->data.base(), res->resok->data.size());
    if (out_fd == 0) {
	int temp_fd = get_fd(final_name);
	if (temp_fd < 0) {
	    finish("gc::get_data(): Unable to open\n");
	    return;
	}
	if (-1 == lseek(temp_fd, res->resok->offset, SEEK_SET)) {
	    finish("gc::get_data(): Unable to lseek");
	    return;
	}

	//warnx << "Writing to " << final_name << " and offset "
	//    << res->resok->offset << "\n";

	newdat.output(temp_fd);
    }
    else {
 	assert(out_fd == -1);
	buf->copyu(&newdat);
    }
        
    if (res->resok->end) {
        dwarn(DEBUG_CLIENT) << "gc::Finished GET..\n";
        finish(NULL);
        return;
    }

    gtc_get_data_arg arg = xferId;
    ref<gtc_get_data_res> dres = New refcounted<gtc_get_data_res>;
    gtc_c->call(GTC_PROC_GET_DATA, &arg, dres,
                wrap(this, &get_client::get_data, dres));
}

void
get_client::finish(str err)
{
    (*cb) (err);
    delete this;
}

get_client::~get_client()
{
    dwarn(DEBUG_CLIENT) << "gc::Destroying get_client\n";
}
