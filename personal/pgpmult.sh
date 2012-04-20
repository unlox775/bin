#!/bin/sh
/usr/local/bin/pgpe -ast -r `echo $* | sed 's/ / -r /g' `
