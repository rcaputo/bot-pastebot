# $Id$

# Rocco's IRC bot stuff.

package Client::IRC;

use strict;

use POE::Session;
use POE::Component::IRC;

sub MSG_SPOKEN    () { 0x01 }
sub MSG_WHISPERED () { 0x02 }
sub MSG_EMOTED    () { 0x04 }

use Util::Conf;
use Util::Data;
use Server::Web;

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

#------------------------------------------------------------------------------
# Build a map from IRC name to web server name I could add an extra
# key to the irc sections but that would be redundant

my %irc_to_web;
foreach my $webserver (get_names_by_type('web_server')) {
  my %conf = get_items_by_name($webserver);
  $irc_to_web{$conf{irc}} = $webserver;
}

#------------------------------------------------------------------------------
# Spawn the IRC session.

foreach my $server (get_names_by_type('irc')) {
  my %conf = get_items_by_name($server);

  my $web_alias = $irc_to_web{$server};

  POE::Component::IRC->new($server);

  POE::Session->create
    ( inline_states =>
      { _start => sub {
          my ($kernel, $heap, $session) = @_[KERNEL, HEAP, SESSION];

          $kernel->alias_set( "irc_client_$server" );
          $kernel->post( $server => register => 'all' );

          $heap->{server_index} = 0;

          # Keep-alive timer.
          $kernel->delay( autoping => 300 );

          $kernel->yield( 'connect' );
        },

        autoping => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];
          $kernel->post( $server => userhost => $conf{nick} )
            unless $heap->{seen_traffic};
          $heap->{seen_traffic} = 0;
          $kernel->delay( autoping => 300 );
        },

        connect => sub {
          my ($kernel, $heap) = @_[KERNEL, HEAP];

          my $server = $conf{server}->[$heap->{server_index}];
          my $port = 6667;
          if ($server =~ s/[\s\:]+(\S+)\s*$//) {
            $port = $1;
          }

          warn "server($server) port($port)";

          $kernel->post( $server => connect =>
                         { Debug     => 0,
                           Nick      => $conf{nick},
                           Server    => $server,
                           Port      => $port,
                           Username  => $conf{uname},
                           Ircname   => $conf{iname},
                           LocalAddr => $conf{localaddr},
                         }
                       );

          $heap->{server_index}++;
          $heap->{server_index} = 0
            if $heap->{server_index} >= @{$conf{server}};
      },

      join => sub {
        my ($kernel, $channel) = @_[KERNEL, ARG0];
        $kernel->post( $server => join => $channel );
      },

      irc_msg => sub {
	my ($kernel, $heap, $sender, $msg) = @_[KERNEL, HEAP, ARG0, ARG2];

	my ($nick) = $sender =~ /^([^!]+)/;
	print "Message $msg from $nick\n";
	if ($msg =~ /^\s*help(?:\s+(\w+))?\s*$/) {
	  my $what = $1 || 'help';
	  if ($helptext{$what}) {
	    $kernel->post( $server => privmsg => $nick,
			   $helptext{$what});
	  }
	}
	elsif ($msg =~ /^\s*ignore\s/) {
	  unless ($msg =~ /^\s*ignore\s+(\S+)(?:\s+(\S+))?\s*$/) {
	    $kernel->post( $server => privmsg => $nick,
			   "Usage: ignore <wildcard> [<channels>]");
	    return;
	  }
	  my ($mask, $channels) = ($1, $2);
	  unless ($mask =~ /^-?\d+(\.(\*|\d+)){3}$/
		 || $mask eq '-') {
	    $kernel->post($server => privmsg => $nick,
			  "Invalid wildcard.  Try: help wildcards");
	    return;
	  }

	  # save it for later
	  push(@{$heap->{work}{lc $nick}},
	       [ ignore => $mask => $channels ]);

	  # only for chanops - find out where they are
	  @{$heap->{work}{lc $nick}} > 1
	    or $kernel->post($server => whois => $nick );
	}
	elsif ($msg =~ /^\s*ignores\s/) {
	  unless ($msg =~ /^\s*ignores\s+(\#\S+)\s*$/) {
	    $kernel->post( $server => privmsg => $nick,
			   "Usage: ignores <channel>");
	    return;
	  }
	  my $channel = lc $1;
	  my @masks = get_ignores($conf{name}, $channel);
	  unless (@masks) {
	    $kernel->post( $server => privmsg => $nick,
			   "No ignores on $channel" );
	    return;
	  }
	  my $text = join " ", @masks;
	  substr($text, 100) = '...' unless length $text < 100;
	  $kernel->post( $server=> privmsg => $nick,
			 "Ignores on $channel are: $text");
	}
	elsif ($msg =~ /^\s*delete\s/) {
	  unless ($msg =~ /^\s*delete\s+(\d+)\s*$/) {
	    $kernel->post( $server => privmsg => $nick,
			   "Usage: delete <pasteid>");
	    return;
	  }

	  # save it for later
	  push(@{$heap->{work}{lc $nick}}, [ delete => $1 ]);

	  @{$heap->{work}{lc $nick}} > 1
	    or $kernel->post($server => whois => $nick );
	}
        elsif ($msg =~ /^\s*uptime\s*$/) {
          my ($user_time, $system_time) = (times())[0,1];
          my $wall_time = (time() - $^T) || 1;
          my $load_average =
            sprintf("%.4f", ($user_time+$system_time) / $wall_time);
          $kernel->post
            ( $server => privmsg => $nick,
              "I was started on " . scalar(gmtime($^T)) . " GMT. " .
              "I've been active for " . format_elapsed($wall_time, 2) . ". " .
              sprintf( "I have used about %.2f%% of a CPU during my lifespan.",
                       (($user_time+$system_time)/$wall_time) * 100
                     )
            );
        }
      },

      irc_319 => sub {
	my ($kernel, $heap, $msg) = @_[KERNEL, HEAP, ARG1];

	my ($nick, $channels) = split ' ', $msg, 2;
	$channels =~ s/^://;
	my @channels = grep /^@/, split ' ', lc $channels;
	s/^@// for @channels;
	my %channels = map { $_, $_ } @channels;

	my $work = delete $heap->{work}{lc $nick};
	for my $job (@$work) {
	  my $action = shift @$job;
	  if ($action eq 'ignore') {
	    my ($mask, $channels) = @$job;
	    my @igchans;
	    if ($channels) {
	      @igchans = split ',', lc $channels;
	    }
	    else {
	      @igchans = map "#\L$_", @{$conf{channel}};
	    }
	    # only the channels the user is an operator on
	    @igchans = grep $channels{$_}, @igchans;
	    @igchans or next;
	    if ($mask eq '-') {
	      for my $chan (@igchans) {
		clear_channel_ignores($conf{name}, $chan);
		print "Nick '$nick' deleted all ignores on $chan\n";
	      }
	      $kernel->post( $server => privmsg => $nick =>
			     "Removed all ignores on @igchans");
	    }
	    elsif ($mask =~ /^-(.*)$/) {
	      my $mask = $1;
	      for my $chan (@igchans) {
		clear_ignore($conf{name}, $chan, $mask);
	      }
	      $kernel->post( $server => privmsg => $nick =>
			     "Removed ignore $mask on @igchans");
	    }
	    else {
	      for my $chan (@igchans) {
		set_ignore($conf{name}, $chan, $mask);
	      }
	      $kernel->post( $server => privmsg => $nick =>
			     "Added ignore mask $mask on @igchans");
	    }
	  }
	  elsif ($action eq 'delete') {
	    my $paste_chan = fetch_paste_channel($job->[0]);

	    if (defined $paste_chan) {
	      if ($channels{lc $paste_chan}) {
		delete_paste($conf{name}, $paste_chan, $job->[0], $nick)
		  or print "It didn't delete!\n";
		$kernel->post( $server => privmsg => $nick =>
			       "Deleted paste $job->[0]")
	      }
	      else {
		$kernel->post( $server => privmsg => $nick =>
			       "Paste $job->[0] was sent to $paste_chan - " .
                               "you aren't a channel operator on $paste_chan"
                             )
	      }
	    }
	    else {
	      $kernel->post( $server => privmsg => $nick =>
			     "No such paste")
	    }
	  }
	  else {
	    print "Unknown action $action\n";
	  }
	}

      },

      # negative on /whois
      irc_401 => sub {
	my ($kernel, $heap, $msg) = @_[KERNEL, HEAP, ARG1];

	my ($nick) = split ' ', $msg;
	delete $heap->{work}{lc $nick};
      },

      _stop => sub {
        my $kernel = $_[KERNEL];
        $kernel->post( $server => quit => $conf{quit} );
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
          $kernel->post( $server => mode => $conf{nick} => $conf{flags} );
        }
        $kernel->post( $server => away => $conf{away} );

        foreach my $channel (@{$conf{channel}}) {
          $kernel->yield( join => "\#$channel" );
        }

        $heap->{server_index} = 0;
      },

      announce => sub {
        my ($kernel, $heap, $channel, $message) = @_[KERNEL, HEAP, ARG0, ARG1];
        $kernel->post( $server => privmsg => $channel => $message );
      },

      irc_ctcp_version => sub {
        my ($kernel, $sender) = @_[KERNEL, ARG0];
        my $who = (split /!/, $sender)[0];
        print "ctcp version from $who\n";
        $kernel->post( $server => ctcpreply => $who, "VERSION $conf{cver}" );
      },

      irc_ctcp_clientinfo => sub {
        my ($kernel, $sender) = @_[KERNEL, ARG0];
        my $who = (split /!/, $sender)[0];
        print "ctcp clientinfo from $who\n";
        $kernel->post( $server => ctcpreply =>
                       $who, "CLIENTINFO $conf{ccinfo}"
                     );
      },

      irc_ctcp_userinfo => sub {
        my ($kernel, $sender) = @_[KERNEL, ARG0];
        my $who = (split /!/, $sender)[0];
        print "ctcp userinfo from $who\n";
        $kernel->post( $server => ctcpreply =>
                       $who, "USERINFO $conf{cuinfo}"
                     );
      },

      irc_invite => sub {
        my ($kernel, $who, $where) = @_[KERNEL, ARG0, ARG1];
        $kernel->yield( join => $where );
      },

      irc_join => sub {
        my ($kernel, $who, $where) = @_[KERNEL, ARG0, ARG1];
        my ($nick) = $who =~ /^([^!]+)/;
        add_channel($where) if lc $nick eq lc $conf{nick};
      },

      irc_kick => sub {
        my ($kernel, $who, $where, $nick, $reason) = @_[KERNEL, ARG0..ARG3];
        print "$who was kicked from $where: $reason\n";
        remove_channel($where) if lc $nick eq lc $conf{nick};
        # $kernel->delay( join => 15 => $where );
      },

      irc_disconnected => sub {
        my ($kernel, $server) = @_[KERNEL, ARG0];
        print "Lost connection to server $server.\n";
        clear_channels();
        $kernel->delay( connect => 60 );
      },

      irc_error => sub {
        my ($kernel, $error) = @_[KERNEL, ARG0];
        print "Server error occurred: $error\n";
        clear_channels();
        $kernel->delay( connect => 60 );
      },

      irc_socketerr => sub {
        my ($kernel, $error) = @_[KERNEL, ARG0];
        print "IRC client ($server): socket error occurred: $error\n";
        clear_channels();
        $kernel->delay( connect => 60 );
      },

      irc_public => sub {
        my ($kernel, $heap, $who, $where, $msg) = @_[KERNEL, HEAP, ARG0..ARG2];
        $who = (split /!/, $who)[0];
        $where = $where->[0];
        print "<$who:$where> $msg\n";

        $heap->{seen_traffic} = 1;

        # Do something with input here?
      },
    },
  );
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

#------------------------------------------------------------------------------
1;
