# $Id$

# Rocco's POE web server helper functions.  Do URL en/decoding.  Load
# static pages, and do template things with them.

package Util::Web;

use strict;
use vars qw(@ISA @EXPORT);

use Exporter;

@ISA    = qw(Exporter);
@EXPORT = qw( url_decode url_encode parse_content static_response
              dump_content dump_query_as_response base64_decode
              html_encode
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

  foreach (split(/[&;]/, $content)) {
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

# Generate a static response from a file.
sub static_response {
  my ($filename, $record) = @_;
  my ($code, $content);

  if (open(FILE, "<$filename")) {
    $code = 200;
    local $/;
    $content = <FILE>;
    close FILE;
  }
  else {
    $code = 500;
    $content =
      ( "<html><head><title>YASd Error</title></head>" .
        "<body>Error opening $filename: $!</body></html>"
      );
  }

  my $content_is_okay = 1;

  while ($content =~ /^(.*?)<<\s*([^<>\s]+)\s*(.*?)\s*>>(.*)$/s) {
    $content = $1;
    my ($tag, $markup, $right) = ($2, $3, $4);
    my %attribute;
    while ($markup =~ s/\s*(.*?)\s*=\s*([\'\"]?)(.*?)\2\s*//) {
      $attribute{$1} = $3;
    }

    # Field labels change to reflect the status of their contents.

    if ($tag eq 'label') {
      my ($name, $flags, $text) = @attribute{'name', 'flags', 'text'};

      my @badness_reasons;

      # Field is required to contain non-whitespace.
      if ($flags =~ /r/) {
        unless ( defined($record) and
                 exists($record->{$name}) and
                 ($record->{$name} =~ /\S/)
               ) {
          push @badness_reasons, 'required';
        }
      }

      # Field must match another field.  Used for passwords.
      if ($flags =~ /\(m:(.*?)\)/) {
        unless ( defined($record) and
                 exists($record->{$name}) and
                 exists($record->{$1}) and
                 ($record->{$name} eq $record->{$1})
               ) {
          push @badness_reasons, "doesn't match";
        }
      }

      # Field can get its reason from an external field.
      if ($flags =~ /\(x:(.*?)\)/) {
        if ( defined($record) and
             exists($record->{$1})
           ) {
          push @badness_reasons, $record->{$1};
        }
      }

      if (@badness_reasons) {
        $content .=
          ( "$text <font size='-1' color='#C02020'>(" .
            join('/', @badness_reasons) .
            ")</font>"
          );
        $content_is_okay = 0;
      }
      else {
        $content .= "$text <font size='-1' color='#202080'>(ok)</font>";
      }
    }

    # Replace value markers with values from the record.

    elsif ($tag eq 'value') {
      my $name = $attribute{name};
      if (defined($record) and exists($record->{$name})) {
        $content .= $record->{$name};
      }
    }

    # Unknown meta-markup.

    else {
      $content .= "[ [$tag]";
      foreach (sort keys %attribute) {
        $content .= " [$_=$attribute{$_}]";
      }
      $content .= ' ] ';
    }

    $content .= $right;
  }

  my $response = new HTTP::Response($code);
  $response->push_header('Content-type', 'text/html');
  $response->content($content);

  if (wantarray()) {
    return($content_is_okay, $response);
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
    $content =
      ( '<html><head><title>No Response</title></head>' .
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
  $response->content
    ( "<html><head><title>Content Dump: /signup-do</title></head><body>" .
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

#------------------------------------------------------------------------------
1;
