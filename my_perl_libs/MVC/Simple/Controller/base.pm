package MVC::Simple::Controller::base;

#########################
###  Dave/OpSystem/base.pm
###  Version: $Id: base.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Base object for OpSystem Section objects
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::ErrorSystem qw(:oo_methods);

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
  }
}

###  Inheritance
use base qw( MVC::Simple::ObjectShare );


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $mvc, $hash ) = @_;
  $hash ||= {};

  my $self = bless( { mvc         => $mvc,
                      RaiseError   => 1,
                      %$hash,
                      },
                    $pkg);

  ###  Let them pass a mvc object or a mvc,
  ###    but set my mvc to the normalized one 
  ###    from a mvc object
  my $mvc_obj = ( ( UNIVERSAL::isa($self->{'mvc'}, 'MVC::Simple') )
                   ? $self->{'mvc'}
                   : $self->our_mvc
                   );
  $self->{'mvc'} = $mvc_obj->{'mvc'};
  $self->join_object_share_pool( $mvc_obj );

  return $self;
}


#########################
###  Selectively Shared Methods, using @selective_ISA

sub default_shell {
  my $self = shift;
  if ( $self->parent ) { return $self->parent->default_shell; }
  return 'default.html';
}
  
sub auth_check {
  my $self = shift;
  if ( $self->parent ) { return $self->parent->auth_check( @_ ); }
  return( 1, undef ); # success if not defined
}
  
sub snh_error {
  my $self = shift;
  if ( $self->parent ) { return $self->parent->snh_error( @_ ); }

  my ( $what, $details ) = @_;
  $self->do_error(119, { site => $self->{'site'}, what => $what, details => $details });
}


#########################
###  Utility Methods, shared but not @selective_ISA

sub parent {
  my $self = shift;
  no strict 'refs';
  my $var = ref($self).'::selective_ISA';
  return unless @{$var};
  $self->{'parent'} ||= $self->our_mvc->get_section_obj( ${$var}[0] );
  use strict 'refs';
  return $self->{'parent'};
}

sub get_shell {
  my $self = shift;
  my ( $page ) = @_;

  if ( $self->pages->{ $page } 
       && $self->pages->{ $page }{'shell'}
       ) {
    return $self->pages->{ $page }{'shell'};
  }
  return $self->default_shell;
}

sub pages {
  my $self = shift;
  return $self->{'pages'} if $self->{'pages'};

  my $pkg = ref($self);
  no strict 'refs';
  $self->{'pages'} = \ %{$pkg. '::pages'};
  use strict 'refs';
  return $self->{'pages'};
}

1;


__END__


=head1 NAME

MVC::Simple::Controller::base - Base object for OpSystem Section objects

=head1 SYNOPSIS

    use base qw( MVC::Simple::Controller::base );
    our @selective_ISA = qw( MyApp::admin );

    my $parent_section = $self->parent;
    my $undef_if_no_die = $self->snh_error("What should not have happened", {details => $details});
    my $pages = $self->pages;
    my $shell_url = $self->get_shell($page_name);
    my $default_shell_url = $self->default_shell;

=head1 ABSTRACT

=over 4

Thie main magic going on in this base library is the invented
idea of "Selective ISA".  The basic idea is that we want Some
methods to do normal ISA fallback, but not for all methods.
These section objects have tens or hundreds of methods specific
to handling page catch, pitch or page handlers, but the idea that
handlers in OpSystem/admin.pm should be used as valid handlers
for pages in /op/admin/products/<page>.tpl is not right.  But,
some methods like snh_error and default_shell we would really
like to act like traditional ISA, so that admin.pm can have it's
own SNH error and it's own default shell differing from
reseller.pm's.

=back

=head1 FUNCTIONS

=over 4

=item parent()

This reads the @selective_ISA local list for $self and returns
the parent object.  Note, that this prohibits Multiple
Inheritance because we are saying that each opject has exactly 1
parent.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug
    Dave::ErrorSystem
    Dave::ObjectShareBySite

=back
