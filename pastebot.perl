#!/usr/bin/perl -w
# $Id$

use strict;
use lib '.';
use File::Basename;
use Env;

# Old way - hard coded paths. Now the library location
# is told in /etc/pastebot/pastebot.lib and read upon startup.
#
# use lib '/usr/share/pastebot';
# use  POE ;
# use  Server::Web ;
# use  Client::IRC ;

#  The last file overrides. This file can tell where the libraries
#  by including statement:
#
#    push @INC, '/path/to/pastebotlibs';

# Places where the libraries may be found.
my @CONFIG_FILE = qw(
   ./pastebot.lib
   $HOME/.pastebot.lib
   /etc/pastebot/pastebot.lib
   /usr/local/etc/pastebot/pastebot.lib
);

# Libraries we need.
my @LIBS = qw(
   Client::IRC
   POE
   Perl::Tidy
   Server::Web
);

sub Error ($ $) {
    my ($lib, $msg) = @_;

    $msg =~ s/ in \@INC.*//s;

    my $liberr = << "EOF";
$0 Error while loading $lib: $msg
Please make sure that the following libraries
have been installed:
@LIBS
EOF

    die "While loading library [$lib]\n$liberr";
}

sub LoadLibraries () {
    push @INC, dirname $0;

    for my $config ( @CONFIG_FILE ) {
	if ( -f $config ) {
	    require $config  or  die $!;
	}
    }

    #  Run time loading

    for my $lib ( @LIBS ) {
	eval "use $lib;" ;

	$@ and Error($lib, $@);
    }
}

LoadLibraries();
POE::Kernel->run();
exit 0;
