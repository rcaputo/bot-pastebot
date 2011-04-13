# Rocco's POE web server helper functions.  Do URL en/decoding.  Load
# static pages, and do template things with them.
#
# TODO - We could probably replace them with an actual CPAN library or
# two.

package Bot::Pastebot::WebUtil;

use warnings;
use strict;

use CGI::Cookie;

use base qw(Exporter);
our @EXPORT_OK = qw(
  url_decode url_encode parse_content parse_cookie static_response
  dump_content dump_query_as_response base64_decode html_encode
  is_true cookie redirect
);

#------------------------------------------------------------------------------
# Build two URL-encoding maps.  Map non-printable characters to
# hexified ordinal values, and map hexified ordinal values back to
# non-printable characters.

my (%raw_to_url, %url_to_raw);

# Nonprintable characters
for (my $ord = 0; $ord < 256; $ord++) {
  my $character = chr($ord);
  my $hex = lc(unpack('H2', $character));

  # Map characters to their hex values, including the escape.
  $raw_to_url{ $character } = '%' . $hex;

  # Map hex codes (lower- and uppercase) to characters.
  $url_to_raw{    $hex } = $character;
  $url_to_raw{ uc $hex } = $character;
}

# Return a cookie string for a Set-Cookie header. The request argument is
# used to figure out domain.
sub cookie {
  my ($name, $value, $request) = @_;

  return CGI::Cookie->new(
    -name => $name,
    -value => $value,
    -expires => '+36M',
    -domain => (split /:/, $request->headers->header('Host'))[0],
    -path => '/',
  )->as_string;
}

# Decode url-encoded data.  This code was shamelessly stolen from
# Lincoln Stein's CGI.pm module.  Translate plusses to spaces, and
# then translate %xx sequences into their corresponding characters.
# Avoid /e on the regexp because "eval" is close to "evil".
sub url_decode {
  my $data = shift;
  return undef unless defined $data;
  $data =~ tr[+][ ];
  $data =~ s/%([0-9a-fA-F]{2})/$url_to_raw{$1}/g;
  return $data;
}

