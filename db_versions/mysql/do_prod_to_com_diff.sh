#!/bin/tcsh -f

echo Dumping dbname_prod on dbname-db
./db_version_dump.pl dbname_prod.diff.sql dbname-db:dbname_prod | & cat - > /dev/null
echo Dumping dbname_com on dbname-db
./db_version_dump.pl dbname_com.diff.sql  dbname-db:dbname_com

echo "Writing recursive diff to prod_to_com_diff.txt..."
diff -rcbB dbname_prod.diff.sql dbname_com.diff.sql > prod_to_com_diff.txt
echo "Viewing diff with less..."
exec less prod_to_com_diff.txt;
