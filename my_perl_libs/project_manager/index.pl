#!/usr/bin/perl -w

#########################
###  Project Manager
#
# Version : $Id: index.pl,v 1.1 2010/11/17 23:34:19 dave Exp $
#
#########################

###  Pragmas
use strict;

#########################
###  Configuration, Setup

use CGI qw( :standard &escape );
use Bug qw(:common);
use Global qw(:sys_context $env_mode);
use Util qw(&uniq &split_delim_line &get_sql_date &get_mdy_date &join_delim_line );
use Storable qw(&nfreeze &thaw);  $Storable::forgive_me = 1;  $Storable::accept_future_minor = 1;
use CGI::Util qw( &escape &unescape );
use LWP::UserAgent;

our $DAVE_SAFE_BASE = '/sandbox/logs';

###  Debugging / timing flags
$DEBUG::DAVE_DAVE_TIMERS = 0;

###  Globals
my $SYSTEM_PROJECT_BASE = '/sandbox/projects/';
my $CVS_CMD =     'cd ' .$ENV{DAVE_CVS_BASE}. ';    export CVS_RSH=ssh; sudo -u project /usr/bin/cvs -d ":ext:project@dev.dave.org:/sandbox/cvsroot"';
$CVS_CMD =        'cd ' .$ENV{DAVE_CVS_BASE}. ';    export CVS_RSH=ssh; sudo -u project /usr/bin/cvs -d "/sandbox/cvsroot"'                          if -d "/sandbox/cvsroot";
my $CVS_CMD_4CO = 'cd ' .$ENV{DAVE_CVS_BASE}. '/..; export CVS_RSH=ssh; sudo -u project /usr/bin/cvs -d ":ext:project@dev.dave.org:/sandbox/cvsroot"';
$CVS_CMD_4CO    = 'cd ' .$ENV{DAVE_CVS_BASE}. '/..; export CVS_RSH=ssh; sudo -u project /usr/bin/cvs -d "/sandbox/cvsroot"'                          if -d "/sandbox/cvsroot";

my %cvs_cache = ();
my $MAX_BATCH_SIZE = 500;
my $MAX_BATCH_STRING_SIZE = 4096;

#########################
###  Main Runtime

###  See if we are doing a read-only user
our $READ_ONLY_MODE = ( grep { $_ eq $ENV{REMOTE_USER} } qw(guest pmgr_tunnel) ) ? 1 : 0;

&reset_timers() if $DEBUG::DAVE_DAVE_TIMERS;

