# $Id$

# Data management.

package Util::Data;

use strict;
use Exporter;
use Carp qw(croak);

use vars  qw(@ISA @EXPORT);
@ISA    = qw(Exporter);
@EXPORT = qw( store_paste fetch_paste delete_paste
              fetch_paste_channel clear_channel_ignores
              set_ignore clear_ignore get_ignores is_ignored
            );

sub PASTE_TIME    () { 0 }
sub PASTE_BODY    () { 1 }
sub PASTE_SUMMARY () { 2 }
sub PASTE_ID      () { 3 }
sub PASTE_NETWORK () { 4 }
sub PASTE_CHANNEL () { 5 }
sub PASTE_HOST    () { 6 }

my $id_sequence = 0;
my %paste_cache;
my %ignores; # $ignores{$ircnet}{lc $channel} = [ mask, mask, ... ];

# Save paste, returning an ID.

sub store_paste {
  my ($id, $summary, $paste, $ircnet, $channel, $ipaddress) = @_;
  my $new_id = ++$id_sequence;
  $paste_cache{$new_id} =
    [ time(),       # PASTE_TIME
      $paste,       # PASTE_BODY
      $summary,     # PASTE_SUMMARY
      $id,          # PASTE_ID
      $ircnet,      # PASTE_NETWORK
      lc($channel), # PASTE_CHANNEL
      $ipaddress,   # PASTE_HOST
    ];
  return $new_id;
}

# Fetch paste by ID.

sub fetch_paste {
  my $id = shift;
  my $paste = $paste_cache{$id};
  return(undef, undef, undef) unless defined $paste;
  return( $paste->[PASTE_ID],
          $paste->[PASTE_SUMMARY],
          $paste->[PASTE_BODY]
        );
}

# Fetch the channel a paste was meant for.

sub fetch_paste_channel {
  my $id = shift;
  return $paste_cache{$id}->[PASTE_CHANNEL];
}

# Delete a possibly sensitive or offensive paste.

sub delete_paste {
  my ($ircnet, $channel, $id, $bywho) = @_;

  if ($paste_cache{$id}[PASTE_NETWORK] eq $ircnet &&
      $paste_cache{$id}[PASTE_CHANNEL] eq lc $channel) {
    # place the blame where it belongs
    $paste_cache{$id}[PASTE_BODY] = "Deleted by $bywho";
  }
  else {
    return;
  }
}

# manage channel/IRC network based ignores of http requestors

sub _convert_mask {
  my $mask = shift;

  $mask =~ s/\./\\./g;
  $mask =~ s/\*/\\d+/g;

  $mask;
}

sub is_ignored {
  my ($ircnet, $channel, $host) = @_;

  $ignores{$ircnet}{lc $channel} && @{$ignores{$ircnet}{lc $channel}}
    or return;

  for my $mask (@{$ignores{$ircnet}{lc $channel}}) {
    $host =~ /^$mask$/ and return 1;
  }

  return;
}

sub set_ignore {
  my ($ircnet, $channel, $mask) = @_;

  $mask = _convert_mask($mask);

  # remove any existing mask - so it's not fast
  @{$ignores{$ircnet}{lc $channel}} = 
    grep $_ ne $mask, @{$ignores{$ircnet}{lc $channel}};
  push @{$ignores{$ircnet}{lc $channel}}, $mask;
}

sub clear_ignore {
  my ($ircnet, $channel, $mask) = @_;

  $mask = _convert_mask($mask);

  @{$ignores{$ircnet}{lc $channel}} = 
    grep $_ ne $mask, @{$ignores{$ircnet}{lc $channel}};
}

sub get_ignores {
  my ($ircnet, $channel) = @_;

  $ignores{$ircnet}{lc $channel} or return;

  my @masks = @{$ignores{$ircnet}{lc $channel}};

  for (@masks) {
    s/\\d\+/*/g;
    s/\\././g;
  }

  @masks;
}

sub clear_channel_ignores {
  my ($ircnet, $channel) = @_;

  $ignores{$ircnet}{lc $channel} = [];
}

### End.

1;
