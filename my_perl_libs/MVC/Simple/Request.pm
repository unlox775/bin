package MVC::Simple::Request;

#########################
###  MVC/Simple/Request.pm
###  Version: $Id: Request.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###

use strict;
use Dave::Bug qw(:common);


#########################
###  Package Config

use Dave::Util qw( &taint_safe_env );
use Dave::ErrorSystem qw(:oo_methods);
use MVC::Simple;
use MVC::Simple::ContextWrap;
# use MVC::Simple::FileServe;
use CGI qw( &escape );
use CGI::Cookie;

###  Mod Perl detection
use constant MOD_PERL => (exists $ENV{MOD_PERL} || exists $ENV{MOD_PERL_API_VERSION});
use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2);
BEGIN {
  # Test mod_perl versione and use the appropriate components
  if (MOD_PERL) {
    if (MP2) {
      require Apache2::RequestRec;
      require Apache2::RequestIO;
      require Apache2::RequestUtil;
      require Apache2::Const;
      Apache2::Const->import( -compile => qw(OK DECLINED HTTP_OK HTTP_MOVED_TEMPORARILY));
    } else {
      # Mod Perl 1 compat here...
    }
  }
  else {
    # CGI compat here...
  }
}

###  Inheritance
use base qw( MVC::Simple::ObjectShare MVC::Simple::RequestBase );


#########################
###  Constructor

sub new {
  my $pkg = shift;
  my ( $mvc, $uri_or_reqobj, $form, $hash ) = @_;
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

  ###  MOD_PERL requests will pass an Apache2::RequestRec
  if ( UNIVERSAL::isa($uri_or_reqobj, 'Apache2::RequestRec') ) {
    $self->{'mode'} = 'apache_request';
    $self->{'apache_request'} = $uri_or_reqobj;
    $self->{'uri'} = $self->{'apache_request'}->uri;
    $self->{'hostname'} = $self->{'apache_request'}->hostname;
    $self->{'form'} = $form;
#    bug $self->{'apache_request'}->args;
#    bug [ $self->{'apache_request'}->args ];
#    bug $self->{'apache_request'}->vars;
#    bug [ $self->{'apache_request'}->vars ];
  }
  ###  CGI mode
  else {
    $self->{'mode'} = 'cgi';
    $self->{'uri'} = $uri_or_reqobj;
    $self->{'hostname'} ||= $ENV{'HTTP_HOST'};
    $self->{'form'} = $form;
  }

#  ###  Get the Context Object
#  $self->{'context'} = $self->our_mvc->new_context({op_request_obj => $self});

  return $self;
}

sub context { $_[0]->{'context'} }
sub request_time { $_[0]->{'apache_request'} ? ($_[0]->{'apache_request'}->request_time()) : $^T; }
sub mode     { $_[0]->{'mode'} }
sub uri      { $_[0]->{'uri'} }
sub hostname { $_[0]->{'hostname'} }
sub form     { $_[0]->{'form'} }


#########################
###  Shared Methods

