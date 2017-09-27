use strict;
use warnings;
use IO::Socket;

# CONFIGURATION #
print STDOUT "% Loading configuration and initilization procedures...\n";
my @_CONFIG;
  $_CONFIG[0] = "damibot"; # - nickname - #
  $_CONFIG[1] = "damibot"; # - username - #
  $_CONFIG[2] = "You are all going to die down here."; # - realname - #
  $_CONFIG[3] = "192.168.0.10"; # - local ip - #
  $_CONFIG[4] = "tally.derivan.ld"; # - local host - #

  $_CONFIG[5] = "irc.psyfin.net"; # - server name - #
  $_CONFIG[6] = "6667"; # - server port - #
  $_CONFIG[7] = ""; # - server password - #


 # CHANNELS #
my @_CHAN;
  $_CHAN[0] = "#derivan";
  $_CHAN[1] = "#noobforces";
  $_CHAN[2] = "#scriptaholics";
 # !CHANNELS! #

# !CONFIGURATION! #

open DEBUG, "> debug.log"
  or die("% Unable to open debug log\n");
DEBUG->autoflush(1);

# SCRIPT #
my $_SENDDATA;
my $_GETDATA;
my @_DATA;
my @_SETTING;
  $_SETTING[0] = 0; # - is connected - #
  $_SETTING[1] = ""; # - servername - #
  $_SETTING[2] = ""; # - nickname - #
  $_SETTING[3] = ""; # - hostname - #
  $_SETTING[4] = ""; # - usermodes - #

print STDOUT "% Attempting to connect to $_CONFIG[5]:$_CONFIG[6] ...\n";

my $_SOCKET = new IO::Socket::INET(PeerAddr => $_CONFIG[5], PeerPort => $_CONFIG[6], Proto => 'tcp')
  or die("% Connection failed.\n");

print STDOUT "% Sending authentication strings ...\n";

sub sendData {
  $_SENDDATA = shift;
  print $_SOCKET $_SENDDATA;
  print DEBUG "OUT: $_SENDDATA";
}

sendData "NICK $_CONFIG[0]\n";
sendData "USER $_CONFIG[1] $_CONFIG[4] $_CONFIG[3] :$_CONFIG[2]\n";
if (length($_CONFIG[7]) > 0) {
  sendData "PASS $_CONFIG[7]\n";
}

while (<$_SOCKET>) {
  $_GETDATA = $_;
  print STDOUT " IN: $_GETDATA";
#  @_DATA = split(/ /, $_GETDATA);

  if ($_GETDATA =~ /^(PING)\s(:(.*))/) {
    sendData "PONG $2";
  }

  

}

close($_SOCKET)
  or die("% Unable to close socket.");

print STDOUT "% I have been closed :(\n";
