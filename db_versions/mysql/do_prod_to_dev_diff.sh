#!/bin/tcsh -f

echo Dumping dbname_prod on dbname-db
./db_version_dump.pl dbname_prod.diff.sql dbname-db:dbname_prod | & cat - > /dev/null
echo Dumping dbname_dev on dbname-db
./db_version_dump.pl dbname_dev.diff.sql  dbname-db:dbname_dev

echo "Writing recursive diff to prod_to_dev_diff.txt..."
diff -rcbB dbname_prod.diff.sql dbname_dev.diff.sql > prod_to_dev_diff.txt
echo "Viewing diff with less..."
exec less prod_to_dev_diff.txt;
