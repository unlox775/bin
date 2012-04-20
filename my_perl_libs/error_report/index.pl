#!/usr/bin/perl -w

#########################
###  error_report.i
#
# Version : $Id: index.pl,v 1.1 2009/02/03 23:43:24 dave Exp $
#
#########################

###  Pragmas
use strict;
use lib qw(..);

#########################
###  Configuration, Setup

use CGI qw( :standard &escape &escapeHTML );
use Dave::Bug qw(:common);
use Dave::Util qw(&get_epoch_date &get_utc_date &get_mdy_date);
use Dave::ErrorSystem;
use Dave::ErrorSystem::Reports;
# use Text::Highlight;

our $MOD_BASE = '/project/lib';
our $CVS_BASE = '/project';


#########################
###  Main Runtime

###  At the start of each request, clean slate...
&Dave::ErrorSystem::Reports::expire_cache;

my $reports = Dave::ErrorSystem::Reports->new;

###  Action Handler
if ( param('action') eq 'query_errors' ) {
    print header;
    &query_errors_page()
}
elsif ( param('action') eq 'view_error' ) {
    print header;
    &view_error_page()
}
elsif ( param('action') eq 'view_file' ) {
    print header;
    &view_file_page()
}
else {
    print header;
    &index_page();
}

exit 0;



#########################
###  Hacked Page handlers (use Template Toolkit asap!)

