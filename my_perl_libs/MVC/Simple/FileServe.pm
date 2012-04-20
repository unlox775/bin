package MVC::Simple::FileServe;

#########################
###  Dave/FileServe.pm
###  Version: $Id: FileServe.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Handler to serve all supporting files for Skins and Layouts
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::Global qw( &taint_safe_env );
use Dave::Site;
use Dave::Context;
use Dave::WebSystem;
use Dave::WebSystem::PageStyle;
use Dave::WebSystem::SkinStyle;
use Dave::WebSystem::Layout;
use Dave::WebSystem::Skin;
use Dave::Util qw(&get_epoch_date);

#use IO::File;
#use Apache2::File;
#use File::Type;

use APR::Table;
use Apache2::Response ();
use Apache2::RequestRec ();
use Apache2::RequestIO ();
use Apache2::Const -compile => qw(OK DECLINED HTTP_OK HTTP_NOT_FOUND FORBIDDEN HTTP_NOT_MODIFIED );


###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
  }
}

###  Inheritance
use base qw( Dave::ObjectShareBySite );


#########################
###  Main Runtime

sub handler {
  my $r = shift;

  ###  From Dave::Global, enforce some things
  &taint_safe_env;
  
  &Dave::Site::debug_which_thread('Start FileServe');
  ###  /op/(images|css|js)
  if ( $r->uri =~ m@^/op/((?:images|css|js)/.+?)$@ ) {
    return &handle_op_skin_rsc($r, $1);
  }
  ###  Skin
  if ( $r->uri =~ m@^/op/skin/(\d+)/(\d+)/(.+?)$@ ) {
    return &handle_skin( $r, $1, $2, $3 );
  }
  ###  Layout
  elsif ( $r->uri =~ m@^/op/layout/(\d+)/(.+?)$@ ) {
    return &handle_layout( $r, $1, $2 );
  }
  ###  Not Found
  else {
    &Dave::Site::debug_which_thread('End FileServe NOT FOUND');
    return Apache2::Const::HTTP_NOT_FOUND;
  }
}