###  Action Handler
if ( param('action') && param('action') eq 'view_project' ) {
    print header;
    print &style_sheet;
    &view_project_page()
}
elsif ( param('action') eq 'update' ) {
    die "Permission Denied" if $READ_ONLY_MODE;

    my $project_name = param('pname');
    my $tag = param('tag');
    if (! $tag ) {
        print header;
        print &style_sheet;
        &view_project_page()
    }

    die "Please don't hack..." if $tag =~ /[^\w\_\-\.]/;

    ###  Target mode
    my $do_file_tag_update = 0;
    my $file_tags;
    if ( $tag eq 'Target' ) {
        $do_file_tag_update = 1;
        $tag = 'HEAD';
        ###  Read in the file tags CSV
        $file_tags = &get_file_tags( $project_name );
    }

    ###  Prepare Update/Checkouts (to Tag, Head or specific revision)
    my @update_cmd =   ( qw(update -r ), $tag );
    my @checkout_cmd = ( qw(co     -r ), $tag );
    if ( $tag eq 'HEAD' ) {
        @update_cmd =    qw(update -PAd );
        @checkout_cmd =  qw(co     -rHEAD );
    }
    my @tag_files;
    my ( $do_update, $do_checkout ) = (0,0);
    foreach my $file ( &get_affected_files($project_name) ) {
        ( my $parent_dir = $file) =~ s@/[^/]+$@@;
        ###  Remove files with specific tags from the main update
        if ( $do_file_tag_update && $file_tags->{ $file } ) {
            push @tag_files, $file;
            next;
        }
        ###  Do files that don't exist in a "checkout" batch command
        elsif ( ! -d "$ENV{DAVE_CVS_BASE}/$parent_dir" ) {
            my $my_file = $file;
            $my_file = "dave/$file" unless $file =~ /^dave/;
            push @checkout_cmd, '"'. $my_file .'"';
            $do_checkout ||= 1;
            next;
        }
        ###  Normal batch update of existing files
        push @update_cmd, '"'. $file .'"';
        $do_update ||= 1;
    }

    ###  Run the UPDATE command (if any)
    my $cmd = '';
    my $command_output = '';
    if ( $do_update ) {
        my $update_cmd = "$CVS_CMD ". join(' ', @update_cmd);
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        &log_cvs_action($update_cmd);
        $command_output .= `$update_cmd 2>&1 | cat -`;
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        $cmd .= "\n".( length($cmd) ? ' ; ' : ''). $update_cmd;
    }

    ###  Run the CHECKOUT command (if any)
    if ( $do_checkout ) {
        my $checkout_cmd = "$CVS_CMD_4CO ". join(' ', @checkout_cmd);
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        &log_cvs_action($checkout_cmd);
        $command_output .= `$checkout_cmd 2>&1 | cat -`;
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        $cmd .= "\n".( length($cmd) ? ' ; ' : ''). $checkout_cmd;
    }

    ###  File tag update
    if ( $do_file_tag_update ) {
        foreach my $file ( @tag_files ) {
            my @tag_cmd = ( qw(update -r ), $file_tags->{ $file }, '"'. $file .'"' );
            my $tag_cmd = "$CVS_CMD ". join(' ', @tag_cmd);
            START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
            &log_cvs_action($tag_cmd);
            $command_output .= "\n--\n". `$tag_cmd 2>&1 | cat -`;
            END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
            $cmd .= ( length($cmd) ? ' ; ' : ''). $tag_cmd;
        }
    }

    $command_output = '</xmp><i>No output</i>'if ! $command_output;

    ###  If the Bounce URL is too long for HTTP protocol maximum then just print out the stuff...
    my $bounce_url = "?action=view_project&pid=$$&pname=". &escape($project_name) ."&cmd=". &escape($cmd) ."&command_output=". &escape($command_output);
    if ( length( $bounce_url ) > 2000 ) {
        print header;
        print &style_sheet;
        print "<font color=red><h3>Command Output (Too Large for redirect)</h3>\n<p><a href=\"javascript:history.back()\">Go Back</a></p>\n<hr>\n";
        print "<xmp>> $cmd\n\n$command_output\n</xmp>\n\n";
        print "</font>\n\n";
    }
    ###  Else, just bounce
    else {
        print "Location: $bounce_url\n\n";
    }
}
elsif ( param('action') eq 'tag' ) {
    die "Permission Denied" if $READ_ONLY_MODE;

    my $project_name = param('pname');
    my $tag = param('tag');
    if (! $tag ) {
        print header;
        print &style_sheet;
        &view_project_page()
    }

    die "Please don't hack..." if $tag =~ /[^\w\_\-\.]/;

    ###  Prepare Update/Remove_Tags (to Tag, Head or specific revision)
    my @tag_cmd =   ( qw(tag -F), $tag );
    my @remove_tag_cmd = ( qw(tag -d), $tag );
    my ( $do_tag, $do_remove_tag ) = (0,0);
    foreach my $file ( &get_affected_files($project_name) ) {
        ( my $parent_dir = $file) =~ s@/[^/]+$@@;
        ###  Do files that don't exist in a "remove_tag" batch command
        if ( ! -d "$ENV{DAVE_CVS_BASE}/$parent_dir" || ! -f "$ENV{DAVE_CVS_BASE}/$file" ) {
            push @remove_tag_cmd, '"'. $file .'"';
            $do_remove_tag ||= 1;
            next;
        }
        ###  Normal batch tag of existing files
        else {
            push @tag_cmd, '"'. $file .'"';
            $do_tag ||= 1;
        }
    }

    ###  Run the TAG command (if any)
    my $cmd = '';
    my $command_output = '';
    if ( $do_tag ) {
        my $tag_cmd = "$CVS_CMD ". join(' ', @tag_cmd);
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        &log_cvs_action($tag_cmd);
        $command_output .= `$tag_cmd 2>&1 | cat -`;
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        $cmd .= "\n".( length($cmd) ? ' ; ' : ''). $tag_cmd;
    }

    ###  Run the REMOVE_TAG command (if any)
    if ( $do_remove_tag ) {
        my $remove_tag_cmd = "$CVS_CMD ". join(' ', @remove_tag_cmd);
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        &log_cvs_action($remove_tag_cmd);
        $command_output .= `$remove_tag_cmd 2>&1 | cat -`;
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        $cmd .= "\n".( length($cmd) ? ' ; ' : ''). $remove_tag_cmd;
    }

    $command_output = '</xmp><i>No output</i>'if ! $command_output;

    ###  If the Bounce URL is too long for HTTP protocol maximum then just print out the stuff...
    my $bounce_url = "?action=view_project&pid=$$&pname=". &escape($project_name) ."&cmd=". &escape($cmd) ."&command_output=". &escape($command_output);
    if ( length( $bounce_url ) > 2000 ) {
        print header;
        print &style_sheet;
        print "<font color=red><h3>Command Output (Too Large for redirect)</h3>\n<p><a href=\"javascript:history.back()\">Go Back</a></p>\n<hr>\n";
        print "<xmp>> $cmd\n\n$command_output\n</xmp>\n\n";
        print "</font>\n\n";
    }
    ###  Else, just bounce
    else {
        print "Location: $bounce_url\n\n";
    }
}
elsif ( param('action') eq 'part_log' ) {
    print header;
    print &style_sheet;
    &part_log_page();
}
elsif ( param('action') eq 'full_log' ) {
    print header;
    print &style_sheet;
    &full_log_page();
}
elsif ( param('action') eq 'diff' ) {
    print header;
    print &style_sheet;
    &diff_page();
}
elsif ( param('action') eq 'remote_call' ) {
    print header;
    my $remote_call = param('remote_call');
    my $params = param('params');
    my $wantarray = param('wantarray');

    die "Please don't hack..." if $remote_call !~ /^(get_project_ls|get_project_stat|project_file_exists|get_project_file|get_projects)$/s;

    $params = &thaw(&unescape($params));

    my $send_obj;
    no strict 'refs';
    if ( $wantarray ) { $send_obj =          [ &{ $remote_call }( @$params ) ]; }
    else              { $send_obj =  \ scalar( &{ $remote_call }( @$params ) ); }
    use strict 'refs';

    print "|=====|". &escape(&nfreeze($send_obj)) ."|=====|";
}
else {
    print header;
    print &style_sheet;
    &index_page();
}

&report_timers( \*STDOUT ) if $DEBUG::DAVE_DAVE_TIMERS;

# exit 0;



#########################
###  Hacked Page handlers (use Template Toolkit asap!)

