#!/usr/bin/perl

$username = 'dbanme';
$ignore_schemas   = qr/^(information_schema|pg_catalog|pg_temp_1|pg_toast.*|public)$/;
$ignore_tables    = undef;

@verbose = grep { /^-\w*?v\w*?$/ } @ARGV;
@debug =   grep { /^-\w*?d\w*?$/ } @ARGV;
@help =    grep { /^-\w*?h\w*?$/ } @ARGV;
@ARGV =    grep { !/^-\w+$/       } @ARGV;
$host_arg    = '';
$host_prefix = '';
$dir         = shift @ARGV;
$database    = shift @ARGV;

if ( $database =~ /^([\w\.\-]+)\:(\w+)$/ ) {
    $host_arg = " --host $1 ";
    $host_prefix = "$1:";
    $database = $2;
}

###  Print Help Info
if ( @help ) {
    print <<EDOC;
Usage: db_version_dump.pl [options] <output dir> [host@]<database>

Options:
    -d Turn on debugging output
    -v Turn on progress output
    -h print this message

NOTE: This runs psql and pg_dump commands as you using the
username, "dbanme".  It runs more than 50 of these and will ask
you for your password for each unless you set up a ~/.pgpass like
this one:

localhost:5432:dbanme:dbanme:DBPASS123
localhost:5432:dbanme_qa:dbanme:DBPASS123
localhost:5432:dbanme_beta:dbanme:DBPASS123
live.dbanme.org:5432:dbanme:dbanme:DBPASS123

EDOC
    exit;
}

@code_tables = split(/\s+/,join('',`egrep -v '^#' ../tables_considered_as_code.txt`));

###  Get all Schemas
my $GET_SCHEMAS = 'psql '.$host_arg.$database.' '.$username.' -c '."'".'\dn'."'".' | perl -pe '."'".'unless( s/^\s(\S+)\s.+$/$1/ ) { $_ = "" }'."'".'';
print $GET_SCHEMAS."\n" if @debug;
foreach my $schema ( split("\n", `$GET_SCHEMAS` ) ) {
    next if ! $schema || ($ignore_schemas && $schema =~ $ignore_schemas);

    `mkdir -p ./$dir`;
    `rm    -f ./$dir/$schema.sql`;

    ###  Get all Tables
    my $GET_TABLES = 'psql '.$host_arg.$database.' '.$username.' -c '."'".'\dt '.$schema.'.*'."'".' | perl -pe '."'".'unless( s/^[^\|]*\|\s(\S+)\s.+$/$1/ ) { $_ = "" }'."'".'';
    my $GET_VIEWS  = 'psql '.$host_arg.$database.' '.$username.' -c '."'".'\dv '.$schema.'.*'."'".' | perl -pe '."'".'unless( s/^[^\|]*\|\s(\S+)\s.+$/$1/ ) { $_ = "" }'."'".'';
    print $GET_TABLES."\n" if @debug;
    print $GET_VIEWS."\n" if @debug;
    foreach my $table ( sort split("\n", `$GET_TABLES`."\n".`$GET_VIEWS`) ) {
        next if ! $table || ($ignore_tables && $table =~ $ignore_tables);

        print "Dumping TABLE $host_prefix$database/$schema/$table...\n" if @verbose;
        $_ = `pg_dump -i -s -U $username -t $schema.$table $host_arg$database | egrep -v '^(--|SET|\$)'| grep -v 'OWNER TO dbanme' | perl -pe 's/\;\$/\;\n/' >> ./$dir/$schema.sql`;
        print if @verbose;
    }

    print "Dumping FUNCTIONS $host_prefix$database/$schema...\n" if @verbose;
    $_ = `pg_dump -i -s -U $username -n $schema $host_arg$database | perl -pe '(\$a,\$b) = (1,0) if /^CREATE FUNCTION/i;  \$b = 1 if /^CREATE SEQUENCE/i;  \$_ = "" unless \$a && ! \$b'| egrep -v '^(--|SET|\$)' | grep -v 'OWNER TO dbanme' | perl -pe 's/\;\$/\;\n/' >> ./$dir/$schema.sql`;
    print if @verbose;

    if ( $schema eq 'community' ) {
        foreach my $table ( @code_tables ) {
            print "Dumping TABLE DATA $host_prefix$database/$schema/$table...\n" if @verbose;
            $_ = `pg_dump -i -adD -U $username -t $schema.$table $host_arg$database | egrep -v '^(--|SET|\$)'| grep -v 'OWNER TO dbanme' | sort >> ./$dir/$schema.sql`; #  | perl -pe 's/\;\$/\;\n/'
            print if @verbose;
        }
    }
}

exit;
