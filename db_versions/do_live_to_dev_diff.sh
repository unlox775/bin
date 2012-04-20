#!/bin/tcsh -f

echo Dumping dbanme on live.dbanme.org
./db_version_dump.pl dbanme_live live.dbanme.org:dbanme | & cat - > /dev/null
echo Dumping dbanme on localhost
./db_version_dump.pl dbanme_dev  dbanme

echo "Writing recursive diff to live_to_dev_diff.txt..."
diff -rcbB dbanme_live dbanme_dev > live_to_dev_diff.txt
echo "Viewing diff with less..."
exec less live_to_dev_diff.txt;
