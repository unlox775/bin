package Dave::ErrorSystem::Reports;

#########################
###  CMS/ErrorSystem/Reports.pm
###  Version : $Id: Reports.pm,v 1.1 2009/02/03 23:42:14 dave Exp $
###
###  A Reporting interface for the ErrorSystem
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::Global qw(:dirs &onAlpha);
use Dave::Util qw(&get_utc_date &get_epoch_date &binary_search &split_delim_line &join_delim_line &uniq );
use Dave::ErrorSystem qw( &archive_error_dir &archive_day_dir $ERROR_SYSTEM_TZ );
use Dave::ErrorSystem::Instance;
use CGI::Util qw( &escape &unescape );
use Storable qw(&freeze &thaw);  $Storable::forgive_me = 1;

###  Globals
my %day_count_cache;
my %day_lines_cache;
my %hour_count_cache;
my %hour_lines_cache;
my $cache_age = 0;


#########################
###  Constructor

sub new {
    my $pkg = shift;
    my ( $error, $details, $objid ) = @_;

    my $self = bless( {}, $pkg );

    return $self;
}


#########################
###  Query Methods

sub count_errors { 
    my $self = shift;
    my ( $errno, $start_datetime, $end_datetime ) = @_;

    my $sum = 0;
    $sum += $self->count_day_errors($errno, @$_) foreach ( $self->get_dates_included($start_datetime, $end_datetime) );

    return $sum;
}

sub get_brief_lines {
    my $self = shift;
    my ( $errno, $start_datetime, $end_datetime ) = @_;

    my @lines;
    push @lines, $self->count_day_errors($errno, @$_, 1) foreach ( $self->get_dates_included($start_datetime, $end_datetime) );

    return @lines;
}

sub get_errors {
    my $self = shift;

    return map { $self->get_error($_[0], $_) } $self->get_brief_lines( @_ );
}

sub get_dates_included {
    my $self = shift;
    my ( $start_datetime, $end_datetime ) = @_;

    return if &get_epoch_date($start_datetime) > &get_epoch_date($end_datetime);

    ###  Prepare
    my ( $start_day, $start_time ) = ( split(' ', &get_utc_date($start_datetime), 2) );
    my ( $end_day,   $end_time   ) = ( split(' ', &get_utc_date($end_datetime  ), 2) );

    ###  If the start and end day are the same, then simple return
    return [$start_day, $start_time, $end_time] if $start_day eq $end_day;

    my $whole_days = int( ( &get_epoch_date($end_day) - &get_epoch_date($start_day)
                            + (3600 * 6) # work over Daylight savings glitches
                            )
                          / 86400
                          );

    ###  Assemble the list
    my @days;
    ###  First day
    push @days, ( ($start_time =~ /^0+:0+:0+$/) ? [$start_day,'-','-'] : [$start_day,$start_time,'-'] );
    ###  Middle days
    push @days, map {[ ( split(' ', &get_utc_date( &get_epoch_date($start_day)
                                                   + (86400 * $_)
                                                   + (3600 * 6)
                                                   )) 
                         )[0],
                       '-',
                       '-'
                       ]} (1 .. ($whole_days - 1));
    ###  Last day (optional)
    push @days, ( ($end_time =~ /^0+:0+:0+$/) ? () : [$end_day,'-',$end_time] );

    return @days;
}