# Url-encode data.  This code was shamelessly stolen from Lincoln
# Stein's CGI.pm module.  Translate nonprintable characters to %xx
# sequences, and spaces to plusses.  Avoid /e too.
sub url_encode {
  my $data = shift;
  return undef unless defined $data;
  $data =~ s/([^a-zA-Z0-9_.:=\&\#\+\?\/-])/$raw_to_url{$1}/g;
  return $data;
}

# HTML-encode data.  More theft from CGI.pm.  Translates the
# blatantly "bad" html characters.
sub html_encode {
  my $data = shift;
  return undef unless defined $data;
  $data =~ s{&}{&amp;}gso;
  $data =~ s{<}{&lt;}gso;
  $data =~ s{>}{&gt;}gso;
  $data =~ s{\"}{&quot;}gso;
  # XXX: these bits are necessary for Latin charsets only, which is us.
  $data =~ s{\'}{&#39;}gso;
  $data =~ s{\x8b}{&#139;}gso;
  $data =~ s{\x9b}{&#155;}gso;
  return $data;
}

# Parse content.  This doesn't care where the content comes from; it
# may be from the URL, in the case of GET requests, or it may be from
# the actual content of a POST.  This code was shamelessly stolen from
# Lincoln Stein's CGI.pm module.
sub parse_content {
  my $content = shift;
  my %content;

  return \%content unless defined $content and length $content;

  foreach (split(/[\&\;]/, $content)) {
    my ($param, $value) = split(/=/, $_, 2);
    $param = &url_decode($param);
    $value = &url_decode($value);

    if (exists $content{$param}) {
      if (ref($content{$param}) eq 'ARRAY') {
        push @{$content{$param}}, $value;
      }
      else {
        $content{$param} = [ $content{$param}, $value ];
      }
    }
    else {
      $content{$param} = $value;
    }
  }

  return \%content;
}

# Parse a cookie string (found usually in the Cookie: header), returning a 
# hashref containing cookies values, not CGI::Cookie objects.
sub parse_cookie {
  my ($cookie) = @_;

  return {} if not defined $cookie;
  return { map url_decode($_), map /([^=]+)=?(.*)/s, split /; ?/, $cookie };
}

sub _render_template {
  my ($template, $filename, $record) = @_;

  my ($content, $error);
  if (open(my $template_fh, "<", $filename)) {

    $content = eval { $template->process($template_fh, $record) };

    if ($@ || !defined $content || !length $content) {
      my $template_error = $template->error || 'unknown error';
      $error = 1;
      $content = (
        "<html><head><title>Template Error</title></head>" .
        "<body>Error processing $filename: $template_error</body></html>"
      );
    }
  } else {
    $error = 1;
    $content = (
      "<html><head><title>Template Error</title></head>" .
      "<body>Error opening $filename: $!</body></html>"
    );
  }

  return +{
    content => $content,
    error => 1,
  };
}

# Generate a static response from a file.
sub static_response {
  my ($template, $filename, $record) = @_;

  my $code = 200;
  my $result = _render_template( $template, $filename, $record );
  $code = 500 if $result->{error};

  my $response = HTTP::Response->new($code);
  $response->push_header('Content-type', 'text/html');
  $response->content( $result->{content} );

  if (wantarray()) {
    return(1, $response);
  }
  return $response;
}

# redirect to a paste
sub redirect {
  my ($template, $filename, $record, $response_code) = @_;

  my $response = HTTP::Response->new( $response_code || 303 );
  my $paste_link = $record->{paste_link};
  $response->push_header( "Location", $paste_link );

  my $result = _render_template( $template, $filename, $record );
  unless( $result->{error} ) {
    $response->push_header( "Content-type", "text/html" );
    $response->content( $result->{content} );
  }

  return $response;
}

# Dump a query's content as a table.
sub dump_content {
  my $content = shift;
  if (defined $content) {
    my %parsed_content = %{ &parse_content($content) };
    $content = '<table border=1><tr><th>Field</th><th>Value</th></tr>';
    foreach my $key (sort keys %parsed_content) {
      $content .= "<tr><td>$key</td><td>$parsed_content{$key}</td></tr>";
    }
    $content .= '</table>';
  }
  else {
    $content = (
      '<html><head><title>No Response</title></head>' .
      '<body>This query contained no content.</body></html>'
    );
  }
  return $content;
}

# Dump content as a page.  This just wraps &dump_content in a page
# template.
sub dump_query_as_response {
  my $request = shift;
  my $response = new HTTP::Response(200);
  $response->push_header('Content-Type', 'text/html');
  $response->content(
    "<html><head><title>Content Dump: /signup-do</title></head><body>" .
    &dump_content($request->content()) .
    "</body></html>"
  );
  return $response;
}

# Decode base64 stuff.  Shamelessly stolen from MIME::Decode::Base64
# but no longer needed.
sub base64_decode {
  my $data = shift;
  if (defined($data) and length($data)) {
    $data =~ tr[A-Za-z0-9+/][]cd;
    $data .= '===';
    $data = substr($data, 0, ((length($data) >> 2) << 2));
    $data =~ tr[A-Za-z0-9+/][ -_];
    $data = unpack 'u', chr(32 + (0.75 * length($data))) . $data;
  }
  return $data;
}

# Determine if a checkbox/radio thingy is true.

my %bool = (
  1 => 1, t => 1, y => 1, yes => 1, da => 1, si => 1, on => 1,
  0 => 0, f => 0, n => 0, no  => 0, nyet => 0, off => 0,
);

sub is_true {
  my $value = shift;
  return 0 unless defined $value and length $value;
  $value = lc($value);
  return $bool{$value} if exists $bool{$value};
  return 0;
}

1;
