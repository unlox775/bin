#!/bin/tcsh -f 

set file = perms_$1.snap

cat $file | perl -pe 'chomp; my ($f, $p) = split(/\t/); my $o = sprintf "%04o", (stat($f))[2] & 07777; if ( $o ne $p ) { `chmod $p "$f"`; $_ = "Set perms for $f to $p (was $o)\n"; } else { $_ = ""; }'
# cat $file | perl -pe 'chomp; my ($f, $p) = split(/\t/); my $o = sprintf "%04o", (stat($f))[2] & 07777; if ( $o ne $p ) { `chmod $p "$f"`; $_ = "Set perms for $f to $p (was $o)\n"; } else { $_ = "No Change: $f\n"; }'
