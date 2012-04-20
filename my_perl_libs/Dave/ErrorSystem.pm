package Dave::ErrorSystem;

#########################
###  Dave/ErrorSystem.pm
###  Version : $Id: ErrorSystem.pm,v 1.2 2009/02/03 23:39:18 dave Exp $
###
###  Central Error Handling/Archving system
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::Global qw(:dirs :sys_context);

#$SHOW_DEBUG::TRANS = 1;
#$SHOW_DEBUG::ES_ATTEMPT_TIMERS = 1;
#$SHOW_DEBUG::ERRORSYSTEM_TIMERS = 1;

######  Exporter Parameters
###  Get the Library and use it
use Exporter;
use vars qw( @ISA @EXPORT_OK %EXPORT_TAGS $ERROR_RECORD_BASE $ERROR_CONF_BASE $PID_ERROR_COUNT $MY_PID $DOIN_A_DIE $SENDMAIL_RUN_METHOD $ERROR_SYSTEM_TZ );
@ISA = ('Exporter');

sub attempt($*$@);
sub success_check(&);
sub failure(&);
sub no_die_failure(&);
sub grab_from_object(&);

###  Define the Exported Symbols
@EXPORT_OK = qw( &throw_error
                 &throw_silent_error
                 
                 &do_error
                 &do_silent_error
                 &are_errors
                 &play_errors
                 &grab_errors
                 &play_or_grab_errors

                 &archive_error_dir
                 &archive_day_dir

                 &attempt
                 &success_check
                 &failure
                 &no_die_failure
                 &grab_from_object
                 &begin_attempt
                 &end_attempt

                 $ERROR_RECORD_BASE
                 $ERROR_CONF_BASE
                 $ERROR_SYSTEM_TZ
                 $PID_ERROR_COUNT
                 $SENDMAIL_RUN_METHOD
                 );
%EXPORT_TAGS = ( common => [qw( &throw_error
                                &throw_silent_error
                                )],
                 oo_methods => [qw( &do_error
                                    &do_silent_error
                                    &are_errors
                                    &play_errors
                                    &grab_errors
                                    &play_or_grab_errors
                                    )],
                 attempt => [qw( &attempt
                                 &success_check
                                 &failure
                                 &no_die_failure
                                 &grab_from_object
                                 &begin_attempt
                                 &end_attempt
                                 )],
                 );

our $ATTEMPT_SCOPE_CHECK = (onLive) ? 0 : 1;

###  Globals
$ERROR_SYSTEM_TZ = 'MST';
$ERROR_RECORD_BASE = $Dave_SAFE_BASE . '/error_archive';
$ERROR_CONF_BASE =   $Dave_CVS_BASE  . '/modules/errors';

###  Start (or reset the PID)
$MY_PID ||= $$;
$PID_ERROR_COUNT = 0 if ! defined $PID_ERROR_COUNT || $MY_PID != $$;
$MY_PID = $$;

BEGIN {

  sub my_sig_die {
    die @_ if ! $ENV{REQUEST_METHOD} || $DOIN_A_DIE;
    my $error = ( @_ > 1 ) ? [ @_ ] : $_[0];

    ###  If we are in an eval - let the eval handle the die
    ###    UNLESS, it is the mod_perl handler's eval or
    ###    our serve_page handler eval
    my $i = 0;
    my $last_func_was_mod_perl_handler = 0;
    my $last_func_was_serve_page_handler = 0;
    while (my($package, $file, $line, $sub, $hasargs, $wantarray) = caller($i++)) {
      if ( $sub eq '(eval)'
           && $package ne 'Apache::PerlRun'
           && ! $last_func_was_mod_perl_handler
           && ! $last_func_was_serve_page_handler
           ) { die @_; }
      $last_func_was_mod_perl_handler = (($ENV{MOD_PERL} && $sub =~ /\:\:handler$/) ? 1 : 0);
      $last_func_was_serve_page_handler = (($ENV{MOD_PERL} && $sub =~ /\:\:serve_page$/) ? 1 : 0);
    }

    &throw_error( 99, { error => $error, dbi_errstr => $DBI::errstr, '*die_message*' => join(',',@_) } );
  }

  ###  Catch $SIG{DIE} and send it to throw_error()
  $SIG{__DIE__} = \&my_sig_die;
};


#########################
###  Error Handling Functions