sub index_page {

    ###  List of projects
    print "<h3>List of Projects</h3>\n";
    print( "<table width=100%>\n"
            . "<tr>"
            . "<th width=30% align=left>Name</th>"
            . "<th align=center>Created by</th>"
            . "<th align=center>Last Modified</th>"
            . "<th align=center>Number of files</th>"
            . "<th align=center>Summary File</th>"
            . "<th align=left>Actions</th>"
            . "</tr>\n"
            );
    my @projects;
    foreach my $project ( &get_projects ) {

        ###  Get more info from ls
        my @ls = (-d $SYSTEM_PROJECT_BASE) ? (split(/\s+/,&get_project_ls($project))) : ();
#        my @stat = (-d $SYSTEM_PROJECT_BASE) ? (&get_project_stat($project)) : ();
        my @stat = &get_project_stat($project);

        my %project = ( name                => $project,
                        creator             => ($ls[2] || '-'),
                        group               => ($ls[3] || '-'),
                        mod_time            => ($stat[9] || 0),
                        mod_time_display    => (@stat ? &get_mdy_date($stat[9])  : '-'),
                        has_summary         => ( (-d $SYSTEM_PROJECT_BASE)
                                                 ? ( &project_file_exists( $project, "summary.txt" ) ? "YES" : "")
                                                 : '-'
                                                 ),
                        aff_file_count      => scalar(&get_affected_files($project)),
                      );

        push @projects, \%project;
    }

    foreach my $project ( sort {$b->{mod_time} cmp $a->{mod_time}} @projects ) {
#        print "<tr><td></li>\n";
        print( "<tr>"
                . "<td><a href=\"?action=view_project&pname=". escape($project->{name}) ."\">$project->{name}</a></td>"
                . "<td align=center>$project->{creator}</td>"
                . "<td align=center>$project->{mod_time_display}</td>"
                . "<td align=center>$project->{aff_file_count}</td>"
                . "<td align=center>$project->{has_summary}</td>"
                . "<td><a href=\"?action=view_project&pname=". escape($project->{name}) ."\">View</a> | <a href=\"javascript:alert('Not supported yet...  Sorry.')\">Archive</a></td>"
                . "</tr>\n"
                );
    }
    print "</table>\n";

    print "</ul>\n\n";
}

sub view_project_page {
    my ( $cmd, $command_output ) = ( param('cmd'), param('command_output') );
    my $project_name = param('pname');

    ###  Command output
    if ( $cmd ) {
        print "<font color=red><h3>Command Output</h3>\n";
        print "<xmp>> $cmd\n\n$command_output\n</xmp>\n\n";
        print "</font>\n\n";
        print "<br><br><a href=\"?action=view_project&pname=$project_name\" style=\"font-size:70%\">&lt;&lt;&lt; Click here to hide Command output &gt;&gt;&gt;</a><br>\n\n";
    }

    print "<h2>Project: $project_name</h2>\n\n";

    ###  Actions
    if ( $READ_ONLY_MODE ) {
        print <<"ENDHTML";
<table width="100%" border=0 cellspacing=0 cellpadding=0>
<tr>
  <td align="left" valign="top">
    <h3>Actions</h3>
    <i>You must log in as a privileged user to perform CVS actions.  Sorry.</i>
  </td>
  <td align="left" valign="top">
ENDHTML
    }
    else {
        print <<"ENDHTML";
<table width="100%" border=0 cellspacing=0 cellpadding=0>
<tr>
  <td align="left" valign="top">
    <h3>Actions</h3>
    Update to: <a href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=Target')\"   >Target</a>
                 | <a href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=HEAD')\"     >HEAD</a>
                 | <a href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=PROD_TEST')\">PROD_TEST</a>
                 | <a href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=PROD_SAFE')\">PROD_SAFE</a>
    <br>Tag as:    <a href=\"javascript: confirmAction('TAG',   '?action=tag&pname=$project_name&tag=PROD_TEST')\"     >PROD_TEST</a>
                 | <a href=\"javascript: confirmAction('TAG',   '?action=tag&pname=$project_name&tag=PROD_SAFE')\"     >PROD_SAFE</a>
  </td>
  <td align="left" valign="top">
ENDHTML
    }

    ###  Rollout process for different phases
    if ( onAlpha() ) {
        print <<"ENDHTML";
            <h3>Rollout Process</h3>
            When you are ready, review the below file list to make sure:
            <ol>
            <li>All needed code and display logic files are here</li>
            <li>Any needed database patch scripts are listed (if any)</li>
            <li>In the "Current Status" column everything is "Up-to-date"</li>
            <li>In the "Changes by" column, they are all your changes</li>
            </ol>
            Then, tell QA and they will continue in the <a href="https://admin.beta.dave.org/project_manager/?action=view_project&pname=$project_name">QA Staging Area</a>
ENDHTML
    }
    elsif ( onBeta() ) {
        if ( $READ_ONLY_MODE ) {
            print <<"ENDHTML";
            <h3>Rollout Process - QA STAGING PHASE</h3>
            <b>Step 1</b>: Once developer is ready, Update to Target<br>
            <b>Step 2</b>: <i> -- Perform QA testing -- </i><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 2a</b>: For minor updates, Update to Target again<br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 2b</b>: If major problems, Roll back to PROD_TEST<br>
            <b>Step 3</b>: When everything checks out, Tag as PROD_TEST<br>
            <br>
            Then, <a href="https://admin.dave.org/project_manager/?action=view_project&pname=$project_name">Switch to Live Production Area</a>
ENDHTML
        }
        else {
            print <<"ENDHTML";
            <h3>Rollout Process - QA STAGING PHASE</h3>
            <b>Step 1</b>: Once developer is ready, <a href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=Target')\"   >Update to Target</a><br>
            <b>Step 2</b>: <i> -- Perform QA testing -- </i><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 2a</b>: For minor updates, <a      href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=Target')\"   >Update to Target again</a><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 2b</b>: If major problems, <a      href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=PROD_TEST')\">Roll back to PROD_TEST</a><br>
            <b>Step 3</b>: When everything checks out, <a href=\"javascript: confirmAction('TAG',   '?action=tag&pname=$project_name&tag=PROD_TEST')\"     >Tag as PROD_TEST</a><br>
            <br>
            Then, <a href="https://admin.dave.org/project_manager/?action=view_project&pname=$project_name">Switch to Live Production Area</a>
ENDHTML
        }            
    }
    elsif ( onLive() ) {
        if ( $READ_ONLY_MODE ) {
            print <<"ENDHTML";
            <h3>Rollout Process - LIVE PRODUCTION PHASE</h3>
            Check that in the "Current Status" column there are <b><u>no <b>"Locally Modified"</b> or <b>"Needs Merge"</b> statuses</u></b>!!
            <br>
            <b>Step 4</b>: Set set a safe rollback point, Tag as PROD_SAFE<br>
            <b>Step 5</b>: Then to roll it all out, Update to PROD_TEST<br>
            <b>Step 6</b>: <i> -- Perform QA testing -- </i><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 6a</b>: If any problems, Roll back to PROD_SAFE<br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 6b</b>: While fixes are made, Re-tag to PROD_TEST<br>
            Then, go back to the <a href="https://admin.beta.dave.org/project_manager/?action=view_project&pname=$project_name">QA Staging Area</a> and continue with <b>Step 1</b> or <b>Step 2</b>.
ENDHTML
        }
        else {
            print <<"ENDHTML";
            <h3>Rollout Process - LIVE PRODUCTION PHASE</h3>
            Check that in the "Current Status" column there are <b><u>no <b>"Locally Modified"</b> or <b>"Needs Merge"</b> statuses</u></b>!!
            <br>
            <b>Step 4</b>: Set set a safe rollback point, <a href=\"javascript: confirmAction('TAG',   '?action=tag&pname=$project_name&tag=PROD_SAFE')\"     >Tag as PROD_SAFE</a><br>
            <b>Step 5</b>: Then to roll it all out, <a      href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=PROD_TEST')\">Update to PROD_TEST</a><br>
            <b>Step 6</b>: <i> -- Perform QA testing -- </i><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 6a</b>: If any problems, <a      href=\"javascript: confirmAction('UPDATE','?action=update&pname=$project_name&tag=PROD_SAFE')\">Roll back to PROD_SAFE</a><br>
            &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;<b>Step 6b</b>: While fixes are made, <a href=\"javascript: confirmAction('TAG','?action=tag&pname=$project_name&tag=PROD_TEST')\">Re-tag to PROD_TEST</a><br>
            Then, go back to the <a href="https://admin.beta.dave.org/project_manager/?action=view_project&pname=$project_name">QA Staging Area</a> and continue with <b>Step 1</b> or <b>Step 2</b>.
ENDHTML
        }
    }

    ###  End table
    print <<"ENDHTML";
  </td>
