package MVC::Simple::Template;

#########################
###  Dave/Template.pm
###  Version: $Id: Template.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Library for template parsing by Template Toolkit
###  though it's best done accessing things through an
###  MVC::Simple::Template::OpInstance object which carries the
###  Individual template content and print_out function
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Template; # Template Toolkit 2
use Template::Stash;
use Dave::ErrorSystem qw(:oo_methods);
use Dave::Util qw(&split_delim_line);
use MVC::Simple::ContextWrap qw(&wrap_all_objects);
use CGI qw( &escapeHTML &escape );

#$SHOW_DEBUG::TEMPLATE_TIMERS = 1;

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
  }
}

###  Inheritance
use base qw( MVC::Simple::ObjectShare );

###  Globals
use vars qw( $current_mvc_obj $current_instance_obj $current_context_obj );


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $mvc ) = @_;

  my $self = bless( { mvc         => $mvc,
                      RaiseError   => 1,
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
  
  return $self;
}


#########################
###  Shared Methods

sub new_instance {
  my $self = shift;

  require MVC::Simple::Template::Instance;
  return MVC::Simple::Template::Instance->new( $self->our_mvc, @_ );
}

sub parse {
  my $self = shift;
  my ( $content_ref, $vals, $output_ref, $tpl_instance, $prefs ) = @_;
  $prefs ||= {};
  $output_ref ||= \ '';
  die "no content ref" unless UNIVERSAL::isa($content_ref, 'SCALAR');

  ###  Setup some environment for extensions
  local $current_mvc_obj = $self->our_mvc;
  local $current_instance_obj = $tpl_instance;
  local $current_context_obj = $tpl_instance->context;

  ###  Wrap and secure vars
#  &wrap_all_objects(\$vals, $tpl_instance->context);
  $vals->{'bug'} ||= sub { local $Dave::Bug::caller_level = 3;
                           local $Dave::Bug::force_filename = 1;
                           &bug(@_);
                           return '';
                         };
  $vals->{'listfix'} ||= sub { # bug \@_;
                               return( (@_ == 1 && UNIVERSAL::isa($_[0], 'ARRAY') ) ? $_[0] : [@_] );
                         };
  $vals->{'die'} ||= sub { die($_[0]. " at " . ( caller(2) )[1] . ' line ' . ( caller(2) )[2] . ".\n"); };

  my $tt_context = $tpl_instance->get_context_obj({
                            FILTERS      => { 'format_price'      => [ \&ttf_format_price, 1 ],
                                              'format_bare_price' => \&ttf_format_bare_price,
                                              nbsp                => \&ttf_nbsp,
                                              uri_param           => \&ttf_uri_param,
                                              js_escape           => \&ttf_js_escape,
                                              nowrap              => \&ttf_nbsp,
                                              bug                 => \&ttf_bug,
                                              dev_null            => \&ttf_dev_null,
                                              hole                => \&ttf_dev_null,
                                              erase               => \&ttf_dev_null,
                                              mime_to_short_type  => \&ttf_mime_to_short_type,
                                              human_bytes         => \&ttf_human_bytes,
                                              chop_ext            => \&ttf_chop_ext,
                                            },
                          });

#  require Dave::Template::Plugin::testnamespace;
  my $tt = Template->new( INTERPOLATE  => 0,               # do NOT expand "$var" in plain text
                          POST_CHOMP   => 1,               # cleanup whitespace
#                          PRE_PROCESS  => 'header',        # prefix each template
                          EVAL_PERL    => 0,               # do NOT evaluate Perl code blocks
                          ###  Home brewed Context object
                          CONTEXT      => $tt_context,
                          ###  Add-on Filters 
#                          NAMESPACE => { tn => Dave::Template::Plugin::testnamespace->new(),
#                                       },
                          );
  
#  bug $vals;
  START_TIMER TemplateToolkit_process if $SHOW_DEBUG::TEMPLATE_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  my $success = $tt->process($content_ref, $vals, $output_ref);
  END_TIMER TemplateToolkit_process if $SHOW_DEBUG::TEMPLATE_TIMERS || $SHOW_DEBUG::ALL_TIMERS;
  ###  Handle errors
  if ( ! $success ) {
    my $error = $tt->error();
    ###  If the primary template file was not found
    if ( $error->type eq 'file' 
         && ! ref($error->info)
         && $error->info =~ /^$prefs->{primary_template}\:/
         ) {
      return $self->do_error(97, {type => $error->type, info => $error->info, include_path => $tt_context });
    }
    ###  General Parse Error
    return $self->do_error(98, {type => $error->type, info => $error->info, include_path => $tt_context });
  }


  return( $output_ref );
}

###  Virtual method for scalars, to allow CSV splitting
$Template::Stash::SCALAR_OPS->{ split_delim } = sub {
  return [ &split_delim_line($_[1], $_[0], $_[2]) ];
};

sub ttf_format_price {
  my ($context, $currency) = @_;

  return sub {
    my $text = shift;
    return $text unless $text =~ /^\d+(\.\d+?)?$/s || $text eq 'XXXXX';
    return( scalar( $current_mvc_obj->our_ecom->format_price($text, $currency) ) );
  }
}

sub ttf_format_bare_price {
  my $text = shift;
  return $text unless $text =~ /^\d+(\.\d+)?$/s 
    || ($text = $current_mvc_obj->our_ecom->unformat_price($text)) =~ /^\d+(\.\d+)?$/s;
  return( ( $current_mvc_obj->our_ecom->format_price($text) )[2] );
}

sub ttf_nbsp {
  my $text = shift;
  $text =~ s/[\t ]/&nbsp;/g;
  return( $text );
}

sub ttf_uri_param {
  my $text = shift;
  return( &escape($text) );
}

sub ttf_js_escape {
  my $text = shift;
  return( join('\n" +'."\n".'"', map {s/\"/\\\"/g; s/\$/\\\$/g; $_;} split(/\n/, $text)) );
}

sub ttf_chop_ext {
  my $text = shift;
  $text =~ s/\.\w{2,5}$//;
  return( $text );
}

sub ttf_bug {
  my $text = shift;
  return &Dave::Bug::bug_out( $text );
}

sub ttf_dev_null {
  return '';
}

sub ttf_mime_to_short_type {
  my ( $mime ) = @_;

  my %map = ( 'image/jpeg' => 'JPEG',
              'image/tiff' => 'TIFF',
              'image/gif' => 'GIF',
              'image/x-png' => 'PNG',
              'image/x-ms-bmp' => 'BMP',
              'image/x-bmp' => 'BMP',
              );
  return $map{ $mime } || 'Error';
}

sub ttf_human_bytes {
  local $_;
  my ( $bytes, $max_prec, $min_prec, $prec_threshold ) = @_;
  $max_prec ||= 1;
  $min_prec ||= 0;
  $prec_threshold ||= 100;

  my @levels = qw( bytes k M G Tb Ex Pb );
  my $str;
  foreach my $i (0..$#levels) {
    $str = $levels[$i];
    last if $bytes < 1024;
    $bytes /= 1024;
  }
  my $prec = ($bytes < $prec_threshold) ? $max_prec : $min_prec;

  return sprintf("%.${prec}f$str", $bytes);
}

1;


__END__


=head1 NAME

Dave::Template - Library for template parsing by Template Toolkit

=head1 SYNOPSIS

    use Dave::Template;
    my $template = Dave::Template->new('bar.com');

    use base qw(Dave::ObjectShareByMvc);
    $self->our_template->...();
    
    ###  Get a Template instance and print a page
    my $tpli = $self->our_template->new_instance($shell_url, $page_url);
    $tpli->print_out( \%swaps_area,
                      { page_area => \%page_area,
                        error_area => \%error_area,
                        }
                      );

    ###  Manually parse a content hunk with Template Toolkit
    my $content = '[% swap.foo %]';
    my $result = '';
    $self->our_template->parse( \$content,
                                { swap  => \%swaps_area,
                                  page  => \%page_area,
                                  error => \%error_area,
                                  mvc  => \%mvc_area,
                                  x     => \%x_area,
                                },
                                \$result,
                                $instance_obj,
                                  { primary_template => $pagename,
                                    }
                                );
    print $result;

=head1 ABSTRACT

=over 4

This library is here to facilitate "our way of using Template
Toolkit".  Right now there are not many things we are overriding
over the default, but the ones we are overriding are important:

    1) passing an INCLUDE_PATH with reseller fallback and added
       contexts for clips and other TT pieces.

    2) Items standardized by Dave::Template::Instance

      a) swaps, mvc, page, and error "areas" accessible in TT
         through [% mvc.foo %], [% page.foo %], etc.  These
         provide some "environment" for the page in that every
         page will have a mvc area and can reference any value
         available from a Dave::Mvc->get() call.  The page area
         can hold information such as the URI and other
         page-specific globals.  Eventually we can let access to
         a form area, or reseller area, or whatever, and they all
         get added by default by adding them to Instance.

      b) How to assemble the shell with the content section
         inside of it.

Eventually we can also use this to override some of the deeper
features of TT such as adding our own modules or changing
grammar, and they are all abstracted through this interface.

=back

=head1 METHODS

=over 4

=item new_instance()

Get a Dave::Template::Instance object passing the mvc
objectshare, and the calling parameters.

=item parse($cont_ref, $hashref, $ret_ref, $instance_obj, $prefs)

Get a Template Toolkit object and use it to parse the content in
the passed scalar ref $cont_ref using the values in $hashref as
swap parameters.  The content is parsed and the scalar referenced
by $ret_ref is assigned the parsed value.

Currently the $instance object is only used to get the base
INCLUDE_PATH by calling get_include_path on it.  This may change
in the future.  The include path retrieved is an arrayref which
is used to form the actual INCLUDE_PATH passed to TT.  For each
item in the array_ref, corresponding items are added for the
effective relative paths ./, ./clips/, ./<path to primary
template>/.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug
    Dave::ErrorSystem
    Dave::ObjectShare
    Template

=back

This module loads these libs when needed:

=over 4

    Dave::Template::Instance

=back