sub do_error {
  local $_;
  my $self = shift;
  my ( $errno, $details ) = @_;
  
  require Dave::ErrorSystem::Instance;

  ###  Reset the PID error count if our PID has changed (by fork or something)
  $PID_ERROR_COUNT = 0 if ! defined $PID_ERROR_COUNT || $MY_PID != $$;
  $MY_PID = $$;
  ###  Increment the count, because this is a new error
  ###    The new error Instance read and stores this var
  $PID_ERROR_COUNT++;
  
  my $err_instance = Dave::ErrorSystem::Instance->new( $errno, $details, ($self->{'site'} || $self->{'reseller_code'}) );
  $err_instance->archive_error;
  $err_instance->send_notifications;

  ###  Check RaiseError thru our parents
  my $RaiseError = &check_RaiseError($self);

  ###  RaiseError ON : User Message and die()
  if ( $RaiseError ) {
    $err_instance->print_error_report;
    ###  For Non-Apache servers, print error splash to STDERR
    if ( ! $ENV{REQUEST_METHOD} ) {
      my $was = select STDERR;
      local $ENV{REQUEST_METHOD} = undef;
      $err_instance->print_error_report;
      select $was;
    }
    local $DOIN_A_DIE = 1;
    die $err_instance->die_message;
  }
  ###  RaiseError OFF : Add it to the error queue
  else {
    if ( $ENV{'REQUEST_METHOD'} 
         ) { bug "RaiseError OFF, delay error $errno at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2]. ", " . ( caller(1) )[1] . ' line ' . ( caller(1) )[2]; }
    else   { bugw "RaiseError OFF, delay error $errno at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2]. ", " . ( caller(1) )[1] . ' line ' . ( caller(1) )[2]; }
    $self->{'ErrorSystem_deferred'} ||= [];
    push @{ $self->{'ErrorSystem_deferred'} }, $err_instance->prepare_for_defer;
  }

  return;
}

sub check_RaiseError {
  my ( $self ) = @_;

  my $parent = $self;
  my @parents;
  while ( ( defined $parent ) && 
          ( UNIVERSAL::isa($parent, 'HASH') ) &&
          
          ###  Avoid Infinite Loops
          ( ! grep { ref $parent eq $_ } @parents )
          ) {
    push @parents, ref $parent;
    if ( $parent->{'RaiseError'} || ! exists $parent->{'RaiseError'} ) {
      return 1;
    }
    last unless $parent->{'parent'};
    $parent = $parent->{'parent'};
  }

  return 0;
}

sub do_silent_error {
  local $_;
  my $self = shift;
  my ( $errno, $details ) = @_;

  eval {
    require Dave::ErrorSystem::Instance;

    my $err_instance = Dave::ErrorSystem::Instance->new( $errno, $details, ($self->{'site'} || $self->{'reseller_code'}) );

    $err_instance->archive_error;
    $err_instance->send_notifications;
  };
  warn $@ if $@;

  return;
}

sub are_errors {
  local $_;
  my $self = shift;

  my $error_count = @{ $self->{'ErrorSystem_deferred'} || [] };
  if ( $error_count ) {
    if ( wantarray ) {
      return( map { $_->flat_array } @{ $self->{'ErrorSystem_deferred'} || [] } );
    }
    else { return $error_count }
  }

  return;
}

sub play_errors {
  my $self = shift;
  return unless UNIVERSAL::isa($self->{'ErrorSystem_deferred'}, 'ARRAY');

  ###  Throw each of the deferred errors (though the first will most likely die())
  foreach my $err_instance ( @{ $self->{'ErrorSystem_deferred'} } ) {
    $err_instance->print_error_report;
    ###  For Non-Apache servers, print error splash to STDERR
    if ( ! $ENV{REQUEST_METHOD} ) {
      my $was = select STDERR;
      local $ENV{REQUEST_METHOD} = undef;
      $err_instance->print_error_report;
      select $was;
    }
    local $DOIN_A_DIE = 1;
    ###  Clear the errors, after this we are done with them
    undef @{ $self->{'ErrorSystem_deferred'} };
    die $err_instance->die_message;
  }
}

sub grab_errors {
  my $self = shift;
  my ( $grab_from_obj ) = @_;
  return if ($self.'') eq ($grab_from_obj.''); # ignore grab from self
  return if ( $self->{'ErrorSystem_deferred'} && $grab_from_obj->{'ErrorSystem_deferred'} 
              && ($self->{'ErrorSystem_deferred'}.'') eq ($grab_from_obj->{'ErrorSystem_deferred'}.'')
              ); # ignore grab from linked objs
  return unless UNIVERSAL::isa($grab_from_obj->{'ErrorSystem_deferred'}, 'ARRAY');

  ###  Grab the errors from X object so someone can call play_errors on us
  $self->{'ErrorSystem_deferred'} ||= [];
  push @{ $self->{'ErrorSystem_deferred'} }, @{ $grab_from_obj->{'ErrorSystem_deferred'} };
  undef @{ $grab_from_obj->{'ErrorSystem_deferred'} };

  return;
}

sub play_or_grab_errors {
  my $self = shift;
  my ( $the_obj ) = @_;
  return 0 unless ref($the_obj);

  if ( $the_obj->can('are_errors') && $the_obj->are_errors ) {
    if ( &check_RaiseError($self) ) { bug "playing" if $SHOW_DEBUG::TRANS || $SHOW_DEBUG::ALL;  $the_obj->play_errors;          return 1; } # should never reach return
    else                         { bugs "grabbed" if $SHOW_DEBUG::TRANS || $SHOW_DEBUG::ALL;  $self->grab_errors( $the_obj ); return 1; } # should reach return
  }
  bugs "no errors" if $SHOW_DEBUG::TRANS || $SHOW_DEBUG::ALL;
  return( 0 ); # if no errors then returning 0 can be a signal not to do an "&& return"
}


#########################
###  Experimental Transaction-tied Try-Catch mechanism

my ( @ATTEMPT_OBJS, @CHECK_ATTEMPT_STACKS );

sub begin_attempt {
  START_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  my ( $self ) = shift;
  my ( $trans, $proxy_delta ) = @_;

  die "Invalid transaction object: $trans at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    if $trans && ! UNIVERSAL::can($trans, 'rollback') && ! UNIVERSAL::can($trans, 'AUTOLOAD');

  push @ATTEMPT_OBJS, [$self,$trans];

  ###  If ATTEMPT_SCOPE_CHECK, then enforce same-scope begin_attempt, attempt
  if ( $ATTEMPT_SCOPE_CHECK ) {
    $CHECK_ATTEMPT_STACKS[$#ATTEMPT_OBJS] = [ &attempt_stack($proxy_delta) ];
  }
  
  END_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  return Dave::ErrorSystem::AttemptScope->new($self, $#ATTEMPT_OBJS);
}

sub end_attempt {
  START_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  my ( $self ) = shift;
  my ( $obj_idx_to_delete ) = @_;

  warn "In end_attempt(), cleanup was already done"                      if $#ATTEMPT_OBJS == ($obj_idx_to_delete - 1);
  warn "In end_attempt(), cleanup was more than done"                    if $#ATTEMPT_OBJS <  ($obj_idx_to_delete - 1);
  warn "In end_attempt(), cleanup hadn't happened for previous scope(s)" if $#ATTEMPT_OBJS >   $obj_idx_to_delete;
  bugsw [ [ map {["$ATTEMPT_OBJS[$_][0]", "$ATTEMPT_OBJS[$_][1]"]} (0..$#ATTEMPT_OBJS) ], $obj_idx_to_delete ] if $#ATTEMPT_OBJS != $obj_idx_to_delete;
  splice( @ATTEMPT_OBJS, $obj_idx_to_delete)         unless $obj_idx_to_delete > $#ATTEMPT_OBJS;
  splice( @CHECK_ATTEMPT_STACKS, $obj_idx_to_delete) unless $obj_idx_to_delete > $#CHECK_ATTEMPT_STACKS || !$ATTEMPT_SCOPE_CHECK;
  
  END_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  return 1;
}

sub attempt_stack {
  my ( $proxy_delta ) = @_;
  $proxy_delta ||= 0;

  my @new_attempt_stack = ();
  my $i = ( -1
            + 1 # for us, this attempt_stack() subroutine
            + 1 # for our caller since we *should* ONLY be called by another ErrorSystem sub
            + $proxy_delta # for any subroutines acting as proxy for the real $self
            );
  unshift @new_attempt_stack, (caller($i))[3] while ( caller(++$i) );
  
  return @new_attempt_stack;
}

sub attempt($*$@) {
  START_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  START_TIMER ErrorSystem_attempt if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  my ( $obj, $method, $params, @subs ) = @_;

  if ( $ATTEMPT_SCOPE_CHECK ) {
    my $new_as = [ &attempt_stack() ];
    my $chk_as = $CHECK_ATTEMPT_STACKS[$#ATTEMPT_OBJS];
#    bug [$chk_as, $new_as];
    die "Can't use attempt without first calling begin_attempt in the same scope at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
      unless ( $ATTEMPT_SCOPE_CHECK
               && $chk_as
               ###  Stacks are the same length, or...
               && ( (@$chk_as == @$new_as)
                    ###  Allow 1-off if subs are in the same package
                    || ( ((@$chk_as + 1) == @$new_as)
                         && ( $new_as->[-1] eq '(eval)'
                              || &pkg_part($chk_as->[-1]) eq &pkg_part($new_as->[-1])
                              )
                         )
                    )
               ###  Make sure that at least up to the check stack, the stacks are the same
               && ( ! grep { $chk_as->[$_] ne $new_as->[$_] } (0..$#{ $chk_as }) )
               );
  }
  my ($self, $my_savepoint) = @{ $ATTEMPT_OBJS[-1] };

  ###  Method comes fully qualified (Dave::Package::method), 
  ###    Strip off the leader...
  $method =~ s/^.+\://g;

  ###  Check out the object
  die "Can't call method \"$method\" on an undefined value at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless defined $obj;
  die "Can't locate object method \"$method\" via package \"$obj\" (perhaps you forgot to load \"$obj\"?) at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless ref $obj || UNIVERSAL::can($obj, $method);
  die "Can't call method \"$method\" on unblessed reference at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless UNIVERSAL::can($obj, 'can');
  ###  Check out the method
  die "Can't locate object method \"$method\" via package \"".(ref($obj) || $obj)."\" at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless $obj->can($method);
  ###  Check out the params
  die "Type of arg 3 to Dave::ErrorSystem::attempt must be scalar array ref, got it? :-D at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless UNIVERSAL::isa($params, 'ARRAY');
  ###  Check out the subs params
  foreach my $i ( 0..@subs ) {
    if ( ($i%2) == 0 && ref($subs[$i]) ) {
      die "Type of arg ".($i+4)." to Dave::ErrorSystem::attempt must be a subroutine name, perfectly clear? :-D at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n";
    }
    elsif ( UNIVERSAL::isa($params, 'CODE') ) {
      die "Type of arg ".($i+4)." to Dave::ErrorSystem::attempt must be a block or sub {}, make sense? :-D at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n";
    }
  }
  my %subs = @subs;

  ###  Run the method, if it dies, trap it 
  my ($rv, $success, $dollar_at);
  my $use_dbi_errstr_for_success_check = (ref($obj) && ref($obj) =~ /DB[ID]/ && ! $DBI::errstr); # only use DBI if there isn't alrady an error
  my $wantarray = wantarray;
  ;{
    ###  Only set RaiseError off for objects that
    ###    appear to be @ISA ErrorSystem (have do_error method)
    local $obj->{'RaiseError'} = 0 if UNIVERSAL::isa($obj, 'HASH') && $obj->can('do_error'); #
    
    eval {
      PAUSE_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
      PAUSE_TIMER ErrorSystem_attempt if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
#      bugs [$obj.'', $method.'', [ map {$_.''} @$params ] ];
      if ( $wantarray ) { $rv = []; @$rv = $obj->$method( @$params );  $success = $rv->[0]; }
      else              {            $rv = $obj->$method( @$params );  $success = $rv; }
      RESUME_TIMER ErrorSystem_attempt if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
      RESUME_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
    };
  };
  ###  Catch die()
  if ( $@ ) {
    $dollar_at = $@;
    $success = 0;
  }
  ###  If no die caught, then...
  else {
    ###  Run a custom success_check
    if ( $subs{'success_check'} ) {
      $ATTEMPT::errstr = ''; # to allow people to preserve this and signal failure
      $success = &{ $subs{'success_check'} }( wantarray ? (@$rv) : $rv );
      $success = 0 if $ATTEMPT::errstr;
    }
    ###  DBI Shortcut Helper Code: $DBI::errstr = ! success
    elsif ( $use_dbi_errstr_for_success_check ) {
      if ( $DBI::errstr ) {
        $success = 0;
        $ATTEMPT::errstr = $DBI::errstr; # protect because savepoint->rollback will surely change it
      }
      ###  Use the Perl-standard "If list context, check for > 0 entries"
      ###    This means that an array of (0) or even (undef) would qualify 
      ###    as a successful return
      else { $success = ( $wantarray ? ( @$rv ) : $rv); }
    }
  }

  ###  Check success
  if ( ! $success ) {
    if ( $subs{'failure'} ) {
      &{ $subs{'failure'} }( wantarray ? (@$rv) : $rv );
    }
    $my_savepoint->rollback if $my_savepoint;

    ###  Grab errors from object
    my $grab_from_object;
    if ( $subs{'grab_from_object'} ) {
      &{ $subs{'grab_from_object'} }( wantarray ? (@$rv) : $rv );
    }
    $grab_from_object ||= $obj;
    $self->play_or_grab_errors($obj) && return;

    if ( $dollar_at ) {
      ###  Make it appear as if the error really happened on their line
      $dollar_at =~ s@ at \S*/Dave/modules/Dave/ErrorSystem\.pm line \d+.\n$@" at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"@eg;
      die $dollar_at;
    }
    ###  If failed, but no die...
    if ( $subs{'no_die_failure'} ) {
      return &{ $subs{'no_die_failure'} }( wantarray ? (@$rv) : $rv );
    }
    return; # return false
  }
  
  END_TIMER ErrorSystem_attempt if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  END_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  return( wantarray ? (@$rv) : $rv);
}
sub success_check(&)    { ('success_check'   ,$_[0]); }
sub failure(&)          { ('failure'         ,$_[0]); }
sub no_die_failure(&)   { ('no_die_failure'  ,$_[0]); }
sub grab_from_object(&) { ('grab_from_object',$_[0]); }

sub pkg_part { return( ($_[0] =~ /^(.+?)\:\:\w+$/)[0] ); }

#########################
###  Non Object-Oriented Functions

sub throw_error {
  bless( { RaiseError => 1 }, __PACKAGE__ )->do_error( @_ );
}

sub throw_silent_error {
  bless( { RaiseError => 1 }, __PACKAGE__ )->do_silent_error( @_ );
}

sub archive_error_dir {
  my ( $epoch_timestamp, $errno ) = @_;
    
  &archive_day_dir($epoch_timestamp) ."/". $errno;
}

sub archive_day_dir {
  my ( $epoch_timestamp ) = @_;

  local $ENV{TZ} = $ERROR_SYSTEM_TZ;
  my $day = ((localtime($epoch_timestamp))[5] + 1900).'-'.sprintf("%.2d",(localtime($epoch_timestamp))[4] + 1).'-'.sprintf("%.2d",(localtime($epoch_timestamp))[3]);
  return "$ERROR_RECORD_BASE/$day";
}

#########################
###  AttemptScope to allow pass-out-of-scope cleanup of scope cache

###  Without pass-out-of-scope level cleanup, there is NO Guaranteed
###    way to make sure that we don't hold onto references to objects
###    and transactions that otherwise would have passed out of scope
###    cleaned-up or done a rollback.

package Dave::ErrorSystem::AttemptScope;

use Dave::Bug qw(:common);

my $inc = 0;
my %linktable;

sub new {
  START_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  my $pkg = shift;
  my ( $self, $scope_stack ) = @_;
  my $key = $inc++;
  $linktable{ $key } = [ $self, $scope_stack ];
  
  ###  MOD_PERL Cleanup Handler 
  ###    or Non-MOD_PERL END block:
  ###    clean out shared objects
  $FIXUPHANDLER::TODO{'Process::Transaction::AttemptScope::linktable'} ||=
    ###  DESTROY before deleting because Transactions can and do refer to each other
    sub { $linktable{$_}->DESTROY foreach (grep {UNIVERSAL::can($linktable{$_}, 'can')} keys %linktable);
          delete $linktable{$_}   foreach (keys %linktable);
        };
  
  END_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  return bless { key => $key }, $pkg;
}

sub DESTROY {
  START_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  $linktable{ $_[0]->{'key'} }[0]->end_attempt($linktable{ $_[0]->{'key'} }[1]);
  END_TIMER ErrorSystem_attemptsys if $SHOW_DEBUG::ES_ATTEMPT_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
}

1;


__END__


=head1 NAME

Dave::ErrorSystem - Central Error Handling/Archving system

=head1 SYNOPSIS

    use Dave::ErrorSystem qw(:oo_methods);

    sub mymethod {
      my $self = shift;
      
      # ...

      if ( $somethingbadhappened ) {
        return $self->do_error( 892, { detail_one => $detail_one, 
                                       detail_two => $detail_two 
                                       } );
        # if $self->{'RaiseError'} was off then the above return()
        # returns undef or empty list, otherwise, die() will be called 
      }
      elsif ( $somethingelsehappened ) {
        $self->do_silent_error( 892, { detail_one => $detail_one, 
                                       detail_two => $detail_two 
                                       } );
        &do_more_stuff();
      }

      return 1;
    }

    package OtherPackage;

    sub thecallingmethod {
      
      local $aboveexample->{'RaiseError'} = 0;
      my $result = $aboveexample->mymethod();

      if ( (! $result) 
           || ($aboveexample->are_errors) 
           ) {
        &clean_up_some_other_stuff();
        &rollback_other_stuff;

        return $aboveexample->play_errors;
        # this should die (we know because we checked are_errors)
      }
    }


    #########################
    ###  Attempt and Process::Transaction example:

    ###  Set a savepoint (like in Oracle, or PostgreSQL, these nest as well)
    my $transaction_obj = Process::Transaction->new;  # using a lib I wrote
    $self->begin_attempt( $transaction_obj ); # pass the trans object to ErrorSystem

    my $rv =
      attempt $someobj, do_something_method, ['param 1','param 2'],
      no_die_failure { die Exception->new(); } # it would automagically call $transaction_obj
      or return; 
    ###  We know it's success here...

    ###  Add a "roll this back" item
    $transaction->add_rollback_item( $someobj, 'undo_something_method', ['param 1','param 2']);

    ...

    if ( $whatever_went_wrong ) {
        die "The Message"; # when $transaction_obj passes out of scope ->rollback will be called
                           # which will call $someobj->undo_something_method('param 1','param 2')
    }

    ###  No more rolling back
    $transaction_obj->commit;

=head1 ABSTRACT

=over 4

This library was created to accomplish these tasks:

        1) Be able to report errors to the user in a uniform manner

        2) Report the occurrence of configured errors to the
           proper developer or admin.

        3) Record error details in an archive for liability
           purposes and problem tracking.  Archives can also be
           used by CRM people as they are searchable
           representations of problems actual customers are
           seeing.

        4) Allow developers to write failure-tolerant code by
           using RaiseError on any library using ErrorSystem

        5) Ability to detect an error has happened, clean up some
           things and then throw the error out to be viewed by
           the user.

Reasons for "attempt" system:

        0) I guess the main goal is to implement die()-less error
           handling using the RaiseError style.

        1) In most cases you should be checking return values because:

           a) There are really 3 case in any function call:
              Success, Failure with Exception and Failure without
              exception.

              Yes, failure with exception could just fall
              backward until it reaches a die(), but you still
              need to check for an empty response value.

       	2) A common sequence in try-catch syntax is:

             my $rv;
             try { $rv = $obj->meth( $param1, $param2) ); }
             catch {
               $transaction->rollback;
               die shift;
             }
             if ( ! $rv ) { die Exception->new(); }

           This is simplified by the attempt syntax:

             $self->begin_attempt( $self, $transaction );
             my $rv = 
               attempt $obj, meth, [ $param1, $param2 ],
               no_die_failure { die Exception->new(); };


