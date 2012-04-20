package Dave::ErrorSystem::Instance;

#########################
###  CMS/ErrorSystem/Instance.pm
###  Version : $Id: Instance.pm,v 1.2 2009/02/03 23:41:53 dave Exp $
###
###  An Instance of an error, to do the throwing
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::ErrorSystem qw( $ERROR_RECORD_BASE $ERROR_CONF_BASE $PID_ERROR_COUNT &archive_error_dir );
use Dave::Util qw( &split_delim_line &join_delim_line &read_conf );
use Storable qw(&freeze &thaw);  $Storable::forgive_me = 1;
use Data::Dumper;  $Data::Dumper::Sortkeys = 1;  $Data::Dumper::Quotekeys = 0;
use File::Path;
use File::NFSLock;
use CGI::Util qw( &escape &unescape );
use CGI qw( &escapeHTML );
use IPC::Run qw(run timeout);

my $running_wo_internet_skip_emails;
#$running_wo_internet_skip_emails = 1; # uncomment to skip emails when offline


#########################
###  Error Handling Functions

sub new {
  my $pkg = shift;
  my ( $error, $details, $objid, $log_entry ) = @_;

  die "No Error id passed to Dave::ErrorSystem::Instance->new" unless defined($error);

  my $self;
  if ( $log_entry ) {
      $self = bless( { error      => $error,
                       details    => ($details || $log_entry->{'details'}),
                       stack      => $log_entry->{'stack'},
                       env        => $log_entry->{'env'},
                       script     => $log_entry->{'script'},
                       objid      => $log_entry->{'objid'},
                       error_time => $log_entry->{'time'},
                       hostname   => $log_entry->{'host'},
                       pid        => $log_entry->{'host'},
                       pid_error_count => $log_entry->{'pid_error_count'},

                       archived => 1, # prevents certain operations
                   }, $pkg );
  }
  else {
      ###  Magic details
      my $custom_die_message;
      if ( exists $details->{'*die_message*'} ) {
          $custom_die_message = $details->{'*die_message*'};
          delete $details->{'*die_message*'};
      }

      ###  Simple Stack trace dump
      my @stack;  my $i = 0;
      while ( caller($i+1) ) { $i++;  push @stack, [ caller($i) ]; }

      ###  Get Hostname
      my $hostname = $ENV{HOST};
      if ( ! $hostname ) { 
          local $ENV{PATH} = '/bin';
          $hostname = `hostname`;
          $hostname =~ s/\n// if $hostname;
      }
      $hostname ||= 'nohost';

      my $time = time();
      $self = bless( { error      => $error, 
                       details    => $details,
                       stack      => \@stack,
                       env        => { %ENV },
                       script     => ($ENV{SCRIPT_NAME} || $0 || 'noscript'),
                       objid      => ($objid || $ENV{ERROR_SYSTEM_OBJ_ID} || $ENV{REMOTE_USER} || $ENV{HTTP_HOST} || 'noobjid'),
                       error_time => $time,
                       hostname   => $hostname,
                       pid        => $$,
                       custom_die_message => $custom_die_message,
                   }, $pkg );
  }

  return Dave::ErrorSystem::Instance::ObjectLink->new($self);
}
sub error { $_[0]->{'error'} }

