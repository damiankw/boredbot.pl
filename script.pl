use IPC::Open2;

local $| = 1;

our ($reader,$writer,$halPID);

sub t2s ($) {
  my $sh = new IO::Socket::INET(Proto => 'udp',PeerAddr=>'localhost',PeerPort=>7717) or return 0;
  return 0 unless defined $sh;
  foreach (@_) {
    my ($buf,$line) = $_;
    while ($buf) {
      $buf =~ /^(.{200,250}[\.\!\?])\s+(.+)$/ && do { $buf = $1; $line = $2; 1 } || do { $line = $buf; $buf = ''; };
      $line =~ s/^\W+//g; $line =~ s/(\W)\W+$/\1/g;
      print $sh $line;
    }
  }
  close $sh;
}

sub getHalResponse ($) {
  my $intext = join(' ',@_);
  my ($result,$inline,$inbuf,$br) = ('','','');

  $intext =~ s/[\r\n]+/ /gms;

  do { open(DOOMLOG,'>>doomcookielog.txt'); print DOOMLOG '['.(scalar localtime)."] <$nick $chan> $striptext\n"; close DOOMLOG; };
  print "<$nick $chan> $striptext\n";

  $striptext !~ /^#/ && t2s "$nick ".(($striptext =~ /\?$/)?'asks':(($striptext =~ /\!$/)?'exclaims':'says'))."; $striptext";

  while (!defined $result || $result !~ /^\d+$/ || !defined $reader || !defined $writer || !$reader->opened || !$writer->opened) {
    eval { $result = $writer->syswrite($intext."\r\n\r\n"); };
    if (!defined $result || $result !~ /^\d+$/) {
      close $reader if defined $reader;
      close $writer if defined $writer;
      $halPID = open2($reader,$writer,'megahal.exe') or do { print STDERR "Can't open megahal: $! $? $@\n"; return ''; };
      $reader->blocking(0);
      $writer->autoflush(1);
      $br = 512;
      while ($br >= 512 || $br == 2) {
        $br = sysread($reader,$inline,512);
      }
    }
  }


  # this bit blocks until a reply is forthcoming...
  if ($intext !~ /^#(save)/i) {
    $br = 512;
    while ($br >= 512 || $br == 2) {
      $br = sysread($reader,$inline,512);
      $inbuf .= $inline;
    }

    my @halLines = split(/[\r\n]+/,$inbuf);
    $inbuf = pop @halLines unless $inbuf =~ /[\r\n]+$/;
    $inline = '';
    foreach (@halLines) {
      s/>\s//g;
      $inline .= "$_ " unless (/^\+-/ or /^\|\s/);
    }
    $inline =~ s/\s+$//gms; $inline =~ s/\s+/ /gms; $inline =~ s/\Q$botnick\E([^\@])/$nick\1/gi;

    do { open(DOOMLOG,'>>doomcookielog.txt'); print DOOMLOG '['.(scalar localtime)."] <$botnick $chan> $inline\n"; close DOOMLOG; };
    print "<$botnick $chan> $inline\n";

    t2s "$botnick replies; $inline";

    return $inline;
  }
  else {
    sysread($reader,$inline,2);
    return '';
  }
}

