# Rocco's IRC bot stuff.

package Bot::Pastebot::Client::Irc;

use strict;

use POE::Session;
use POE::Component::IRC::State;

sub MSG_SPOKEN    () { 0x01 }
sub MSG_WHISPERED () { 0x02 }
sub MSG_EMOTED    () { 0x04 }

use Bot::Pastebot::Conf qw( get_names_by_type get_items_by_name );
use Bot::Pastebot::Data qw(
  clear_channels fetch_paste_channel delete_paste
  clear_channel_ignores set_ignore clear_ignore get_ignores
  add_channel remove_channel channels
);
use Bot::Pastebot::Server::Http;

my %helptext =
  (
   help => <<EOS,
Commands: help, ignore, ignores, delete, about, uptime. Use help
<command> for help on that command Other topics: about wildcards
pasteids
EOS
   ignore => <<EOS,
Usage: ignore <wildcard> [<channels>] where <wildcard> is a wildcard
IP address.  It is only ignored for the given channels of those you
are an operator on. Put - in front of a mask to remove it.  "ignore -"
to delete all ignores.
EOS
   ignores => <<EOS,
Usage: ignores <channel>.  Returns a list of all ignores on <channel>.
EOS
   delete => <<EOS,
Usage: delete <pasteid> where <pasteid> has been pasted to the
bot. You can only delete pastes to a channel you are an operator on.
EOS
   about => <<EOS,
pastebot is intended to reduce the incidence of pasting of large
amounts of text to channels, and the aggravation caused those pastes.
The user pastes to a web based form (see the /whois for this bot), and
this bot announces the URL in the specified channel
EOS
   wildcards => <<EOS,
A set of 4 sets of digits or *.  Valid masks: 168.76.*.*, 194.237.235.226
Invalid masks: 168.76.*, *.76.235.226
EOS
   pasteids => <<EOS,
The digits in the paste URL after the host and port.  eg. in
http://nopaste.snit.ch:8000/22 the pasteid is 22
EOS
   uptime => <<EOS,
Display how long the program has been running and how much CPU it has
consumed.
EOS
  );

# easy to enter, make it suitable to send
for my $key (keys %helptext) {
  $helptext{$key} =~ tr/\n /  /s;
  $helptext{$key} =~ s/\s+$//;
}

# Return this module's configuration.

use Bot::Pastebot::Conf qw(SCALAR LIST REQUIRED);

my %conf = (
  irc => {
    name          => SCALAR | REQUIRED,
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
    nickserv_pass => SCALAR,
  },
);

sub get_conf { return %conf }

#------------------------------------------------------------------------------

