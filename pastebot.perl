#!/usr/bin/perl -w
# $Id$

use strict;

use POE;
use Server::Web;
use Client::IRC;

$poe_kernel->run();
exit 0;

__END__

10:48 <Fletch^> how long a memory does it have?
10:48 <mjb> cool
10:49 <dngor> as long as it stays up... it doesn't save paste
10:49 <CanyonMan> that's cool
10:49 <Fletch^> verrrry interesting
10:49 <CanyonMan> Did everybody enjoy my paste?  :)  It's something I wrote a while ago to resolve MIB entries and cache them in an sql database
10:49 * Fletch^ sinks back behind the bushes
10:49 <dngor> but it could.  it's a hack right now.
10:50 <Fletch^> you could md5 or sha1 the content and use that as the identifier
10:50 <_ology> Maybe give it a "trim bogus whitespace and autformat the text" for non-code? Somehow... radio button maybe.
10:50 <Fletch^> run it through perltidy
10:50 <dngor> all good suggestions.
10:50 <CanyonMan> and voting buttons!  Click here if you think this code (1) is pretty good (2) is not very good (3) the author should be shot

...

