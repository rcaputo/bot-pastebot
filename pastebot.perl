#!/usr/bin/perl -w
# $Id$

use strict;

use POE;
use Server::Web;
use Client::IRC;

$poe_kernel->run();
exit 0;
