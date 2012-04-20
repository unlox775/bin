#!/usr/bin/perl

use DBI;
use DBD::mysql;
use Dave::Bug qw(:common);

$username = 'dbanme';
$ignore_tables    = undef;

@verbose = grep { /^-\w*?v\w*?$/ } @ARGV;
@debug =   grep { /^-\w*?d\w*?$/ } @ARGV;
@help =    grep { /^-\w*?h\w*?$/ } @ARGV;
@ARGV =    grep { !/^-\w+$/       } @ARGV;
$host    = 'localhost';
$host_arg    = '';
$host_prefix = '';
$out         = shift @ARGV;
$database    = shift @ARGV;
$username = "dbuser";
$password = "DBPASS123";


if ( $database =~ /^([\w\.\-]+)\:(\w+)$/ ) {
    $host = $1;
    $host_arg = " -h $1 ";
    $host_prefix = "$1:";
    $database = $2;
}

###  Print Help Info
if ( @help ) {
    print <<EDOC;
Usage: db_version_dump.pl [options] <output dir> [host:]<database>

Options:
    -d Turn on debugging output
    -v Turn on progress output
    -h print this message

EDOC
    exit;
}

@code_tables = split(/\s+/,join('',`egrep -v '^#' ../tables_considered_as_code.txt`));


#########################
###  Pre-Caching

###  Connect to the database
our $dbh = DBI->connect("dbi:mysql:$database:$host:3306", $username, $password) or die $DBI::errstr;

###  List of Tables
our $tables_sql = "SELECT a.table_name
                     FROM INFORMATION_SCHEMA.tables a
                    WHERE a.table_schema = '$database'
                   ";
our $tables = $dbh->selectcol_arrayref($tables_sql);
bug($tables, $out);


`rm    -f ./$out`;

###  Get all Tables
foreach my $table ( @$tables ) {
    next if ! $table || ($ignore_tables && $table =~ $ignore_tables);
    bug($table);

    print "Dumping TABLE $host_prefix$database/$table...\n" if @verbose;
    $data_opt = ( grep {$_ eq $table} @code_tables ) ? '' : '--no-data';
    $_ = `mysqldump --skip-lock-tables -c -e --skip-quick --order-by-primary $data_opt $host_arg -u $username --password=$password $database $table | egrep -v '^(-- (Host: |Dump completed on))' | perl -pe 's/ AUTO_INCREMENT=[0-9]+//g' >> ./$out`;
    print if @verbose;
}

# print "Dumping FUNCTIONS $host_prefix$database...\n" if @verbose;
# $_ = `pg_dump -i -s -U $username -n $schema $host_arg$database | perl -pe '(\$a,\$b) = (1,0) if /^CREATE FUNCTION/i;  \$b = 1 if /^CREATE SEQUENCE/i;  \$_ = "" unless \$a && ! \$b'| egrep -v '^(--|SET|\$)' | grep -v 'OWNER TO dbanme' | perl -pe 's/\;\$/\;\n/' >> ./$out`;
# print if @verbose;

exit;