sub serve_page {
  my $self = shift;

  ###  Handle AJAX requests differently
  ###    For now, do this before the Archive check...
  ###    I don't currently forsee too much being lost
  ###    by not restricting AJAX requests
  if ( substr($self->uri, -5) eq '.ajax' ) {
    return $self->serve_ajax_request;
  }

  #########################
  ###  Catch the previous step

  ###  Get the page submitted from
  my $catch_uri = $self->form->{'catch'}; # a full URI
  my $reserve_catch_page;
  if ( $catch_uri ) {
    my ( $catch_sect, $catch_page ) = $self->our_mvc->get_section_obj_by_uri($catch_uri);
    if ( $catch_sect ) {
      local $self->{'this_uri'} = $catch_uri;

      $self->do_auth_check($catch_sect) or return;

      ###  Try the catch handler
      if ( $catch_sect->can($catch_page . '_catch') ) {
        my $handler = $catch_page . '_catch';
        $self->{'catch_response'} = $catch_sect->$handler($self->form, $self);
        return if $self->do_location_redirect;

        ###  If failure, re-output the page
        if ( ! $self->{'catch_response'} ) { $reserve_catch_page = $catch_uri; }
      }
    }
  }


  #########################
  ###  Run Pitch Handler(s) (optional)

  ###  Only do pitch if the catch was successful.
  ###    No need to re-pitch a page that has been
  ###    served and the catch failed.
  my ( $pitch_uri, $pitch_sect, $pitch_page );
  if ( ! $reserve_catch_page ) {
    $pitch_uri = $self->uri;

    ###  Since the pitch handlers can bounce to each other, go through a loop until one returns 1
    my @pitched_uris;
    PITCHLOOP : while ( ! $self->{'pitch_response'} ) {
      
      ###  Try the pitch handler
      push @pitched_uris, $pitch_uri;
      ( $pitch_sect, $pitch_page ) = $self->our_mvc->get_section_obj_by_uri($pitch_uri);
      if ( $pitch_sect 
           && $pitch_sect->can($pitch_page . '_pitch') 
           ) {
        local $self->{'this_uri'} = $pitch_uri;

        $self->do_auth_check($pitch_sect) or return;

        my $handler = $pitch_page . '_pitch';
        my $new_pitch_uri;
        ($self->{'pitch_response'}, $new_pitch_uri) = $pitch_sect->$handler($self->form, $self);
        $pitch_uri = $new_pitch_uri if ! $self->{'pitch_response'};
        return if $self->do_location_redirect;

        ###  Stop a possible infinite loop
        if ( ! $self->{'pitch_response'}
             && grep { $_ eq $pitch_uri } @pitched_uris ) {
          $self->do_error(122, {uri => $self->uri, form => $self->form, pitched_uris => \@pitched_uris} );
        }
      }

      ###  Otherwise, simulate a successful one...
      else { $self->{'pitch_response'} = 1; }
    }
  }


  #########################
  ###  Run Page Handler to output the page

  ###  Get the target, to-be-displayed page
  my $page_uri = ( $reserve_catch_page || $pitch_uri || $self->uri );
  my ($page_sect, $page );
  if ( $pitch_sect ) { ($page_sect, $page ) = ( $pitch_sect, $pitch_page ) }
  else               { ($page_sect, $page ) = $self->our_mvc->get_section_obj_by_uri($page_uri); }
  if ( $page_sect ) {
    local $self->{'this_uri'} = $page_uri;

    $self->do_auth_check($page_sect) or return;

    ###  Try the page handler
    if ( $page_sect->can($page . '_page') ) {
      my $handler = $page . '_page';
      $self->{'page_response'} = $page_sect->$handler($self->form, $self);
      return if $self->do_location_redirect;
    }

    ###  Get the shell for this page
    if ( $page_sect->can('get_shell') ) {
      $self->{'shell'} = $page_sect->get_shell( $page );
    }
    else {
      $self->{'shell'} = $self->our_mvc->get_section_obj('MVC::Simple::Controller::base')->get_shell;
    }
  }
  ###  No lib, default template
  else {
    $self->{'shell'} = $self->our_mvc->get_section_obj('MVC::Simple::Controller::base')->get_shell;
  }

  return if $self->do_location_redirect;
  
  ###  Override the shell with a query param
  $self->{'shell'} = $self->form->{'shell'} if $self->form->{'shell'};
  
  ###  Determine the page url
  my $URL_BASE = $self->our_mvc->URL_BASE;
  ( my $chopped_uri = $page_uri ) =~ s@^\Q$URL_BASE\E@@;

  ###  Prepare Errors
  my %error_area;
#  bug $self->{'error'};
  if ( $self->{'error'} ) {
    $error_area{$_} = '<b><font color="red">'.$self->{'error'}{$_}[0].'</font></b>' 
      foreach ( grep { UNIVERSAL::isa( $self->{'error'}{$_}, 'ARRAY') } keys %{ $self->{'error'} } );
  }

  ###  Load and call the template object
  my $tpli = $self->our_template->new_instance($self->{'shell'}, $chopped_uri, $self);
  $tpli->print_out( $self->{'page_response'},
                      { page_area => $self->page_area($page_uri),
                        session => $self->session_ro,
                        error_area => \%error_area,
                        view_area => $self->view_area,
                      }
                    );

  return 1;
}

