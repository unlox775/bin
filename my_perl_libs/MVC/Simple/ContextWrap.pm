package MVC::Simple::ContextWrap;

#########################
###  Dave/Template::ContextWrap.pm 
###  Version : $Id: ContextWrap.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Object Wrapping for Context Implementation and Security
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use vars qw($AUTOLOAD);

###  Exporter Parameters
use Exporter;
use vars qw( @ISA @EXPORT_OK );
@ISA = ('Exporter');

###  Define the Exported Symbols
@EXPORT_OK = qw( &wrap_all_objects
                 );


#########################
###  Constructor

sub new {
  my $pkg = shift;

  ###  Disallow hacking obj calls to new()
  die "Access denied to method ". ref($pkg) ."->new called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    if ref( $pkg );

  my %tieme;
  tie(%tieme, 'MVC::Simple::ContextWrap::secure', @_);
  bless( \%tieme, $pkg);
}


#########################
###  Method Hook

sub can {
#  my $self = shift;
#  my ( $sub_name ) = @_;
  return 0;
#
#  return 1 if $sub_name eq 'AUTOLOAD';
#
#  my $secure = tied(%$self);
#  return unless $secure;
#  my $obj = $secure->obj;
#  return $obj->can($sub_name);
}

sub isa {
  my $self = shift;
  my ( $isa_what ) = @_;

  my $secure = tied(%$self);
  return unless $secure;
  my $obj = $secure->obj;
  return $obj->isa($isa_what);
}

