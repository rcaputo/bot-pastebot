# $Id$

# The PerlMud web server portion of our program.

use strict;

package Server::Web;

use Socket;
use HTTP::Response;

use POE::Session;
use POE::Preprocessor;
use POE::Component::Server::TCP;
use POE::Filter::HTTPD;

use Util::Conf;
use Util::Web;
use Util::Data;

# Dumps the request to stderr.
sub DUMP_REQUEST () { 0 }

sub WEB_SERVER_TYPE () { "web_server" }

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
       $my_name, $my_host, $my_port, $my_ifname, $my_isrv, $my_chans
     ) = @_[HEAP, ARG0..ARG8];

  # TODO: I think $my_host is obsolete.  Maybe it can be removed, and
  # $my_ifname can be used exclusively?

  $heap->{my_host}  = $my_host;
  $heap->{my_port}  = $my_port;
  $heap->{my_name}  = $my_name;
  $heap->{my_inam}  = $my_ifname;
  $heap->{my_isrv}  = $my_isrv;
  $heap->{my_chans} = $my_chans;

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

  ### Store paste.

  if ($url eq '/paste') {
    my $content = parse_content($request->content());

    if (defined $content->{paste} and length $content->{paste}) {
      my $channel = $content->{channel};
      defined $channel or $channel = "";

      my $error = "";
      if ($channel) {
        # See if it matches.
        if (is_ignored($heap->{my_isrv}, $channel, $heap->{remote_addr})) {
          $error =
            ( "<p><b>" .
              "Your IP address has been blocked from pasting to $channel." .
              "</b></p>"
            );
          $channel = "";
        }
      }

      my $nick = $content->{nick};
      $nick = "" unless defined $nick;
      $nick =~ s/\s+/ /g;
      $nick =~ s/^\s+//;
      $nick =~ s/\s+$//;
      $nick = html_encode($nick);

      if (length $nick) {
        $nick = qq("$nick");
      } else {
        $nick = "Someone";
      }

      $nick .= " at $heap->{remote_addr}";

      # <CanyonMan> how about adding a form field with a "Subject"
      # line ?

      my $summary = $content->{summary};
      $summary = "" unless defined $summary;
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

      $summary = html_encode($summary);
      $summary = "something" unless length $summary;

      my $id = store_paste( $nick, $summary, $paste,
                            $heap->{my_isrv}, $channel, $heap->{remote_addr}
                          );
      my $paste_link = "http://$heap->{my_inam}:$heap->{my_port}/$id";

      $paste = fix_paste($paste);

      my $response = HTTP::Response->new(200);
      $response->push_header( 'Content-type', 'text/html' );
      $response->content
        ( "<html><head><title>You pasted...</title></head><body>" .
          $error .
          "<p>" .
          "This paste is stored as <a href='$paste_link'>$paste_link</a>." .
          "</p><p>" .
          "From: $nick" .
          "<br>" .
          "Summary: ($summary)" .
          "</p>" .
          "<pre>$paste</pre>" .
          "</body></html>"
        );

      if ($channel and $channel =~ /^\#/) {
        $kernel->post( "irc_client_$heap->{my_isrv}" => announce =>
                       $channel => "$nick pasted $summary at $paste_link"
                     );
      }

      $heap->{wheel}->put( $response );
      return;
    }

    # Error goes here.
  }

  ### Fetch paste.

  if ($url =~ m!^/(\d+)(/nolines)?!) {
    my ($num, $nolines) = ($1, $2);
    my ($nick, $summary, $paste) = fetch_paste($num);

    if (defined $paste) {

      ### Make the paste pretty.

      my $paste = fix_paste($paste, $nolines);

      # Spew the paste.

      my $response = HTTP::Response->new(200);
      $response->push_header( 'Content-type', 'text/html' );
      $response->content
        ( "<html><head><title>Introducing... paste!</title></head>" .
          "<body><h1>Here you go...</h1>" .
          ( $nolines
            ? qq(<p><a href="/$num">Add line numbers.</a></p>)
            : qq(<p><a href="/$num/nolines">Remove line numbers.</a></p>)
          ) .
          "<p>" .
          "From: $nick" .
          "<br>" .
          "Summary: $summary" .
          "</p>" .
          "<pre>$paste</pre>" .
          "</body></html>"
        );

      $heap->{wheel}->put( $response );
      return;
    }

    my $response = HTTP::Response->new(404);
    $response->push_header( 'Content-type', 'text/html' );
    $heap->{wheel}->put( $response );
    return;
  }

  ### Root page.

  if ($url eq '/') {
    my $response = HTTP::Response->new(200);
    $response->push_header( 'Content-type', 'text/html' );

    # Dynamically build the channel options from the configuration
    # file's list.  The first one is the default.

    my @channels = @{$heap->{my_chans}};
    @channels = map { "<option value='\#$_'>\#$_" } @channels;
    $channels[0] =~ s/\'\>\#/\' selected>\#/;
    @channels = sort @channels;
    push(@channels, "<option value=''>(none)");

    # Build content.

    $response->content
      ( "<html><head><title>$heap->{my_name} main menu</title></head>" .
        "<body>" .
        "<h1>No paste!</h1>" .
        "<p>This is an experiment in automatic non-pasting.  People post " .
        "content here, and the bot sends an URL to channel to retrieve it." .
        "  This service is tailored for source code listings." .
        "<form method='post' action='/paste' " .
        "enctype='application/x-www-form-urlencoded'>" .
        "<p>Channel: " .
        "<select name='channel'>@channels</select>" .
        "</p>" .
        "<p>Nick (optional): " .
        "<input type='text' name='nick' size='25' maxlength='25'></p>" .
        "<p>Summary (optional): " .
        "<input type='text' name='summary' size='80' maxlength='160'></p>" .
        "Source code:<br>" .
        "<textarea name='paste' rows=25 cols=75 " .
        "style='width:100%' wrap='none'></textarea>" .
        "<p><input type='submit' name='Paste it' value='Paste it'></p>" .
        "</body></html>"
      );

    $heap->{wheel}->put( $response );
    return;
  }

  ### Default handler dumps everything it can about the request.

  my $response = HTTP::Response->new( 200 );
  $response->push_header( 'Content-type', 'text/html' );

  # Many of the headers dumped here are undef.  We turn off warnings
  # here so the program doesn't constantly squeal.

  local $^W = 0;

  $response->content
    ( "<html><head><title>test</title></head>" .
      "<body>Your request was strange:<table border=1>" .

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
              $ircconf{channel}
            ],
          );
      },
    );
}

