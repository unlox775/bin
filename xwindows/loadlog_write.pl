#!/usr/bin/perl -w


###  Generate the time to die
my $dietime = time() + 60;

###  Get the Host name (not in Env when cron job) and generate the logfile
(my $HOST = lc(`/bin/hostname`)) =~ s/[\n\t\r\s]//g;
if ( $HOST =~ /^(.+).inetz.com$/i ) { $HOST = lc($1); }
if ( $HOST =~ /^(.+).mrsfields.com$/i ) { $HOST = lc($1); }

my $logfile = "/shared/logs/$HOST\_loadlog";

###  Loop until this minute is over
while (1)
{
	###  Get the Current time aned exit if it's time to die
	my $nowtime =  time();
	if ( $nowtime >= $dietime ) { exit 0; }

	###  Get the load and write it to the file
	my ($uptime, $theload) = (`/usr/bin/uptime`);
	if ( $uptime =~ /averages?:\s*([\d\.]+)/i ) 
	{ 
		###  Make sure the last entry is more than 4 seconds old (to stop 2 running processes from stepping on each other's toes)
		my $lastentry = `/usr/bin/tail -c6 $logfile`;    
#		my @lastentry = unpack('Si', substr($lastentry,0,6));
		if ( abs( ( unpack('Si', substr($lastentry,0,6)) )[1] - time() ) > 4 ) 
		{  

			$theload = int( &parse_num($1) * 100 );

			if ( open(LOGFILE,">>$logfile") ) { print LOGFILE pack('Si', $theload, time() );    close LOGFILE; }
                        else { die "Could Not open Loadlog $logfile : $!"; }
		}
	}
        else { die "Could Not Read uptime output : '$uptime'"; }

	###  Wait 5 seconds
	sleep 5;
}

exit 0;







sub
parse_num { my $str = shift;    return 0 unless defined $str;    $str =~ s/[^\d\.]//g;    $str =~ s/^(\d*)((?:\.\d+)?)(\..*)?$/$1$2/;    $str =~ s/^0*//;    $str =~ s/0*$// if $str =~ /\./;    $str = 0 unless $str;    $str; }