sub archive_error {
  my $self = shift;

  START_TIMER errorsystem_archive if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;

  return 1 if $self->{'archived'};

  ###  The Dir to use
  my $dir = &archive_error_dir($self->{'error_time'}, $self->{'error'});

  ###  Make the dir if it's not there
  mkpath($dir, 0, 0775) unless -d $dir;
  unless ( -d $dir ) { warn "ErrorSystem: For error $self->{error}, could not create Error archive directory : $dir : $!";  return; }

  ###  Add to the brief and log files
  my $lock = File::NFSLock->new({ file      => "$dir/brief.csv",
                                  lock_type => 'BLOCKING',
                                  blocking_timeout   => 10,      # 10 sec
                                  stale_lock_timeout => 30 * 60, # 30 min
                                });
  unless ( $lock ) { warn "ErrorSystem: For error $self->{error}, could not get a blocking lock on brief file: $dir/brief.csv : $!";  return; }

  my $already_has_header = (-e "$dir/brief.csv");
  unless ( open(BRIEF, ">>$dir/brief.csv") ) { warn "ErrorSystem: For error $self->{error}, could not open brief file: $dir/brief.csv : $!";  return; }
  if ( ! $already_has_header ) {
    print BRIEF &join_delim_line( ',', [qw( time
                                            host
                                            pid
                                            pid_error_count
                                            script
                                            objid
                                            )], '"')."\n";
  }
  print BRIEF &join_delim_line( ',', [ $self->{'error_time'},
                                       $self->{'hostname'},
                                       $self->{'pid'},
                                       $PID_ERROR_COUNT,
                                       $self->{'script'},
                                       $self->{'objid'},
                                       ], '"' )."\n";
  close BRIEF;

  $already_has_header = (-e "$dir/detail.csv");
  unless ( open(DETAIL, ">>$dir/detail.csv") ) { warn "ErrorSystem: For error $self->{error}, could open detail file: $dir/detail.csv : $!";  return; }
  if ( ! $already_has_header ) {
    print DETAIL &join_delim_line( ',', [qw( time
                                             host
                                             pid
                                             pid_error_count
                                             env
                                             stack
                                             details
                                             )], '"')."\n";
  }
  print DETAIL &join_delim_line( ',', [ $self->{'error_time'},
                                        $self->{'hostname'},
                                        $self->{'pid'},
                                        $PID_ERROR_COUNT,
                                        &escape( &my_freeze( $self->{'env'} ) ),
                                        &escape( &my_freeze( $self->{'stack'} ) ),
                                        &escape( &my_freeze( $self->{'details'} ) ),
                                        ], '"' )."\n";
  close DETAIL;

  $self->{'archived'} = 1;
  END_TIMER errorsystem_archive if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;

  return 1;
}

sub my_freeze {
  my $frozen = eval {&freeze(@_)};
  if ( $@ ) {
    &BUGSW("Error, caught die() while trying to freeze(): $@");
    return &freeze(['Error, caught die() while trying to freeze(): $@']) if UNIVERSAL::isa($_[0], 'ARRAY');
    return &freeze({err => 'Error, caught die() while trying to freeze(): $@'}) if UNIVERSAL::isa($_[0], 'HASH');
    return &freeze(\ 'Error, caught die() while trying to freeze(): $@') if UNIVERSAL::isa($_[0], 'SCALAR');
  }
  return $frozen;
}

sub conf {
  my $self = shift;
  
  if ( ! $self->{'conf'} ) {
    $self->{'conf'} = &read_conf( $ERROR_CONF_BASE .'/'. $self->{'error'} .'.conf', {no_file_is_ok => 1} );
    ###  Since all error confs are in a trusted directory, UNTAINT ALL VALUES
    ( $self->{'conf'}{$_} ) = ($self->{'conf'}{$_} =~ /^(.+)$/s ) foreach (keys %{ $self->{'conf'} });
    ###  If no internal_name or admin_message, switch to default_error.conf
    if ( ( ! $self->{'conf'}{'internal_name'} ) || ( ! $self->{'conf'}{'admin_message'} ) ) {
      BUGW($ERROR_CONF_BASE .'/'. $self->{'error'} .'.conf');
      $self->{'conf'} = &read_conf( $ERROR_CONF_BASE .'/default_error.conf');
    }
  }
  $self->{'conf'};
}