</table>
ENDHTML

    ###  Read in the file tags CSV
    my $file_tags = &get_file_tags( $project_name );

    ###  Print File details
    ###    Hack for now... When we rewrite, use open!!
    print "<h3>Affected Files</h3>\n";
    print( "<table width=100%>\n"
            . "<tr><td>&nbsp;</td><td colspan=5 align=center style=\"border: solid black; border-width: 1px 1px 0px 1px\"><b>Revisions</b></td><td>&nbsp;</td><td>&nbsp;</td></tr>"
            . "<tr>"
            . "<td width=30%><b>File Name</b></td>"
            . "<td align=center><b>Current Status</b></td>"
            . "<td align=center><b>Target</b></td>"
            . "<td align=center><b>HEAD</b></td>"
            . "<td align=center><b>PROD_TEST</b></td>"
            . "<td align=center><b>PROD_SAFE</b></td>"
            . "<td align=center><b>Changes By</b></td>"
            . "<td align=left><b>Action</b></td>"
            . "</tr>\n"
            );
    my @files = &get_affected_files($project_name);
    &cache_cvs_logs( @files );
    &cache_cvs_statuses( @files );
    my $locally_modified = 0;
    foreach my $file ( @files ) {

        my ($cur_vers, $head_vers, $prod_test_vers, $prod_safe_vers) = ('','','','');
        my $target_vers = '->';

        ###  Get Current Version
        my ($status, $cur_rev);
        if ( ! -e "$ENV{DAVE_CVS_BASE}/$file" ) {
            $cur_vers = '<i>-- n/a --</i>';
        } elsif ( -d "$ENV{DAVE_CVS_BASE}/$file" ) {
            $cur_vers = '<i>Directory</i>';
        } else {
            my $cstat = &get_cvs_status($file);;
            if ( $cstat =~ /Status:\s*([^\n]+)/ ) {
                $status = $1;
                if ( $cstat =~ /Working revision:\s*(\S+)/ ) {
                    $cur_rev = $1;
                } else {
                    $cur_vers = "<i>malformed cvs status</i><!--$cstat-->";
                }

                ###  Add a diff link if Locally Modified
                if ( $status eq 'Locally Modified'
                     || $status eq 'Needs Merge'
                     || $status eq 'File had conflicts on merge'
                   ) {
                    $cur_vers = "<a href=\"?action=diff&from_rev=$cur_rev&to_rev=local&file=". escape($file) ."\">$status</a>, $cur_rev";
                    $locally_modified = 1;
                }
                else { $cur_vers = "$status, $cur_rev"; }
            } else {
                $cur_vers = "<i>exists, but not in CVS!</i><!--$cstat-->";
            }
        }

        my ($head_rev, $target_rev, $prod_test_rev, $prod_safe_rev);
        my $clog = &get_cvs_log($file);

        ###  Get PROD_SAFE Version
        if ( $clog =~ /^\tPROD_SAFE:\s*(\S+)/m ) {
            $prod_safe_rev = $1;
            if ( $prod_safe_rev ne $cur_rev ) {
                $prod_safe_vers = "<b><font color=red>$prod_safe_rev</font></b>";
            }
            else { $prod_safe_vers = $prod_safe_rev; }
        }
        else { $prod_safe_vers = '<i>-- n/a --</i>'; }

        ###  Get PROD_TEST Version
        if ( $clog =~ /^\tPROD_TEST:\s*(\S+)/m ) {
            $prod_test_rev = $1;
            if ( $prod_test_rev ne $cur_rev ) {
                $prod_test_vers = "<b><font color=red>$prod_test_rev</font></b>";
            }
            else { $prod_test_vers = $prod_test_rev; }
        }
        else { $prod_test_vers = '<i>-- n/a --</i>'; }

        ###  Get HEAD Version
        if ( $clog =~ /^head:\s*(\S+)/m ) {
            $head_rev = $1;
            if ( $head_rev ne $cur_rev
                 && ( ! $file_tags->{ $file }
                      || $file_tags->{ $file } eq $cur_rev
                      )
                 ) {
                $head_vers = "<b><font color=red>$head_rev</font></b>";
            }
            else { $head_vers = $head_rev; }
            
            ###  Set Target version if it's there
            if ( $file_tags->{ $file } ) {
                if ( $file_tags->{ $file } ne $cur_rev ) {
                    $target_vers = "<b><font color=red>". $file_tags->{ $file } ."</font></b>";
                }
                else { $target_vers = $file_tags->{ $file }; }
                
                $target_rev = $file_tags->{ $file };
            }
            else { $target_rev = $head_rev }
        } elsif ( $clog =~ /nothing known about|no such directory/ ) {
            $head_vers = "<i>Not in CVS</i><!--$clog-->";
        } else {
            $head_vers = "<i>malformed cvs log</i><!--$clog-->";
        }

        ###  Changes by
        my $changes_by = '<i>n/a</i>';
        my $c_by_rev = onLive() ? $cur_rev : $prod_test_rev;
        if ( $c_by_rev && $target_rev ) {
            my @entries = map { &get_log_entry( $clog, $_ ) } ( reverse &get_revs_in_diff($c_by_rev, $target_rev) );
            my @names = &uniq( map { $_ = (/author:\s+(\w+);/)[0] } @entries );

            ###  Find regressions!
            $changes_by = undef;
            if ( @entries == 0 && $c_by_rev ne $target_rev ) {
                my @reverse_revs = &get_revs_in_diff($target_rev, $c_by_rev);
                if ( @reverse_revs > 0 ) {
                    $changes_by = '<font color=red><b><i>-'. @reverse_revs .' rev'. (@reverse_revs == 1 ? '' : 's'). '!!!</i></b></font>';
                }
            }
            $changes_by ||= @entries .' rev'. (@entries == 1 ? '' : 's') . (@names ? (', '. join(', ',@names)) : '');
        }

        ###  Actions
        my $actions = '<i>n/a</i>';
        if ( $c_by_rev && $target_rev ) {
            $actions = ( "<a         href=\"?action=part_log&from_rev=$c_by_rev&to_rev=$target_rev&file=". escape($file) ."\">Log</a>"
                         . "&nbsp;<a     href=\"?action=diff&from_rev=$c_by_rev&to_rev=$target_rev&file=". escape($file) ."\">Diff</a>"
                         );
        }

        print( "<tr>"
                . "<td><a href=\"?action=full_log&file=". escape($file) ."\">$file</a></td>"
                . "<td align=center>$cur_vers</td>"
                . "<td align=center>$target_vers</td>"
                . "<td align=center>$head_vers</td>"
                . "<td align=center>$prod_test_vers</td>"
                . "<td align=center>$prod_safe_vers</td>"
                . "<td align=center>$changes_by</td>"
                . "<td align=left>$actions</td>"
                . "</tr>\n"
                );
    }
    print "</table>\n";

    ###  If there were any locally modified files, then
    ###    DISABLE Updating until they are fixed
    if ( $locally_modified ) {
        print <<"ENDHTML";
<script>
disable_actions = 1;
</script>
ENDHTML
    }

    ###  Summary File
    print "<h3>Summary</h3>\n<pre>";
    if ( &project_file_exists( $project_name, "summary.txt" ) ) {
        print &get_project_file( $project_name, "summary.txt" );
    } else {
        print "-- No project summary entered --\n\n";
    }
    print "</pre>\n\n";

}

