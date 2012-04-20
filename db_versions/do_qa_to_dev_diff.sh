#!/bin/tcsh -f

echo Dumping dbanme_qa on localhost
./db_version_dump.pl dbanme_qa dbanme_qa | & cat - > /dev/null
echo Dumping dbanme on localhost
./db_version_dump.pl dbanme_dev  dbanme

echo "Writing recursive diff to qa_to_dev_diff.txt..."
diff -rcbB dbanme_qa dbanme_dev > qa_to_dev_diff.txt
echo "Viewing diff with less..."
exec less qa_to_dev_diff.txt;
