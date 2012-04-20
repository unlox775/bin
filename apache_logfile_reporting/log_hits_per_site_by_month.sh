#!/bin/bash -norc

echo Summing Hits per Site in these log files: ~/logs/\*-"$1"\* for all lines 1>&2


zgrep '\]' ~/logs/*-$1* | perl -pe '/^(.+)-\w{3}-\d{4}.gz:([\d\.]+)[^\[]+\[([^\]]+)\]/;  $_ = "$1\n"; ' | sort | uniq -c | ~/bin/sort_by_fwn | perl -pe 's/\/home\d*\/elikirkc\/logs\///'