process: for ($command) {
  /^privmsg$/i && do {
    if ($nick =~ /^triffid_(idle|hunter)$/i && $chan eq '') {
      for ($striptext) {
        /^disconnect(\s+(.*))?/i     && do { $disconnect = 1; Send "quit :$2"; last; };
        /^msg\s+(\S+)\s+(.+)/i       && do { msg $1, $2; last; };
        /^ctcp\s+(\S+)\s+(.+)/i      && do { ctcp $1, $2; last; };
        /^ctcpreply\s+(\S+)\s+(.+)/i && do { ctcpReply $1, $2; last; };
        /^log\s?/i                   && do { $isLogging = 1 - $isLogging; msg $nick, $isLogging; last; };
        /^nicklist\s+(\S+)/i         && do { $" = ' '; if (exists $ChannelNickList{lc $1}) { my @list = @{$ChannelNickList{lc $1}}; msg $nick, 'nicklist for '.$1.': ['.(scalar @list)."] @list"; } else { msg $nick, "I am not on $1!"; } last; };
        /^chanlist/i                 && do { my @mylist = keys %ChannelNickList; msg $nick, "channels: @mylist"; last; };
        /^sockList$/i                && do { print "starting socklist\n"; foreach (keys %botSocketNames) { print "$_: ${$botSocketNames{$_}}{Status}\n"; }; last; };
        /^(sock\S+)\s+(.+)/i         && do { my @sockOpts = split(/\s+/,$2); eval "print '$1(".join(',',@sockOpts).")'.\"\n\".$1('".join("','",@sockOpts)."').\"\n\n\";"; last; };
        /^cIP\s+(\S+)/i              && do { print "$text [".convIP($1)."] from $nick\n"; msg $nick, convIP($1); last; };
        Send $text;
      }
    }
    elsif ($nick !~ /^(nick|help|chan|love|note)op$/) {
      ($striptext =~ /^\s*\w/ || ($nick =~ /^triffid_(hunter|idle)$/i && $striptext =~ /^#/)) && ($chan =~ /^#doomcookie$/i || $chan eq '' || ($striptext =~ /^\Q$botnick\E.?\s+(.+)$/i && ($striptext = $1))) && # should we respond to this?
        ($striptext !~ /http/i && $striptext !~ /.#\S/ && $striptext !~ /www/i && $striptext !~ /^(.*\s)?[^\@\s]+\.(com|net|org|at|to)/i) &&                                                                                    # is it spam?
          addTimer '',1,10,"Send 'PRIVMSG ".(($chan =~ /^#./)?"$chan":"$nick").' :'.(($chan =~ /^#./)?"$nick: ":"").do{my $tmp = getHalResponse($striptext) || last process; $tmp =~ s/'/\\'/gms; $tmp =~ s/[\s\r\n]+/ /gms; $tmp;}."';"; # get response & send
    }
    $nick =~ /^(nick|chan|help|love)op$/i && print "\n$nick : $striptext\n\n";
    $nick =~ /^nickop$/i && do {
      $striptext =~ /msg\s+nickop\@austnet\.org\s+identify/i && do {
        msg 'nickop@austnet.org','identify sfifhk55';        
      };
    };
    last process;
  };
  /^notice$/i && do {
    $nick =~ /^(nick|chan|help|love|note)op$/i && print "\n$nick : $striptext\n\n";
    $nick =~ /^nickop$/i && do {
      $striptext =~ /msg\s+nickop\@austnet.org\s+identify/i && do {
        msg 'nickop@austnet.org','identify sfifhk55';        
      };
    };
  };
  /^kick$/i && do {
    $flags =~ /^\Q$chan\E\s+\Q$botnick\E$/ && do {
      Send "JOIN $chan";
      my $snick = $nick;
      if ($striptext =~ /^\((\S+)\)\s/) { $snick = $1; }
      ($striptext =~ /./ && $nick !~ /^(chan|nick|love|help)op$/i) && Send "PRIVMSG $snick :".getHalResponse($striptext);
    };
  };
  /^join$/i && $chan =~ /^#doomcookie$/i && (lc $nick ne lc $botnick) && do {
    notice $nick, "Welcome to DoomCookie's dungeon of despair! Just type to talk to me, though I will ignore any sentences that don't start with a letter. If I insult you, I apologise. I don't really mean it!";
    Send "mode $chan +v $nick";
  };
  /^332$/ && do {
    #Send "PRIVMSG Triffid_Hunter :Topic of $chan is: $text";
    last process;
  };
  /^333$/ && do {
    #Send "PRIVMSG Triffid_Hunter :$chan topic set on ".(localtime $flagTokens[3]);
    last process;
  };
  /^376$/ && do { # end of MOTD - generally a good spot to do 'now connected' things...
    Send 'JOIN #doomcookie,#petem,#adventjah,#..|..,#sex,#chatzone,#teens,#perl,#|bounce|,#devintownsend,#trancore,#shrineofinsanity,#hippy,#xpuser-bt';
    #Send "JOIN #doomcookie,#perl";
    last;
  };
  /^sockListen$/i && do {
    sockAccept 'sockTest';
    last;
  };
  /^sockRead$/i && do {
    print "Received ".length($text)." from Socket $nick\n";
    last;
  };
  /^sockClose$/i && do {
    print "Socket \"$nick\" closed.\n";
  };
  /^ctcp$/i && do {
    ($striptext =~ /^\w/ || ($nick =~ /^triffid_(hunter|idle)$/i && $striptext =~ /^#/)) && (lc $flags eq 'action') && ($chan eq '' || $striptext =~ /\Q$botnick\E/i) && # should we respond to this?
      ($striptext !~ /http/i && $striptext !~ /.#\S/ && $striptext !~ /www/i && $striptext !~ /\.(com|net|org|at|to)/i) &&                                                # is it spam?
          addTimer '',1,10,"Send 'PRIVMSG ".(($chan =~ /^#./)?"$chan":"$nick")." :\001ACTION ".do{my $tmp = getHalResponse($striptext) || last process; $tmp =~ s/'/\\'/gms; $tmp =~ s/[\s\r\n]+/ /gms; $tmp;}."\001';";                                     # get response & send

    $flags =~ /^version$/i && ctcpReply $nick, "VERSION AI powerwed by MegaHal engine by Jason Hutchens - http://www.megahal.net";
    print "CTCP from $nick $chan = $flags $text\n" if $chan !~ /./;
  };
  /^ctcpReply$/i && do {
    print "CTCPREPLY from $nick $chan - $flags $text\n";
  };
  /^disconnect$/i && do {
    print $writer "#quit\r\n\r\n";
    close $writer; close $reader;
  };
  /^nick$/i && do {
    (lc $nick eq lc $botnick) && do {
      print "Changing nick to DoomCookie\n\n";
      Send 'nick DoomCookie';
    };
  };
};
