# $Id$

# The PerlMud web server portion of our program.

use strict;

package Server::Web;

use Socket;
use HTTP::Negotiate;
use HTTP::Response;

use POE::Session;
use POE::Preprocessor;
use POE::Component::Server::TCP;
use POE::Filter::HTTPD;

use Util::Conf;
use Util::Web;
use Util::Data;

use Perl::Tidy;

# Dumps the request to stderr.
sub DUMP_REQUEST () { 0 }

sub WEB_SERVER_TYPE () { "web_server" }

sub PAGE_FOOTER () {
  ( "<div align=right><font size='-1'>" .
    "<a href='http://sf.net/projects/pastebot/'>Pastebot</a>" .
    " is powered by " .
    "<a href='http://poe.perl.org/'>POE</a>."
  )
}

macro table_method (<header>) {
  "<tr><td><header></td><td>" . $request-><header>() . "</td></tr>"
}

macro table_header (<header>) {
  "<tr><td><header></td><td>" . $request->header('<header>') . "</td></tr>"
}

#------------------------------------------------------------------------------
# A web server.

# Start an HTTPD session.  Note that this handler receives both the
# local bind() address ($my_host) and the public server address
# ($my_ifname).  It uses $my_ifname to build HTML that the outside
# world can see.

sub httpd_session_started {
  my ( $heap,
       $socket, $remote_address, $remote_port,
       $my_name, $my_host, $my_port, $my_ifname, $my_isrv, $my_chans,
       $proxy, $my_iname,
     ) = @_[HEAP, ARG0..$#_];

  # TODO: I think $my_host is obsolete.  Maybe it can be removed, and
  # $my_ifname can be used exclusively?

  $heap->{my_host}  = $my_host;
  $heap->{my_port}  = $my_port;
  $heap->{my_name}  = $my_name;
  $heap->{my_inam}  = $my_ifname;
  $heap->{my_iname} = $my_iname;
  $heap->{my_isrv}  = $my_isrv;
  $heap->{my_chans} = $my_chans;
  $heap->{my_proxy} = $proxy;

  $heap->{remote_addr} = inet_ntoa($remote_address);
  $heap->{remote_port} = $remote_port;

  $heap->{wheel} = new POE::Wheel::ReadWrite
    ( Handle       => $socket,
      Driver       => new POE::Driver::SysRW,
      Filter       => new POE::Filter::HTTPD,
      InputEvent   => 'got_query',
      FlushedEvent => 'got_flush',
      ErrorEvent   => 'got_error',
    );
}

# An HTTPD response has flushed.  Stop the session.
sub httpd_session_flushed {
  delete $_[HEAP]->{wheel};
}

# An HTTPD session received an error.  Stop the session.
sub httpd_session_got_error {
  my ($session, $heap, $operation, $errnum, $errstr) =
    @_[SESSION, HEAP, ARG0, ARG1, ARG2];
  warn( "connection session ", $session->ID,
        " got $operation error $errnum: $errstr\n"
      );
  delete $heap->{wheel};
}

# Process HTTP requests.
sub httpd_session_got_query {
  my ($kernel, $heap, $request) = @_[KERNEL, HEAP, ARG0];

  ### Log the request.

  # Space-separated list:
  # Remote address (client address)
  # -
  # -
  # [GMT date in brackets: DD/Mon/CCYY:HH:MM:SS -0000]
  # "GET url HTTP/x.y"  <-- in quotes
  # response code
  # response size
  # referer
  # user-agent string

  ### Responded with an error.  Send it directly.

  if ($request->isa("HTTP::Response")) {
    $heap->{wheel}->put($request);
    return;
  }

  ### These requests don't require authentication.

  my $url = $request->url() . '';

  # strip trailing / to prevent odd page errors
  $url =~ s,//+$,/,;

  ### Fetch the highlighted style sheet.

  if ($url eq '/style') {
    my $response =
      static_response( "templates/highlights.css", { } );
    $heap->{wheel}->put( $response );
    return;
  }

  ### Store paste.

  if ($url =~ m,/paste$,) {
    my $content = parse_content($request->content());

    if (defined $content->{paste} and length $content->{paste}) {
      my $channel = $content->{channel};
      defined $channel or $channel = "";
      $channel =~ tr[\x00-\x1F\x7F][]d;

      my $remote_addr = $heap->{remote_addr};
      if ($heap->{my_proxy} && $remote_addr eq $heap->{my_proxy}) {
	# apache sets the X-Forwarded-For header to a list of the 
	# IP addresses that were forwarded from/to
	my $forwarded = $request->headers->header('X-Forwarded-For');
	if ($forwarded) {
	  ($remote_addr) = split ',', $forwarded;
	}
	# else must be local
      }

      if (defined $heap->{my_iname}) {
        my $forwarded = $request->headers->header('X-Forwarded-For');
        if ($forwarded) {
          ($heap->{remote_addr}) = split ',', $forwarded;
        }
      }

      my $error = "";
      if (length $channel) {
        # See if it matches.
        if (is_ignored($heap->{my_isrv}, $channel, $remote_addr)) {
          $error =
            ( "<p><b><font size='+1' color='#800000'>" .
              "Your IP address has been blocked from pasting to $channel." .
              "</font></b></p>"
            );
          $channel = "";
        }
      }

      # Goes as a separate block.
      if (length $channel) {
        unless (grep { "\#$_" eq $channel } @{$heap->{my_chans}}) {
          $error =
            ( "<p><b><font size='+1' color='#800000'>" .
              "The channel you pasted to is not known." .
              "</font></b></p>"
            );
          $channel = "";
        }
      }

      my $nick = $content->{nick};
      $nick = "" unless defined $nick;
      $nick =~ tr[\x00-\x1F\x7F][ ]s;
      $nick =~ s/\s+/ /g;
      $nick =~ s/^\s+//;
      $nick =~ s/\s+$//;
      $nick = html_encode($nick);

      if (length $nick) {
        $nick = qq("$nick");
      } else {
        $nick = "Someone";
      }

      $nick .= " at $remote_addr";

      # <CanyonMan> how about adding a form field with a "Subject"
      # line ?

      my $summary = $content->{summary};
      $summary = "" unless defined $summary;
      $summary =~ tr[\x00-\x1F\x7F][ ]s;
      $summary =~ s/\s+/ /g;
      $summary =~ s/^\s+//;
      $summary =~ s/\s+$//;

      # <TorgoX> [...] in the absence of anything in the subject, it
      # falls back to [the first 30 characters of what's pasted]

      my $paste = $content->{paste};
      unless (length($summary)) {
        $summary = $paste;
        $summary =~ s/\s+/ /g;
        $summary =~ s/^\s+//;
        $summary = substr($summary, 0, 30);
        $summary =~ s/\s+$//;
      }

      $summary = "something" unless length $summary;
      my $html_summary = html_encode($summary);

      my $id = store_paste( $nick, $html_summary, $paste,
                            $heap->{my_isrv}, $channel, $remote_addr
                          );
      my $paste_link;
      if (defined $heap->{my_iname}) {
        $paste_link = $heap->{my_iname} . 
          (($heap->{my_iname} =~ m,/$,) ? $id : "/$id");
      } else {
        $paste_link = "http://$heap->{my_inam}:$heap->{my_port}/$id";
      }

      $paste = fix_paste($paste, 0, 0, 0, 0);

      my $response =
        static_response( "templates/paste-answer.html",
                         { paste_id   => $id,
                           error      => $error,
                           paste_link => $paste_link,
                           nick       => $nick,
                           summary    => $summary,
                           paste      => $paste,
                           footer     => PAGE_FOOTER,
                         }
                       );

      if ($channel and $channel =~ /^\#/) {
        $kernel->post( "irc_client_$heap->{my_isrv}" => announce =>
                       $channel => "$nick pasted \"$summary\" at $paste_link"
                     );
      }

      $heap->{wheel}->put( $response );
      return;
    }

    # Error goes here.
  }

  ### Fetch paste.

  if ($url =~ m{^/(\d+)(?:\?(.*?)\s*)?$}) {
    my ($num, $params) = ($1, $2);
    my ($nick, $summary, $paste) = fetch_paste($num);

    if (defined $paste) {

      my $query = parse_content($params);

      ### Make the paste pretty.

      my $ln   = is_true($query->{ln});
      my $tidy = is_true($query->{tidy});
      my $hl   = is_true($query->{hl});
      my $tx   = is_true($query->{tx});
      my $wr   = is_true($query->{wr});

      my $variants = [
	['html', 1.000, 'text/html',  undef, 'us-ascii', 'en', undef],
	['text', 0.950, 'text/plain', undef, 'us-ascii', 'en', undef],
      ];
      my $choice = choose($variants, $request);
      $tx = 1 if $choice && $choice eq 'text';

      $paste = fix_paste($paste, $ln, $tidy, $hl, $wr) unless $tx;

      # Spew the paste.

      my $response;
      if ($tx) {
        $response = HTTP::Response->new(200);
        $response->push_header( 'Content-type', 'text/plain' );
        $response->content($paste);
      }
      else {
        $response = static_response
          ( "templates/paste-lookup.html",
            { bot_name => $heap->{my_name},
              paste_id => $num,
              nick     => $nick,
              summary  => $summary,
              paste    => $paste,
              footer   => PAGE_FOOTER,
              tidy     => ( $tidy ? "checked" : "" ),
              hl       => ( $hl   ? "checked" : "" ),
              ln       => ( $ln   ? "checked" : "" ),
              tx       => ( $tx   ? "checked" : "" ),
              wr       => ( $wr   ? "checked" : "" ),
            }
          );
      }

      $heap->{wheel}->put( $response );
      return;
    }

    my $response = HTTP::Response->new(404);
    $response->push_header( 'Content-type', 'text/html' );
    $response->content(
      "<html>" .
      "<head><title>Paste Not Found</title></head>" .
      "<body><p>Paste not found.</p></body>" .
      "</html>"
    );
    $heap->{wheel}->put( $response );
    return;
  }

  ### Root page.

  if ($url =~ m,^/(\w+)?,) {

    # Dynamically build the channel options from the configuration
    # file's list.

    my @tmpchans = @{$heap->{my_chans}};
    my @channels;

    # set default channel from request URL, if possible
    my $prefchan = $1;
    if ($prefchan) {
      push @channels, grep { $_ eq $prefchan } @tmpchans;
      push @channels, grep { $_ ne $prefchan } @tmpchans;
    } else {
      @channels = @tmpchans;
    }

    if (@channels) {
      @channels = map { "<option value='\#$_'>\#$_" } @channels;
      $channels[0] =~ s/\'\>\#/\' selected>\#/;
      @channels = sort @channels;
    }
    unshift(@channels, "<option value=''>(none)");

    # Build content.

    my $response =
      static_response( "templates/paste-form.html",
                       { bot_name => $heap->{my_name},
                         channels => "@channels",
                         footer   => PAGE_FOOTER,
                       }
                     );
    $heap->{wheel}->put($response);
    return;
  }

  ### Default handler dumps everything it can about the request.

  my $response = HTTP::Response->new( 200 );
  $response->push_header( 'Content-type', 'text/html' );

  # Many of the headers dumped here are undef.  We turn off warnings
  # here so the program doesn't constantly squeal.

  local $^W = 0;

  $response->content
    ( "<html><head><title>Strange Request Dump</title></head>" .
      "<body>" .
      "<p>" .
      "Your request was strange.  " .
      "Here is everything I could figure out about it:" .
      "</p>" .
      "<table border=1>" .

      {% table_method authorization             %} .
      {% table_method authorization_basic       %} .
      {% table_method content_encoding          %} .
      {% table_method content_language          %} .
      {% table_method content_length            %} .
      {% table_method content_type              %} .
      {% table_method content                   %} .
      {% table_method date                      %} .
      {% table_method expires                   %} .
      {% table_method from                      %} .
      {% table_method if_modified_since         %} .
      {% table_method if_unmodified_since       %} .
      {% table_method last_modified             %} .
      {% table_method method                    %} .
      {% table_method protocol                  %} .
      {% table_method proxy_authorization       %} .
      {% table_method proxy_authorization_basic %} .
      {% table_method referer                   %} .
      {% table_method server                    %} .
      {% table_method title                     %} .
      {% table_method url                       %} .
      {% table_method user_agent                %} .
      {% table_method www_authenticate          %} .

      {% table_header Accept     %} .
      {% table_header Connection %} .
      {% table_header Host       %} .

      {% table_header username  %} .
      {% table_header opaque    %} .
      {% table_header stale     %} .
      {% table_header algorithm %} .
      {% table_header realm     %} .
      {% table_header uri       %} .
      {% table_header qop       %} .
      {% table_header auth      %} .
      {% table_header nonce     %} .
      {% table_header cnonce    %} .
      {% table_header nc        %} .
      {% table_header response  %} .

      "</table>" .

      &dump_content($request->content()) .

      "<p>Request as string=" . $request->as_string() . "</p>" .

      "</body></html>"
    );

  # A little debugging here.
  if (DUMP_REQUEST) {
    my $request_as_string = $request->as_string();
    warn unpack('H*', $request_as_string), "\n";
    warn "Request has CR.\n" if $request_as_string =~ /\x0D/;
    warn "Request has LF.\n" if $request_as_string =~ /\x0A/;
  }

  $heap->{wheel}->put( $response );
  return;
}

# Start the HTTPD server.

foreach my $server (get_names_by_type(WEB_SERVER_TYPE)) {
  my %conf = get_items_by_name($server);
  my %ircconf = get_items_by_name($conf{irc});

  POE::Component::Server::TCP->new
    ( Port     => $conf{port},
      ( (defined $conf{iface})
        ? ( Address => $conf{iface} )
        : ()
      ),
      Acceptor =>
      sub {
        POE::Session->new
          ( _start    => \&httpd_session_started,
            got_flush => \&httpd_session_flushed,
            got_query => \&httpd_session_got_query,
            got_error => \&httpd_session_got_error,

            # Note the use of ifname here in ARG6.  This gives the
            # responding session knowledge of its host name for
            # building HTML responses.  Most of the time it will be
            # identical to iface, but sometimes there may be a reverse
            # proxy, firewall, or NATD between the address we bind to
            # and the one people connect to.  In that case, ifname is
            # the address the outside world sees, and iface is the one
            # we've bound to.

            [ @_[ARG0..ARG2], $server,
              $conf{iface}, $conf{port}, $conf{ifname}, $conf{irc},
              $ircconf{channel}, $conf{proxy}, $conf{iname},
            ],
          );
      },
    );
}

### Fix paste for presentability.

sub fix_paste {
  my ($paste, $line_nums, $tidied, $highlighted, $wrapped) = @_;

  ### If the code is tidied, then tidy it.

  if ($tidied) {
    my $tidy_version = "";
    eval {
      Perl::Tidy::perltidy
        ( source      => \$paste,
          destination => \$tidy_version,
          argv        => [ '-q', '-nanl', '-fnl' ],
        );
    };
    if ($@) {
      $paste = "Could not tidy this paste (try turning tidying off): $@";
    }
    else {
      $paste = $tidy_version;
    }
  }

  ### If the code is to be highlighted, then highlight it.

  if ($highlighted) {
    my @html_args = qw( -q -html -pre );
    push @html_args, "-nnn" if $line_nums;

    my $highlighted = "";
    eval {
      Perl::Tidy::perltidy
        ( source      => \$paste,
          destination => \$highlighted,
          argv        => \@html_args,
        );
    };
    if ($@) {
      $highlighted =
        "Could not highlight the paste (try turning highlighting off): $@";
    }
    return $highlighted;
  }

  ### Code's not highlighted.  HTML escaping time.  Forgive me.

  # Prepend line numbers to each line.

  if ($line_nums) {
    my $total_lines = 0;
    $total_lines++ while ($paste =~ m/^/gm);
    my $line_number_width = length($total_lines);
    $line_number_width = 4 if $line_number_width < 4;  # To match Perl::Tidy.

    my $line_number = 0;
    while ($paste =~ m/^/gm) {
      my $pos = pos($paste);
      substr($paste, pos($paste), 0) =
        sprintf("\%${line_number_width}d ", ++$line_number);
      pos($paste) = $pos + 1;
    }
  }

  $paste = html_encode($paste);

  # Normalize newlines.  Translate whichever format to just \n, and
  # limit the number of consecutive newlines to two.

  $paste =~ s/(\x0d\x0a?|\x0a\x0d?)/\n/g;
  $paste =~ s/\n\n+/\n\n/;

  # Buhbye.

  unless ($wrapped) {
    substr($paste, 0, 0) = "<pre>";
    $paste .= "</pre>";
  }

  return $paste;
}

#------------------------------------------------------------------------------
1;