sub count_day_errors {
    my $self = shift;
    my ( $errno, $day_utc, $start_time, $end_time, $collect_lines ) = @_;

    ###  Scrub the day
    ( $day_utc ) = ( split(' ', &get_utc_date($day_utc), 2) );

    ###  Use Cache if available
    &check_cache_age();
    if ( $start_time eq '-'
         && $end_time eq '-'
         && $day_count_cache{$errno}{$day_utc}
         && ( ! $collect_lines
              || $day_lines_cache{$errno}{$day_utc}
              )
         ) {

#        bug ["CACHE", $day_count_cache{$errno}{$day_utc}];
        ###  Magic return
        if ( $collect_lines )
             { return( @{ $day_lines_cache{$errno}{$day_utc} } ); }
        else { return(    $day_count_cache{$errno}{$day_utc}   ); }
    }

    my $dir = &archive_error_dir(&get_epoch_date("$day_utc 12:00:00"), $errno);
    my $file = "$dir/brief.csv";

    ###  Check and open the file
    if ( ! -e $file ) {
        if ($collect_lines) { return @{[]}; } else { return 0 }
    }
    open(BRIEF, "<$file") or die "Could not open brief file $file: $!";

    ###  If we aren't starting at the beginning...
    my $start_epoch = ($start_time eq '-') ? undef : &get_epoch_date("$day_utc $start_time");
    if ( $start_time ne '-' ) {
        &binary_search($start_epoch, \*BRIEF, (stat($file))[7],
                           { average_line_length => 100,
                             seek_to_closest => 1,
                           }
                      );
    }

    ###  Count the rows
    my @lines;
    my $count = 0;
    my $skipped = 0;
    my $end_epoch = ($end_time eq '-') ? undef : &get_epoch_date("$day_utc $end_time");
    while (<BRIEF>) {
        ###  Ignore header and malformed rows
        next if ! /^(\d+)/;
        my $line = $_;
        my $row_time = $1;

        ###  We may find rows in there that are before the start bound
        next if $start_epoch && $row_time < $start_epoch;

        ###  End-range check (optional)
        if ( $end_epoch
             && $row_time >= $end_epoch
           ) {
            ###  Since some out-of-order will always exists
            ###    because of time sync on boxes, keep going through rows
            ###    to catch stragglers for a bit (20 rows or 5 mins)
            $skipped++;
            last if $skipped == 20 || abs($end_epoch - $row_time) > 300; # more than 5 mins off time sync...
            next;
        }
        $skipped = 0;
        push @lines, $self->read_brief_line($line) if $collect_lines;
        $count++;
    }

    close BRIEF;

    ###  Cache answers if it's a whole grab
    if ( $start_time eq '-'
         && $end_time eq '-'
         ) {
        if ( $collect_lines
             && @lines < 500
             ) {
            $day_lines_cache{$errno}{$day_utc} = \@lines;
        }
        $day_count_cache{$errno}{$day_utc} = $count;
    }

    ###  Magic return
    if ( $collect_lines )
         { return( @lines ); }
    else { return( $count   ); }
}

sub count_hour_errors {
    my $self = shift;
    my ( $errno, $day_utc, $hour, $collect_lines) = @_;

    ###  Scrub
    ( $day_utc ) = ( split(' ', &get_utc_date($day_utc), 2) );
    $hour = int($hour * 1);

    die "Invalid hour: $hour" if ! defined $hour || $hour < 0 || $hour > 23;

    ###  Use Cache if available
    &check_cache_age();
    if ( $hour_count_cache{$errno}{$day_utc}{$hour}
         && ( ! $collect_lines
              || $hour_lines_cache{$errno}{$day_utc}{$hour}
              )
         ) {
        ###  Magic return
        if ( $collect_lines )
             { return( @{ $hour_lines_cache{$errno}{$day_utc}{$hour} } ); }
        else { return(    $hour_count_cache{$errno}{$day_utc}{$hour}   ); }
    }

    ###  Just call count_day_errors()
    my @lines;
    my $count;
    my $start_time = sprintf("%.2d",$hour).     ':00:00';
    $start_time = '-' if $start_time eq '00:00:00';
    my $end_time   = sprintf("%.2d",$hour + 1). ':00:00';
    $end_time = '-' if $end_time eq '24:00:00';
    if ( $collect_lines )
         { @lines = $self->count_day_errors($errno, $day_utc, $start_time, $end_time, $collect_lines ); }
    else { $count = $self->count_day_errors($errno, $day_utc, $start_time, $end_time ); }
    
    ###  Cache answers
    if ( $collect_lines
         && @lines < 500
         ) {
        $hour_lines_cache{$errno}{$day_utc}{$hour} = \@lines;
    }
    $hour_count_cache{$errno}{$day_utc}{$hour} = $count;

    ###  Magic return
    if ( $collect_lines )
         { return( @lines ); }
    else { return( $count   ); }
}



#########################
###  Data Reading Methods

sub read_brief_line {
    my $self = shift;
    my ( $line ) = @_;
    chomp( $line );
    
    my %row;
    @row{qw( time
             host
             pid
             pid_error_count
             script
             objid
             )} = &split_delim_line(',', $line, '"');
    
    return \%row;
}