sub serve_ajax_request {
  my $self = shift;

  #########################
  ###  Run Ajax Handler to output the ajax content

  my $ajax_uri = $self->uri;
  my ($ajax_sect, $ajax ) = $self->our_mvc->get_section_obj_by_uri($ajax_uri);
  if ( $ajax_sect ) {
    local $self->{'this_uri'} = $ajax_uri;

    $self->do_auth_check($ajax_sect) or return;

    ###  Try the ajax handler
    if ( $ajax_sect->can($ajax . '_ajax') ) {
      my $handler = $ajax . '_ajax';
      $self->{'ajax_response'} = $ajax_sect->$handler($self->form, $self);
      return if $self->do_location_redirect;
    }
  }

  return if $self->do_location_redirect;
  print "Status: 200 OK\nContent-type: text/plain\n\n";
  print $self->{'ajax_response'} if $self->{'ajax_response'};

  return 1;
}

sub do_auth_check {
  my $self = shift;
  my ( $sect_obj ) = @_;

  ###  Authenticate
  my ( $success, $username, $redir_url ) = $sect_obj->auth_check($self->form, $self);
  if ( ! $success ) {
    $self->do_location_redirect($redir_url || '/');
  }

  ###  Record details
  $self->{'auth_username'} = $username;
  $self->{'auth_success'} = $success;

  return if $self->do_location_redirect; # either !success or ok, bounce to dest

  return 1;
}
sub username { $_[0]->{'auth_username'} }
sub user { $_[0]->our_mvc->get_user( $_[0]->{'auth_username'} ); }


#########################
###  View System hooks

sub prepare_view {
  my $self = shift;
  my ( $view_code ) = @_;
  
  $self->{'view_code'} = $view_code;
}

sub view { my $self = shift;  return unless $self->{'view_code'};  $self->our_mvc->get_view( $self->{'view_code'} ); }

sub view_area {
  my $self = shift;
  return undef unless $self->{'view_code'};
  
  ###  Wrap this area now
  my $view_area = Dave::Template::ContextWrap->new($self->view, $self->context);

  ###  Wrap 'this_dir', if it's been set
  if ( $self->{'view_this_dir'}
       && $self->{'view_this_dir'}{'dir'}
       ) {
    my $this_dir = Dave::Template::ContextWrap->new($self->{'view_this_dir'}{'dir'}, $self->context);

    ###  Then add things to it
    ###    NOTE: after an object is wrapped, STORE ops on the hash are
    ###    stored without affecting the wrapped object
    $this_dir->{'dir'}  = ( $self->{'view_this_dir'}{'path'}
                            . $self->{'view_this_dir'}{'name'}
                            );                                # [%view.this_dir.dir%]
    $this_dir->{'dir_uri'}  = escape($this_dir->{'dir'});     # [%view.this_dir.dir_uri%]
    $this_dir->{'path'} = $self->{'view_this_dir'}{'path'};   # [%view.this_dir.path%]
    $this_dir->{'name'} = $self->{'view_this_dir'}{'name'};   # [%view.this_dir.name%]

    ###  View preferences : display_view
    ###    NOTE: eventually these prefs may be 
    ###    stored in a permanent user prefs location
    my $view_prefs = $self->session_ro->get('view_prefs');
    if ( $self->form->{'set_display_view'} ) {
      $view_prefs->{ $self->{'view_code'} }{'display_view'} = $self->form->{'set_display_view'};
      $self->session->set(view_prefs => $view_prefs);
    }
    $this_dir->{'display_view'} = $view_prefs->{ $self->{'view_code'} }{'display_view'};   # [%view.this_dir.display_view%]

    ###  View preferences : display_mode
    ###    NOTE: eventually these prefs may be 
    ###    stored in a permanent user prefs location
    my $use_display_view = $this_dir->{'display_view'} || 'no_view'; # hack while we are half-way between view widget porting
    if ( $self->form->{'set_display_mode'} ) {
      $view_prefs->{ $self->{'view_code'} }{ $use_display_view }{'display_mode'} = $self->form->{'set_display_mode'};
      $self->session->set(view_prefs => $view_prefs);
    }
    $this_dir->{'display_mode'} = $view_prefs->{ $self->{'view_code'} }{ $use_display_view }{'display_mode'};   # [%view.this_dir.display_mode%]

    ###  Now, add 'this_dir' to the $view_area
    ###    NOTE: after an object is wrapped, STORE ops on the hash are
    ###    stored without affecting the wrapped object
    $view_area->{'this_dir'} = $this_dir; # [%view.this_dir%]
  }

  return $view_area;
}

