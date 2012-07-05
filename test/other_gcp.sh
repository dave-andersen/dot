#!/bin/tcsh

set CONF="test/other_gcp.conf"
#set CONF="test/other_gcp_set.conf"
#set CONF="test/other_gcp_opt.conf"

set PARAM="test/params.conf"

setenv DOT_TMP_DIR /tmp/tmp-dot
#setenv XFER_GTC_PORT 15001
gtcd/gtcd -D 2 -f $CONF -v $PARAM -p /tmp/gtcd_deux || sleep 24d
