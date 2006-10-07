# $Id$

# Configuration reading and holding.

package Bot::Pastebot::Conf;

use strict;
use Carp qw(croak);

use base qw(Exporter);
our @EXPORT_OK = qw(
  get_names_by_type get_items_by_name load
  SCALAR LIST REQUIRED
);

sub SCALAR   () { 0x01 }
sub LIST     () { 0x02 }
sub REQUIRED () { 0x04 }

my ($section, $section_line, %item, %config);

sub flush_section {
  my ($conf_file, $conf_definition) = @_;

  if (defined $section) {

    foreach my $item_name (sort keys %{$conf_definition->{$section}}) {
      my $item_type = $conf_definition->{$section}->{$item_name};

      if ($item_type & REQUIRED) {
        die(
          "conf error: section `$section' ",
          "requires item `$item_name' ",
          "at $conf_file line $section_line\n"
        ) unless exists $item{$item_name};
      }
    }

    die(
      "conf error: section `$section' ",
      "item `$item{name}' is redefined at $conf_file line $section_line\n"
    ) if exists $config{$item{name}};

    my $name = $item{name};
    $config{$name} = { %item, type => $section };
  }
}

# Parse some configuration.

sub get_conf_file {
  use Getopt::Std;

  my %opts;
  getopts("f:", \%opts);

  my $conf_file = $opts{"f"};
  my @conf;
  if (defined $conf_file) {
    @conf = ($conf_file);
  }
  else {
    my $f = "pastebot.conf";
    @conf  = (
      "./$f", "$ENV{HOME}/$f", "/usr/local/etc/pastebot/$f", "/etc/pastebot/$f"
    );

    foreach my $try ( @conf ) {
      next unless -f $try;
      $conf_file = $try;
      last;
    }
  }

  unless (defined $conf_file and -f $conf_file) {
    die(
      "\nconf error: Cannot read configuration file [$conf_file], tried: @conf"
    );
  }

  return $conf_file;
}

sub load {
  my ($class, $conf_file, $conf_definition) = @_;

  open(MPH, "<", $conf_file) or
    die "\nconf error: Cannot open configuration file [$conf_file]: $!";

  while (<MPH>) {
    chomp;
    s/\s*\#.*$//;
    next if /^\s*$/;

    # Section item.
    if (/^\s+(\S+)\s+(.*?)\s*$/) {

      die(
        "conf error: ",
        "can't use an indented item ($1) outside of an unindented section ",
        "at $conf_file line $.\n"
      ) unless defined $section;

      die(
        "conf error: item `$1' does not belong in section `$section' ",
        "at $conf_file line $.\n"
      ) unless exists $conf_definition->{$section}->{$1};

      if (exists $item{$1}) {
        if (ref($item{$1}) eq 'ARRAY') {
          push @{$item{$1}}, $2;
        }
        else {
          die "conf error: option $1 redefined at $conf_file line $.\n";
        }
      }
      else {
        if ($conf_definition->{$section}->{$1} & LIST) {
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
      flush_section($conf_file, $conf_definition);

      $section      = $1;
      $section_line = $.;
      undef %item;

      # Pre-initialize any lists in the section.
      while (my ($item_name, $item_flags) = each %{$conf_definition->{$section}}) {
        if ($item_flags & LIST) {
          $item{$item_name} = [];
        }
      }

      next;
    }

    die "conf error: syntax error in $conf_file at line $.\n";
  }

  flush_section($conf_file);

  close MPH;
}

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
