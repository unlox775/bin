#!/bin/tcsh -f

echo Dumping dbanme_beta on localhost
./db_version_dump.pl dbanme_beta dbanme_beta | & cat - > /dev/null
echo Dumping dbanme on localhost
./db_version_dump.pl dbanme_dev  dbanme

echo "Writing recursive diff to beta_to_dev_diff.txt..."
diff -rcbB dbanme_beta dbanme_dev > beta_to_dev_diff.txt
echo "Viewing diff with less..."
exec less beta_to_dev_diff.txt;
