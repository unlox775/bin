package MVC::Simple::Template::AltAbsoluteProvider;

#########################
###  Dave/Template/AltAbsoluteProvider.pm
###  Version: $Id: AltAbsoluteProvider.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  A Template Toolkit Provider to allow alt Absolute path bases
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use MVC::Simple::Template;
use Dave::Util qw( &gva );

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
  }
}

###  Inheritance
use base qw( Template::Provider );


#########################
###  Overriden Methods

sub _init {
  my $self = shift;
  my ($params) = @_;

  ###  Call the SUPER::
  my $ret_self = $self->SUPER::_init( $params );

  $ret_self->{'alt_absolute'} = $params->{'alt_absolute'} || '';
}

sub _fetch {
  my $self = shift;
  my ( $name ) = @_;

  ###  Skip to the end if not absolute
  return( $self->SUPER::_fetch(@_) ) unless $name =~ m@^/@;

  ###  As alt_absolute may be an arrayref, loop through them until we don't get a DECLINED
  my ($data, $error);
  foreach my $alt_absolute ( @{ gva $self->{'alt_absolute'} } ) {
    my $new_name = $alt_absolute.$name;

    ###  Call the SUPER::_fetch
    ($data, $error) = $self->SUPER::_fetch($new_name);
    return($data, $error) unless $error eq Template::Constants::STATUS_DECLINED;
  }
  ###  ONLY would get to this point if
  ###    either a) ALL above calls to SUPER::_fetch returned STATUS_DECLINED
  ###        or b) 'alt_absolute' was an empty arayref, so simulate STATUS_DECLINED
  return($data, $error || Template::Constants::STATUS_DECLINED );
}

1;


__END__


=head1 NAME

MVC::Simple::Template::AltAbsoluteProvider - Overridden Template::Provider for per-context multiple absolute paths

=head1 SYNOPSIS
 
  use Template::Context;
  use MVC::Simple::Template::AltAbsoluteProvider;

  my %prefix_map = 
    ( default => [ MVC::Simple::Template::AltAbsoluteProvider
                   ->new({ alt_absolute =>   $layout->layout_root,
                           INCLUDE_PATH => [ $layout->get_serve_fallback_paths ],
                                             ABSOLUTE => 1,
                                           })
                   ],
      skin => [ MVC::Simple::Template::AltAbsoluteProvider
                ->new({ alt_absolute =>   $skin->skin_root,
                        INCLUDE_PATH => [ $skin->get_serve_fallback_paths ],
                                          ABSOLUTE => 1,
                                        })
                      ],
      layout => [ MVC::Simple::Template::AltAbsoluteProvider
                  ->new({ alt_absolute =>   $layout->layout_root,
                          INCLUDE_PATH => [ $layout->get_serve_fallback_paths ],
                                            ABSOLUTE => 1,
                                          })
                  ],
      );
      
  my $context = Template::Context->new({ PREFIX_MAP => \%prefix_map,
                                         })
    || die $Template::Context::ERROR;

=head1 ABSTRACT

=over 4

The above example uses an undocumented feature of Template
Toolkit 2, that you can create a Templaete::Context object
passing a PREFIX key which is a hashref of Template::Provider
objects.  That allows directives like:

        [%INCLUDE layout:/images/spacer.gif %]

To resolve to <layout_root>/images/spacer.gif.  Also relative
urls like:

        [%INCLUDE layout:chunks/header.tpl %]

Might resolve to: <layout_root>/<language_code>/chunks/header.tpl
because of the passed INCLUDE_PATH and normal inherited
Template::Privoder inherited functionality.

Cool, eh?  Template Toolkit 2 Rocks!

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    MVC::Simple::Template
    Template::Provider

=back
