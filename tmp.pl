use warnings;
use strict;

#print substr("abcd", 1, 3), "\n";

#my @a;
#$a[0] = ":nick!user\@host";
#$a[1] = "JOIN";
#$a[2] = "#derivan";
#$a[3] = ":weeee";

#my $cnt = 0;

#for my $i (@a) {
#  print STDOUT "$cnt -> $a[$cnt]\n";
#  $cnt++;
#}


my $text = ":nick!user\@host JOIN #chan";

if ($text =~ /(\w+)!(\w+)\@(\w+)\s(\w+)/) {
  print "$1, $2, $3\n";
}

$text = "PING :abcdefghijklmnopqrstuvwxyz[]{};':,.\\/<>?\"|`1234567890-=_+~!@#\$\%^&*()";
if ($text =~ /^(PING)\s(:(.*))/) {
  print "$1, $2\n";
}


#exec "pause";