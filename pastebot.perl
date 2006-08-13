#!/usr/bin/perl -w
# $Id: pastebot.perl 96 2004-11-01 16:08:42Z rcaputo $

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

        next unless $@;

        if ($@ =~ /Can't locate (\S+) in \@INC/) {
          die "Can't find library $1.  Please ensure it is installed.\n";
        }

        if ($@ =~ /(conf error: .*? line \d+)/) {
          die "$1\n";
        }

        die;
    }
}

LoadLibraries();
POE::Kernel->run();
exit 0;

sub HELP_MESSAGE {
  my $output = shift;

  print $output "usage:\n";
  print $output "  $0             (use pastebot.conf for configuration)\n";
  print $output "  $0 -f filename (read a particular configuration file)\n";
  exit;
}

sub VERSION_MESSAGE {
  my $output = shift;
  print $output "$0 development snapshot\n";
}