sub set_view_dir {
  my $self = shift;
  my ( $view_code, $form ) = @_;

  ###  Prepare the view
  $self->prepare_view($view_code);

  ###  Read the Form and cache the dir object
  ( $self->{'view_this_dir'}{'dir'},
    $self->{'view_this_dir'}{'path'},
    $self->{'view_this_dir'}{'name'} ) 
    = $self->view->read_dir_from_form($form, { default_to_root => 1 });

  return unless $self->{'view_this_dir'}{'dir'};

  ###  Return the dir object this "View Directory" represents
  ###    This is because all other handler code deals directly with
  ###    the object and not the view directory it is wrapped in
  return $self->{'view_this_dir'}{'dir'}->my_item;
}

sub view_this_dir { $_[0]->{'view_this_dir'}{'dir'}; }

###  Add View System hidden vars to the Page Area
sub page_area_extra {
  my $self = shift;
  my ( $hidden, $area_extra ) = @_;

  ###  View System
  if ( $self->{'view_this_dir'}{'dir'} ) {
    my $view_hidden = $self->{'view_this_dir'}{'dir'}->hidden_inputs;
    %$hidden = ( %$hidden, %$view_hidden );
  }
}


#########################
###  Apache Content Handler for all .tpl files

###  The fixup handler to route the request to the proper handler

###    NOTE: some other systems use the FIXUPHANDLER namespace
###    which is actually misnamed as it is actually used by us at
###    the CleanupHandler phase, and handled by the below
###    &cleanup_handler() function.

sub fixup_handler {
  my $apache_req = shift;

  &reset_timers;

  ###  If the requested file is a .tpl
  if ( substr($apache_req->filename, -4) eq '.tpl'
       || substr($apache_req->filename, -5) eq '.ajax'
     ) {
    $apache_req->handler('perl-script');
    $apache_req->set_handlers(PerlResponseHandler => \&handler);
  }

  ###  Otherwise, fall back to the 'default-handler'
  else {
    $apache_req->handler('default-handler');
    $apache_req->set_handlers(PerlResponseHandler => undef);
  }
       
  return &Apache2::Const::OK;
}


###  The Apache Content Handler
sub handler {
  my $apache_req = shift;

  ###  From Dave::Util, enforce some things
  &taint_safe_env;

  my $q = CGI->new;

  ###  If this is a POST method, merge in URL params with POST params
  if ( $ENV{REQUEST_METHOD} eq 'POST' ) {
    $q->append(-name => $_, -values => [$q->url_param($_)]) foreach ( $q->url_param() );
  }

  my %FORM = $q->Vars;


  ###  Get our OO object of ourselves
  my $mvc_req = MVC::Simple::Request->new($apache_req->hostname, $apache_req, \%FORM);

  $apache_req->content_type('text/html');
  $ENV{CONTENT_TYPED} = 1;

  ###  Setup ErrorSystem as the SIG DIE
  local $SIG{__DIE__} = \&Dave::ErrorSystem::my_sig_die;

  ###  Trap the call in an eval so we can do cleanup
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

  ###  If a specific exit status is set, then use it
  if ( ! $success && $mvc_req->{'return_http_status'} ) {
    return $mvc_req->{'return_http_status'};
  }

  &report_timers;

  return &Apache2::Const::OK;
}


#########################
###  Apache PerlCleanUpHandler

###  Currently running by the the PerlLogHandler hook
sub cleanup_handler {
  return &Apache2::Const::OK unless %FIXUPHANDLER::TODO;

  ###  Run people's fixup code
  foreach my $key ( sort keys %FIXUPHANDLER::TODO ) {
    my $code_ref = $FIXUPHANDLER::TODO{ $key };
    eval { &$code_ref(); };
    warn "Error Running \%FIXUPHANDLER::TODO item: $@" if $@;
  }
  %FIXUPHANDLER::TODO = (); # reset this list each hit

  ###  Run people's fixup code
  foreach my $code_ref ( values %FIXUPHANDLER::DO_EVERY_HIT ) {
    eval { &$code_ref(); };
    warn "Error Running \%FIXUPHANDLER::DO_EVERY_HIT item: $@" if $@;
  }

  return &Apache2::Const::OK;
}

sub END {
  &cleanup_handler;
}

1;


__END__


=head1 NAME

MVC::Simple::Request - Object for an instance of a request to an OpSystem page