sub part_log_page {
    my $file     = param('file');
    my $from_rev = param('from_rev');
    my $to_rev   = param('to_rev');

    die "Please don't hack..." if $file =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@ || $from_rev =~ /[^\d\.]+/ || $to_rev =~ /[^\d\.]+/;

    print "<h2>cvs log entries of $file from -r $from_rev to -r $to_rev</h2>\n<p><a href=\"javascript:history.back()\">Go Back</a></p>\n<hr>\n\n";

#    ###  TESTING
#    bug [&get_revs_in_diff(qw(1.15 1.17))];
#    bug [&get_revs_in_diff(qw(1.17 1.15))];
#    bug [&get_revs_in_diff(qw(1.15 1.12.2.12))];
#    bug [&get_revs_in_diff(qw(1.15 1.17.2.12))];
#    bug [&get_revs_in_diff(qw(1.12.2.12 1.16))];
#    bug [&get_revs_in_diff(qw(1.12.2.12 1.10))];
#    bug [&get_revs_in_diff(qw(1.12.2.12 1.10.11.17))];
#    bug [&get_revs_in_diff(qw(1.10.2.12 1.12.11.17))];

    ###  Get the partial log
    my $clog = &get_cvs_log($file);
    my @entries = map { [$_, &get_log_entry( $clog, $_ )] } ( reverse &get_revs_in_diff($from_rev, $to_rev) );

    ###  Turn the revision labels into links
    foreach my $entry ( @entries ) {
        $entry->[1] =~ s/^(revision [\d\.]+)\s+/&revision_link($file, $entry->[0], $1, undef, '<xmp>', "<\/xmp>", $&)/esg;
    }

    print "<xmp>\n". join("\n----------------------------", map {$_->[1]} @entries) ."\n</xmp>";
}

sub revision_link {
    my ( $file, $rev, $str, $project_name, $s_esc, $e_esc, $whole_match) = @_;
    return $whole_match if $rev eq '1.1';
    $s_esc ||= '';
    $e_esc ||= '';

    my $tag = "$e_esc<a href=\"?action=diff&from_rev=". &get_prev_rev($rev) ."&to_rev=". $rev ."&file=". escape($file) ."\">$s_esc";
    return $tag . $str ."$e_esc<\/a>$s_esc"
}

sub full_log_page {
    my $file     = param('file');

    die "Please don't hack..." if $file =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;

    print "<h2>cvs log of $file</h2>\n<p><a href=\"javascript:history.back()\">Go Back</a></p>\n<hr>\n\n";

    ###  Get the partial log
    my $clog = &get_cvs_log($file);
    $clog =~ s/\r?\n(revision ([\d\.]+))\r?\n/&revision_link($file, $2, $1, undef, '<xmp>', "<\/xmp>", $&)/emg;
    print "<xmp>\n$clog\n</xmp>";
}