sub index_page {

    ###  Header stuff
    print '<html><head><title>Error Report</title><meta http-equiv="refresh" content="600"></head><body>';
    print '<script src="/graph_bar.js"></script>';

#     ###  Actions
#     print "<h3>Actions</h3>\n";
#     print "Go to: <a href=\"?\"     >Error_Reportect List</a>\n";
#     print "<br>Update to: <a href=\"?action=update&pname=$error_reportect_name&tag=Target\"   >Target</a>\n";
#     print "             | <a href=\"?action=update&pname=$error_reportect_name&tag=HEAD\"     >HEAD</a>\n";
#     print "             | <a href=\"?action=update&pname=$error_reportect_name&tag=TEST\"     >TEST</a>\n";
#     print "             | <a href=\"?action=update&pname=$error_reportect_name&tag=PROD_TEST\">PROD_TEST</a>\n";
#     print "             | <a href=\"?action=update&pname=$error_reportect_name&tag=PROD_SAFE\">PROD_SAFE</a>\n";
#     print "<br>Tag as:    <a href=\"?action=tag&pname=$error_reportect_name&tag=TEST\"          >TEST</a>\n";
#     print "             | <a href=\"?action=tag&pname=$error_reportect_name&tag=PROD_TEST\"     >PROD_TEST</a>\n";
#     print "             | <a href=\"?action=tag&pname=$error_reportect_name&tag=PROD_SAFE\"     >PROD_SAFE</a>\n";

    ###  Print Error List
    print "<h3>List of Errors in the Last Week</h3>\n";
    print( "<table width=100%>\n"
           . "<tr><td>&nbsp;</td><td>&nbsp;</td><td colspan=5 align=center style=\"border: solid black; border-width: 1px 1px 0px 1px\"><b>Number of Errors...</b></td><td>&nbsp;</td><td>&nbsp;</td></tr>"
           . "<tr>"
           . "<td width=10%><b>Error&nbsp;#</b></td>"
           . "<td width=15%><b>Name</b></td>"
           . "<td align=center><b>This Hour</b></td>"
           . "<td align=center><b>Prev Hour</b></td>"
           . "<td align=center><b>Today</b></td>"
           . "<td align=center><b>Yesterday</b></td>"
           . "<td align=center><b>7 day</b></td>"
           . "<td align=center><b>Last 24 hrs</b></td>"
           . "<td align=center><b>Last 30 days</b></td>"
           . "</tr>\n"
           );
    my $trunc_day_epoch = &get_epoch_date(   &get_mdy_date(time()) ); # mdy date truncates to day. hack!
    my $trunc_hour_epoch = &get_epoch_date( (&get_utc_date(time()) =~ /^(.+? \d+)/)[0] . ':00:00' );
    my $this_hour       = &get_hour( time() );
    foreach my $errno ( $reports->which_errors_occurred(($trunc_day_epoch - (6 * 86400)), $trunc_day_epoch) ) {
        my $error_conf = $reports->error_conf($errno);

        ###  This Hour
        my $this_hour_start = &get_utc_date($trunc_hour_epoch);
        my $this_hour_end   = &get_utc_date($trunc_hour_epoch + 3600);
        my $this_hour_count = $reports->count_errors($errno, $this_hour_start, $this_hour_end );

        ###  Prev Hour
        my $prev_hour_start = &get_utc_date($trunc_hour_epoch - 3600);
        my $prev_hour_end   = &get_utc_date($trunc_hour_epoch);
        my $prev_hour_count = $reports->count_errors($errno, $prev_hour_start, $prev_hour_end );

        ###  Today
        my $today_start = &get_utc_date($trunc_day_epoch);
        my $today_end   = &get_utc_date($trunc_day_epoch + 86400); # daylight savings may be a little off...
        my $today_count = $reports->count_day_errors($errno, $today_start, '-', '-' );
        
        ###  Yesterday
        my $yesterday_start = &get_utc_date($trunc_day_epoch - 86400); # daylight savings may be a little off...
        my $yesterday_end   = &get_utc_date($trunc_day_epoch);
        my $yesterday_count = $reports->count_day_errors($errno, $yesterday_start, '-', '-' );
        
        ###  7 day
        my $seven_day_start = &get_utc_date($trunc_day_epoch - (86400 * 6)); # daylight savings may be a little off...
        my $seven_day_end   = &get_utc_date($trunc_day_epoch + 86400);
        my $seven_day_count = $reports->count_errors($errno, $seven_day_start, $seven_day_end );

        ###  Last 24 hours graph
        my @last_24_hrs = map { local $_ = $_;
                                my $x = ($trunc_hour_epoch - (3600 * $_));
                                $reports->count_hour_errors($errno, &get_utc_day($x), &get_hour($x));
                              } reverse(0 .. 23);
        
        ###  Last 30 days graph
        my @last_30_days = map { local $_ = $_;
                                 my $x = ($trunc_day_epoch - (86400 * $_));
                                 $reports->count_day_errors($errno, &get_utc_day($x), '-', '-') || 0;
                               } reverse(0 .. 29);
        
        print( "<tr>"
#               . "<td><a href=\"?action=&file=". escape($errno) ."\">$errno</a></td>"
               . "<td>$errno</td>\n"
               . "<td>". ($error_conf->{'internal_name'} || 'Unnamed Error') ."</td>\n"
               . "<td align=center><a href=\"?action=query_errors&errno=$errno&range_start=". escape($this_hour_start) ."&range_end=". escape($this_hour_end) ."\">$this_hour_count</a></td>\n"
               . "<td align=center><a href=\"?action=query_errors&errno=$errno&range_start=". escape($prev_hour_start) ."&range_end=". escape($prev_hour_end) ."\">$prev_hour_count</a></td>\n"
               . "<td align=center><a href=\"?action=query_errors&errno=$errno&range_start=". escape($today_start    ) ."&range_end=". escape($today_end    ) ."\">$today_count</a></td>\n"
               . "<td align=center><a href=\"?action=query_errors&errno=$errno&range_start=". escape($yesterday_start) ."&range_end=". escape($yesterday_end) ."\">$yesterday_count</a></td>\n"
               . "<td align=center><a href=\"?action=query_errors&errno=$errno&range_start=". escape($seven_day_start) ."&range_end=". escape($seven_day_end) ."\">$seven_day_count</a></td>\n"
               . "<td align=center><img src=\"/graph.i?width=150&height=50&dataset=". escape(join(',',@last_24_hrs))   ."\" width=150 height=50 border=0></td>\n"
               . "<td align=center><img src=\"/graph.i?width=150&height=50&dataset=". escape(join(',',@last_30_days))  ."\" width=150 height=50 border=0></td>\n"
###  The old Javascript lib way by Paul Seamons (didn't work in IE)
#                . "<td align=center>
#                     <script>
#                     graph_bar({
#                       div_id: '30_day',
#                       border: '1px solid black',
#                       padding: '2px',
#                       width: 150,
#                       height: 50,
#                       data : [". join(',',@last_30_days) ."]
#                     });
#                     </script>
#                   </td>\n"
#                . "</tr>\n"
               );
    }
    print "</table>\n";

}

sub get_utc_day { (split(' ', &get_utc_date( $_[0] )))[0]; }
sub get_hour  { ( localtime(&get_epoch_date( $_[0] )) )[2]; }