sub send_notifications {
  my $self = shift;
  return 1 if $running_wo_internet_skip_emails;
  START_TIMER errorsystem_notify if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;

  ###  If no 'notify_emails' in conf or bad format that will cause the To: line to fail
  my $email_re = qr/[a-z0-9][a-z0-9\.\-\+]*\@([a-z0-9\-]+\.)+[a-z]{2,}/;
  if ( ( ! $self->conf->{'notify_emails'} ) 
       || ( ( $self->conf->{'notify_emails'} ne 'none' )
            && ( $self->conf->{'notify_emails'} !~ /^\s*$email_re(\s*,\s*$email_re)*\s*$/ )
            )
       ) {
    warn "ErrorSystem: For error $self->{error}, missing or invalid key 'notify_emails' in error conf for error ". $self->{'error'};
    $self->conf->{'notify_emails'} ||= 'none'; # doesn't modify conf file
  }

  ###  Skip out if they have selected to not send emails
  if ( $self->conf->{'notify_emails'} eq 'none' ) {
    END_TIMER errorsystem_notify if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
    return;
  }

  ###  Prefix to the subject depending on environment
  my $subject_prefix = '';
#  $subject_prefix = 'ALPHA ' if onAlpha;
#  $subject_prefix = 'TEST ' if onTest;

  ###  Assemble the message
  my $message = ( "To: ". $self->conf->{'notify_emails'} .
                  "\nFrom: \"CMS Error System\" <errorsystem\@NOREPLY.NOWHERE>" .
                  "\nSubject: ${subject_prefix}ErrorReport: ". $self->{'error'}  .' '. ($self->conf->{'internal_name'} || 'Unnamed Error') .
                  "\n\n" . 
                  $self->error_report_content('text/plain','admin')
                  );

  ###  Pipe to sendmail
  local $ENV{PATH} = '/usr/sbin'; # possible problems
#  my @cmd = ('sendmail','-ODeliveryMode=b','-f','errorsystem@CMS.com',$self->conf->{'notify_emails'});
  my @cmd = ('sendmail','-f','errorsystem@CMS.com',$self->conf->{'notify_emails'});
  if ( $Dave::ErrorSystem::SENDMAIL_RUN_METHOD
       && $Dave::ErrorSystem::SENDMAIL_RUN_METHOD eq 'simple'
       ) {
    ###  Run old-style
    open(SENDMAIL, '|-', join(' ', @cmd) ) or warn "ErrorSystem: For error $self->{error}, sendmail had bad return status : $?, ". ($? & 127) .", ". (($? & 128) ? 'with' : 'without') ." coredump\n";
    print SENDMAIL $message;
    close SENDMAIL;

    END_TIMER errorsystem_notify if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
    return 1;
  }

  ###  Run using IPC::Run
  my ($out, $err) = ('','');
  my $close_status = run( \@cmd, \$message, \$out, \$err, timeout( 120 ) );
  if ( !$close_status ) { warn "ErrorSystem: For error $self->{error}, sendmail had bad return status : $?, ". ($? & 127) .", ". (($? & 128) ? 'with' : 'without') ." coredump\n"; }
  if ( $err ) { warn "ErrorSystem: For error $self->{error}, sendmail returned STDERR : $err"; }
  if ( $out ) { warn "ErrorSystem: For error $self->{error}, sendmail returned STDOUT : $out"; }
  
  END_TIMER errorsystem_notify if $SHOW_DEBUG::ERRORSYSTEM_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  return $close_status;
}

sub print_error_report {
  my $self = shift;

  if ( $ENV{REQUEST_METHOD} ) {
    if ( ! $ENV{CONTENT_TYPED} ) {
      print "Content-type: text/html\n\n";
      $ENV{CONTENT_TYPED} = 1;
    }
    print $self->error_report_content('text/html');
  }
  else {
    print $self->error_report_content('text/plain');
  }
}