=head1 SYNOPSIS

    use base qw( MVC::Simple::ObjectShare );
    my $request = $self->our_mvc->new_request( '/op/admin/index.tpl',
                                                 $form,
                                                 { RaiseError => 0 },
                                                 );

    ###  Run the request and print out the content
    $request->serve_page;
    
    ###  Get the context
    $request->context;

    ###  Run the ModPerl cleanup handler manually to clean out namespaces or whatever
    &MVC::Simple::Request::cleanup_handler();

=head1 ABSTRACT

=over 4

This object handles a Request to an OpSystem page basically.
Included is the code to use all the handlers in the
MVC::Simple::<section> objects.  The serve_page() method
performs one iteration of the Catch, Pitch, Page handler pass.

=back

=head1 METHODS

=over 4

=item serve_page()

This method does the actual handling to catch the previous step,
prepare the next page to be output and actually print to STDOUT
the content including headers.

The first phase is to catch the previous step.  Exactly which
step that was is determined by the form parameter 'catch' which
is the URI of the page submitted from.  NOTE: this URI must be
from another page in the OpSystem.  We cannot catch the page
from a WebSystem request.  The object for the to-be-caught page
is obtained, and a method called <page>_catch is called if it
exists.  The return value is tested as a perl Boolean value as to
whether the page was validated without errors.  A false return
value causes the catch page to be re-served so the user can fix
inputs on the form.  At that point the actual URI from the
request object is ignored and the URI in 'catch' is used instead.
NOTE: this means that the browser URL line will be showing the
URL of the page to-have-been-displayed if all validation passed
on the previous page, however the content served will be the
previous page.  Some care needs to be taken so that Client-Side
JavaScript does not use the document elements to obtain the URI
which may be wrong.  Once the catch handler returns true meaning
the previous page was caught successfully, we move onto the pitch
handler step.

The pitch handler's job is to answer the basic question: Should
this page be served next?  Often a page submission could take you
any number of places depending on the conditions of the form
inputs.  The "Edit" button in some of the UI interfaces is a good
example.  If only one non-directory box was checked the page that
should be served is the "Edit Single Item" page.  If A Directory
box is checked the user should choose 1) Edit the Directory Item,
2) Edit All Items under the driectory or 3) Edit the Driectory
Item and all of it's subitems.  This is the "Determine Edit
Page".  But it multiple Non-Directory items are checkedm, there
is no ambiguity about what the user wants to do and we can take
them straight to the "Edit Multiple Items" page.  Another common
example is in a wizard-style path flow, certain pages may be
optional based on decisions made in previous steps.

The pitch handler for a page is <page>_pitch.  If a pitch handler
returns 1, that is a "Successful Pitch" and the page handler will
be served.  If the pitch handler wants to answer "No, don't serve
this page", it returns 2 parameters, 0 and the URI of the page to
pitch in it's stead.  That new URI is interpreted and section
object retrieved.  The pitch handler for that step is then
called.  Pitch handlers can bounce around to each other until one
returns True.  Once a pitch handler has accepted the request, the
process moves onto the page handler for that page.

The page handler is called similarly looking for the method named
<page>_page to call.  This method will return a hash-ref of
values to give to the Template parser as swap values.  They are
made available to in the Template through tags like [%swap.foo%].
Note, page handlers *Should Never Fail*!  All validation on a
page or whether to serve a page should have been handled in a
previous step.  If there is no page handler swaps will be set to
an empty hashref.

The final step is to print the page using the Template library.
The shell for the page is determined by calling get_shell on the
page section object.  It can also be overridden by a passed query
form parameter 'shell' which is a shell relative to
odyc://my.reseller/op_skins/base/shells.  An Dave::Template::Instance object is
created and all the needed pieces are passed to the print_out()
method.

One of the key items passed is the 'page' area, which is accessed
in the TT Template using [%page.foo%].  One of the key items of
this hashref is the 'hidden' key.  That is a string of <input
type="hiddem" ...> tags which preserves any auto-state
information to be carried in the query string from page to page
and most-importantly it contains the 'catch' hidden field.  All
that will be needed in most Templates is a simple [%page.hidden%]
tag just following the <form> tag.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Bug
    MVC::Simple::ObjectShare
    Dave::ErrorSystem
    
    MVC::Simple
    MVC::Simple::FileServe
    CGI

=back
