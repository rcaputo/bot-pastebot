# $Id$

use POE;

use Test::More tests => 5;

use_ok("Bot::Pastebot::Conf");
use_ok("Bot::Pastebot::Data");
use_ok("Bot::Pastebot::WebUtil");
use_ok("Bot::Pastebot::Client::Irc");
use_ok("Bot::Pastebot::Server::Http");
