package Session::Simple;

#########################
###  Session/Simple.pm
###  Version: $Id: Simple.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  A lightweight alternative to Apache::Session
#########################

use strict;

#########################
###  Package Config

use File::Path;
use File::NFSLock;
use Storable qw(&retrieve &nstore);  $Storable::forgive_me = 1;


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $prefs ) = @_;
  return &do_error($prefs, "Syntax: Session::Simple->new({filename => \$filename})")
    unless UNIVERSAL::isa($prefs, 'HASH') && $prefs->{'filename'};

  ###  Further Syntax checking
  foreach my $key ( CORE::keys %$prefs ) {
    if ( ! grep { $key eq $_ } qw(filename read_only do_mkpath blocking_timeout stale_lock_timeout) ) {
      return &do_error($prefs, "Syntax: Session::Simple->new({filename => \$filename}), illegal param: $key");
    }
  }

  ###  Create Self
  my %defaults = ( RaiseError         => 1,
                   read_only          => 0,
                   do_mkpath          => 0,
                   blocking_timeout   => 60,        # default: 60 sec
                   stale_lock_timeout => (30 * 60), # default: 30 min
                   );
  my $self = bless( {%defaults, %$prefs}, $pkg );

  ###  If file exists, can we write to it?
  stat($self->{'filename'});
  if ( -e _ ) {
    if ( ! -r _ ) { return $self->do_error("Could not create session, file exists but is not readable: ". $self->{'filename'}); }
    elsif ( ! $self->{'read_only'} && ! -w _ ) { return $self->do_error("Could not create write-access session, file exists and is not writable: ". $self->{'filename'}); }
    $self->{'file_exists'} = 1;
  }
  
  ###  Check out the dir filename is in
  ###    NOTE: with any options we still need to
  ###    have write access to use File::NFSLock
  my ( $dir, $filename ) = ( $self->{'filename'} =~ m@^(.*?)([^/]+)$@ );
  $dir = './' unless defined $dir && length $dir;
  stat($dir);
  ###  Exists
  if ( ! $self->{'file_exists'} && ! -d _ ) {
    if ( -e _ ) { return $self->do_error("Could not create session, error creating directory: file exists"); }
    elsif ( $self->{'do_mkpath'} ) {
      my $num = eval { mkpath( $dir ); };
      my $err = ($@ || $!);
      stat($dir);
      if ( ! -d _ ) { return $self->do_error("Could not create session, error creating directory: $err ($num)"); }
    }
    else { return $self->do_error("Could not create session, directory does not exist: $dir"); }
  }
  ###  Writable
  if ( ! -w _ ) { return $self->do_error("Could not create session, directory does not exist: $dir"); }

  ###  If NOT read_only, then get a write_lock so
  ###    only 1 write-access session can exists at one time
  if ( ! $self->{'read_only'} ) {
    $self->get_write_lock;
  }

  return $self;
}
sub do_mkpath          { $_[0]->{'do_mkpath'} }
sub blocking_timeout   { $_[0]->{'blocking_timeout'} }
sub stale_lock_timeout { $_[0]->{'stale_lock_timeout'} }


#########################
###  Internal Session File Access and Lock Methods

sub read_data {
  my $self = shift;

  ###  If file doesn't exist
  if ( ! $self->{'file_exists'} ) {
    $self->{'data'} = {};
    return 1;
  }

  $self->get_access_lock('SHARED') or return;

  ###  Read in the data
  $self->{'data'} = eval { retrieve($self->{'filename'}); };
  my $err = ($@ || $!);
  if ( ! defined $self->{'data'} ) { return $self->do_error("Storable Error while reading data: $err", 1); }
  if ( ! UNIVERSAL::isa( $self->{'data'}, 'HASH') ) { return $self->do_error("Error in read_data: storable retrieved a non-HASH strcture: ". $self->{'data'},1); }

  $self->release_access_lock;
  return 1;
}

sub write_data {
  my $self = shift;
  return $self->do_error("Error: attempt to write data when session is read_only", 1) if $self->{'read_only'};
  return 1 if ! $self->{'data'};

  $self->get_access_lock('BLOCKING') or return;

  ###  Write out the data
  my $success = eval { nstore($self->{'data'}, $self->{'filename'}); };
  my $err = ($@ || $!);
  if ( ! defined $success ) { return $self->do_error("Storable Error while writing data: $err", 1); }

  $self->{'file_exists'} = 1;

  $self->release_access_lock;
  return 1;
}

sub get_access_lock {
  my $self = shift;
  my ( $lock_type ) = @_;

  $self->{'access_lock'} =
    File::NFSLock->new( $self->{'filename'}, $lock_type, $self->{'blocking_timeout'}, $self->{'stale_lock_timeout'} )
  or return $self->do_error("Timeout while waiting for $lock_type access lock", 2);

  return 1;
}

