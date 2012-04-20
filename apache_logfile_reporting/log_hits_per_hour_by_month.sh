#!/bin/bash -norc

echo Summing Hits per Site in these log files: ~/logs/\*-"$1"\* for all lines 1>&2


zgrep '\[' ~/logs/*-$1* | perl -pe '$_ = "" unless /^(.+)-\w{3}-\d{4}.gz:([\d\.]+)[^\[]+\[([^\]]+)\]/;  $_ = substr($3, 12, 2). "\n"; ' | sort | uniq -c | perl -pe 's/^\s*(\d+)\s+(\S.*)$/$2\t$1/'