sub handle_op_skin_rsc {
  my ( $r, $path ) = @_;
  
  ###  Get the site object
  my $site = Dave::Site->new($r->hostname());
  
  ####  Get the file and 
  my $filename = $site->our_op_style->get_serve_filename($path);
  
  if ( -e $filename ) {
    ###  Get the mime-type
#    my $ft = File::Type->new();
    my $mime_type = 'text/plain';#$ft->checktype_filename($filename);
    if    ( $filename =~ /\.jpe?g$/i ) { $mime_type = "image/jpeg"; }
    elsif ( $filename =~ /\.png$/i   ) { $mime_type = "image/png"; }
    elsif ( $filename =~ /\.gif$/i   ) { $mime_type = "image/gif"; }
    
    ###  Print Header
    my @stat = stat($filename);

    ###  Return HTTP Not Modified if browser already has it cached
    my $if_modified_since = $r->headers_in->{'If-Modified-Since'};
    if ( $if_modified_since
         && $stat[9] > &parse_if_modified_since($if_modified_since)
         ) {
      &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_MODIFIED');
      return Apache2::Const::HTTP_NOT_MODIFIED;
    }
    
    ###  Set up the HTTP Headers
    $r->content_type( $mime_type );
    $r->set_last_modified( $stat[9] );
    $r->set_content_length( $stat[7] );
#    my $etag = $r->make_etag();
#    $r->set_etag();
    $r->headers_out->add('Accept-Ranges' => 'bytes');

    ###  Print File
    open(FILE, $filename) or die "Could not open file $filename : $!"; 
    my $buffer;
    while (read(FILE, $buffer, 4096)) {
      $r->print( $buffer );
    }
    close FILE;

    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  See if there is a genereated .tpl version
  $filename = $site->our_op_style->get_serve_filename($path.'.tpl');
  if ( -e $filename ) {
    $r->content_type('text/html');
    $r->print( "Yep, we'll be able to parse that with Template toolkit soon..." );
    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  Otherwise, error_404
  &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_FOUND');
  return Apache2::Const::HTTP_NOT_FOUND;
}

sub handle_skin { 
  my ( $r, $skin_style_id, $page_style_id, $path ) = @_;
  
  ###  Reject Prohibited addresses
  if ( $path =~ m@(^(skin.tpl|skin.conf|skin_schema.conf|page_schema.conf)$|(^|/)..($|/))@ ) {
    &Dave::Site::debug_which_thread('End FileServe FORBIDDEN');
    return Apache2::Const::FORBIDDEN;
  }

  ###  Get the site object
  my $site = Dave::Site->new($r->hostname());
  
  ####  Get the file and 
  my $context = $site->new_context({ non_mod_perl_cgi => 1});
  my $skin_style = $site->our_websys->get_skin_style( $skin_style_id );
  my $skin = $site->our_websys->get_skin($skin_style->get('skin_url'));
  my $page_style = $site->our_websys->get_page_style( $page_style_id );
  my $filename = $skin->get_serve_filename($path, $context, $skin_style, $page_style);
  
  if ( $filename ) {
    ###  Get the mime-type
#    my $ft = File::Type->new();
    my $mime_type = 'text/plain';#$ft->checktype_filename($filename);
    if    ( $filename =~ /\.jpe?g$/i ) { $mime_type = "image/jpeg"; }
    elsif ( $filename =~ /\.png$/i   ) { $mime_type = "image/png"; }
    elsif ( $filename =~ /\.gif$/i   ) { $mime_type = "image/gif"; }
    
    ###  Print Header
    my @stat = stat($filename);

    ###  Return HTTP Not Modified if browser already has it cached
    my $if_modified_since = $r->headers_in->{'If-Modified-Since'};
    if ( $if_modified_since
         && $stat[9] > &parse_if_modified_since($if_modified_since)
         ) {
      &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_MODIFIED');
      return Apache2::Const::HTTP_NOT_MODIFIED;
    }
    
    ###  Set up the HTTP Headers
    $r->content_type( $mime_type );
    $r->set_last_modified( $stat[9] );
    $r->set_content_length( $stat[7] );
#    my $etag = $r->make_etag();
#    $r->set_etag();
    $r->headers_out->add('Accept-Ranges' => 'bytes');

    ###  Print File
    open(FILE, $filename) or die "Could not open file $filename : $!";
    my $buffer;
    while (read(FILE, $buffer, 4096)) {
      $r->print( $buffer );
    }
    close FILE;

    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  See if there is a genereated .tpl version
  $filename = $skin->get_serve_filename($path.'.tpl', $context, $skin_style, $page_style);
  if ( -e $filename ) {
    $r->content_type('text/html');
    $r->print( "Yep, we'll be able to parse that with Template toolkit soon..." );
    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  Otherwise, error_404
  &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_FOUND');
  return Apache2::Const::HTTP_NOT_FOUND;
}

sub handle_layout { 
  my ( $r, $page_style_id, $path ) = @_;
  
  ###  Reject Prohibited addresses
  if ( $path =~ m@(^(layout.tpl|layout.conf|layout_schema.conf|page_schema.conf)$|(^|/)..($|/))@ ) {
    &Dave::Site::debug_which_thread('End FileServe FORBIDDEN');
    return Apache2::Const::FORBIDDEN;
  }

  ###  Get the site object
  my $site = Dave::Site->new($r->hostname());
  
  ####  Get the file and other objects
  my $context = $site->new_context({ non_mod_perl_cgi => 1});
  my $page_style = $site->our_websys->get_page_style( $page_style_id );
  my $layout = $site->our_websys->get_layout($page_style->get('layout_url'));
  my $filename = $layout->get_serve_filename($path, $context, $page_style);
  
  if ( $filename ) {
    ###  Get the mime-type
#    my $ft = File::Type->new();
    my $mime_type = 'text/plain';#$ft->checktype_filename($filename);
    if    ( $filename =~ /\.jpe?g$/i ) { $mime_type = "image/jpeg"; }
    elsif ( $filename =~ /\.png$/i   ) { $mime_type = "image/png"; }
    elsif ( $filename =~ /\.gif$/i   ) { $mime_type = "image/gif"; }
    
    ###  Print Header
    my @stat = stat($filename);

    ###  Return HTTP Not Modified if browser already has it cached
    my $if_modified_since = $r->headers_in->{'If-Modified-Since'};
    if ( $if_modified_since
         && $stat[9] > &parse_if_modified_since($if_modified_since)
         ) {
      &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_MODIFIED');
      return Apache2::Const::HTTP_NOT_MODIFIED;
    }
    
    ###  Set up the HTTP Headers
    $r->content_type( $mime_type );
    $r->set_last_modified( $stat[9] );
    $r->set_content_length( $stat[7] );
    $r->set_etag();
#    $r->headers_out->add('Accept-Ranges' => 'bytes');

    ###  Print File
    open(FILE, $filename) or die "Could not open file $filename : $!";
    my $buffer;
    while (read(FILE, $buffer, 4096)) {
      $r->print( $buffer );
    }
    close FILE;

    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  See if there is a genereated .tpl version
  $filename = $layout->get_serve_filename($path.'.tpl', $context, $page_style);
  if ( -e $filename ) {
    $r->content_type('text/html');
    $r->print( "Yep, we'll be able to parse that with Template toolkit soon..." );
    &Dave::Site::debug_which_thread('End FileServe OK');
    return Apache2::Const::OK;
  }
  
  ###  Otherwise, error_404
  &Dave::Site::debug_which_thread('End FileServe HTTP_NOT_FOUND');
  return Apache2::Const::HTTP_NOT_FOUND;
}

sub parse_if_modified_since {
  my ( $value ) = @_;

  if ( $value =~ /\w{3}, (\d{1,2}) (\w{3}) (\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ([A-Z]{3})/ ) {
    my $date = $&;
    return &get_epoch_date( $date ) || 0;
  }
  return 0;
}

1;


__END__


=head1 NAME

MVC::Simple::FileServe - Handler to serve all supporting files for Skins and Layouts

=head1 SYNOPSIS

    ###  Direct handler call
    use MVC::Simple::FileServe;
    &MVC::Simple::FileServe::handler($apache_req);

    ###  Apache Conf Syntax
    PerlModule MVC::Simple::FileServe
    <FilesMatch "(skin|layout)">
      SetHandler modperl
      PerlResponseHandler MVC::Simple::FileServe
    </FilesMatch>

=head1 ABSTRACT

=over 4

Some supporting files for layouts and skins are images or CSS
stylesheet text docs.  These files need no Template parsing or
system handling but can be served in normal HTTP style.

For Skins the URI to an example file would be:

        /op/skin/<skin_style_id>/<page_style_id>/images/title.gif

The Dave::SkinStyle and Dave::PageStyle objects are obtained by
the pieces of the path.  An Dave::Context object is also applied
and with the combination of all three items, magic association to
find the requested file can be done.  For example there may be
these different files, relative to the skin root dir:

        /images/title.gif             # image with the words "Home Title"
        /ESL/images/title.gif         # image with the words "Casera Titulo"
        /subpage/images/title.gif     # image with the words "Subpage Title"
        /ESL/subpage/images/title.gif # image with the words "Subpagina Titulo"

Then sensitive to Enlish or Spanish and whether it was a home
page or sub-page, the image would serve properly.

Layouts work the same with this example URI:

        /op/layout/<page_style_id>/css/style.css

NOTE: This currently does not handler Content-type'ing for all
file types.  I tried to use File::Type, File::MMagic and
File::MimeInfo to do some magic mime detection, but they all seem
to have problems with Apache 2 or ModPerl 2.  Right now it's just
using file extension handling .jpg, .png, and .gif.  Then it
defaults to text/plain.

=back

=head1 FUNCTIONS

=item handler()

Takes a ModPerl 2 Apache RequestRec Object and decides whether to
serve a layout file or a skin file.  Both styles support etags
and HTTP 302 Not Modified to utilize Browser Cache.  Also added
is a stub for someday allowing these subpages to be served with
Template Toolkit parsing.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    ModPerl 2
    Dave::Bug
    Dave::Site
    Dave::Context
    Dave::WebSystem
    Dave::WebSystem::PageStyle
    Dave::WebSystem::SkinStyle
    Dave::WebSystem::Layout
    Dave::WebSystem::Skin
    Dave::Util
    
    APR::Table
    Apache2::Response
    Apache2::RequestRec
    Apache2::RequestIO
    Apache2::Const

=back