sub initialize {

  # Build a map from IRC name to web server name I could add an extra
  # key to the irc sections but that would be redundant

  my %irc_to_web;
  foreach my $webserver (get_names_by_type('web_server')) {
    my %conf = get_items_by_name($webserver);
    $irc_to_web{$conf{irc}} = $webserver;
  }

  foreach my $server (get_names_by_type('irc')) {
    my %conf = get_items_by_name($server);

    my $web_alias = $irc_to_web{$server};
    my $irc = POE::Component::IRC::State->spawn();

    POE::Session->create(
      inline_states => {
        _start => sub {
          my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

          $kernel->alias_set( "irc_client_$server" );
          $irc->yield( register => 'all' );

          $heap->{server_index} = 0;

          # Keep-alive timer.
          $kernel->delay( autoping => 300 );

          $kernel->yield( 'connect' );
        },

        autoping => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          $irc->yield( userhost => $heap->{my_nick})
            unless $heap->{seen_traffic};
          $heap->{seen_traffic} = 0;
          $kernel->delay( autoping => 300 );
        },

        connect => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];

          my $chosen_server = $conf{server}->[$heap->{server_index}];
          my $chosen_port = 6667;
          if ($chosen_server =~ s/[\s\:]+(\S+)\s*$//) {
            $chosen_port = $1;
          }

          # warn "server($chosen_server) port($chosen_port)";

          $heap->{nick_index} = 0;
          $heap->{my_nick} = $conf{nick}->[$heap->{nick_index}];

          $irc->yield(
            connect => {
              Debug     => 1,
              Nick      => $heap->{my_nick},
              Server    => $chosen_server,
              Port      => $chosen_port,
              Username  => $conf{uname},
              Ircname   => $conf{iname},
              LocalAddr => $conf{localaddr},
            }
          );

          $heap->{server_index}++;
          $heap->{server_index} = 0 if $heap->{server_index} >= @{$conf{server}};
        },

        join => sub {
          my ($kernel, $channel) = @_[KERNEL, ARG0];
          $irc->yield( join => $channel );
        },

        irc_msg => sub {
          my ($kernel, $heap, $sender, $msg) = @_[KERNEL, HEAP, ARG0, ARG2];

          my ($nick) = $sender =~ /^([^!]+)/;
          print "Message $msg from $nick\n";

          $msg = remove_colors($msg);

          if ($msg =~ /^\s*help(?:\s+(\w+))?\s*$/) {
            my $what = $1 || 'help';
            if ($helptext{$what}) {
              $irc->yield( privmsg => $nick, $helptext{$what} );
            }
          }
          elsif ($msg =~ /^\s*ignore\s/) {
            unless ($msg =~ /^\s*ignore\s+(\S+)(?:\s+(\S+))?\s*$/) {
              $irc->yield(
                privmsg => $nick, "Usage: ignore <wildcard> [<channels>]"
              );
              return;
            }
            my ($mask, $channels) = ($1, $2);
            unless (
              $mask =~ /^-?\d+(\.(\*|\d+)){3}$/ || $mask eq '-'
            ) {
              $irc->yield(
                privmsg => $nick, "Invalid wildcard.  Try: help wildcards"
              );
              return;
            }
            my @igchans;
            if ($channels) {
              @igchans = split ',', lc $channels;
            }
            else {
              @igchans = map lc, channels($conf{name});
            }
            # only the channels the user is an operator on
            @igchans = grep {
              exists $heap->{users}{$_}{$nick}{mode} and
              $heap->{users}{$_}{$nick}{mode} =~ /@/
            } @igchans;
            @igchans or return;

            if ($mask eq '-') {
              for my $chan (@igchans) {
                clear_channel_ignores($conf{name}, $chan);
                print "Nick '$nick' deleted all ignores on $chan\n";
              }
              $irc->yield(
                privmsg => $nick => "Removed all ignores on @igchans"
              );
            }
            elsif ($mask =~ /^-(.*)$/) {
              my $clearmask = $1;
              for my $chan (@igchans) {
                clear_ignore($conf{name}, $chan, $clearmask);
              }
              $irc->yield(
                privmsg => $nick => "Removed ignore $clearmask on @igchans"
              );
            }
            else {
              for my $chan (@igchans) {
                set_ignore($conf{name}, $chan, $mask);
              }
              $irc->yield(
                privmsg => $nick => "Added ignore mask $mask on @igchans"
              );
            }
          }
          elsif ($msg =~ /^\s*ignores\s/) {
            unless ($msg =~ /^\s*ignores\s+(\#\S+)\s*$/) {
              $irc->yield( privmsg => $nick, "Usage: ignores <channel>" );
              return;
            }
            my $channel = lc $1;
            my @masks = get_ignores($conf{name}, $channel);
            unless (@masks) {
              $irc->yield( privmsg => $nick, "No ignores on $channel" );
              return;
            }
            my $text = join " ", @masks;
            substr($text, 100) = '...' unless length $text < 100;
            $irc->yield( privmsg => $nick, "Ignores on $channel are: $text" );
          }
          elsif ($msg =~ /^\s*delete\s/) {
            unless ($msg =~ /^\s*delete\s+(\d+)\s*$/) {
              $irc->yield( privmsg => $nick, "Usage: delete <pasteid>" );
              return;
            }
            my $pasteid = $1;
            my $paste_chan = fetch_paste_channel($pasteid);

            if (defined $paste_chan) {
              if ($heap->{users}{$paste_chan}{$nick}{mode} =~ /@/) {
                delete_paste($conf{name}, $paste_chan, $pasteid, $nick)
                  or print "It didn't delete!\n";
                $irc->yield( privmsg => $nick => "Deleted paste $pasteid" );
              }
              else {
                $irc->yield(
                  privmsg => $nick =>
                  "Paste $pasteid was sent to $paste_chan - " .
                  "you aren't a channel operator on $paste_chan"
                );
              }
            }
            else {
              $irc->yield( privmsg => $nick => "No such paste" );
            }
          }
          elsif ($msg =~ /^\s*uptime\s*$/) {
            my ($user_time, $system_time) = (times())[0,1];
            my $wall_time = (time() - $^T) || 1;
            my $load_average = sprintf(
              "%.4f", ($user_time+$system_time) / $wall_time
            );
            $irc->yield(
              privmsg => $nick,
              "I was started on " . scalar(gmtime($^T)) . " GMT. " .
              "I've been active for " . format_elapsed($wall_time, 2) . ". " .
              sprintf(
                "I have used about %.2f%% of a CPU during my lifespan.",
                (($user_time+$system_time)/$wall_time) * 100
              )
            );
          }
        },

        # negative on /whois
        irc_401 => sub {
          my ($kernel, $heap, $msg) = @_[KERNEL, HEAP, ARG1];

          my ($nick) = split ' ', $msg;
          delete $heap->{work}{lc $nick};
        },

        # Nick is in use
        irc_433 => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];

          $heap->{nick_index}++;
          my $newnick = $conf{nick}->[$heap->{nick_index} % @{$conf{nick}}];
          if ($heap->{nick_index} >= @{$conf{nick}}) {
            $newnick .= $heap->{nick_index} - @{$conf{nick}};
            $kernel->delay( ison => 120 );
          }
          $heap->{my_nick} = $newnick;

          warn "Nickclash, now trying $newnick\n";
          $irc->yield( nick => $newnick );
        },

        ison => sub {
          $irc->yield( ison => @{$conf{nick}} );
        },

        # ISON reply
        irc_303 => sub {
          my ($kernel, $heap, $nicklist) = @_[KERNEL, HEAP, ARG1];

          my @nicklist = split " ", lc $nicklist;
          for my $totry (@{$conf{nick}}) {
            unless (grep $_ eq lc $totry, @nicklist) {
              $irc->yield( nick => $totry );
              return;
            }
          }
          $kernel->delay( ison => 120 );
        },

        _stop => sub {
          my $kernel = $_[KERNEL];
          $irc->yield( quit => $conf{quit} );
        },

        _default => sub {
          my ($state, $event, $args, $heap) = @_[STATE, ARG0, ARG1, HEAP];
          $args ||= [ ];
          print "default $state = $event (@$args)\n";
          $heap->{seen_traffic} = 1;
          return 0;
        },

        irc_001 => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];

          if (defined $conf{flags}) {
            $irc->yield( mode => $heap->{my_nick} => $conf{flags} );
          }
          $irc->yield( away => $conf{away} );

          foreach my $channel (@{$conf{channel}}) {
            $channel =~ s/^#//;
            $kernel->yield( join => "\#$channel" );
          }

          if (defined $conf{nickserv_pass}) {
             $irc->yield(
                privmsg => 'NickServ',
                "IDENTIFY $conf{nickserv_pass}"
             );
          }

          $heap->{server_index} = 0;
        },

        announce => sub {
          my ($kernel, $heap, $channel, $message) =
            @_[KERNEL, HEAP, ARG0, ARG1];

    my ($nick, $addr) = $message =~ /^"?(.*?)"? at ([\d\.]+) /;

    if (my $data = $irc->nick_info ($nick)) {
      #TODO: maybe check $addr with $data->{Host} ?
      #      instead of the simple nick test below
    }

    if (   $nick eq "Someone"
        or $irc->is_channel_member( $channel, $nick)) {
            $irc->yield( privmsg => $channel => $message );
    }
        },

        irc_ctcp_version => sub {
          my ($kernel, $sender) = @_[KERNEL, ARG0];
          my $who = (split /!/, $sender)[0];
          print "ctcp version from $who\n";
          $irc->yield( ctcpreply => $who, "VERSION $conf{cver}" );
        },

        irc_ctcp_clientinfo => sub {
          my ($kernel, $sender) = @_[KERNEL, ARG0];
          my $who = (split /!/, $sender)[0];
          print "ctcp clientinfo from $who\n";
          $irc->yield( ctcpreply => $who, "CLIENTINFO $conf{ccinfo}" );
        },

        irc_ctcp_userinfo => sub {
          my ($kernel, $sender) = @_[KERNEL, ARG0];
          my $who = (split /!/, $sender)[0];
          print "ctcp userinfo from $who\n";
          $irc->yield( ctcpreply => $who, "USERINFO $conf{cuinfo}" );
        },

        irc_invite => sub {
          my ($kernel, $who, $where) = @_[KERNEL, ARG0, ARG1];
          $where =~ s/^#//;
          if ( $conf{join_cfg_only} &&
               1 > grep $_ eq $where, @{$conf{channel}} ) {
            print "$who invited me to $where, but i'm not allowed\n";
          }
          else {
            $kernel->yield( join => "#$where" )
          }
        },

        irc_join => sub {
          my ($kernel, $heap, $who, $where) = @_[KERNEL, HEAP, ARG0, ARG1];
          my ($nick) = $who =~ /^([^!]+)/;
          if (lc ($nick) eq lc($heap->{my_nick})) {
            add_channel($conf{name}, $where);
            $irc->yield( who => $where );
          }
          @{$heap->{users}{$where}{$nick}}{qw(ident host)} =
            (split /[!@]/, $who, 8)[1, 2];
        },

        irc_kick => sub {
          my ($kernel, $heap, $who, $where, $nick, $reason)
            = @_[KERNEL, HEAP, ARG0..ARG3];
          print "$nick was kicked from $where by $who: $reason\n";
          delete $heap->{users}{$where}{$nick};
          if (lc($nick) eq lc($heap->{my_nick})) {
            remove_channel($conf{name}, $where);
            delete $heap->{users}{$where};
          }
          # $kernel->delay( join => 15 => $where );
        },

        irc_quit => sub {
          my ($kernel, $heap, $who, $what) = @_[KERNEL, HEAP, ARG0, ARG1];

          my ($nick) = $who =~ /^([^!]+)/;
          for (keys %{$heap->{users}}) {
            delete $heap->{users}{$_}{$nick};
          }
        },

        irc_part => sub {
          my ($kernel, $heap, $who, $where) = @_[KERNEL, HEAP, ARG0, ARG1];

          my ($nick) = $who =~ /^([^!]+)/;
          delete $heap->{users}{$where}{$nick};
        },

        # who reply
        irc_352 => sub {
          my ($kernel, $heap, $what) = @_[KERNEL, HEAP, ARG1];

          my @reply = split " ", $what, 8;
          @{$heap->{users}{$reply[0]}{$reply[4]}}{qw(ident host mode real)} = (
            $reply[1], $reply[2], $reply[5], $reply[7]
          );
        },

        irc_mode => sub {
          my ($kernel, $heap, $issuer, $location, $modestr, @targets)
            = @_[KERNEL, HEAP, ARG0..$#_];

          my $set = "+";
          for (split //, $modestr) {
            $set = $_ if ($_ eq "-" or $_ eq "+");
            if (/[bklovehI]/) { # mode has argument
              my $target = shift @targets;
              if ($_ eq "o") {
                if ($set eq "+") {
                  $heap->{users}{$location}{$target}{mode} .= '@'
                    unless $heap->{users}{$location}{$target}{mode} =~ /\@/;
                }
                else {
                  $heap->{users}{$location}{$target}{mode} =~ s/\@//;
                }
              }
            }
          }
        },

        # end of /names
        irc_315 => sub {},
        # end of /who
        irc_366 => sub {},

        irc_disconnected => sub {
          my ($kernel, $heap, $server) = @_[KERNEL, HEAP, ARG0];
          print "Lost connection to server $server.\n";
          clear_channels($conf{name});
          delete $heap->{users};
          $kernel->delay( connect => 60 );
        },

        irc_error => sub {
          my ($kernel, $heap, $error) = @_[KERNEL, HEAP, ARG0];
          print "Server error occurred: $error\n";
          clear_channels($conf{name});
          delete $heap->{users};
          $kernel->delay( connect => 60 );
        },

        irc_socketerr => sub {
          my ($kernel, $heap, $error) = @_[KERNEL, HEAP, ARG0];
          print "IRC client ($server): socket error occurred: $error\n";
          clear_channels($conf{name});
          delete $heap->{users};
          $kernel->delay( connect => 60 );
        },

        irc_public => sub {
          my ($kernel, $heap, $who, $where, $msg) = @_[KERNEL, HEAP, ARG0..ARG2];
          $who = (split /!/, $who)[0];
          $where = $where->[0];
          print "<$who:$where> $msg\n";

          $heap->{seen_traffic} = 1;

          # Do something with input here?
          # If so, remove colors from it first.
        },
      },
    );
  }
}