sub AUTOLOAD {
  my $self = shift;
  
  ###  Only OO Please...
  die "Undefined subroutine \&$AUTOLOAD called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    unless ref( $self ) eq __PACKAGE__; # note we are also disallowing PolyMorphism

  my ( $sub_name ) = ( $AUTOLOAD =~ /([^:]+)$/ );
  return if $sub_name eq 'DESTROY';

  my $secure = tied(%$self);
  return unless $secure;
  my $obj = $secure->obj;

  ###  Answer "No!" to calls for undefined methods
  if ( $sub_name ne 'DESTROY'
       && ! $obj->can($sub_name)
       && ! $obj->can($sub_name.'_cx')
       ) {
    ###  Template toolkit looks for this syntax die in order
    ###    to switch to calling hash keys
    die "Can't locate object method \"$sub_name\" via package \"". ref($self) ."\" (a wrapped \"". ref($obj) ."\" object) at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n";
  }

  ###  If the Object has this method...
  if ( $obj->can('context_wrap_ok')
       && $obj->context_wrap_ok->{ $sub_name }
       ) {
    ###  If the sub has it's own context-specific sub...
    my $call_sub = $sub_name;
    if ( $obj->context_wrap_ok->{ $sub_name } == 2 ) {
      $call_sub = $sub_name.'_cx';
    }
    die "Undefined subroutine \&$call_sub called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
      unless $obj->can($call_sub);

    ###  Run the sub in the right context
    local $obj->{'ContextWrap_context'} = $secure->{'context'};
    ###  NOTE TO THE WEARY TRAVELER/CODER : If you are getting a "not a CODE reference"
    ###    type error from the below lines, just try restarting your webserver.  I think
    ###    it's due to a subroutine that was erased, and Apache::Reload messes it up...
    if ( wantarray ) {
      my $res = eval { [ $obj->$call_sub( @_ ) ]; };
      ###  Dies because of not locating an object method after this point *should NOT* be
      ###    captured by Template Toolkit and forgotten
      if ($@) { $_ = $@;  s/Can\'t locate object method/can\'t locate object method/g;  die $_; }
      return @{ ${ &wrap_all_objects(\$res, $secure->{'context'}) } };
    }
    else {
      my $res = eval { $obj->$call_sub( @_ ); };
      ###  Dies because of not locating an object method after this point *should NOT* be
      ###    captured by Template Toolkit and forgotten
      if ($@) { $_ = $@;  s/Can\'t locate object method/can\'t locate object method/g;  die $_; }
      return ${ &wrap_all_objects(\$res, $secure->{'context'}) };
    }
  }

  ###  Otherwise, access denied...
  if ( $sub_name ne 'DESTROY' ) {
    die "Access denied to method ". ref($obj) ."->$sub_name called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n";
  }
}

sub wrap_all_objects {
  my ( $ref_ref, $context, $seen ) = @_;
  $seen ||= [];

  ###  Disallow hacking obj calls to new()
  die "Access denied to method ". ref($ref_ref) ."->wrap_all_objects called at " . ( caller(0) )[1] . ' line ' . ( caller(0) )[2] . ".\n"
    if UNIVERSAL::isa( $ref_ref, 'UNIVERSAL');

  return $ref_ref unless defined($$ref_ref);
  my $strobj = $$ref_ref.'';

  ###  Wrap if this ref is an object
  if ( UNIVERSAL::isa( $$ref_ref, 'UNIVERSAL')
       && substr($strobj, 0, 7) ne '(?-xism' # this is for qr// refs
       ) {
    return if ref($$ref_ref) eq 'MVC::Simple::ContextWrap';

    ###  This is the guts of new() at the top of this file...
    my %tieme;
    tie(%tieme, 'MVC::Simple::ContextWrap::secure', $$ref_ref, $context);
    $$ref_ref = bless( \%tieme, 'MVC::Simple::ContextWrap');

    ###  Don't descend into object's sub-structures:
    ###    The above FETCH() method will disallows direct key access
    ###    to sub-structures in the object.  Objects returned by
    ###    method calls will be wrapped by AUTOLOAD using this func.
  }
  ###  Descend into (non-object) sub-structures
  else {
    ###  Only wrap each obj once
    return if grep { $strobj eq $_ } @$seen;
    push @$seen, $strobj;

    ###  Types of refs
    if ( UNIVERSAL::isa( $$ref_ref, 'ARRAY') ) {
      foreach my $i ( 0 .. $#{ $$ref_ref } ) {
        &wrap_all_objects( \$$ref_ref->[$i], $context, $seen )     if ref $$ref_ref->[$i];
      }
    }
    elsif ( UNIVERSAL::isa( $$ref_ref, 'HASH') ) {
      foreach my $key ( keys %$$ref_ref ) {
        &wrap_all_objects( \$$ref_ref->{ $key }, $context, $seen ) if ref $$ref_ref->{ $key };
      }
    }
    elsif ( UNIVERSAL::isa( $$ref_ref, 'SCALAR') ) {
      &wrap_all_objects( \$$$ref_ref, $context, $seen )            if ref $$$ref_ref;
    }
  }

  $ref_ref;
}


#########################
###  Secure layer for the Tied Hash

package MVC::Simple::ContextWrap::secure;
use Dave::Bug qw(:common);

sub TIEHASH {
  my $pkg = shift;
  my ( $obj, $context, $local_vars ) = @_;
  $local_vars ||= {};

  if ( UNIVERSAL::isa($obj, 'ARRAY') ) {
    return bless( {call_me => $obj, context => $context, data => $local_vars}, $pkg );
  }
  my $self = bless( {obj => $obj, context => $context, data => $local_vars}, $pkg );
  die "Wrapped object must be a hash ref" unless UNIVERSAL::isa( $self->{'obj'}, 'HASH');
  return $self;
}

sub obj {
  my $self = shift;
  return $self->{'obj'} unless $self->{'call_me'};

  my ( $obj, $method, $params ) = @{ $self->{'call_me'} };
  $self->{'obj'} = $obj->$method(@{$params || []});
  die "Wrapped object must be a hash ref" unless UNIVERSAL::isa( $self->{'obj'}, 'HASH');

  ###  If not even an object, kludge it.  Now it is like a secured hashref
  ###    Nobody can actually edit the hash and it is safe to expose
  $self->{'obj'} = bless { %{ $self->{'obj'} } }, 'UNIVERSAL' unless UNIVERSAL::can($self->{'obj'},'can');

  delete $self->{'call_me'};

  $self->{'obj'};
}

###  The tie suite
sub FETCH    { return $_[0]->{'data'}{ $_[1] } if exists $_[0]->{'data'}{ $_[1] };  my $obj = $_[0]->obj;  return( ref($obj->{$_[1]}) ? undef : $obj->{$_[1]}); }
sub FIRSTKEY { my $obj = $_[0]->obj;  keys %$obj;  each %$obj; }
sub NEXTKEY  { each %{$_[0]->obj}; }
sub EXISTS   { exists $_[0]->obj->{$_[0]}; }
sub STORE    { $_[0]->{'data'}{ $_[1] } = $_[2]; }
sub DELETE   { delete $_[0]->{'data'}{ $_[1] }; }
sub CLEAR    { %{ $_[0]->{'data'} } = (); }

1;


__END__


=head1 NAME

MVC::Simple::ContextWrap - Object Wrapping for Context Implementation and Security

=head1 SYNOPSIS

    use MVC::Simple::ContextWrap qw( &wrap_all_objects );

    my $w_obj         = MVC::Simple::ContextWrap->new($self->our_ptree,     $context_obj);
    my $w_delayed_obj = MVC::Simple::ContextWrap->new([$self, 'our_ptree'], $context_obj);

    ###  Recursively find and wrap all objects in a structure
    &wrap_all_objects(\$vals, $context_obj);

=head1 ABSTRACT

=over 4

The 2 main purposes of this library are 1) Context Implementation
and 2) Security of system elements from the Template Toolkit
parse environment.

