# $Id$

# Configuration reading and holding.

package Util::Conf;

use strict;
use Exporter;
use Carp qw(croak);
use Getopt::Std;
use Env;

use vars qw(@ISA @EXPORT %OPTS);
@ISA    = qw(Exporter);
@EXPORT = qw( get_names_by_type
              get_items_by_name
            );

sub SCALAR   () { 0x01 }
sub LIST     () { 0x02 }
sub REQUIRED () { 0x04 }

my %define =
  ( web_server =>
    { name    => SCALAR | REQUIRED,
      iface   => SCALAR,
      ifname  => SCALAR,
      port    => SCALAR | REQUIRED,
      irc     => SCALAR | REQUIRED,
      proxy   => SCALAR,
      iname   => SCALAR,
    },
    irc =>
    { name          => SCALAR | REQUIRED,
      server        => LIST   | REQUIRED,
      nick          => LIST   | REQUIRED,
      uname         => SCALAR | REQUIRED,
      iname         => SCALAR | REQUIRED,
      away          => SCALAR | REQUIRED,
      flags         => SCALAR,
      join_cfg_only => SCALAR,
      channel       => LIST   | REQUIRED,
      quit          => SCALAR | REQUIRED,
      cuinfo        => SCALAR | REQUIRED,
      cver          => SCALAR | REQUIRED,
      ccinfo        => SCALAR | REQUIRED,
      localaddr     => SCALAR,
    },
    pastes =>
    { name      => SCALAR | REQUIRED,
      check	=> SCALAR,
      expire	=> SCALAR,
      count	=> SCALAR,
      throttle	=> SCALAR,
      store     => SCALAR | REQUIRED,
    },
  );

my ($section, $section_line, %item, %config);

sub flush_section {
  if (defined $section) {

    foreach my $item_name (sort keys %{$define{$section}}) {
      my $item_type = $define{$section}->{$item_name};

      if ($item_type & REQUIRED) {
        die "$section section needs a(n) $item_name item at $section_line\n"
          unless exists $item{$item_name};
      }
    }

    die "$section section $item{name} is redefined at $section_line\n"
      if exists $config{$item{name}};

    my $name = $item{name};
    $config{$name} = { %item, type => $section };
  }
}

my %opts;
getopts("f:", \%opts);
my $cfile = $opts{"f"}; 
my $f = "pastebot.conf";
my @conf  = ("./$f", "$HOME/$f", "/etc/pastebot/$f");

unless ( $cfile ) {
    for my $try ( @conf ) {
	if ( -f $try ) {
	    $cfile = $try;
	    last;
	}
    }
}

unless ( $cfile  and  -f $cfile ) {
    die "\n$0: Cannot read configuration file [$cfile], tried: @conf";
}


open(MPH, "<$cfile") or die "config file [$cfile] $!";
while (<MPH>) {
  chomp;
  s/\s*\#.*$//;
  next if /^\s*$/;

  # Section item.
  if (/^\s+(\S+)\s+(.*?)\s*$/) {

    die "item outside a section at pastebot.conf line $.\n"
      unless defined $section;

    die "unknown $section item at pastebot.conf line $.\n"
      unless exists $define{$section}->{$1};

    if (exists $item{$1}) {
      if (ref($item{$1}) eq 'ARRAY') {
        push @{$item{$1}}, $2;
      }
      else {
        die "option $1 redefined at pastebot.conf line $.\n";
      }
    }
    else {
      if ($define{$section}->{$1} & LIST) {
        $item{$1} = [ $2 ];
      }
      else {
        $item{$1} = $2;
      }
    }
    next;
  }

  # Section leader.
  if (/^(\S+)\s*$/) {

    # A new section ends the previous one.
    &flush_section();

    $section      = $1;
    $section_line = $.;
    undef %item;

    # Pre-initialize any lists in the section.
    while (my ($item_name, $item_flags) = each %{$define{$section}}) {
      if ($item_flags & LIST) {
        $item{$item_name} = [];
      }
    }

    next;
  }

  die "syntax error in pastebot.conf at line $.\n";
}

&flush_section();

close MPH;

sub get_names_by_type {
  my $type = shift;
  my @names;

  while (my ($name, $item) = each %config) {
    next unless $item->{type} eq $type;
    push @names, $name;
  }

  return @names if @names;
  croak "no configuration type matching \"$type\"";
}

sub get_items_by_name {
  my $name = shift;
  return () unless exists $config{$name};
  return %{$config{$name}};
}

1;