sub diff_page {
    my $file     = param('file');
    my $from_rev = param('from_rev');
    my $to_rev   = param('to_rev');

    die "Please don't hack..." if $file =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@ || $from_rev =~ /[^\d\.]+/ || $to_rev !~ /^([\d\.]+|local)$/;

    print "<h2>cvs diff of $file from -r $from_rev to -r $to_rev</h2>\n<p><a href=\"javascript:history.back()\">Go Back</a></p>\n<hr>\n\n";

    ###  Get the partial diff
    my $to_rev_clause = ($to_rev eq 'local' ? "" : "-r $to_rev");
    START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
    my $cdiff = `$CVS_CMD diff -bc -r $from_rev $to_rev_clause "$file" 2>&1 | cat`;
    END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;

    print "<xmp>\n$cdiff\n</xmp>";
}

#########################
###  CVS batch caching (for speed)

sub get_cvs_log {
    my ( $file ) = @_;

    ###  If not cached, get it and cache
    if ( ! $cvs_cache{log}{$file} ) {
        ( my $parent_dir = $file) =~ s@/[^/]+$@@;
        if ( -d "$ENV{DAVE_CVS_BASE}/$parent_dir" ) {
            START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
            $cvs_cache{log}{$file} = `$CVS_CMD log "$file" 2>&1 | cat`;
            END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        }
        else {
            $cvs_cache{log}{$file} = "cvs [status aborted]: no such directory `$parent_dir'";
        }
    }

    return $cvs_cache{log}{$file};
}

sub cache_cvs_logs {
    my ( @files ) = @_;

    my $cache_key = 'log';

    ###  Batch and run the command
    while ( @files > 0 ) {
        my @round;
        my $round_str = '';
        while ( @files && @round < $MAX_BATCH_SIZE && length($round_str) < $MAX_BATCH_STRING_SIZE ) {
            my $file = shift @files;

            ###  Skip ones whos parent dir ! exists
            ( my $parent_dir = $file) =~ s@/[^/]+$@@;
            next if ! -d "$ENV{DAVE_CVS_BASE}/$parent_dir";

            push @round, $file;
            $round_str .= " \"$file\"";
        }

        my %round_checkoff = map {($_,1)} @round;
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        my $all_entries = `$CVS_CMD log $round_str 2>&1 | cat`;
#        bug substr($all_entries, -200);
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        ENTRY : foreach my $entry ( split(m@===================================================================+\n@s, $all_entries) ) {
            next if $entry =~ /^\s*$/s;

            ###  Get the filename
            my $file;
            if ( $entry =~ m@^\s*RCS file: /sandbox/cvsroot/(?:dave/)?(.+?),v\n@s ) {
                $file = $1;
            }
            ###  Other than "normal" output
            else {
                # silently skip
                next ENTRY;
            }

            ###  Cache
            if ( ! exists $round_checkoff{$file} ) {
                next ENTRY;
#                BUG [$file,\%round_checkoff];
#                die "file not in round";
            }
            delete $round_checkoff{$file};
            $cvs_cache{$cache_key}{$file} = $entry;
        }
    }
}

sub get_cvs_status {
    my ( $file ) = @_;

    ###  If not cached, get it and cache
    if ( ! $cvs_cache{status}{$file} ) {
        ( my $parent_dir = $file) =~ s@/[^/]+$@@;
        if ( -d "$ENV{DAVE_CVS_BASE}/$parent_dir" ) {
            START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
            $cvs_cache{status}{$file} = `$CVS_CMD status "$file" 2>&1 | cat`;
            END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        }
        else {
            $cvs_cache{status}{$file} = "cvs [status aborted]: no such directory `$parent_dir'";;
        }
    }

    return $cvs_cache{status}{$file};
}

sub cache_cvs_statuses {
    my ( @files ) = @_;

    my $cache_key = 'status';

    ###  Batch and run the command
    while ( @files > 0 ) {
        my @round;
        my $round_str = '';
        while ( @files && @round < $MAX_BATCH_SIZE && length($round_str) < $MAX_BATCH_STRING_SIZE ) {
            my $file = shift @files;

            ###  Skip ones whos parent dir ! exists
            ( my $parent_dir = $file) =~ s@/[^/]+$@@;
            next if ! -d "$ENV{DAVE_CVS_BASE}/$parent_dir";

            push @round, $file;
            $round_str .= " \"$file\"";
        }

        my %round_checkoff = map {($_,1)} @round;
        START_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        my $all_entries = `$CVS_CMD status $round_str 2>&1 | cat`;
#        bug substr($all_entries, -200);
        END_TIMER CVS_CMD if $DEBUG::DAVE_DAVE_TIMERS;
        ENTRY : foreach my $entry ( split(m@===================================================================+\n@s, $all_entries) ) {
            next if $entry =~ /^\s*$/s;

            ###  Get the filename
            my $file;
            if ( $entry =~ m@Repository revision:\s*[\d\.]+\s*/sandbox/cvsroot/(?:dave/)?(.+?),v\n@s ) {
                $file = $1;
                shift @round;
            }
            elsif ( $entry =~ m@^File: (?:no file )?(.+?)\s+Status@s ) {
                $file = $1;

                if ( $round[0] =~ m@/\Q$file\E$@ ) {
                    $file = shift @round;
                }
                else {
#                    bug [$entry, $file];
                }
            }
            ###  Other than "normal" output
            else {
 #               bug [$entry];
                # silently skip
                next ENTRY;
            }

            ###  Cache
            if ( ! exists $round_checkoff{$file} ) { 
                next ENTRY;
                # BUG [$entry, \@round, $file,\%round_checkoff];
                # die "file not in round"; 
            }
            delete $round_checkoff{$file};
            $cvs_cache{$cache_key}{$file} = $entry;
        }
    }
}


#########################
###  Project base access subroutines