The entire ODYC system has been architected to be able to handle
language overriding and customization by user preference.
Individual calls like Dave::ProductTree::Item->get_content() can
be called and passed a language code, but how to make All calls
to get_content in a web page parse pass the right language code
in the expanded calling syntax.  And how to do that without
unneccessary DB overhead like pre-fetching All values in the
proper language.

Also I wanted to hand a lot of the power to access objects to the
Template creators rather than making the page handler or CGI
pre-assemble All the values that the page parse could want into
swaps before the page parse is called.

The next purpose is Security.  If I'm going to be sticking
objects into Template Toolkit's reach, there is the potential for
layout creators calling obj->delete() on some objects that would
oblige.  Template Toolkit allows FULL object access to all
objects that are passed to it in the Vars.  There is only one
perl construct which I could see would be able to secure away the
object: tie(); As far as I can see there is no way for Template
Toolkit directives to call tied() on a symbol in one of it's
namespaces.  We will have to make SURE that that continues to be
the case.

To secure an object in the swaps, for example, [%swap.item_obj%],
the key $vars->{swap}{item_obj} is changed to a new hashref which
is blessed into the MVC::Simple::ContextWrap class, and also
tie()'d to the MVC::Simple::ContextWrap::secure package.  The
object that was referenced in $vars->{swap}{item_obj} is stored
in the MVC::Simple::ContextWrap::secure object.  Thus the only
way to get to the actual object is to call:

        tied($vars->{swap}{item_obj})->{'obj'}

Method calls to $vars->{swap}{item_obj}->methodname() are handled
by MVC::Simple::ContextWrap->AUTOLOAD which calls the method
on the hidden actual object, and runs &wrap_all_objects on the
return value.  This makes sure that new objects returned by
methods are also wrapped.

Fetch of hash keys like $vars->{swap}{item_obj}->{item_id} are
handled by MVC::Simple::ContextWrap::secure->FETCH.  For good
reasons, FETCH restricts to only non-ref (!ref()) keys.  I do not
recommend storing objects inside of objects whenever possible,
and when they must be I will create a method to access it rather
than letting people directly access the key in my hash.  Access
is also restricted to non-object refs stored as keys of your
object because we can't secure sub-structures without modifying
the actual object.  Deep issues here, if you want more detail,
ask Dave.

The main reason for hiding away the actual object is so that we
can impose method-level access permissions.  By default through
ContextWrap, calling any method will result an error like this:

        Access denied to method <package>-><method> called at <source> line <linenumber>.

Access to individual methods for Object X can be added by adding
a method X->context_wrap_ok which returns a hashref where the
keys are method names and the values are either 1 or 2.  A value
of 1 means basic access.  A value of 2 means that the method has
an in-context method defined to handle calls when being called
through ContextWrap.  This method name is always <method>_cx.
The <method>_cx is NOT auto-detected, and must be explicitly be
flagged using the value 2.  Usually the <method>_cx method calls
the non-context-aware <method> after performing some checks.

With Every ContextWrap instantiation, the Dave::Context object is
included so that method calls can have access to it.  Because we
don't want to change the calling syntax of methods just to be
in-context, the Dave::Context object is passed by locally setting
$obj->{ContextWrap_context} just before the method call is made.
Thus methods do not Need to create an _cx version to be
context-aware, and can easily check if they are in context by
checking for the existence of $self->{ContextWrap_context}.

=back

=head1 FUNCTIONS

=item new()

You pass the object that you want wrapped, and the Dave::Context
object.

Another cool feature: you pass an arrayref as the first
parameter, where the first item is an object, the second is a
method, and the third is an (optional) arrayref of arguments.
This will neatly delay the calling of the method until the object
is needed.  For objects in the system, a call to new() usually
triggers an database operation to check that item's existence.
Often in a Template Call, we make many many objects *available*
for the template to call when needed, but often most of the
objects passed in are not called, wasting the effort of their
instantiation.  In the above example, the [%ptree%] area is
wrapped with a delayed method call.  The first time the template
calls [%ptree.<method>%], ContextWrap runs the method call once
and caches the object.  From that point on it is *exactly* the
same as if an Dave::Ecom::ProductTree item was passed into
ContextWrap->new().  But, if the template did not ever call
[%ptree.<method>%], then the only thing wasted was a few internal
structure creations.

=item wrap_all_objects()

This function is called passing a scalar ref of the structure you
want crawled, and an Dave::Context object.  The structure is
crawled through scalar refs, arrayrefs and hashrefs.  When an
object ref is encountered it is wrapped and tied and the parent
synbol is modified.  That is why a scalar ref is passed in every
call.  Also, when an object ref is encountered, crawling of that
key is stopped, we do NOT crawl into the object's structure.  See
the above security notes on how object's sub-structure is secured.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug

=back