### Fix paste for presentability.

sub fix_paste {
  my ($paste, $nonums) = @_;

  # Prepend line numbers to each line.

  if ($nonums) {
    # <br>s without spaces between them don't get a blank line
    $paste =~ s/\n\r?\n/\n \n/g;
  }
  else {
    my $total_lines = 0;
    $total_lines++ while ($paste =~ m/^/gm);
    my $line_number_width = length($total_lines);

    my $line_number = 0;
    while ($paste =~ m/^/gm) {
      my $pos = pos($paste);
      substr($paste, pos($paste), 0) =
        sprintf("\%${line_number_width}d: ", ++$line_number);
      pos($paste) = $pos + 1;
    }
  }

  # Escape some HTML.  Forgive me.

  $paste = html_encode($paste);

  $paste =~ s/(\x0d\x0a?|\x0a\x0d?)/<br \/>/gi;  # pp breaks
  $paste =~ s/(?:<br \/>\s*){2,}<br \/>/<br \/><br \/>/gi;
  $paste =~ s/\t/    /g;  # can mess up internal tabs, oh well

  # Preserve indents and other whitespacey things.

  $paste =~ s/(^|<br \/>| ) /$1&nbsp;/g;

  # Buhbye.

  return $paste;
}

#------------------------------------------------------------------------------
1;
