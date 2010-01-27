# Miscellaneous administrivia.

package Bot::Pastebot::Administrivia;

use warnings;
use strict;

use Carp qw(croak);
use Bot::Pastebot::Conf qw( get_names_by_type get_items_by_name );

use base qw(Exporter);
our @EXPORT_OK = qw(get_pid write_pidfile uses_pidfile);

# Return this module's configuration.

use Bot::Pastebot::Conf qw(SCALAR REQUIRED);

my %conf = (
  administrivia => {
    name      => SCALAR | REQUIRED,
    pidfile   => SCALAR,
  },
);

sub get_conf { return %conf }

# return the name used in the config for this section.
sub _get_name {
  my $name;
  eval { ($name) = get_names_by_type('administrivia') };
  return $name unless $@;
}

# Do we have a pidfile configured?
sub uses_pidfile {
  _get_name();
}

# Examine the PID file to see if there's a session running already.
sub get_pid {
  my $name = _get_name();
  my %conf = get_items_by_name($name);
  my $pidfile = $conf{pidfile};
  return unless -e $pidfile;
  my $pid = do {
    local $/;
    open my $fh, '<', $pidfile or die "open($pidfile): $!";
    <$fh>;
  };
  my $is_running = kill 0, $pid;
  return $pid if $is_running;
}

# We don't seem to be running, so write our PID file.
sub write_pidfile {
  my $name = _get_name();
  my %conf = get_items_by_name($name);
  my $pidfile = $conf{pidfile};
  open my $fh, '>', $pidfile or die "open($pidfile): $!";
  print $fh $$;
  close $fh;
}

1;
