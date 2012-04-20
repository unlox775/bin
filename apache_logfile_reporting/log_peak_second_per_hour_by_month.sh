#!/bin/bash -norc

echo Finding the top second in each hour in these log files: ~/logs/\*-"$1"\* for all lines 1>&2


zgrep '\[' ~/logs/*-$1* | perl -pe '/^(.+)-\w{3}-\d{4}.gz:([\d\.]+)[^\[]+\[([^\]]+)\]/;  $_ = substr($3, 0, 20). "\n"; ' | sort | uniq -c | sort_by_fwn | perl -pe 's/^\s*(\d+)\s+\d+\/\w+\/\d+\:(\d+)\:(\d+)\:(\d+)$/$2\t$1/' | sort_by_fwn | perl -pe '($h,$c) = /^(\d+)\t(\d+)$/; $lh = "-" if $lh eq ""; $_ = ""; if ($c) { $max ||= $c; $max = $c if $c > $max;  if ($h ne "-" && $h != $lh) { print "$lh\t$max\n"; $max = 0; } $lh = $h; }  END {print "$lh\t$max\n";}'

