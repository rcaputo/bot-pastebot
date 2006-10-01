# $Id$

use warnings;
use strict;

use ExtUtils::MakeMaker;

# Touch CHANGES so it exists.
open(CHANGES, ">>CHANGES") and close CHANGES;

WriteMakefile(
  NAME         => 'Bot::Pastebot',
  AUTHOR       => 'Rocco Caputo <rcaputo@cpan.org>',
  ABSTRACT     => 'The original clipboard-to-chat gateway.',
  VERSION_FROM => 'pastebot',
  PREREQ_PM    => {
    'POE'                 => 0.38,
    'Test::More'          => 0.63,
    'Perl::Tidy'          => 1.46,
    'HTTP::Request'       => 1.40,
    'HTTP::Response'      => 1.53,
    'POE::Component::IRC' => 5.03,
    'Text::Template'      => 1.44,
  },
	EXE_FILES    => [ 'pastebot' ],
  dist         => {
    COMPRESS   => 'gzip -9f',
    SUFFIX     => 'gz',
    PREOP      => (
      'svn-log.perl | tee ./$(DISTNAME)-$(VERSION)/CHANGES > ./CHANGES'
    ),
  },
);
