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
    'File::ShareDir'      => 0.05,
    'HTTP::Request'       => 1.40,
    'HTTP::Response'      => 1.53,
    'POE'                 => 0.38,
    'POE::Component::IRC' => 5.03,
    'Perl::Tidy'          => 1.46,
    'Test::More'          => 0.63,
  },
  EXE_FILES    => [ 'pastebot' ],
  dist         => {
    COMPRESS   => 'gzip -9f',
    SUFFIX     => 'gz',
    PREOP      => (
      'svn-log.perl | tee ./$(DISTNAME)-$(VERSION)/CHANGES > ./CHANGES'
    ),
  },
  depend       => { pm_to_blib => 'setup_shared' },
);

sub MY::postamble {
  my $postamble = (
    "setup_shared:\n" .
    "\t\$(NOECHO) \$(ABSPERLRUN) -MExtUtils::Install -e " .
    "'pm_to_blib({\@ARGV}, '\\''\$(INST_LIB)/auto'\\'', " .
    "'\\''\$(PM_FILTER)'\\'')' -- \\\n"
  );

  my @to_copy;
  foreach (<static/*>) {
    next unless -f $_;
    next if /\~$/;
    s!^static/!!;
    push @to_copy, "static/$_ blib/arch/auto/Bot/Pastebot/$_";
  }

  $postamble .= "\t  " . join("\\\n\t  ", @to_copy) . "\n";

  return $postamble;
}