sub query_errors_page {
    my $errno = param('errno');
    my $range_start = param('range_start');
    my $range_end =   param('range_end');

    my $error_conf = $reports->error_conf($errno);

    ###  Header stuff
    print '<html><head><title>Error Query</title></head><body>';

    ###  Print Error List
    print "<h3>Error $errno, \"". ($error_conf->{'internal_name'} || 'Unnamed Error') ."\" from $range_start to $range_end</h3>\n";
    print "Go to: <a href=\"?\"     >Main Error List</a><br>\n";
    print( "<table width=100%>\n"
           . "<tr>"
           . "<td><b>Date</b></td>"
           . "<td align=center><b>Host</b></td>"
           . "<td align=center><b>PID</b></td>"
           . "<td align=center><b>Script</b></td>"
           . "<td align=center><b>Who/What</b></td>"
           . "</tr>\n"
           );
    foreach my $error ( $reports->get_brief_lines($errno, $range_start, $range_end) ) {
        my $utc_time = &get_utc_date( $error->{'time'} );

        print( "<tr>"
               . "<td><a href=\"?action=view_error&errno=$errno&time=". $error->{'time'} ."&host=". escape($error->{'host'}) ."&pid=". $error->{'pid'} ."&pid_error_count=". $error->{'pid_error_count'} ."\">$utc_time</a></td>"
               . "<td align=center>". $error->{'host'} ."</td>"
               . "<td align=center>". $error->{'pid'} ."</td>"
               . "<td align=center>". $error->{'script'} ."</td>"
               . "<td align=center>". $error->{'objid'} ."</td>"
               . "</tr>\n"
               );
    }
    print "</table>\n";

}

sub view_error_page {
    my $errno = param('errno');
    my $time = param('time');
    my $host = param('host');
    my $pid = param('pid');
    my $pid_error_count = param('pid_error_count');

    my $error_conf = $reports->error_conf($errno);

    ###  Get the error
    my $error = $reports->get_error($errno, $time, $host, $pid, $pid_error_count);

    ###  Header stuff
    print "<html><head><title>Error $errno Detail: ". &get_utc_date($time) ."</title></head><body>";

    ###  Print Error List
    print "<h3>Error $errno, \"". ($error_conf->{'internal_name'} || 'Unnamed Error') ."\" on ". &get_utc_date($time) ."</h3>\n";
    print "Go to: <a href=\"?\"     >Main Error List</a> | <a href=\"javascript:history.back()\">Go Back</a><br>\n";

    print "<h3>This is what the user should have seen:</h3>\n<hr>\n";
    print $error->error_report_content("text/html","user");

    ###  Print the full details
    print "<hr><br><br><h3>This is the full detail:</h3>\n<hr>\n";
    my $error_report_content =  $error->error_report_content("text/html","admin");

    ###  Make links out of stack trace
    $error_report_content =~ s/(&nbsp;called&nbsp;at&nbsp;)(([^\&\;]+)&nbsp;line&nbsp;(\d+))/$1 . &file_line_tag($2, $3, $4)/eg;
    ###  Hilite,,,,
    $error_report_content =~ s/(my_sig_die)(&nbsp;called&nbsp;at)/<b>$1<\/b>$2/g;

    print $error_report_content;

}

sub file_line_tag {
    my ($stuff, $file, $line) = @_;

    if ( -e "$MOD_BASE/$file" ) {
        return '<a href="?action=view_file&file='. escape($file) .'#'. $line .'">'. $stuff .'</a>';
    }
    elsif ( -e $file
            && $file =~ m@^$CVS_BASE/(.+)$@
            ) {
        $file = $1;
        return '<a href="?action=view_file&root=var_dub&file='. escape($file) .'#'. $line .'">'. $stuff .'</a>';
    }

    return $stuff;
}

sub view_file_page {
    my $file = param('file');
    my $root = $MOD_BASE;
    $root = '$CVS_BASE' if param('root') eq 'var_dub';

    die "Please don't hack!" if $file =~ /\.\./;

    ###  Header stuff
    print "<html><head><title>View File: $file</title></head><body>";

    print "<h3>File content of $root/$file</h3>\n";
    print "Go to: <a href=\"?\">Main Error List</a> | <a href=\"javascript:history.back()\">Go Back</a><br>\n";

    my $code = `cat $root/$file`;

    ###  Print Stylesheet
    print "
<style>
.line_num { font-size: 80% }

/* //// Perl Syntax //// */
.comment { color: red }
.string  { color: green }
.number  { color: black }
.key1    { color: blue }
.key2    { color: blue }
.key3    { color: black }
/* .key4    { color:  } */
/* .key5    { color:  } */
/* .key6    { color:  } */
/* .key7    { color:  } */
/* .key8    { color:  } */
</style>
";

    ###  Escape code and hilight Perl syntax
    my $th = new Text::Highlight(wrapper => "<pre>%s</pre>\n");
    my $hilite_code = $th->highlight('Perl', $code);

    my $i = 1;
    $hilite_code =~ s/^(<pre>)?(.?)/$1 . '<span class="line_num"><a name="'. $i .'">'. sprintf("%5d", $i++) . '<\/a><\/span>&nbsp;&nbsp;' . $2/egm;

    print $hilite_code;

    ###  Print Error List

}
