=info
Author: Triffid_Hunter

Copyright (c) 2002-2003 Mike Jackson

You may use this code for non-commercial purposes only.

If you modify this code, you MUST leave this message here, and add your own under it.

You may only distribute this code as long as this message is in place, and that you only attempt to take credit for the modifications you perform.

I take no responsibility for your use of this code. It has the potential to open your computer to external security threats if user scripts are badly written, and thus may cause loss of data or damage to property, quality of life, relationships, etc.
In other words; use at your own risk!

I also take no responsibility towards notifying you of updates and/or bugfixes to this code.

Basically, I have written this for my own benefit, and don't want to hear about it if it does anything untoward, in any way, shape or form, unless you're offering constructive criticism or ideas/snippets for additions...

=cut

#use strict;
use warnings;
#use diagnostics;

use IO::Socket;
use IO::Socket::INET;
use IO::Select;

print "Initializing variables...\n";

my ($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext);
our @flagTokens;
our $isLogging = 0;
our ($k,$b,$u,$o) = ("\003","\002","\031","\015");
our $disconnect = 0;

my $sock; my $sel;
my ($line,$bnum,@ready,$inBuf);
my $sockIsClosed = 0;
my $isHalted = 0;

my (%botSocketNames,%botSocketHandles,$accept,$incomingSocket);

our %IAL;
our %ChannelNickList;

our $botnick = 'DoomCookie';

my @serverList = qw/nazgul netspace.vic.au.austnet.org pacific.nsw.au.austnet.org yoyo.vic.au.austnet.org spin.nsw.au.austnet.org/;
my $currentServer=0;

my ($lastCommandTime,@commandQueue) = (0);

my %timerData;

# next line to stop 'used only once' warnings by copying to a temporary variable;
do { my @temp = ($k,$b,$u,$o); };

print "Initializing Procedures...\n";

# =====

sub Send {
  push @commandQueue,@_;
}

sub SendNow {
  unshift @commandQueue,@_;
}

sub haltdef () { $isHalted = 1; }

sub msg ($$) {
  my ($nick,$message) = @_;
  Send "PRIVMSG $nick :$message";
}

sub describe ($$) {
  my ($nick,$message) = @_;
  Send "PRIVMSG $nick :\001ACTION $message\001";
}

sub ctcp ($$) {
  my ($nick,$message) = @_;
  Send "PRIVMSG $nick :\001$message\001";
}

sub ctcpReply ($$) {
  my ($nick,$message) = @_;
  Send "NOTICE $nick :\001$message\001";
}

sub Quit ($) {
  $disconnect = 1;
  Send "quit :$_[0]";
}

sub notice ($$) {
  my ($nick,$message) = @_;
  Send "NOTICE $nick :$message";
}

sub readINI ($$$) {
  my ($filename,$section,$item) = @_;
  my $currentSection;

  open INI,"<$filename" or return 0;
  while (<INI>) {
    chomp;
    if (/^\s*;/) { }
    elsif (/^\s*[\s*(.+)\s*]\s*/) {
      $currentSection = $1;
    }
    elsif (/^\s*\Q$item\E\s*=(.*)/ && $section =~ /^\Q$currentSection\E$/i) {
      close INI;
      return $1;
    }
  }
  close INI;
  return '';
}

