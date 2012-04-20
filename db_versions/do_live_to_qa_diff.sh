#!/bin/tcsh -f

echo Dumping dbanme on live.dbanme.org
./db_version_dump.pl dbanme_live live.dbanme.org:dbanme | & cat - > /dev/null
echo Dumping dbanme_qa on localhost
./db_version_dump.pl dbanme_qa  dbanme_qa

echo "Writing recursive diff to live_to_qa_diff.txt..."
diff -rcbB -8 dbanme_live dbanme_qa > live_to_qa_diff.txt
echo "Viewing diff with less..."
exec less live_to_qa_diff.txt;
