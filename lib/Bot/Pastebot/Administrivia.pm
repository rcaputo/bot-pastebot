# Miscellaneous administrivia.

package Bot::Pastebot::Administrivia;

use warnings;
use strict;

use Carp qw(croak);
use Bot::Pastebot::Conf qw( get_names_by_type get_items_by_name );

use base qw(Exporter);
our @EXPORT_OK = qw(get_pastebot_pid);

# Return this module's configuration.

use Bot::Pastebot::Conf qw(SCALAR REQUIRED);

my %conf = (
  administrivia => {
    name      => SCALAR | REQUIRED,
    pidfile   => SCALAR | REQUIRED,
  },
);

sub get_conf { return %conf }

# Examine the PID file to see if there's a session running already.
sub get_pastebot_pid {
  my %conf = get_items_by_name('administrivia');
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
sub write_pid_file {
  my %conf = get_items_by_name('administrivia');
  my $pidfile = $conf{pidfile};
  open my $fh, '>', $pidfile or die "open($pidfile): $!";
  print $fh $$;
  close $fh;
}
1;
