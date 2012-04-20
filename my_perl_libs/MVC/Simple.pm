package MVC::Simple;

#########################
###  MVC/Simple.pm
###  Version: $Id: Simple.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::Util qw( &taint_safe_env );
use Dave::ErrorSystem qw(:oo_methods);

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
#     require Dave::OpSystem::Request;
#     require Dave::Reseller;
#     require Dave::OpSystem::View;
# 
#     require Dave::OpSystem::base;
#     require Dave::OpSystem::root;
#     require Dave::OpSystem::admin;
#     require Dave::OpSystem::admin::account;
#     require Dave::OpSystem::admin::images;
#     require Dave::OpSystem::admin::orders;
#     require Dave::OpSystem::admin::products;
#     require Dave::OpSystem::admin::upgrade;
#     require Dave::OpSystem::admin::web_pages;
#     require Dave::OpSystem::reseller;

#    require Dave::OpSystem::odyc;
#    require Dave::OpSystem::odyc::mvc;
  }
}

use constant URL_BASE => '/';
use constant TEMPLATE_BASE => '/var/www/temlpates';

###  Inheritance
use base qw( MVC::Simple::ObjectShare );

###  List of methods ok to be called through Dave::Template::ContextWrap
sub context_wrap_ok { {
}; }


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $mvc ) = @_;

  my $self = bless( { mvc         => $mvc,
                      RaiseError   => 1,
                      },
                    $pkg);

#   ###  Let them pass a mvc object or a mvc,
#   ###    but set my mvc to the normalized one 
#   ###    from a mvc object
#   my $mvc_obj = ( ( UNIVERSAL::isa($self->{'mvc'}, 'Dave::Mvc') )
#                    ? $self->{'mvc'}
#                    : $self->our_mvc
#                    );
  $self->join_object_share_pool( $self );
  
  return $self;
}


#########################
###  Shared Methods

sub cgi_handler {
  my $pkg = shift;

  ###  From Dave::Util, enforce some things
  &taint_safe_env;

  my $q = CGI->new;
  ###  If this is a POST method, merge in URL params with POST params
  if ( $ENV{REQUEST_METHOD} eq 'POST' ) {
    $q->append(-name => $_, -values => [$q->url_param($_)]) foreach ( $q->url_param() );
  }
  my %FORM = $q->Vars;

  my $path = $ENV{SCRIPT_NAME}.$ENV{PATH_INFO};

  my $self = $pkg->new();

  my $mvc_req = $self->new_request($path, \%FORM);
  ###  Set the default content-type
  $mvc_req->{content_type} = 'text/html';

  my $success = eval { $mvc_req->serve_page; };
  my $errstr = $@;

  ###  Cleanup (release Session objects, etc.)
  $mvc_req->cleanup;

  ###  Continue and die() if we caught a die()
  if ( $errstr ) {
    local $Dave::ErrorSystem::DOIN_A_DIE = 1;
    &report_timers;
    die $errstr;
  }

  &report_timers;
}

sub get_shell_filename { 
  my $self = shift;
  my ( $shell ) = @_;

  return ( $self->can('SHELL_BASE')
           ? $self->SHELL_BASE.'/'.$shell
           : $self->TEMPLATE_BASE.'/shells/'.$shell
         );
}

sub get_template_filename { 
  my $self = shift;
  my ( $page ) = @_;

  return $self->TEMPLATE_BASE.'/'.$page;
}

sub new_request {
  my $self = shift;

  require MVC::Simple::Request;
  return MVC::Simple::Request->new( $self, @_ );
}

