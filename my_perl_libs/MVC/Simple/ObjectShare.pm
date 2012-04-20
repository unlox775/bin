package MVC::Simple::ObjectShare;

#########################
###  MVC::Simple/ObjectShare.pm 
###  Version : $Id: ObjectShare.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Lib for common object sharing
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

###  Object Sharing Config
my %obj_types = ( 'MVC::Simple' => 'mvc',
                  'MVC::Simple::Template' => 'template',
#                   'MVC::Simple::Web::XMLBridge' => 'xmlbridge',
#                   'MVC::Simple::Web::Context' => 'context',
                  );

our %last_requests_dbhs;
our %stashes;

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
    require MVC::Simple;
#     require MVC::Simple::OrderSystem;
#     require MVC::Simple::Web;
#     require MVC::Simple::Web::PageSystem;
#     require MVC::Simple::Web::Template;
#     require MVC::Simple::Web::XMLBridge;
#     require MVC::Simple::Web::Context;
  }
}


#########################
###  Object Sharing

sub our_shared_object {
  my $self = shift;
  my ( $key ) = @_;
  return( $stashes{ $self->{'shared_objs'}{'key'} }{ $key } )
    if $self->{'shared_objs'} && $stashes{ $self->{'shared_objs'}{'key'} }{ $key };

  $self->set_my_obj_type unless $self->{'obj_type'};

  ###  Return either our object or a new one
  $self->{'shared_objs'} ||= MVC::Simple::ObjectShare::stash->new;
  unless ( $stashes{ $self->{'shared_objs'}{'key'} }{ $key } ) {
    my $method = "_new_$key";
    if ( ! $self->can($method) ) { BUGS;  die "_new_<key> method not defined for label: $key"; }
    $stashes{ $self->{'shared_objs'}{'key'} }{ $key } = $self->$method();
    if ( $stashes{ $self->{'shared_objs'}{'key'} }{$key}->isa('MVC::Simple::ObjectShare') ) {
      $stashes{ $self->{'shared_objs'}{'key'} }{$key}{'obj_type'} = $key;
      $stashes{ $self->{'shared_objs'}{'key'} }{$key}{'shared_objs'} = $self->{'shared_objs'};
    }
  }

  $stashes{ $self->{'shared_objs'}{'key'} }{$key};
}

###  When the obj_type is not defined, then try to figure it out...
sub set_my_obj_type {
  my $self = shift;

  ###  Go through the different obj types and check ->isa
  foreach my $isa_exp ( keys %obj_types ) {
    my ( $isa, $check_key, $check_val ) = ( $isa_exp =~ /^([\w\:]+)(?:\;(\w+)\=(.+?))?$/ );
    die "Bad syntax of \%obj_types key in MVC::Simple::ObjectShare" unless $isa;
    if ( $self->isa( $isa )
         && ( ! $check_key
              || $self->{ $check_key } eq $check_val
              )
         ) {
      $self->{'obj_type'} = $obj_types{ $isa_exp };
      $self->{'shared_objs'} ||= MVC::Simple::ObjectShare::stash->new;
      $stashes{ $self->{'shared_objs'}{'key'} }{ $obj_types{ $isa_exp } } = $self;
      last;
    }
  }

  $self->{'obj_type'} ||= 'indefinate';
}

###  This is only necessary for objects that call other
###    shared objects in their new() constructor
sub join_object_share_pool {
  my $self = shift;
  my ( $other_obj ) = @_;
  
  ###  Grab their shared objects
  $other_obj->{'shared_objs'} ||= MVC::Simple::ObjectShare::stash->new;
  $self->{'shared_objs'} = $other_obj->{'shared_objs'};

  $self->set_my_obj_type;
}

sub our_mvc      { $_[0]->our_shared_object('mvc'); }
sub _new_mvc     { require MVC::Simple;  MVC::Simple->new( ); }
#sub _new_mvc     { require MVC::Simple;  MVC::Simple->new( $_[0]->{'system_id'}, { shared_objs => $_[0]->{'shared_objs'} } ); }

sub our_template      { $_[0]->our_shared_object('template'); }
sub _new_template     { require MVC::Simple::Template;  MVC::Simple::Template->new( $_[0]->our_mvc ); }

sub parent { return $_[0]->{'parent'}; }


#########################
###  Some Our-System specific object sharing

sub our_dbh { my $self = shift;  $self->our_mvc->our_dbh( @_ ); }


#########################
###  Object Shared Objs stash Package

package MVC::Simple::ObjectShare::stash;

my $inc = 0;

sub new {
  my $pkg = shift;
  my $key = $inc++;
  $MVC::Simple::ObjectShare::stashes{ $key } = {};

  ###  MOD_PERL Cleanup Handler 
  ###    or Non-MOD_PERL END block:
  ###    clean out shared objects
  $FIXUPHANDLER::TODO{'MVC::Simple::ObjectShare::stash'} ||= \&purge_stashes;
  
  return bless { key => $key }, $pkg;
}

sub add_to_stash {
  my $self = shift;
  my ( $key, $value ) = @_;
  
  $MVC::Simple::ObjectShare::stashes{ $self->{'key'} }{ $key } = $value;
}

sub delete_from_stash {
  my $self = shift;
  my ( $key ) = @_;
  
  delete $MVC::Simple::ObjectShare::stashes{ $self->{'key'} }{ $key };
}

###  Sadly this will never get called as just about every
###    object in %MVC::Simple::ObjectShare::stashes references me
###
###  Instead, see the FIXUPHANDLER::TODO in the new() method
###
# sub DESTROY {
#   &MVC::Simple::Bug::BUG( "Destroying stash object");
#   delete $MVC::Simple::ObjectShare::stashes{ $_[0]->{'key'} };
# }

###  Function to purge the objects in %MVC::Simple::ObjectShare::stashes
###    before every request in the PerlFixUpHandler
sub purge_stashes {
  my ($key, $no_DESTROY) = @_;
  $no_DESTROY ||= [];

  ###  Use the passed key or purge everything
  my @keys = ( defined( $key )
               ? ($key)
               : (keys %MVC::Simple::ObjectShare::stashes)
               );

  ###  Now, reset the stash
#  &MVC::Simple::Bug::BUG("Destroying stashes objects");
  foreach my $key ( @keys ) {
    ###  Call DESTROY on any objects we can
    foreach my $obj_label ( keys %{ $MVC::Simple::ObjectShare::stashes{ $key } } ) {
      my $obj = $MVC::Simple::ObjectShare::stashes{ $key }{ $obj_label };
#      &MVC::Simple::Bug::BUG("Destroying $obj");
      $obj->DESTROY if ( ref($obj) && ($obj.'') =~ /=/ && $obj->can('DESTROY')
                         && ! grep {$_ eq ref($obj)} @$no_DESTROY
                         );
    }
    delete $MVC::Simple::ObjectShare::stashes{$key};
  }
}


1;