sub error_report_content {
  my $self = shift;
  my ( $format, $mode ) = @_;

  ###  Format shortcut
  my $html = 1;
  $html = 0 if $format && $format eq 'text/plain';

  ###  Mode determination
  my $admin = 1;
#  $admin = 0 if ($mode && $mode eq 'user') || (!$mode && !&onAlpha);

  ###  Base content swap for Alpha
  my $content;
  if ( $admin ) {
    ###  ADMIN HTML Version
    if ( $html ) {
      $content = <<ETX;
<style>
  h2 {font-family: Arial, Helvetica, Sans-Serif;
      font-size: 16pt;
    color: #0000ff;
      font-weight: bold;
    }
  .body {font-family: Arial, Helvetica, Sans-Serif;
         font-size: 10pt;
       }
  .mycode {font-family: Monaco, Terminal, Courier;
           font-size: 8pt;
          }
  .bcode {font-family: Arial, Helvetica, Sans-Serif;
          font-size: 9pt;
         }
</style>
<h2>Error: <[swap.error/]> - <[error.internal_name/]></h2><br>
<div class=body>
<b>User Message:</b><br>
<[error.user_message/]><br><br>
<b>Admin Message:</b><br>
<[error.admin_message/]><br><br>
</div>
<table width="100%" class="mycode" cellpadding=5 border=0>
<tr>
  <td><b class="bcode">Error Time</b>: <[swap.error_time/]></td>
  <td><b class="bcode">Host, Pid</b>: <[swap.hostname/]>, <[swap.pid/]></td>
</tr>
<tr>
  <td width="10%" valign="top">
    <b class="bcode">Stack</b>:<br>
    <[swap.stack/]>
  </td>
  <td width="90%" valign="top">
    <b class="bcode">Environment</b>:<br>
    <[swap.ENV/]>
  </td>
</tr>
</table>
ETX
    }
    ###  ADMIN TEXT Version
    else {
    $content = <<ETX;
<[swap.error/]> - <[error.internal_name/]>
----------------------------------------

User Message:
----------------------------------------
<[error.user_message/]>

Admin Message:
----------------------------------------
<[error.admin_message/]>

Error Time: <[swap.error_time/]>
Host, Pid: <[swap.hostname/]>, <[swap.pid/]>

Stack:
----------------------------------------
<[swap.stack/]>

Environment:
----------------------------------------
<[swap.ENV/]>
ETX
    }
  }
  else {
    ###  USER HTML Version
    if ( $html ) {
      $content = <<ETX;
<b>An Error Occurred:</b><br><br>
<[error.user_message/]><br><br>
<b>Error Code: <[swap.error/]></b><br>
ETX
    }
    ###  USER TEXT Version
    else {
    $content = <<ETX;
An Error Occurred:
----------------------------------------

<[error.user_message/]>

Error Code: <[swap.error/]>
ETX
    }
  };
  
  ###  Parse all tags
  $self->parse_content(\$content, $html);

  return $content;
}

sub parse_content {
  my $self = shift;
  my ( $content_ref, $html ) = @_;

  ###  Do the basic swaps
  my %swap = ( error      => $self->{'error'},
               error_time => scalar(localtime($self->{'error_time'})),
               hostname   => $self->{'hostname'},
               pid        => $self->{'pid'},
               details    => $self->{'details'},
               );
  ###  Format Stack
  my @formatted_stack;
  foreach my $call ( @{ $self->{'stack'} }  ) {
    (my $file = $call->[0].'.pm') =~ s@::@/@g;
    $file = $call->[1] if $call->[1] !~ /\Q$file\E$/;
    (my $shortsub = $call->[3]) =~ s/^.*?([^\:]+)$/$1/;
    my $format = "$shortsub called at $file line $call->[2]";
    $format =~ s/ /&nbsp;/g if $html;
    push @formatted_stack, $format;
  }
  $swap{'stack'} = join(($html ? "<br>\n" : "\n"), @formatted_stack);

  ###  Format Env
  $swap{'env'} = $self->{'env'};
  $swap{'ENV'} = $self->{'env'};

  ###  Swap in the tags
  foreach (1..10) {
    my $s = 0;
    $s += ($$content_ref =~ s@<\[details\.(\w+)/\]>@$self->err_format_swap($swap{'details'}{$1}, $html, $1, $&)@eg);
    $s += ($$content_ref =~ s@<\[swap\.(\w+)/\]>@$self->err_format_swap($swap{$1},               $html, $1, $&)@eg);
    $s += ($$content_ref =~ s@<\[error\.(\w+)/\]>@$self->err_format_swap($self->conf->{$1},      $html, $1, $&)@eg);
    last unless $s;
  }

  return 1;  
}