sub get_brief_line {
    my $self = shift;
    my ( $errno, $time, $host, $pid, $pid_error_count ) = @_;
    if ( UNIVERSAL::isa($time, 'HASH') ) {
        ( $time, $host, $pid, $pid_error_count ) = ($time->{'time'}, $time->{'host'}, $time->{'pid'}, $time->{'pid_error_count'});
    }

    ###  Scrub
    $time = &get_epoch_date($time);

    my $dir = &archive_error_dir($time, $errno);
    my $file = "$dir/brief.csv";

    my @target_vals = ($time, $host, $pid, $pid_error_count);

    ###  Check and open the file
    return unless -e $file;
    open(BRIEF, "<$file") or die "Could not open brief file $file: $!";

    my $line = &binary_search($time, \*BRIEF, (stat($file))[7],
                       { average_line_length => 100,
                         seek_to_closest => 1,
                     }
                   );
    ###  Most of the time this line found will be the one we want...
    if ( $line ) {
        my @line_vals = &split_delim_line( ',', $line, '"');
        
        ###  If it matches every val, we got it!
        if ( ! grep { $target_vals[$_] ne $line_vals[$_] } (0 .. $#target_vals) ) {
            close BRIEF;
            return $self->read_brief_line($line);
        }
    }

    ###  But if not, then read for a while to try to find it.
    ###    but not forever, only 20 lines or until the lines
    ###    are more than 5 mins later than the time we're
    ###    looking for.
    my $skipped = 0;
    while (<BRIEF>) {
        ###  Ignore header and malformed rows
        next if ! /^(\d+)/;
        my $row_time = $1;
        my $line = $_;

        ###  Get the first part of the string and parse
        my @line_vals = &split_delim_line( ',', $line, '"');

        ###  If it matches every val, we got it!
        if ( ! grep { $target_vals[$_] ne $line_vals[$_] } (0 .. $#target_vals) ) {
            close BRIEF;
            return $self->read_brief_line($line);
        }
        ###  Otherwise, skip for a while
        else {
            ###  Since some out-of-order will always exists
            ###    because of time sync on boxes, keep going through rows
            ###    to catch stragglers for a bit (20 rows or 5 mins)
            $skipped++;
            last if $skipped == 20 || abs($time - $row_time) > 300; # more than 5 mins off time sync...
            next;
        }
    }

    close BRIEF;
    
    return;
}

###  Just a copy of get_brief_line() with a find/replace and a change of 'average_line_length'
sub get_detail_line {
    my $self = shift;
    my ( $errno, $time, $host, $pid, $pid_error_count ) = @_;
    if ( UNIVERSAL::isa($time, 'HASH') ) {
        ( $time, $host, $pid, $pid_error_count ) = ($time->{'time'}, $time->{'host'}, $time->{'pid'}, $time->{'pid_error_count'});
    }

    ###  Scrub
    $time = &get_epoch_date($time);

    my $dir = &archive_error_dir($time, $errno);
    my $file = "$dir/detail.csv";

    my @target_vals = ($time, $host, $pid, $pid_error_count);

    ###  Check and open the file
    return unless -e $file;
    open(DETAIL, "<$file") or die "Could not open detail file $file: $!";

    my $line = &binary_search($time, \*DETAIL, (stat($file))[7],
                       { average_line_length => 4096, # who knows with storable crud in there...
                         seek_to_closest => 1,
                     }
                   );
    ###  Most of the time this line found will be the one we want...
    if ( $line ) {
        my @line_vals = &split_delim_line( ',', $line, '"');
        
        ###  If it matches every val, we got it!
        if ( ! grep { $target_vals[$_] ne $line_vals[$_] } (0 .. $#target_vals) ) {
            close DETAIL;
            return $self->read_detail_line($line);
        }
    }

    ###  But if not, then read for a while to try to find it.
    ###    but not forever, only 20 lines or until the lines
    ###    are more than 5 mins later than the time we're
    ###    looking for.
    my $skipped = 0;
    while (<DETAIL>) {
        ###  Ignore header and malformed rows
        next if ! /^(\d+)/;
        my $row_time = $1;
        my $line = $_;

        ###  Get the first part of the string and parse
        my @line_vals = &split_delim_line( ',', $line, '"');

        ###  If it matches every val, we got it!
        if ( ! grep { $target_vals[$_] ne $line_vals[$_] } (0 .. $#target_vals) ) {
            close DETAIL;
            return $self->read_detail_line($line);
        }
        ###  Otherwise, skip for a while
        else {
            ###  Since some out-of-order will always exists
            ###    because of time sync on boxes, keep going through rows
            ###    to catch stragglers for a bit (20 rows or 5 mins)
            $skipped++;
            last if $skipped == 20 || abs($time - $row_time) > 300; # more than 5 mins off time sync...
            next;
        }
    }

    close DETAIL;
    
    return;
}

sub read_detail_line {
    my $self = shift;
    my ( $line ) = @_;
    chomp( $line );
    
    my %row;
    @row{qw( time
             host
             pid
             pid_error_count
             env
             stack
             details
             )} = &split_delim_line(',', $line, '"');

    ###  Unencapsulate and thaw variables
    foreach my $key ( qw(env stack details) ) {
        $row{ $key } = &my_thaw( &unescape( $row{ $key } ) );
    }
    
    return \%row;
}

sub my_thaw {
  my $unfrozen = eval {&thaw(@_)};
  if ( $@ ) {
    &BUGSW("Error, caught die() while trying to thaw(): ". $@);
    return ['Error, caught die() while trying to thaw(): '. $@];
  }
  return $unfrozen;
}

sub get_error {
    my $self = shift;
    my ( $errno, $time, $host, $pid, $pid_error_count, $brief_line, $detail_line ) = @_;
    $brief_line = $time if UNIVERSAL::isa($time, 'HASH');

    ###  Call get_brief_line() and get_detail_line() with our params...
    $brief_line ||=  $self->get_brief_line( $errno, $time, $host, $pid, $pid_error_count);
    $detail_line ||= $self->get_detail_line($errno, $time, $host, $pid, $pid_error_count);
    
    ###  Amd create an object for it...
    Dave::ErrorSystem::Instance->new($errno, undef, undef, {%$detail_line, %$brief_line});
}

sub error_conf {
    my $self = shift;
    my ( $errno ) = @_;

    return bless({error => $errno}, "Dave::ErrorSystem::Instance")->conf;
}

#########################
###  Cache methods

sub which_errors_occurred {
    my $self = shift;
    my ( $start_day_utc, $end_day_utc ) = @_;

    ###  Get the days included in the time range
    my @days = ( map { &get_utc_date( $_->[0] ) } # keep only the day part
                 $self->get_dates_included( (&get_epoch_date($start_day_utc) + (12 * 3600)),
                                            (&get_epoch_date($end_day_utc)   + (12 * 3600))
                                            )
                 );

    ###  Assemble and uniq, and sort numerically
    return sort {$a <=> $b} &uniq( map {( $self->errors_on_day($_) )} @days );
}

sub errors_on_day {
    my $self = shift;
    my ( $day_utc ) = @_;

    ###  Scrub
    ( $day_utc ) = ( split(' ', &get_utc_date($day_utc), 3) );

    my $dir = &archive_day_dir( &get_epoch_date($day_utc)
                                + (3600 * 12) # daylight savings workaround
                                );
    return if ! -d $dir;

    ###  Read the directory
    opendir(DIR, $dir) or die "Can't opendir $dir: $!";
    my @errors = grep { -d "$dir/$_" && /^\d+$/ } readdir(DIR);
    closedir DIR;

    return @errors;
}


#########################
###  Cache methods

sub check_cache_age {
    if ( (time() - $cache_age) > (60 * 2) ) {
        &expire_cache();
        
        $cache_age = time();
    }
}

sub expire_cache {
    undef %day_count_cache;
    undef %day_lines_cache;
    undef %hour_count_cache;
    undef %hour_lines_cache;
}


1;

__END__


=head1 NAME

  Dave::ErrorSystem::Reports - A Reporting interface for the ErrorSystem

=head1 SYNOPSIS

  use Dave::ErrorSystem::Reports;

  my $reports = Dave::ErrorSystem::Reports->new();

  ###  Query error logs
  my $count =    $reports->count_errors(99,$start_datetime,$end_datetime);
  my $instance = $reports->get_error($errno,$time,$host,$pid,$pid_error_count);
  my @lines =    $reports->get_brief_lines(99,$start_datetime,$end_datetime,$limit,$offset);
  my @errors =   $reports->get_errors(99,$start_datetime,$end_datetime,$limit,$offset);

  ###  Mostly internal methods (which define cache levels)
  my $day_count =  $reports->count_day_errors(99,'2007-06-20','-','10:03:28');
  my $hour_count = $reports->count_hour_errors(99,'2007-06-20','17');

  ###  Graphing methods
  my $img_url = $reports->graph_error(99,'hourly',$start_datetime,$end_datetime,$format_prefs);

  ###  Query which error numbers occurred by date
  my @errnos = $reports->which_errors_occurred($start_day_utc,$end_day_utc);
  my @errnos = $reports->errors_on_day($day_utc);

=head1 ABSTRACT

=over 4

Still to be documented

=back

=head1 FUNCTIONS

=back

=head1 DEPENDENCIES

This module loads these libs when needed:

=over 4