sub get_project_ls {
    my ($project) = @_;

    die "Please don't hack..." if $project =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;

    return &call_remote( (caller(0))[3], \@_ ) unless -d $SYSTEM_PROJECT_BASE;
    return `/bin/ls -la --time-style=long-iso $SYSTEM_PROJECT_BASE/$project | head -n2 | tail -n1`;
}

sub get_project_stat {
    my ($project) = @_;

    die "Please don't hack..." if $project =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;

    return &call_remote( (caller(0))[3], \@_ ) unless -d $SYSTEM_PROJECT_BASE;
    return stat("$SYSTEM_PROJECT_BASE/$project");
}

sub project_file_exists {
    my ($project, $file) = @_;

    die "Please don't hack..." if $project =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;
    die "Please don't hack..." if $file =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;

    return &call_remote( (caller(0))[3], \@_ ) unless -d $SYSTEM_PROJECT_BASE;
    return ( -e "$SYSTEM_PROJECT_BASE/$project/$file" );
}

sub get_project_file {
    my ($project, $file) = @_;

    die "Please don't hack..." if $project =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;
    die "Please don't hack..." if $file =~ m@^/|(^|/)\.\.?($|/)|[\"\'\`\(\)\[\]\&\|\>\<]@;

    return &call_remote( (caller(0))[3], \@_ ) unless -d $SYSTEM_PROJECT_BASE;
    return `cat $SYSTEM_PROJECT_BASE/$project/$file`;
}

sub get_projects {
    return &call_remote( (caller(0))[3], \@_ ) unless -d $SYSTEM_PROJECT_BASE;
    return split("\n",`ls -1 $SYSTEM_PROJECT_BASE | grep -E -v '^(archive|logs)\$'`);
}

sub call_remote {
    my ($sub, $params) = @_;

    $sub =~ s/^.+:://;

    my $url = "https://admin.beta.dave.org/project_manager/";
    $url = "https://pmgr_tunnel:h53clK88FvB5\@admin.beta.dave.org/project_manager/" if $ENV{REMOTE_USER};

    my %params = ( action      => 'remote_call',
                   remote_call => $sub,
                   params      => &escape( &nfreeze( $params ) ),
                   'wantarray' => (wantarray ? 1 : 0),
                 );
    my $agent = LWP::UserAgent->new;
    my $response = $agent->post($url, \%params);

    my ($frozen) = ($response->content =~ /\|=====\|(.+)\|=====\|/);
    my $response_obj;
    if ( $frozen ) {
        $response_obj = &thaw(&unescape($frozen));
        if ( ! ref($response_obj) ) {
            BUG ["Not a ref", $frozen, $response_obj];
            die "Not a ref : ". $response->content;
        }
    }
    else {
        BUG ["Bad Response", $response->content];
        die "Bad Response : ". $response->content;
    }

    return( wantarray && UNIVERSAL::isa($response_obj, 'ARRAY')
            ? (@{$response_obj})
            : $$response_obj
          );
}


#########################
###  Utility functions

sub log_cvs_action {
    my ( $command ) = @_;

    my $log_line = &join_delim_line(',', [time(), $$, scalar(localtime()), $command], '"'). "\n";

    my $file = "$DAVE_SAFE_BASE/project_cvs_log_${env_mode}.csv";
    open(LOG, ">>$file") or die "Could not log cvs command : $command";
    print LOG $log_line;
    close LOG;
}

sub get_affected_files {
    my ( $project_name ) = @_;

    my @files;
    foreach my $file ( split("\n",&get_project_file( $project_name, "affected_files.txt" )) ) {
        $file =~ s/(\s*\#.*$|\s+)$//g;
        next if ! length $file;

        push @files, $file;
    }

    return @files;
}

sub get_file_tags {
    my ( $project_name ) = @_;

    my %file_tags;
    foreach my $line ( split("\n",&get_project_file( $project_name, "file_tags.csv" )) ) {
        my @vals = &split_delim_line(',',$line,'"');
        next unless @vals >= 2 && $vals[1] !~ /[\"]/ && $vals[1] =~ /^\d+\.\d+(\.\d+\.\d+)?$/;
        $file_tags{ $vals[0] } = $vals[1];
    }

    return \%file_tags;
}

sub get_revs_in_diff {
    my ( $from, $to ) = @_;
    return if $from =~ /[^\d\.]/ || $to =~ /[^\d\.]/;
    return if $from eq $to;

    my @revs;

    ###  Determine revisions between
    my ($f_trunk, $f_rev) = ($from =~ /^([\d\.]+?)(\d+)$/);
    my ($t_trunk, $t_rev) = ($to   =~ /^([\d\.]+?)(\d+)$/);
    ###  If along the same trunk it's easy
    if ( $f_trunk eq $t_trunk ) {
        return if $f_rev >= $t_rev;
        @revs = map { "$f_trunk$_" } ( ($f_rev+1) .. $t_rev );
    }
    ###  If moving to a branch from non-branch, check ...
    elsif ( $f_trunk =~ /^\d+\.$/           && $t_trunk =~ /^\d+\.\d+\.\d+\.$/ ) {
        my ( $t_branch_start_rev ) = ( $t_trunk =~ /^$f_trunk(\d+)\.\d+\.$/ );
        die unless $t_branch_start_rev;

        ###  If branch is a leap back, just show the branch revs
        if ( $t_branch_start_rev <= $f_rev ) {
            return if $t_rev < 1;
            @revs = map { "$t_trunk$_" } ( 1 .. $t_rev );
        }
        ###  Otherwise, show all the trunk revs up to the 
        ###    branch, and then then branch revs
        else {
            return if $t_rev < 1;
            @revs = ( (map { "$f_trunk$_" } ( ($f_rev+1) .. $t_branch_start_rev )),
                      (map { "$t_trunk$_" } ( 1 .. $t_rev )),
                      );
        }
    }
    ###  If moving back to a non-branch from a branch
    elsif ( $f_trunk =~ /^\d+\.\d+\.\d+\.$/ && $t_trunk =~ /^\d+\.$/           ) {
        my ( $f_branch_start_rev ) = ( $f_trunk =~ /^$t_trunk(\d+)\.\d+\.$/ );
        die unless $f_branch_start_rev;
        return if $f_branch_start_rev >= $t_rev;
        @revs = map { "$t_trunk$_" } ( ($f_branch_start_rev+1) .. $t_rev );
    }
    ###  Moving from one branch to another (rare)
    ###    just jump back to the head of the from-branch
    ###    and run our self as if moving from that trunk rev
    elsif ( $f_trunk =~ /^\d+\.\d+\.\d+\.$/ && $t_trunk =~ /^\d+\.\d+\.\d+\.$/ ) {
        my ( $f_branch_start ) = ( $f_trunk =~ /^(\d+\.\d+)\.\d+\.$/ );
        die unless $f_branch_start;
        return &get_revs_in_diff($f_branch_start, $to);
    }
    ###  Else, DIE!
    else { die "What the heck are ya!? ($from, $to)"; }

    return @revs;
}

sub get_prev_rev {
    my ( $rev ) = @_;
    return $rev if $rev eq '1.1';

    if ( $rev =~ /^(\d+\.\d+)\.\d+\.1$/ ) {
        return $1;
    }
    elsif ( $rev =~ /^(\d+\.(?:\d+\.\d+\.)?)(\d+)$/ ) {
        return $1.($2-1);
    }
}

sub get_log_entry {
    my ( $clog, $rev ) = @_;

    return ( $clog =~ /---------+\n(revision \Q$rev\E\n.+?)(?:\n=========+$|\n---------+\nrevision )/s )[0];
}


#########################
###  Display Logic

sub style_sheet {
    my $ret = <<"ENDSTYLE";
<style>
body, td        { font-family: Verdana, Arial, Helvetica;
                  font-color: #111111;
                  color: #111111;
                  font-size: 10pt;
                }
td { white-space: nowrap }
th              { font-weight: bold;
                  font-color: #000000;
                  color: #000000;
                }
a               { text-decoration: none;  white-space: nowrap }

</style>
ENDSTYLE

    ###  HACK, add JavaScript...
    $ret .= <<'ENDSCRIPT';
<script>
var disable_actions = 0;

function confirmAction(which,newLocation) {
    //  If locally modified files, diabled actions
    if ( disable_actions ) {
        alert("Some of the below files are locally modified, or have conflicts.  CVS update actions would possibly conflict the file leaving code files in a broken state.  Please resolve these differences manually (command line) before continuing.\n\nActions are currently DISABLED.");
        return void(null);
    }

    var confirmed = confirm("Please confirm this action.\n\nAre you sure you want to "+which+" these files?");
    if (confirmed) { location.href = newLocation }
}
</script>
ENDSCRIPT

    ###  HACK, add a line of status for sandbox location
    $ret .= &env_header();

    return $ret;
}

sub env_header {

    ###  A line of status for sandbox location
    my $ret = "<table width=\"100%\" cellspacing=0 cellpadding=0 border=0><tr><td><div style=\"font-size:70%\">";
    $ret .= "<b>Go to:</b> <a href=\"?\">Project List</a>\n";
    $ret .= "<br><b>Current Sandbox Root</b>: $ENV{DAVE_CVS_BASE}";
    if ( $ENV{DAVE_CVS_BASE} =~ m@^/tmp/@ ) {
        my $mtime = (stat("$ENV{DAVE_CVS_BASE}/reports/modules_detect.txt"))[9];
        $ret .= "<i><b>Last Mirrored</b>: ". scalar(localtime($mtime)) .", ". sprintf("%.1f",(time()-$mtime) / 86400) ." days ago</i><br>";
    }

    $ret .= "</div></td><td align=right><div style=\"font-size:70%\">";

    ###  And stuff to switch between environments
    my $uri = $ENV{HTTP_HOST};
    my $query_string = $ENV{QUERY_STRING};
    $query_string =~ s/[\&\?](cmd|command_output|tag)=[^\&]+//g;
    $query_string =~ s/action=(update|tag)/action=view_project/g;
    
    $ret .= "  <a        href=\"https://admin.beta.dave.org/project_manager/?$query_string\">".  ($uri =~ /\.beta($|\.dave)/             ? "<b>" : "") ."QA Staging Sandbox</b></a>\n";
    $ret .= "| <a   href=\"https://admin.dave.org/project_manager/?$query_string\">".            ($uri !~ /\.(beta|l?dev)($|\.dave)/     ? "<b>" : "") ."Live Production</b></a>\n";
    $ret .= ": <b>Switch to Staging Area</b>";
    $ret .= "<br><a href=\"http://admin.dave.dev.dave.org/project_manager/?$query_string\">".    ($uri =~ /(^|\.)dave\./                   ? "<b>" : "") ."Dave</b></a>\n";
    $ret .= "  | <a href=\"http://admin.devin.dev.dave.org/project_manager/?$query_string\">".   ($uri =~ /(^|\.)devin\./                  ? "<b>" : "") ."Devin</b></a>\n";
    $ret .= "  | <a href=\"http://admin.jhenage.dev.dave.org/project_manager/?$query_string\">". ($uri =~ /(^|\.)jhenage\./                ? "<b>" : "") ."Jon</b></a>\n";
    $ret .= "  | <a href=\"http://admin.brenon.dev.dave.org/project_manager/?$query_string\">".  ($uri =~ /(^|\.)brenon\./                 ? "<b>" : "") ."Brenon</b></a>\n";
    $ret .= "  | <a href=\"http://admin.kagan.dev.dave.org/project_manager/?$query_string\">".   ($uri =~ /(^|\.)kagan\./                  ? "<b>" : "") ."Kagan</b></a>\n";
    $ret .= "  | <a href=\"http://admin.qa.dev.dave.org/project_manager/?$query_string\">".      ($uri =~ /(^|\.)qa\./                     ? "<b>" : "") ."QA User</b></a>\n";
    $ret .= ": <b>Switch to Sandbox</b>";
    $ret .= "</div></td></td></table>";

    return $ret;
}

1;