sub err_format_swap {
  my $self = shift;
  my ( $what, $html, $sym, $orig_tag ) = @_;
  unless ( defined($what) ) {
    return ''; # unless &onAlpha;
    $orig_tag =~ s/[\<\>]//g;
    return $orig_tag;
  }

  ###  Refs
  if ( ref($what) ) {

    $what = Data::Dumper->Dump( [$what], [$sym] );
    substr( $what, -1, 1) = '' if substr( $what, -1, 1) eq "\n";
    if ( $html ) {
      $what = &escapeHTML( $what );
      $what =~ s/(?<!<br>)\n/<br>\n/g;
      $what =~ s/\t/    /g;
      $what =~ s/ /&nbsp;/g;
    }
  }
  ###  HTML content
  elsif ( ($html)
          && ( (! $self->conf->{'html_escaping'} ) 
               || ( $self->conf->{'html_escaping'} eq 'br_only' ) ) 
          ) {
    $what =~ s/(?<!<br>)\n/<br>\n/g;
  }

  return $what;
}

sub die_message {
  my $self = shift;
  return $self->{'custom_die_message'} if defined( $self->{'custom_die_message'} );

  ###  NOTE:  caller() 1 deeper than you'd think because we are wrapped within
  ###    an Instance::ObjectLink and AUTOLOAD adds 1 to every external caller
  return 'Error '. $self->{'error'}. ' occurred: '. $self->conf->{'internal_name'} .' at ' . ( caller(2) )[1] . ' line ' . ( caller(2) )[2]. "\n";
}

sub prepare_for_defer {
  my $self = shift;

  ###  NOTE: Currently I cant see the need to clone the details at
  ###    this point since we are archiving the error before defer.
  ###  If we were deferring the archive command as well, then it
  ###    would be an issue because the params passed-by-ref passed
  ###    to us could be changed by other code while are deferred

#  ###  Clone the structure 2 levels deep so that it cannot change
#  ###    while we are deferred.  Otherwise
#  require Clone;
#  $self->{'details'} = &Clone::clone( $self->{'details'}, 2 );
  return Dave::ErrorSystem::Instance::ObjectLink->new($self);
}

sub flat_array {
  my $self = shift;

  my %arg_hash;
  if ( ( $self->{'details'} ) && ( UNIVERSAL::isa($self->{'details'},'HASH') ) ) {
    %arg_hash = map {($_,$self->{'details'}{$_}.'')} keys %{$self->{'details'}};
  }

  return [ $self->{'error'}, \%arg_hash ];
}


#########################
###  ObjectLink to avoid memory leaks

###  So people don't have to store the large Error Instance object in their $self

package Dave::ErrorSystem::Instance::ObjectLink;

my $inc = 0;
my %linktable;

sub new {
  my $pkg = shift;
  my ( $obj ) = @_;
  my $key = ( defined($obj->{'ObjectLink_key'}) ? $obj->{'ObjectLink_key'} : $inc++);
  $obj->{'ObjectLink_key'} = $key;
  $linktable{ $key } ||= $obj;

  ###  MOD_PERL Cleanup Handler 
  ###    or Non-MOD_PERL END block:
  ###    clean out shared objects
  $FIXUPHANDLER::TODO{'Dave::ErrorSystem::Instance::linktable'} ||= 
    sub { %linktable = (); };
  
  return bless { key => $key }, $pkg;
}

use vars qw($AUTOLOAD);
sub AUTOLOAD {
  my $self = shift;

  my ( $sub_name ) = ( $AUTOLOAD =~ /([^:]+)$/ );
  
  if ( ref($self) eq 'Dave::ErrorSystem::Instance::ObjectLink'
       && $linktable{ $self->{'key'} }
       && $linktable{ $self->{'key'} }->can($sub_name)
       ) {
    return $linktable{ $self->{'key'} }->$sub_name(@_);
  }

  die "Undefined subroutine \&$AUTOLOAD called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless substr($AUTOLOAD,-7) eq 'DESTROY';
}

1;


__END__


=head1 NAME

Dave::ErrorSystem::Instance - An Instance of an error, to do the throwing

=head1 SYNOPSIS

    use Dave::ErrorSystem::Instance;

    my $instance = Dave::ErrorSystem::Instance->new($errno, $details);

=head1 ABSTRACT

=over 4

See the perldoc for Dave::ErrorSystem for now.  Eventually this
might be a public accesible object for people to use.

=back

=head1 FUNCTIONS

=back

=head1 DEPENDENCIES

This module loads these libs when needed:

=over 4

    Data::Dumper
    Storable

=back