sub get_section_obj_by_uri {
  my $self = shift;
  my ( $uri ) = @_;

  ###  Parse out the lib
  my $URL_BASE = $self->URL_BASE;
  my ( $lib, $page ) = ( $uri =~ m@^\Q$URL_BASE\E(.*)/([^/]+)$@ );
  $page =~ s/\.\w+$//;
  (my $label = "MVC_Simple_".$lib) =~ s/\W/_/g;

  ###  If I don't have the object get one
  if ( ! $self->{"cached_${label}_obj"} ) {

    ###  Require the file
    my $baselib = ref $self;
    if ( ! $lib ) {
      $lib = $baselib . '::root';
      (my $test_libfile = "$lib.pm") =~ s@::@/@g;
      require $test_libfile;
    }
    else {
      $lib =~ s@/@::@g;
      $lib = $baselib . $lib;
      ###  IF onAlpha, Fallback thru parent directories
      ###  ELSE, require the library
      while ( $lib =~ /\:\:\w+$/ && $lib  ) {
        (my $test_libfile = "$lib.pm") =~ s@::@/@g;
        ###  If not &onAlpha, then no sloppiness or falling back
        if ( ! 1 ) {
          require $test_libfile;
          last;
        }
        ###  onAlpha, and not exists, try the parent directory
        else {
          eval { require $test_libfile; };
          if ( ! $@ ) {
            last;
          }
          elsif ( $@ && $@ !~ /^Can\'t locate .+? in \@INC \(\@INC contains/ ) {
            die "$@\n";
          }
          else { $lib =~ s/\:\:\w+$//g; }
        }
      }
    }

    ###  If the above loop gets down to the baselib, switch to root
    if ( $lib eq $baselib ) {
      $lib = $baselib . '::root';
      (my $test_libfile = "$lib.pm") =~ s@::@/@g;
      require $test_libfile;
    }

    ###  Get the object
    if ( UNIVERSAL::can($lib, "new") ) {
      my $section_obj = $lib->new( $self->our_mvc );

      ###  Add object to ObjectShare stash to prevent memory leaks
      $self->{'shared_objs'}->add_to_stash($label, $section_obj );
      $self->{"cached_${label}_obj"} = 1;
    }
    ###  If no new() method, then return undef
    else { return; }
  }

  return( wantarray ? ($self->our_shared_object($label), $page) : $self->our_shared_object($label) );
}

sub get_section_obj {
  my $self = shift;
  my ( $lib ) = @_;
  my $pkg = ref($self);
  $lib = "$pkg\::". $lib unless $lib =~ /^\Q$pkg\E::/ || $lib eq 'MVC::Simple::Controller::base';;

  ###  Label for identifying the shared object
  (my $label = $lib) =~ s/^Dave:://g;
  $label =~ s/(\:\:|\W)/_/g;

  ###  If I don't have the object get one
  if ( ! $self->{"cached_${label}_obj"} ) {
    ###  Load the library
    (my $libfile = "$lib.pm") =~ s@::@/@g;
    require $libfile;
    my $section_obj = $lib->new( $self->our_mvc );

    ###  Add object to ObjectShare stash to prevent memory leaks
    $self->{'shared_objs'}->add_to_stash($label, $section_obj );
    $self->{"cached_${label}_obj"} = 1;
  }

  return( $self->our_shared_object($label) );
}

1;


__END__


=head1 NAME

MVC::Simple - Library to handle all OpSystem related functions like template locations, and URI parsing

=head1 SYNOPSIS

    use MVC::Simple;
    my $opsys = MVC::Simple->new('foo.com');
    my $opsys = MVC::Simple->new($foo_com_mvc_obj);

    use base qw( MVC::Simple::ObjectShare );
    my $opsys = $self->our_opsys;

    ###  Get a request object
    my $r = $self->our_opsys->new_request($uri_or_apache_req, $form);
    $r->serve_page;

=head1 ABSTRACT

=over 4

This library is primarily for housing all OpSystem specific
things.  The library itself only contains a few methods that are
OpSystem global ideas, like include path for TT page serving.

The question is always asked "What is the OpSystem" and how does
it differ from the Dave::WebSystem set of libraries...  The
OpSystem is short for "/op directory Page-Centric Handler
System".  The idea come from the fact that unlike traditional CGI
applications, the atomic unit in the OpSystem is the page by
itself.  There is no CGI that handles X given set of pages and
only those.  This system is more-suited for a mod_perl
environment where the Request goes directly to the page, and not
to a CGI with a query string or path_info.

Pages are still organized in to logical containers which are perl
modules based on the directory name of the requested template.
These perl modules do not have any procedural script to handle
anything for more than one page.  It only has sets of handlers
named after the names of the templates themselves.

So, how does MVC::Simple differ from Dave::WebSystem?  The
short answer is that MVC::Simple handles page serving for
/op/*/*.tpl and that Dave::WebSystem handles the rest of the
*.tpl's, or all the templates for the front-end website serving
system.  Another important difference is that in WebSystem, the
handlers are organized in libraries named after type of page.
The actual URI for WebSystem pages cannot be directly related to
libraries, since template file and path names are all
user-defined.  Other that that, the systems are quite similar.

The libraries organized below this object are the ones that do
most all of the work:

MVC::Simple::Request - represents a request to a OpSystem
page, and a handler function in that library is the one mod_perl
targets for /op/*/*.tpl pages in the httpd conf files.  This uses
Dave::Template and the OpSystem::<directory>.pm sub libraries
to actually accomplish the serving of the requested page.  Also
in here are the basic hooks and logic of <template>_page and
<template>_catch handlers.

MVC::Simple::base - the base object for shared methods of
OpSystem::<directory>.pm sub libraries.  Each sub library uses
MVC::Simple::base as it's @ISA base, and it's important to
note that sub-sub libraries like MVC::Simple::admin::account
do NOT use their parent directory library MVC::Simple::admin
as the base.  There are limited things the sub-sub library can
inherit from it's parent sub library, but those are not
accomplished using @ISA.

MVC::Simple::<directory>.pm - contains OpSystem handlers
for all templates in the given directory under /op.  For example,
the handlers for /op/admin/account/viewcompany.tpl would be
defined in the library Dave/OpSystem/admin/account.pm.  It is
to our benefit to group pages in sub sub directories to form
relatively small groups.  It helps for organization and code
runtime speed especially when running under mod_perl.

=back

=head1 METHODS

=over 4


=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug
    Dave::ErrorSystem
    Dave::Global
    MVC::Simple::ObjectShare

=back

This module loads these libs when needed:

    Dave::Reseller
    MVC::Simple::Request
    MVC::Simple::View

=over 4


=back
