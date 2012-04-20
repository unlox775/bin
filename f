#!/usr/bin/perl -w

select((select(STDOUT), $| = 1)[0]);

##############################################################
##########################   Main   ##########################
##############################################################

my ( $garbage, $case, $arg, $find, $file, $show_all, $test_only, $force) = ('','','','');
my @patterns;    my ($skip, $fcount, $found, $tot_count, $b_count, $tot_time) = (0,0,0,0,0,0);    my $start_time = time();
foreach $arg (0..$#ARGV)
{
	unless ( ($ARGV[$arg]) && ($skip == 0) ) { $skip = 0;    next; }
	if ($ARGV[$arg] =~ /^-f(ind)?$/) 
	{ 
		$arg++;    my $find = $ARGV[$arg];

		unshift(@patterns,$find) unless $find eq '';

		$skip = 1;    next; 
	}
        if ($ARGV[$arg] =~ /^-file$/)
        {
                $arg++;    $file = $ARGV[$arg];
                if (! -r "$file" ) { print "No Read Priveledges for Pattern File ($file).\n";    exit 0; }
                if ( -d "$file" ) { print "-file ( $file ) is a Directory.\n";    exit 0; }
                unless (open(PATFILE,"$file")) { print "Open of Pattern File ($file) failed.  $!";     exit 0; }
                my @add_pats = <PATFILE>;    close PATFILE;

		foreach (0..$#add_pats) 
		{
			$add_pats[$_] =~ s/([^\w\d])/\\$1/g;    ###  Literal find
			$add_pats[$_] = "\[$add_pats[$_]\]" if ( $add_pats[$_] =~ /^\w$/ ) || ( $add_pats[$_] =~ /^\\\W$/ );    ###  Sq Brackets if 1 char long
			eval "\$garbage =~ /$add_pats[$_]/;";    if ( $@ ne "" ) { $add_pats[$_] = ''; }
		}

		unshift(@patterns,@add_pats);

                $skip = 1;    next;
        }
	if ($ARGV[$arg] =~ /^-i(nsensitive)?$/) { $case = "i";     next; }
	if ($ARGV[$arg] =~ /^-a(ll)?$/) { $show_all = "1";     next; }
	if ($ARGV[$arg] =~ /^-t(est)?$/) { $test_only = "1";     next; }
	if ($ARGV[$arg] =~ /^-force$/) { $force = "1";     next; }

	unless ($fcount) 
	{
		foreach (0..$#patterns) 
		{ 
			eval "\$garbage =~ /$patterns[$_]/;";
			if ( $@ ne "" ) { print "/$patterns[$_]/$case;  --> Bad : $@\n";    $patterns[$_] = '';    exit 0 unless $force; }
			else { print "/$patterns[$_]/$case;  --> Good\n"; } 
		}
		my @tmp_pats = @patterns;    undef @patterns;
		foreach (@tmp_pats) { push(@patterns, $_) if $_ ne ''; }
		unless ( @patterns ) { print "Missing find value(s).\n";    exit 0; }
		@patterns = reverse sort byLength @patterns;
	}

	$fcount++;
	my $file = $ARGV[$arg];
	my $count = 0;

        if ( (-d "$file" ) || (! -T "$file" ) ) { next; }
	if (! -e "$file" ) { print "$file does not exist.\n";    next; }
	if (! -r "$file" ) { print "No Read Priveledges for $file.\n";    next; }

	unless (open(THISFILE,"$file")) { print "Open of Target File '$file' for Read In failed.  $!";     next; }
	my @file_contents = <THISFILE>;
	close THISFILE;

	$b_count += length(join('',@file_contents));

	my ($find, $__);   my $num = 0;    #print "\n(" . length(join('',@file_contents)) . ")(" . length(join('',@patterns)) . ")";
	my @_patterns = @patterns;
	foreach $find (@_patterns)
	{
#		$num++;    print ".";
		next if ($find eq '');

		if ($case) { unless ( grep(/$find/i,@file_contents) ) { next; } }
		else { unless ( grep(/$find/,@file_contents) ) { next; } }
	
		foreach $__ (0..$#file_contents) { if ($case) { $count += ($file_contents[$__] =~ s/$find//ig); }    else { $count += ($file_contents[$__] =~ s/$find//g); } }
	}
        print "$file\t:\n\t\t\t\t\t\t\t\t\t$count occurences found. (file $fcount of ~" . ($#ARGV-3) . ")\n" if ($count) || ($show_all);
        $found++ if $count;    $tot_count += $count;

	undef @file_contents;
}

unless ( @patterns ) { print "Missing find value(s).\n";    exit 0; }

$tot_time = time() - $start_time;    $tot_time = 1 if $tot_time == 0;    (my $secs = ($tot_time % 60)+100) =~ s/^1//;    my $mins = int($tot_time / 60);

print "$tot_count occurrences found in $found of $fcount files searched (" . sprintf("%.1f",$b_count/1024) . " Kb total in $mins:$secs (" . sprintf("%.1f",($b_count/1024)/$tot_time) . " Kb/sec))\n" if $found;
print "No occurrences found in any file (" . sprintf("%.1f",$b_count/1024) . " Kb total in $mins:$secs (" . sprintf("%.1f",($b_count/1024)/$tot_time) . " Kb/sec))\n" unless $found;

##############################################################
########################## End Main ##########################
##############################################################

sub byLength { length($a) <=> length($b); }

