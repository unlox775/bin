#!/bin/tcsh -f

echo Dumping dbname_staging on dbname-db
./db_version_dump.pl dbname_staging.diff.sql dbname-db:dbname_staging | & cat - > /dev/null
echo Dumping dbname_dev on dbname-db
./db_version_dump.pl dbname_dev.diff.sql     dbname-db:dbname

echo "Writing recursive diff to staging_to_dev_diff.txt..."
diff -rcbB dbname_staging.diff.sql dbname_dev.diff.sql > staging_to_dev_diff.txt
echo "Viewing diff with less..."
exec less staging_to_dev_diff.txt;