sub release_access_lock {
  my $self = shift;
  return 1 unless $self->{'access_lock'};

  $self->{'access_lock'}->unlock;
  delete $self->{'access_lock'};
  
  return 1;
}

sub get_write_lock {
  my $self = shift;

  $self->{'write_lock'} =
    File::NFSLock->new( $self->{'filename'}.'.wlock', 'BLOCKING', $self->{'blocking_timeout'}, $self->{'stale_lock_timeout'} )
  or return $self->do_error("Timeout while waiting for BLOCKING write lock", 1);

  return 1;
}

sub release_write_lock {
  my $self = shift;
  return 1 unless $self->{'write_lock'};

  $self->{'write_lock'}->unlock;
  delete $self->{'write_lock'};
  
  return 1;
}


#########################
###  Deconstructor

our $DOING_DESTROY = 0;
sub DESTROY {
  my $self = shift;
  
  ###  Avoiding infinite loops...
  unless ( $DOING_DESTROY ) {
    local $DOING_DESTROY = 1;
    $self->release;
  }
}

sub release {
  my $self = shift;

  if ( $self->{'changed_data'}
       && ! $self->{'read_only'}
       ) {
    $self->write_data;
  }

  $self->release_access_lock;
  $self->release_write_lock;
}

sub delete {
  my $self = shift;
  return $self->do_error("Error: attempt to delete when session is read_only") if $self->{'read_only'};

  $self->release_access_lock;

  local $self->{'do_error_add_caller_depth'} = -1;
  $self->get_access_lock('BLOCKING') or return;

  ###  Delete the file
  unlink $self->{'filename'};
  if ( -e $self->{'filename'} ) { return $self->do_error("Error deleting session file: $!") }

  ###  Clear the session
  delete $self->{'file_exists'};
  delete $self->{'data'};

  $self->release_access_lock;
  return 1;
}


#########################
###  Session Manipulation Methods

sub keys {
  my $self = shift;
  $self->read_data unless $self->{'data'};

  return CORE::keys %{ $self->{'data'} };
}

sub exists {
  my $self = shift;
  my ( $key ) = @_;
  $self->read_data unless $self->{'data'};

  return CORE::exists $self->{'data'}{ $key };
}

sub get {
  my $self = shift;
  my ( $key ) = @_;
  $self->read_data unless $self->{'data'};

  return $self->{'data'}{ $key };
}

sub set {
  my $self = shift;
  my ( $key, $value ) = @_;
  return $self->do_error("Error: attempt to set when session is read_only") if $self->{'read_only'};
  $self->read_data unless $self->{'data'};

  $self->{'data'}{ $key } = $value;
  $self->{'changed_data'} = 1;

  return 1;
}

sub remove {
  my $self = shift;
  my ( $key ) = @_;
  return $self->do_error("Error: attempt to remove when session is read_only") if $self->{'read_only'};
  $self->read_data unless $self->{'data'};

  delete $self->{'data'}{ $key };
  $self->{'changed_data'} = 1;

  return 1;
}

sub clear {
  my $self = shift;
  return $self->do_error("Error: attempt to clear when session is read_only") if $self->{'read_only'};
  $self->read_data unless $self->{'data'};

  $self->{'data'} = {};
  $self->{'changed_data'} = 1;

  return 1;
}


#########################
###  Changing Modes

sub read_only {
  my $self = shift; 
  my ( $new_val ) = @_;
  return $self->{'read_only'} unless defined $new_val;

  ###  If setting to NOT read_only...
  if ( $self->{'read_only'} && ! $new_val ) {
    stat($self->{'filename'});
    if ( -e _ && ! -w _ ) { return $self->do_error("Could not create write-access session, file exists and is not writable: ". $self->{'filename'}); }
    $self->get_write_lock;
  }
  
  ###  If setting TO read_only...
  elsif ( ! $self->{'read_only'} && $new_val ) {
    $self->release;
  }

  $self->{'read_only'} = $new_val;;
  
  return 1;
}


#########################
###  Utility Methods

sub error { $_[0]->{'error'} }

###  Simple hack to check RaiseError and Raise Errors or not
sub do_error {
  my $self = shift;
  my ( $errmsg, $add_caller_depth ) = @_;
  $self = {} unless UNIVERSAL::isa($self, 'HASH');
  local $self->{'RaiseError'} = 1 unless exists $self->{'RaiseError'};

  $add_caller_depth += $self->{'do_error_add_caller_depth'} if $self->{'do_error_add_caller_depth'};

  if ( $self->{'RaiseError'} ) {
    die $errmsg .' at '. ( caller(1 + ($add_caller_depth || 0)) )[1] . ' line ' . ( caller(1 + ($add_caller_depth || 0)) )[2] . ".\n"
  }
  else {
    $self->{'error'} = $errmsg;
    return;
  }
}

1;
