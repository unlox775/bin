package MVC::Simple::Template::Instance;

#########################
###  Dave/Template/Instance.pm
###  Version: $Id: Instance.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  An instance of a Template rendering for OpSystem
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use MVC::Simple::Template;
use MVC::Simple::ContextWrap;

#$SHOW_DEBUG::TEMPLATE_TIMERS = 1;

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
    require Template::Context;
    require Template::Provider;
    require MVC::Simple::Template::AltAbsoluteProvider;
  }
}

###  Inheritance
use base qw( MVC::Simple::ObjectShare );


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $mvc, $shell, $page, $request, $hash ) = @_;
  $hash ||= {};

  $page .= '.tpl' unless $page =~ /\.tpl$/;

  my $self = bless( { mvc       => $mvc,
                      shell      => $shell,
                      page       => $page,
                      request    => $request,
                      RaiseError => 1,
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

  ###  Get filenames
  $self->{'shell_filename'} = $self->our_mvc->get_shell_filename($self->{'shell'});
  $self->{'page_filename'}  = $self->our_mvc->get_template_filename($self->{'page'});
  ( $self->{'page_path'}, $self->{'page_shortname'} )
    = ( $self->{'page'} =~ m@^(.*?)/([^/]+)$@ );
#  bug { shell__url     => $self->{'shell_url'},
#        shell_filename => $self->{'shell_filename'},
#        page__url      => $self->{'page_url'},
#        page_filename  => $self->{'page_filename'},
#      };
  
  return $self;
}

sub context { $_[0]->{'request'}->context; }


#########################
###  Shared Methods

sub print_out {
  my $self = shift;
  my ( $swaps, $hash ) = @_;
  $hash ||= {};

  ###  Read in the shell file
  open( SHELL, $self->{'shell_filename'} ) or die "Could not open shell file $self->{shell_filename}: $!";
  my $content = join('', <SHELL>);
  close SHELL;


  ###  Swap in the $PAGE_FILE_NAME tag
  $content =~ s/\$PAGE_FILE_NAME/$self->{page_shortname}/;

  ###  Parse 
  my $result = '';
  my $extra_swaps = ( $self->our_mvc->can('get_extra_template_swaps') ? $self->our_mvc->get_extra_template_swaps : {} );
  $self->our_template->parse( \$content,
                              { swap => $swaps,
                                error => $hash->{'error_area'},
                                page => $hash->{'page_area'},
                                session => $hash->{'session'},
#                                mvc     => MVC::Simple::ContextWrap->new([$self, 'our_mvc'], $self->context),
                                mvc     => $self->our_mvc,
                                %{$extra_swaps},
                              },
                              \$result,
                              $self,
                                { primary_template => $self->{page_shortname},
                                  }
                              );

  

  $self->{request}->print_header;
  START_TIMER 'print_out' if $SHOW_DEBUG::TEMPLATE_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  print $result;
  END_TIMER 'print_out' if $SHOW_DEBUG::TEMPLATE_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
}


#########################
###  Template Parsing Environment

sub get_context_obj {
  my $self = shift;
  my ( $hash ) = @_;
  $hash ||= {};

  require Template::Context;
  require Template::Provider;
  require MVC::Simple::Template::AltAbsoluteProvider;

  my %prefix_map = 
    ( default => [ MVC::Simple::Template::AltAbsoluteProvider
                   ->new({ alt_absolute => [ $self->our_mvc->TEMPLATE_BASE ],
                           INCLUDE_PATH => [ $self->our_mvc->TEMPLATE_BASE.$self->{'page_path'} ],
                           ABSOLUTE => 1,
                         })
                   ],
      clip => [ MVC::Simple::Template::AltAbsoluteProvider
                ->new({ alt_absolute => [ $self->our_mvc->TEMPLATE_BASE.'/clips' ],
                        INCLUDE_PATH => [ $self->our_mvc->TEMPLATE_BASE.'/clips' ],
                        ABSOLUTE => 1,
                      })
                ],
      );
      
  my $context = Template::Context->new({ PREFIX_MAP => \%prefix_map,
                                         %$hash,
                                         })
    || die $Template::Context::ERROR;
  return $context;
}


1;


__END__


=head1 NAME

MVC::Simple::Template::OpInstance - An instance of a Template rendering for OpSystem

=head1 SYNOPSIS

    use base qw( Dave::ObjectShareByMvc );
    my $instance = $self->our_template->new_op_instance($shell_url, $page_url, $op_request_obj);

    ###  Run the parse and print out
    $instance->print_out( $swaps_hash );

    ###  Things MVC::Simple::Template calls
    my $template_context_obj = 
      $instance->get_context_obj( { FILTERS => { ... },
                                    ...
                                  });

=head1 ABSTRACT

=over 4

Basically this object defines the Template Toolkit environment
for parses of pages in the OpSystem.  This environment makes up
what base areas are available (ptree, page), template
INCLUDE_PATH's, and others.  The only things provided by the
Request object should be which shell, and page, and the swaps.

Any filters, globals, or other Template Toolkit additions that
need to be added which are specific to page parses in the
/op/... directory, should be added here.  Any other additions
which apply everywhere should be added into MVC::Simple::Template.

=back

=head1 FUNCTIONS

=over 4

=item print_out()

This is the method which takes the swaps, calls
MVC::Simple::Template->parse() and then prints the content returned to
STDOUT (or the currently selected filehandle.)

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug
    Dave::ObjectShareByMvc
    MVC::Simple::Template
    MVC::Simple::ContextWrap

=back

This module loads these libs when needed:

=over 4

    Template::Context
    Template::Provider
    MVC::Simple::Template::AltAbsoluteProvider

=back