# Helper function.  Display a number of seconds as a formatted period
# of time.  NOT A POE EVENT HANDLER.

sub format_elapsed {
  my ($secs, $precision) = @_;
  my @fields;

  # If the elapsed time can be measured in weeks.
  if (my $part = int($secs / 604800)) {
    $secs %= 604800;
    push(@fields, $part . 'w');
  }

  # If the remaining time can be measured in days.
  if (my $part = int($secs / 86400)) {
    $secs %= 86400;
    push(@fields, $part . 'd');
  }

  # If the remaining time can be measured in hours.
  if (my $part = int($secs / 3600)) {
    $secs %= 3600;
    push(@fields, $part . 'h');
  }

  # If the remaining time can be measured in minutes.
  if (my $part = int($secs / 60)) {
    $secs %= 60;
    push(@fields, $part . 'm');
  }

  # If there are any seconds remaining, or the time is nothing.
  if ($secs || !@fields) {
    push(@fields, $secs . 's');
  }

  # Reduce precision, if requested.
  pop(@fields) while $precision and @fields > $precision;

  # Combine the parts.
  join(' ', @fields);
}

# Helper functions.  Remove color codes from a message.

sub remove_colors {
  my $msg = shift;

  # Indigoid supplied these regexps to extract colors.
  $msg =~ s/[\x02\x0F\x11\x12\x16\x1d\x1f]//g;    # Regular attributes.
  $msg =~ s/\x03[0-9,]*//g;                       # mIRC colors.
  $msg =~ s/\x04[0-9a-f]+//ig;                    # Other colors.

  return $msg;
}

1;