sub writeINI ($$$$) {
  my ($filename,$section,$item,$data) = @_;
  my $currentSection; my @file; my $isWritten = 0;

  open INI,"< $filename" or return 0;
  while (<INI>) {
    chomp;
    if (/^\s*;/) { }
    elsif (/^\s*[\s*(.+)\s*]/) {
      if (!$isWritten && $section =~ /^\Q$currentSection\E$/i) {
        push @file,"$item=$data"; $isWritten = 1; };
      $currentSection = $1;
    }
    elsif (/^\s*$item\s*=(.*)/ && $section =~ /^\Q$currentSection\E$/i) {
      s/^.*$/$item=$data/;
      $isWritten = 1;
    }
    push @file,'' if /^[.+]$/;
    push @file;
  }
  close INI;

  if ($isWritten == 0) { push @file,'',"[$section]","$item=$data"; $isWritten = 1; }

  $isWritten == 1 && do { open INI,">$filename" or return 0;
       print INI join('
', @file);
       close INI;
  };

  return $isWritten;
}

sub callUserScript {
  our ($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext) = @_;

  $isHalted = 0;
  do {
    $command !~ /^(00|25|37)\d$/ && 0 && do {
      print "calling user script:\n";
      print '($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext)'."\n";
      eval { print "($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext)\n\n"; };
    };
    do 'script.pl';
    if ($@) { print STDERR "$@\n"; }
  };
}

sub parseServerResponse ($) {
  ($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext) = 
  (''   ,''    ,''   ,''     ,''      ,''   ,''      ,''    ,''   ,''        );

  my $line = shift;
  if ($isLogging) { print "$line\n"; }

  # ======

  if ($line =~ /^:(\S+)\s+(.+)$/) {
    if ($line =~ /^:([^\s!@]+)\!([^\s!@]+)\@([^\s!@]+)\s+(.+)$/) {
      ($nick,$ident,$host,$message,$sender) = ($1,$2,$3,$4,$1.'!'.$2.'@'.$3);
      $IAL{lc $nick} = $sender;
    }
    elsif ($line =~ /^:(\S+)\s+(.+)$/) { ($nick,$sender,$message) = ($1,$1,$2); }

    if ($message =~ /^([\d\S]+)\s+(.*)$/) { ($command,$flags) = (uc $1,$2); }
  }
  elsif ($line =~ /^(\S+)(\s+(.+))?$/) {
    ($command, $flags) = (uc $1,$3);
  }
  
  if ($flags =~ /^((.*?)\s)?:(.*)$/) { ($flags,$text) = ($2,$3); }

  if (defined $flags) {
    $flags =~ s/^\s+//; $flags =~ s/\s+$//;
    @flagTokens = split(/\s+/, $flags);
    foreach (@flagTokens) { $chan = $1 if /^(#\S+)$/; }
  }

  # =====

  doProcess: for ($command) {
    m'^PRIVMSG$'i && do {
      if ($text =~ /^\001(\S+)(\s+(.*))?\001$/) {
        ($command,$flags,$text) = ('CTCP',$1,$3);
      }
    };
    m'^NOTICE$'i && do {
      if ($text =~ /^\001(\S+)(\s(.+))?\001$/) {
        ($command,$flags,$text) = ('CTCPREPLY',$1,$3);
      }
    };
    m'^JOIN$'i && do {
      $chan = $text;
      if (lc $nick eq lc $botnick) { @{$ChannelNickList{lc $chan}} = (); }
      else { push @{$ChannelNickList{lc $chan}}, $nick; }
    };
    m'^353$' && do {
     my @userList = split(/\s+/, $text);
     foreach (@userList) { s/^[\@\+]//; }
     push @{$ChannelNickList{lc $chan}}, @userList;
     print "nicklist for $chan: ".join(' ',@{$ChannelNickList{lc $chan}})."\n";
    };
    m'^MODE$'i && do {
      my ($chan,@targets) = (@flagTokens,split(/\s+/, $text));
      my @modeChars = split(/\s*/, shift @targets);
      my $orientation; my $infoString; my $eventName;
      foreach (@modeChars) {
        $eventName = $orientation.uc $_;
        /^[\+\-]$/ && ($orientation = $_);
        /^o$/i && do {
          # op/deop
          $infoString = shift @targets;
          $eventName = (($orientation eq '-')?'DE':'').'OP';
        };
        /^v$/i && do {
          # voice/devoice
          $infoString = shift @targets;
          $eventName = (($orientation eq '-')?'DE':'').'VOICE';
        };
        /^b$/i && do {
          # ban/unban
          $infoString = shift @targets;
          $eventName = (($orientation eq '-')?'UN':'').'BAN';
        };
        /^k$/i && do {
          # add/remove channel key
          $infoString = shift @targets if $orientation eq '+';
          $eventName = (($orientation eq '+')?'':'DE').'KEY';
        };
        /^l$/i && do {
          # channel limits
          if ($orientation eq '+') { $infoString = shift @targets; }
        };

        /^[^\+\-]$/ && callUserScript ($nick,$ident,$host,$sender,$message,$chan,$eventName,$infoString ,'','');
      }
    };
    m'^CTCP$'i && do {
      $flags =~ /^version$/i && ctcpReply $nick, 'VERSION PerlDrop v0.2 by Triffid_Hunter';
    };
  }

  if (defined $text) { $striptext = $text; $striptext =~ s/\003\d{0,2}(\d,\d{1,2})?//gs; $striptext =~ s/[\002\015\031\022]//gs; }

  callUserScript ($nick,$ident,$host,$sender,$message,$chan,$command,$flags,$text,$striptext);

  if ($isHalted == 0) {
    postProcess: for ($command) {
      m'^PING$'i && do {
        SendNow "PONG :$text";
        last;
      };
      m'^CTCP$' && do {
        for ($flags) {
          /^ping$/i    && ctcpReply $nick, "PING $text";
          /^time$/i    && ctcpReply $nick, 'TIME '.localtime;
        }
        last;
      };
    }
  }

  postProcessHouseKeeping: for ($command) {  # management of IAL etc...
    m'^PART$' && do {
      $" = ' ';
      if ($nick =~ /^\Q$botnick\E$/) {
        delete $ChannelNickList{lc $chan};
      }
      else {
        for (0..$#{$ChannelNickList{lc $chan}}) {
          my $cnick = shift @{$ChannelNickList{lc $chan}};
          if ($cnick ne $nick) { push @{$ChannelNickList{lc $chan}}, $cnick };
        }

        my $found = 0;
        onPartFindCommonChan: foreach my $curChan (keys %ChannelNickList) {
          if (lc $curChan ne lc $chan) {
            for (0..$#{$ChannelNickList{$curChan}}) {
              my $cnick = shift @{$ChannelNickList{$curChan}};
              if (lc $cnick eq lc $nick) { $found = 1; last onPartFindCommonChan; }
            }
          }
        }
        delete $IAL{lc $nick} unless $found;
      }
    };
    m'^QUIT$' && do {
      foreach my $curChan (keys %ChannelNickList) {
        for (0..$#{$ChannelNickList{$curChan}}) {
          my $cnick = shift @{$ChannelNickList{$curChan}};
          if (lc $cnick ne lc $nick) { push @{$ChannelNickList{$curChan}}, $cnick };
        }
      }
      delete $IAL{lc $nick};
    };
    m'^KICK$' && do {
      if ($flagTokens[1] =~ /^\Q$botnick\E$/) {
        delete $ChannelNickList{lc $chan};
      }
      else {
        for (0..$#{$ChannelNickList{lc $chan}}) {
          my $cnick = shift @{$ChannelNickList{lc $chan}};
          if (lc $cnick ne lc $flagTokens[1]) { push @{$ChannelNickList{lc $chan}}, $cnick };
        }

        my $found = 0;
        onKickFindCommonChan: foreach my $curChan (keys %ChannelNickList) {
          if (lc $curChan ne lc $chan) {
            for (0..$#{$ChannelNickList{$curChan}}) {
              my $cnick = shift @{$ChannelNickList{$curChan}};
              if (lc $cnick eq lc $nick) { $found = 1; last onKickFindCommonChan; }
            }
          }
        }
        delete $IAL{lc $nick} unless $found;
      }
    };
    m'^NICK$' && do {
      my $newnick = $text;
      delete $IAL{lc $nick};
      if (lc $nick eq lc $botnick) { $botnick = $nick; }
      foreach my $curChan (keys %ChannelNickList) {
        for (0..$#{$ChannelNickList{$curChan}}) {
          my $cnick = shift @{$ChannelNickList{$curChan}};
          push @{$ChannelNickList{$curChan}}, (($cnick eq $nick)?$newnick:$cnick);
        }
      }
    }
  }

  # =====

}

sub sockOpen ($$$) {
  my ($name,$host,$port) = @_;

  $name =~ /^([A-Z_][A-Z0-9\.\_\+\^\-]*)$/ims or do { print STDERR "sockOpen: Invalid Socket Name: \"$name\"\n"; return 0; }; $name = $1;
  $host =~ /^([A-Z][A-Z0-9\.\_\+\^\-]*|\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})$/ims or do { print STDERR "sockOpen: Invalid Host: \"$host\"\n"; return 0; }; $host = $1;
  $port =~ /^\d{1,5}$/ims or do { print STDERR "sockOpen: Invalid Port: \"$port\"\n"; return 0; };

  my $newsock = new IO::Socket::INET(PeerAddr => $host, PeerPort => $port, Proto => 'tcp', ReuseAddr => 1)
    or return 0;
  return 0 unless $newsock;

  $botSocketNames{$name} = {'Name'=>$name,'Host'=>$host,'Port'=>$port,'Handle'=>$newsock,'Status'=>'Connected'};
  $botSocketHandles{$newsock} = {'Name'=>$name,'Host'=>$host,'Port'=>$port,'Handle'=>$newsock,'Status'=>'Connected'};
  $sel->add($newsock);
  return $name;
}

sub sockListen ($$) {
  my ($name,$port) = @_;

  $name =~ /^([A-Z_][A-Z0-9\.\_\+\^\-]*)$/ims or do { print STDERR "sockListen: Invalid Socket Name: \"$name\"\n"; return 0; }; $name = $1;
  $port =~ /^\d{1,5}$/ims or do { print STDERR "sockListen: Invalid Port: \"$port\"\n"; return 0; };

  my $newsock = new IO::Socket::INET(Listen => 1, LocalPort => $port, ReuseAddr => 1)
    or return $!;
  return $! unless $newsock;
  
  $botSocketNames{$name} = {'Name'=>$name,'Host'=>$host,'Port'=>$port,'Handle'=>$newsock,'Status'=>'Listening'};
  $botSocketHandles{$newsock} = {'Name'=>$name,'Host'=>$host,'Port'=>$port,'Handle'=>$newsock,'Status'=>'Listening'};
  $sel->add($newsock);
  return $name;
}

sub sockAccept ($) {
  if (!defined $incomingSocket || !defined $accept) { return 0; }
  my ($newName) = @_;

  $newName =~ /^([A-Z_][A-Z0-9\.\_\+\^\-]*)$/ims or do { print STDERR "sockAccept: Invalid Socket Name: \"$newName\"\n"; return 0; }; $newName = $1;

  $accept = 1;

  $botSocketNames{$newName} = {'Name'=>$newName,'Host'=>$iaddr,'Port'=>$port,'Handle'=>$incomingSocket,'Status'=>'Connected'};
  $botSocketHandles{$incomingSocket} = {'Name'=>$newName,'Host'=>$iaddr,'Port'=>$port,'Handle'=>$incomingSocket,'Status'=>'Connected'};
  $sel->add($incomingSocket);

  return $newName;
}

sub sockWrite ($$) {
  my ($name,$data) = @_;

  $name =~ /^([A-Z_][A-Z0-9\.\_\+\^\-]*)$/ims or do { print STDERR "sockWrite: Invalid Socket Name: \"$name\"\n"; return 0; }; $name = $1;

  if (exists $botSocketNames{$name}) {

    0 && do { # we got a better way to do it
    if (${$botSocketNames{$name}}{Handle}) {
      my $fhandle = ${$botSocketNames{$name}}{Handle};
      if ($fhandle->connected) {
        my $totalWritten;
        while (length $data) {
          my $bytesWritten = syswrite $fhandle,$data;
          $totalWritten += $bytesWritten;
          if ($bytesWritten <= 0) { return 0-$totalWritten; }
          $data = substr($data,$bytesWritten);
        }
        return $totalWritten;
      } else { print STDERR "sockWrite: Socket Not Connected: \"$name\"\n"; return 0; }
    } else { print STDERR "sockWrite: Socket Not Connected: \"$name\"\n"; return 0; }
    };

    ${$botSocketNames{$name}}{SendBuffer} .= $data;
    return 1;

  } else { print STDERR "sockWrite: No Such Socket: \"$name\"\n"; return 0; }
}

sub sockClose ($) {
  my ($name) = @_;

  $name =~ /^([A-Z_][A-Z0-9\.\_\+\^\-]*)$/ims or do { print STDERR "sockOpen: Invalid Socket Name: \"$name\"\n"; return 0; }; $name = $1;

  if (exists $botSocketNames{$name}) {
    close ${$botSocketNames{$name}}{FileHandle} if exists ${$botSocketNames{$name}}{FileHandle};
    my $fhandle = ${$botSocketNames{$name}}{Handle};
    if ($fhandle) {
      $sel->remove($fhandle);
      #$fhandle->shutdown(2);
      close $fhandle if $fhandle && $fhandle-connected;
      delete $botSocketHandles{$fhandle};
    }
    else {
      foreach (keys %botSocketHandles) {
        my $sname = ${$botSocketHandles{$_}}{Name};
        if ($sname eq $name) {
          $sel->remove($_);
          #$_->shutdown(2);
          close $fhandle if $fhandle;
          delete $botSocketHandles{$_};
          last;
        }
      }
    }
    delete $botSocketNames{$name};
    return $name;
  }
  print STDERR "sockClose: No Such Socket: \"$name\"\n";
  return 0;
}

sub convIP ($) {
  my ($cIP) = @_;
  for ($cIP) {
    /^\d+$/ && do {
      my @nums;
      while ($cIP > 0) {
        unshift @nums, scalar($cIP & 255);
        $cIP = ($cIP & 0xFFFFFF00) >> 8;
      }
      return join('.',@nums);
    };
    /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && do {
      my @nums = ($1,$2,$3,$4);
      my $rem = 0;
      while (@nums) { $rem = ($rem << 8) + (1 * shift(@nums)); }
      return $rem;
    };
    /^(.{4})$/ && do {
      return join('.',unpack('CCCC',$cIP));
    };
  }
}

sub addTimer ($$$*) {
  my ($name,$iterations,$timeout,$command) = @_;
  if ($name !~ /./) {
    my $num = 0;
    while (exists $timerData{'Timer'.$num}) { ++$num; }
    $name = 'Timer'.$num;
  }

  #$command =~ s/"/\\"/gms;

  %{$timerData{$name}} = (iterations => $iterations,
                          timeout    => $timeout,
                          command    => $command,
                          nextTriggerTime => (time + $timeout)
                         );
  #print "Created timer $name, triggering $iterations times every $timeout seconds. time is ".(scalar time).", first trigger is at ${$timerData{$name}}{nextTriggerTime}.\n";
  return $name;
}

sub killTimer ($) { delete $timerData{$_[0]} if exists $timerData{$_[0]}; }
sub timerExists ($) { return exists $timerData{$_[0]}; }

# ===== end of subs =====

print "PerlDrop Started.\n";

$sel = new IO::Select;

while (!$disconnect) {

  # *** IDENTD stuff - change '1' in line below to '0' to disable. ***
  if (1) {
    my $result = sockListen '__IDENTD',113;
    if ($result eq '__IDENTD') {
      ${$botSocketNames{$result}}{Internal} = 1;
      ${$botSocketHandles{${$botSocketNames{$result}}{Handle}}}{Internal} = 1;
      print "Starting of IDENTD on INADDR_ANY:113 succeeded.\n";
    }
    else {
      print "Starting of IDENTD on INADDR_ANY:113 failed: $result.\n";
    }
  }

  $currentServer %= @serverList;

  print "Connecting to $serverList[$currentServer] [server ".(1+$currentServer)." of ".(scalar @serverList)."]\n";

  $sock = new IO::Socket::INET(PeerAddr => $serverList[$currentServer], PeerPort => 6667, Proto => 'tcp', ReuseAddr => 1) or do { print "Could not open socket: $!\n"; ++$currentServer; next; };
  do { print "Could not open socket: $!\n"; ++$currentServer; next; } unless $sock->connected;

  $sock->blocking(0);
  $sock->autoflush(1);

  $sel->add($sock);

  print "Socket Connected.\n";

  syswrite $sock,"NICK :$botnick\nUSER $botnick $botnick $botnick :$botnick Perldrop\n";

  print "Connected to IRC.\n";

  $sockIsClosed = 0;
  $isLogging = 0;

  # *** main program loop ***

  while ($sockIsClosed != 1) {
    # --- check all sockets to see if there's any waiting data. ---
    @ready = $sel->can_read(0.01);
    foreach my $fh (@ready) {

      if ($fh == $sock) {				# *** is irc control socket [to be made redundant for multi-server; will use more generic code below] ***
        $bnum = sysread($fh,$line,512);
        if (!defined $bnum) {
          print "Control Connection Error: $!\n";
          $sockIsClosed = 1;
        }
        elsif ($bnum > 0) {
          $inBuf .= $line;
          while ($inBuf =~ /^([^\r\n]+)[\r\n]+(.+)?/ms) {
            if (defined $2) { $inBuf = $2; } else { $inBuf = ''; }
            parseServerResponse $1;
          }
        }
        else { $sockIsClosed = 1; }
      }
      else {						# *** is a non-irc control socket (could be dcc, or user socket) ***

        my $sname = ${$botSocketHandles{$fh}}{Name};
        if (defined ${$botSocketHandles{$fh}}{Status} && ${$botSocketHandles{$fh}}{Status} =~ /^Listen/i) { # *** is a listen socket ***
          $accept = 0; my $paddr; ($incomingSocket,$paddr) = $fh->accept; my ($port,$iaddr) = sockaddr_in($paddr); $iaddr = convIP($iaddr) if $iaddr =~ /^.{4}$/;
          if (${$botSocketNames{$sname}}{Internal}) {
            for ($sname) {				# internal stuff, IDENT server, DCCs, etc
              /^__IDENTD$/ && do {
                my $result = sockAccept '__IDENTD_DATA';
                if ($result eq '__IDENTD_DATA') {
                  ${$botSocketNames{$result}}{Internal} = 1;
                  ${$botSocketHandles{${$botSocketNames{$result}}{Handle}}}{Internal} = 1;
                }
                sockClose $sname;
              };
              /^__DCCSEND(\d+)$/ && do {
                if (exists ${$botSocketNames{$sname}}{FileName} && -e ${$botSocketNames{$sname}}{FileName} && -f ${$botSocketNames{$sname}}{FileName}) {
                  sysopen(${$botsocketNames{$sname}}{FileHandle},${$botSocketNames{$sname}}{FileName},O_RDONLY | O_NONBLOCK) or do { sockClose $sname; last; };
                  my $inbuf;
                  sysread ${$botsocketNames{$sname}}{FileHandle},$inbuf,4096;
                  ${$botSocketNames{$sname}}{SendBuffer} = $inbuf if defined $inbuf;
                }
              };
            }
          }
          else {					# user script created socket
            print "Socket $sname: Incoming connection from $iaddr:$port...\n";
            callUserScript ($sname,$port,$iaddr,$iaddr,'','','SockListen','','','');
            print "Socket $sname: Connection from ".$incomingSocket->peerhost.':'.$incomingSocket->peerport." accepted under new name $newName.\n" if $accepted && !${$botSocketNames{$sname}}{Internal};
          }
          $accept || do {
            print "Socket $sname: Connection from ".$incomingSocket->peerhost.':'.$incomingSocket->peerport." rejected.\n" if !$accepted && !${$botSocketNames{$sname}}{Internal};
            $incomingSocket->shutdown(2);
            $incomingSocket->close;
          };
        }
        else {						# is an open socket (as opposed to listening)
          if ($botSocketHandles{$fh}) {
            my $sname = ${$botSocketHandles{$fh}}{Name};
            if (defined $sname && $sname =~ /./) {
              $bnum = sysread($fh,$line,512);
              if ($bnum > 0) {
                if (${$botSocketNames{$sname}}{Internal}) {
                  for ($sname) {
                    /^__IDENTD_DATA$/ && do {
                      if ($line =~ /^(\d+)\s+,\s+(\d+)/) {
                        print "IDENTD request from ".$fh->peerhost.':'.$fh->peerport.": $1, $2 [".$sock->sockport.', '.$sock->peerport."]\n";
                        if (1 || $2 == $sock->peerport) {
                          print "IDENTD reply: $1, $2 : USERID : UNIX : $botnick.PerlDrop\n";
                          sockWrite $sname, "$1, $2 : USERID : UNIX : $botnick.PerlDrop";
                          sockClose $sname;
                        }
                      }
                    };
                    /^__IRC_DATA(\d*)$/i && do {
                      $line = ${$botSocketNames{$sname}}{buf}.$line;  # re-add saved buffer if end of packet not end of line
                      ${$botSocketNames{$sname}}{buf} = '';
                      my @lines = split(/[\r\n]+/,$line);             # split into individual lines
                      ${$botSocketNames{$sname}}{buf} = pop @lines if $line !~ /[\r\n]$/; # add last section to buffer; dont process if needed
                      foreach(@lines) {
                        parseServerResponse $_;                       # parse each line
                      }
                    };
                    /^__DCCGET(\d+)$/ && do {
                      my $fh = ${$botSocketNames{$sname}}{FileHandle};
                      if ($fh->opened) {
                        syswrite $fh,$line;
                      }
                      else {
                        sockClose $sname;
                      }
                    };
                    /^DCCCHAT(\d+)$/ && do {
                      # TODO
                    };
                  }
                }
                else { callUserScript ($sname,$fh->peerport,$fh->peerhost,$fh->peerhost,'','','SockRead','',$line,$line); }
              }
              else {					# socket has closed
                if (${$botSocketNames{$sname}}{Internal}) { # if its one of ours...
                  for ($sname) {
                    /^__DCC(SEND|GET|CHAT|FSERV)(\d+)$/ && do {
                      # TODO
                    };
                    /^__IRC_DATA(\d*)$/ && do {
                      # TODO
                    };
                  }
                }
                else {					# or if just a user socket, tell the script.
                  callUserScript ($sname,$fh->peerport,$fh->peerhost,$fh->peerhost,'','','SockClose','','','');
                }
							# then clean it all up
                sockClose $sname;
                0 && do {
                  delete $botSocketNames{$sname} if $sname =~ /./;
                  delete $botSocketHandles{$fh} if exists $botSocketHandles{$fh};
                  $sel->remove($fh);
                  close $fh;
                };
              }
            }
          }
        }
      }
    }

    if (!$sock->connected) { $sockIsClosed = 1; }

    # *** now check send buffers ***

    @ready = $sel->can_write(0.01);
    foreach (@ready) {
      my $sname = ${$botSocketHandles{$_}}{Name} or next;
      next if ${$botSocketHandles{$_}}{Status} =~ /^Listen/i;
      my $bw = 0;
      if (exists ${$botSocketNames{$sname}}{SendBuffer} && ${$botSocketNames{$sname}}{SendBuffer} =~ /./) {
        while (defined $bw && ${$botSocketNames{$sname}}{SendBuffer} =~ /./) {
          $bw = syswrite($_,${$botSocketNames{$sname}}{SendBuffer});
          if (defined $bw) { ${$botSocketNames{$sname}}{SendBuffer} = substr(${$botSocketNames{$sname}}{SendBuffer},$bw); }

          # if buffer is too large, this will block. move IF block outside while loop for only one buffer write per program loop

          if (${$botSocketNames{$sname}}{SendBuffer} eq '') { # *** trigger next write cycle if buffer is empty
            if (${$botSocketNames{$sname}}{Internal}) {
              for ($sname) {
                /^__DCCSEND(\d+)$/ && do {
                  if (exists ${$botSocketNames{$sname}}{FileHandle}) {
                    my $fh = ${$botSocketNames{$sname}}{FileHandle};
                    if ($fh->opened) {
                      my ($inbuf,$br);
                      $br = sysread $fh,$inbuf,4096;
                      if ($br) { ${$botSocketNames{$sname}}{SendBuffer} .= $inbuf; }
                      else { close $fh; }
                    }
                    else {
                      sockClose $sname;
                    }
                  }
                };
              }
            }
            else {
              callUserScript ($sname,$_->peerport,$_->peerhost,$_->peerhost,'','','SockWrite','','','');
            }
          }
        }
      }
    }

    # *** end of socket stuff ***

    # *** timers ***

    foreach (keys %timerData) {
      my %cTimer = %{$timerData{$_}};
      if (defined $cTimer{nextTriggerTime}) {
        if ($cTimer{nextTriggerTime} <= time) {
          #print "now eval()ing \"$cTimer{command}\" for timer $_ [$cTimer{nextTriggerTime} / ".(scalar time)."]\n";
          eval $cTimer{command};
          print "Error in timer \"$_\": $@\n" if $@;
          if ($cTimer{iterations} == 0 || --$cTimer{iterations}) {
            $cTimer{nextTriggerTime} = time + $cTimer{timeout};
            %{$timerData{$_}} = %cTimer;
          }
          else {
            delete $timerData{$_};
          }
        }
      }
      else {
        delete $timerData{$_};        
      }
    }

    # *** end timers ***

    # *** message queueing ***

    if (scalar(time) > $lastCommandTime) {
      if (@commandQueue) {
        my $command = shift @commandQueue;
        $command =~ /^names (#.+)$/i && do { @{$ChannelNickList{lc $1}} = (); };
        syswrite $sock,$command."\n";
        $lastCommandTime = time + 2;
      }
    }

    # *** end message queueing ***

    # *** end main loop ***
  }

  print "Disconnected\n";

  callUserScript ('','',$sock->peerhost,'','','','DISCONNECT','',$sock->error,$sock->error);

  $sel->remove($sock);

  close($sock);

  $currentServer = (++$currentServer % scalar(@serverList));

}

