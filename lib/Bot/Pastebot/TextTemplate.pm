# $Id$

package Bot::Pastebot::TextTemplate;

use Text::Template;
use warnings;
use strict;




sub new {
  my($class) = @_;
  return bless { error => undef }, $class;
}




sub process {
  my($self, $fh, $vars) = @_;

  my $template = Text::Template->new(
    TYPE        =>  'FILEHANDLE',
    SOURCE      =>  $fh,
    DELIMITERS  =>  [qw( [% %] )],
  );

  if ($template) {
    my $content = $template->fill_in(HASH => $vars);
    return $content if $content;

    $self->error($Text::Template::ERROR || 'unable to fill_in template');

  } else {
    $self->error($Text::Template::ERROR || 'unable to create template object');
  }

  return;
}




sub error {
  my($self, $error) = @_;
  $self->{error} = $error if @_ == 2;
  return $self->{error};
}




1;

__END__

=pod

=head1 NAME

Bot::Pastebot::TextTemplate - Text::Template glue code

=head1 DESCRIPTION

This module is an interface between Bot::Pastebot and Text::Template.  It
provides simple methods for processing templates and retrieving errors.  If
you wish to implement your own template class for pastebot to use you
will need to adhere to the same interface outlined in this documentation.

=head1 Methods

The only means pastebot uses to access the interface module is by calling
methods.  No attributes are required, and even the type of reference you
bless is irrelevant.  Except for new(), whenever an error is encountered
these methods return undef and set an internal error variable, retrieved via
the error() method documented below.

There are only three methods pastebot calls:

=over 4

=item $class->new

This is responsible for creating and returning an object, obviously.  If
your templating engine requires expensive initialization it would be best to
put it here.  This method is called once per configured web-server on
startup, and the resulting object is stored for later process calls.

This method should simply die if it encounters an error it can't recover
from.


=item $object->process($filehandle, $vars_hashref)

This method is called whenever a template needs to be processed.  The first
argument is an open filehandle to the template file.  The second argument is
a hashref of variables specific to the template file being processed, and
may be empty.  It returns the processed content.


=item $object->error

This method is called whenever an error is encountered.  It returns an error
message.

=back
