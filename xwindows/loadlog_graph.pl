#!/usr/bin/perl -w

select((select(STDOUT), $| = 1)[0]);
select((select(STDERR), $| = 1)[0]);
use Time::ParseDate;



###  Params for output
my $checkdelay = 432;
my $numpages = 0;
my $width = 400;
my $max = 10;
my $stretchmax = 0;
my $char = "\x02";
my $char2 = "-";

###  Get the Host name (not in Env when cron job) and generate the logfile
(my $HOST = lc(`/bin/hostname`)) =~ s/[\n\t\r\s]//g;
if ( $HOST =~ /^(.+).inetz.com$/i ) { $HOST = lc($1); }
if ( $HOST =~ /^(.+).mrsfields.com$/i ) { $HOST = lc($1); }

foreach ( grep(/^-*(t(ime)?|d(elay)?)=?[\.\d]+/,@ARGV) ) { ($checkdelay = $_) =~ s/\D//g; }
foreach ( grep(/^-*p(ages?)?=?[\.\d]+/,@ARGV) ) { ($numpages = $_) =~ s/\D//g; }
foreach ( grep(/^-*w(idth)?=?[\.\d]+/,@ARGV) ) { ($width = $_) =~ s/\D//g; }
foreach ( grep(/^-*m(ax)?=?[\.\d]+/,@ARGV) ) { $max = &parse_num($_); }
foreach ( grep(/^-*s(tretch)?m(ax)?/,@ARGV) ) { $stretchmax = 1; }
foreach ( grep(/^-*c(har)?=?.+/,@ARGV) ) { $char = chop($_); }
foreach ( grep(/^-*c(har)?2=?.+/,@ARGV) ) { $char2 = chop($_); }
foreach ( grep(/^-*h(ost)?=?\s*[\w\.]+\s*$/,@ARGV) ) { ($HOST = $_) =~ s/^-*h(?:ost)?=?\s*([\w\.]+)\s*$/$1/; }




###  Get the From and To Dates
my $now = time();    $now += 3600 * 2 if (localtime($now))[1] < 2;

my %thisday = ('m' => ((localtime($now))[4] + 1), 		'd' => (localtime($now))[3], 		'y' => ((localtime($now))[5] + 1900) );
my %nextday = ('m' => ((localtime($now + 86400))[4] + 1), 	'd' => (localtime($now + 86400))[3], 	'y' => ((localtime($now + 86400))[5] + 1900) );

my $daysago = (localtime($now))[6];    $daysago = 7 unless $daysago;
my %thisweek = ('m' => ((localtime($now - (86400 * $daysago)))[4] + 1), 	'd' => (localtime($now - (86400 * $daysago)))[3], 	'y' => ((localtime($now - (86400 * $daysago)))[5] + 1900) );
my %nextweek = ('m' => ((localtime($now - (86400 * $daysago) + (86400 * 7)))[4] + 1), 	'd' => (localtime($now - (86400 * $daysago) + (86400 * 7)))[3], 	'y' => ((localtime($now - (86400 * $daysago) + (86400 * 7)))[5] + 1900) );

my %thismon = %thisday;    if ( $thismon{'d'} <= 1 ) { %thismon = ('m' => ((localtime($now - 86400))[4] + 1), 'd' => (localtime($now - 86400))[3], 'y' => ((localtime($now - 86400))[5] + 1900) ); }
my %nextmon = %thismon;    $nextmon{'m'}++;    if ($nextmon{'m'} > 12) { $nextmon{'m'} = 1;    $nextmon{'y'}++; }
$thismon{'d'} = 1;    $nextmon{'d'} = 1;

my %thisyear = %thismon;    $thisyear{'m'} = 1;
my %nextyear = %thisyear;    $nextyear{'y'}++;

my ($fromdate,$todate, $m, $d, $y, $h, $mi, $s) = ( ($now-86400), $now );
if ( $ARGV[0] )
{
	if ( $ARGV[0] =~ /^\s*(daily|day)\s*$/i )
	{ 
		$fromdate = &parsedate("$thisday{'m'}/$thisday{'d'}/$thisday{'y'} 00:00:00");    
		$todate = &parsedate("$nextday{'m'}/$nextday{'d'}/$nextday{'y'} 00:00:00"); 
	}
	elsif ( $ARGV[0] =~ /^\s*week(ly)?\s*$/i )
	{ 
		$fromdate = &parsedate("$thisweek{'m'}/$thisweek{'d'}/$thisweek{'y'} 00:00:00");    
		$todate = &parsedate("$nextweek{'m'}/$nextweek{'d'}/$nextweek{'y'} 00:00:00"); 
	}
	elsif ( $ARGV[0] =~ /^\s*mon(th(ly)?)?\s*$/i ) 
	{ 
		$fromdate = &parsedate("$thismon{'m'}/$thismon{'d'}/$thismon{'y'} 00:00:00");    
		$todate = &parsedate("$nextmon{'m'}/$nextmon{'d'}/$nextmon{'y'} 00:00:00"); 
	}
	elsif ( $ARGV[0] =~ /^\s*(year(ly)?|annual)\s*$/i ) 
	{ 
		$fromdate = &parsedate("$thisyear{'m'}/$thisyear{'d'}/$thisyear{'y'} 00:00:00");    
		$todate = &parsedate("$nextyear{'m'}/$nextyear{'d'}/$nextyear{'y'} 00:00:00"); 
	}
	elsif ( $ARGV[0] =~ /^\s*(\d+)\/(\d+)\s*$/i )
	{ 
		($m, $y) = ($1, $2);    $y += 100 if $y < 70;    $y += 1900 if $y < 1900;
		$fromdate = &parsedate("$m/1/$y 00:00:00");    
		$m++;    if ($m > 12) { $m = 1;    $y++; }
		$todate = &parsedate("$m/1/$y 00:00:00") if ! $ARGV[1]; 
	}
	elsif ( $ARGV[0] =~ /^\s*(\d+)\/(\d+)\/(\d+)\s*$/i )
	{ 
		($m, $d, $y) = ($1, $2, $3);    $y += 100 if $y < 70;    $y += 1900 if $y < 1900;
		$fromdate = &parsedate("$m/$d/$y 00:00:00");    
		$todate = $fromdate + 86400 if ! $ARGV[1]; 
	}
	else 
	{  
		$fromdate = &parsedate($ARGV[0]);
		if (! $fromdate) { print STDERR "Error With Date '$ARGV[0]' : ";    print STDERR &parsedate($ARGV[0]);    exit 0; }
		$todate = $fromdate + 86400 if ! $ARGV[1];
	}
}
if ( $ARGV[1] )
{
	if ( $ARGV[1] =~ /^\s*(daily|day)\s*$/i )
	{ 
		$todate = $fromdate + 86400; 
	}
	elsif ( $ARGV[1] =~ /^\s*week(ly)?\s*$/i )
	{ 
		$todate = $fromdate + (86400 * 7); 
	}
	elsif ( $ARGV[1] =~ /^\s*mon(th(ly)?)?\s*$/i ) 
	{ 
		($s, $mi, $h, $d, $m, $y) = localtime($fromdate);    $y += 1900 if $y < 1900;    $m++;
		$m++;    if ($m > 12) { $m = 1;    $y++; }
		$todate = &parsedate("$m/$d/$y " . &alt_pad($h,2) . ":" . &alt_pad($mi,2) . ":" . &alt_pad($s,2)); 
	}
	elsif ( $ARGV[1] =~ /^\s*(year(ly)?|annual)\s*$/i ) 
	{ 
		($s, $mi, $h, $d, $m, $y) = localtime($fromdate);    $y += 1900 if $y < 1900;    $m++;
		$y++;
		$todate = &parsedate("$m/$d/$y " . &alt_pad($h,2) . ":" . &alt_pad($mi,2) . ":" . &alt_pad($s,2)); 
	}
	elsif ( $ARGV[1] =~ /^\s*(\d+)\/(\d+)\s*$/i )
	{ 
		($m, $y) = ($1, $2);    $y += 1900 if $y < 1900;
		$m++;    if ($m > 12) { $m = 1;    $y += 100 if $y < 70;    $y++; }
		$todate = &parsedate("$m/1/$y 00:00:00"); 
	}
	elsif ( $ARGV[1] =~ /^\s*(\d+)\/(\d+)\/(\d+)\s*$/i )
	{ 
		($m, $d, $y) = ($1, $2, $3);    $y += 100 if $y < 70;    $y += 1900 if $y < 1900;
		$todate = $fromdate + 86400; 
	}
	else 
	{  
		$todate = &parsedate($ARGV[1]);
		if (! $todate) { print STDERR "Error With Date '$ARGV[1]' : ";    print STDERR &parsedate($ARGV[1]);    exit 0; }
	}
}

print "From " . scalar localtime($fromdate) . " to " . scalar localtime($todate) . " ...\n";




###  If they have provided a number of pages to fit the range between, reset timedelay
if ($numpages) { $checkdelay = int(($todate - $fromdate) / (200 * $numpages)); }



###  Set the vars to be used in the output format
my ($thismin, $thismax, $date);


###  Set the format of the output
format STDOUT =
@>>>> - @>>>> | @<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< |
$thismin,$thismax,$date
.




my $logfile = "/shared/logs/$HOST\_loadlog";

open(LOGFILE,"<$logfile") or die "Could not open logfile $logfile";


###  Loop until this minute is over
my ($entry, $ch);
my @entries;
while ( read(LOGFILE, $entry, 6) )
{
	my @entry = unpack('Si', substr($entry,0,6));

	while ( ($entry[0] > 30000) || ($entry[1] < 950000000) || ($entry[1] > 1500000000) )
	{
print "skip $entry[0] --> " . scalar localtime($entry[1]) . " ( $entry[1] )\n";
#sleep 1;
		read(LOGFILE, $ch, 1);
		substr($entry,0,1) = '';
		$entry .= $ch;
		@entry = unpack('Si', substr($entry,0,6));
	}

#	print "skip or\n" unless ($entry[1] >= $fromdate) && ($entry[1] <= $todate);
	next unless ($entry[1] > $fromdate) && ($entry[1] < $todate);

#print "good\n";
	$entry[0] = $entry[0] / 100;

	push(@entries, \@entry );
}


my $n = 1;
@entries = sort sortarr @entries;

# ###  Print the range
# print "Load ranged from " . &minarr(\@entries,0) . " to " . &maxarr(\@entries,0);
# print " between " . scalar localtime(&minarr(\@entries,1)) . " and " . scalar localtime(&maxarr(\@entries,1)) . "\n";

# exit 0;

###  my ($mindate, $maxdate, $c) = ( &minarr(\@entries,1), &maxarr(\@entries,1), 0 );
my $maxload = &maxarr(\@entries,0);
$max = int($maxload) + 1 if $stretchmax;
my ($mindate, $maxdate, $c) = ( $fromdate, $todate, 0 );
for ( my $currtime = $mindate ; $currtime <= ($maxdate + $checkdelay) ; $currtime += $checkdelay )
{
	###  Get the min and max values for this tim period
	($thismin, $thismax) = (undef, undef);
	while ( (defined $entries[($c + 1)][1]) && ($entries[$c][1] <= $currtime) && ($_ = $entries[$c++]) 
	)
	{
		 $thismin = $_->[0] if (not defined $thismin) || ($_->[0] < $thismin);
		 $thismax = $_->[0] if (not defined $thismax) || ($_->[0] > $thismax);
	}
	$thismin ||= 0;    $thismax ||= 0;

#	$date = scalar localtime($currtime);
#	write;

        ###  Create the load bar
	my $minbar = (1 + sprintf("%.0f",( $width * &real_remainder(($thismin / $max),1) )));
	my $maxbar = (1 + sprintf("%.0f",( $width * &real_remainder(($thismax / $max),1) )));
        my $bar = ($char x $minbar) . ($char2 x ($maxbar - $minbar));
   
        ###  Put in the load metering lines
        foreach (1..($max-1)) { substr($bar,( sprintf("%.0f",( $width * &real_remainder(($_ / $max),1) )) ),1) = " " if length($bar) > sprintf("%.0f",( $width * &real_remainder(($_ / $max),1) )); }

#       $bar .= " $thismin";

        ###  Print out the bar
        print $bar . "\n";
	
}

sleep 1000;

exit 0;



sub
minarr { my ($list,$n) = @_;    my $min;    foreach ( @{$list} ) { $min = $_->[$n] if (not defined $min) || ($_->[$n] < $min) }    $min; }

sub
maxarr { my ($list,$n) = @_;    my $max;    foreach ( @{$list} ) { $max = $_->[$n] if (not defined $max) || ($_->[$n] > $max) }    $max; }

sub
sortarr { $a->[$n] <=> $b->[$n] }

sub
real_remainder { my ($num, $r) = @_;    return 0 unless $r;    $num - int($num / $r); }

sub
parse_num { my $str = shift;    return 0 unless defined $str;    $str =~ s/[^\d\.]//g;    $str =~ s/^(\d*)((?:\.\d+)?)(\..*)?$/$1$2/;    $str =~ s/^0*//;    $str =~ s/0*$// if $str =~ /\./;    $str = 0 unless $str;    $str; }
	
