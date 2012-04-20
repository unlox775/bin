#!/bin/bash -norc

echo Finding the top 30 minutes with most Hits in these log files: ~/logs/\*-"$1"\* for all lines 1>&2


zgrep '\[' ~/logs/*-$1* | perl -pe '/^(.+)-\w{3}-\d{4}.gz:([\d\.]+)[^\[]+\[([^\]]+)\]/;  $_ = substr($3, 0, 17). "\n"; ' | sort | uniq -c | sort_by_fwn | tail -n 30
