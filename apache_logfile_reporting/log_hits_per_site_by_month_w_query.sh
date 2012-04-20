#!/bin/bash -norc

echo Summing Hits per Site in these log files: ~/logs/\*-"$1"\* for lines that contain: "$2" "$3" 1>&2


zegrep "$2" "$3" ~/logs/*-$1* | perl -pe '/^(.+)-\w{3}-\d{4}.gz:([\d\.]+)[^\[]+\[([^\]]+)\]/;  $_ = "$1\n"; ' | sort | uniq -c | ~/bin/sort_by_fwn | perl -pe 's/\/home\d*\/elikirkc\/logs\///'