=back

=head1 FUNCTIONS

=over 4

=item do_error()

Throw an error that will result in printing a page to user and a
call to die().  If you know what you are doing, the die() can be
caught by an eval().  The $@ will be parseable so you might be
able to handle cleanup after the error with some customization.

If $self->{'RaiseError'} is off then the error will be added to
the archive immediately, and any email notifications will be
sent, but the printing of the user message and the call to die()
will be deferred until play_errors() is called.

=item do_silent_error()

The error will be added to the archive, and email notifications
will be sent, but no user message will be shown or call to die().

=item are_errors()

In scalar context it returns 0 or the number of fatal errors in
queued to be thrown.  In list context it returns a stripped-down
listing of the details of the error to be thrown.  It is stripped
so the nested reference structure is flattened at only a couple
levels deep so that a Data::Dumper of the object will be
guaranteed to not be Humongous.  This is good for adding to the
details of another error throw.

=item play_errors()

This does the displaying of the user message as well as calling
die() for do_error calls that were prevented from doing it
because of a RaiseError setting.  If there are no errors then
nothing is done, and die() is not called, so be sure to check for
the existence of errors using are_errors() first.

=back

=head1 DEPENDENCIES

This module loads these libs when needed:

=over 4

    Data::Dumper
    Dave::Bug
    Dave::ErrorSystem::Instance
    Dave::Global

=back
