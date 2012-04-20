#!/bin/tcsh -f 

set base = $1
set file = perms_$1.snap
set last_file = perms_$1.snap.last

mv -f $file $last_file
find $base | perl -pe 'chomp;  $_ .= sprintf "\t%04o\n", (stat)[2] & 07777;' >> $file
