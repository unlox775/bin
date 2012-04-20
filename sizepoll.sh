#!/bin/tcsh -f
find -x $* -type d | ql | xargs du -sk
