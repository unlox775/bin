package MVC::Simple::RequestBase;

#########################
###  MVC/Simple/RequestBase.pm 
###  Version : $Id: RequestBase.pm,v 1.1 2008/04/29 22:12:50 dave Exp $
###
###  Base Object for Web Request Objects
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use Dave::ErrorSystem qw(:oo_methods);
use Session::Simple;
use MVC::Simple::ContextWrap;
use CGI qw( &escapeHTML &escape );
use CGI::Cookie;

###  Mod Perl detection
use constant MOD_PERL => (exists $ENV{MOD_PERL} || exists $ENV{MOD_PERL_API_VERSION});
use constant MP2 => (exists $ENV{MOD_PERL_API_VERSION} && $ENV{MOD_PERL_API_VERSION} == 2);
BEGIN {
  # Test mod_perl versione and use the appropriate components
  if (MOD_PERL) {
    if (MP2) {
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

###  Make Session::Simple have some "ContextWrap OK" methods
*Session::Simple::context_wrap_ok = 
  sub { { get => 1,
          set => 1,
        }; };


#########################
###  General Utilility

sub print_header {
  my $self = shift;

  print "Content-type: ". $self->{content_type} ."\n\n";
}

sub do_location_redirect {
  my $self = shift;
  my ( $to_where ) = @_;

  ###  If just checking
  if ( ! defined $to_where ) {
    return $self->{'do_location_redirect'};
  }

  ###  Setup the mod_perl return
  $self->{'do_location_redirect'} = $to_where;
  if ( MOD_PERL ) {
    die if ! MP2;
    $self->{'return_http_status'} = &Apache2::Const::HTTP_MOVED_TEMPORARILY;
    $self->{'apache_request'}->headers_out->add('Location' => $to_where);
  }
  ###  CGI
  else {
    print "Status: 302 Moved\nLocation: $to_where\n\n";
  }

  return $self->{'do_location_redirect'};
}

sub cookie {
  my $self = shift;
  my ( $cookie ) = @_;

  if ( ! $self->{'cookies'} ) {
    my $manually_passed = $self->form->{'ENV_HTTP_COOKIE'};

    my %cookies = ( $manually_passed
                    ? ( CGI::Cookie->parse( $manually_passed ) )
                    : (MOD_PERL && MP2)
                    ? ( CGI::Cookie->fetch( $self->{'apache_request'} ) )
                    : (! MOD_PERL)
                    ? ( CGI::Cookie->fetch )
                    : ( die "MP1???" )
                    );
    $self->{'cookies'} = { map { ($_, [$cookies{$_}->value]) } keys %cookies };
  }

  return unless $self->{'cookies'}{ $cookie };
  return(wantarray ? @{$self->{'cookies'}{ $cookie }} : $self->{'cookies'}{ $cookie }[0] );
}


#########################
###  Template Environment

sub page_area {
  my $self = shift;
  my ( $page_uri ) = @_;

  my %hidden = ( %{ $self->{'page_hidden'} || {} },
                 catch => $page_uri,
               );
  ###  Carry along Pause Chain ID
  $hidden{'pause_chain_id'} = $self->form->{'pause_chain_id'} if defined $self->form->{'pause_chain_id'};
  ###  Add a generated form_id if there
  $hidden{'form_id'} = $self->{'generated_form_id'} if defined $self->{'generated_form_id'};

  ###  Run page_area_extra
  my %area_extra;
  if ( $self->can('page_area_extra') ) {
    $self->page_area_extra(\%hidden, \%area_extra );
  }

  ###  Prepare the usable forms
  my $hidden = join("\n",
                    map {'<input type="hidden" name="'.$_.'" value="'.escapeHTML($hidden{$_}).'">'}
                    keys %hidden
                    );
  ###  For URI hidden, drop the 'catch' param as there
  ###    as URI submissions by def are not forms to catch
  delete $hidden{'catch'};
  my $hidden_uri = join("&",
                        map {escape($_).'='.escape($hidden{$_})}
                        keys %hidden
                        );

  ###  The form filling subarea: 'fill'
  my ($fill, $fill_orig) = ({}, {});
  if ( $self->{'fill'} ) {
    $fill_orig = { %{ $self->{'fill'} } }; # copy so we don't modify
    $fill =      { %{ $self->{'fill'} } }; # copy so we don't modify
    $fill->{$_} = &escapeHTML($fill->{$_}) foreach ( keys %$fill );

    ###  Filling in multi-value form elements
    $fill->{'sb'} = $fill->{'selbox'}
    = sub { $fill_orig->{$_[0]} eq $_[1] ? 'selected' : '' };
    $fill->{'rb'} = $fill->{'radbox'} = $fill->{'radbut'}
    = sub { $fill_orig->{$_[0]} eq $_[1] ? 'checked' : '' };
    $fill->{'cb'} = $fill->{'chkbox'}
    = sub { $fill_orig->{$_[0]}          ? 'checked' : '' };
  }
  ###  With value="" fill-in
  $fill->{'sbv'} = $fill->{'selboxval'}
  = sub { ($fill_orig->{$_[0]} eq $_[1] ? 'selected ' : '') .'value="'. escapeHTML($_[1]) .'"' };
  $fill->{'rbv'} = $fill->{'radboxval'} = $fill->{'radbutval'}
  = sub { ($fill_orig->{$_[0]} eq $_[1] ? 'checked ' : '') .'value="'. escapeHTML($_[1]) .'"' };
  $fill->{'cbv'} = $fill->{'chkboxval'}
  = sub { ($fill_orig->{$_[0]}          ? 'checked ' : '') .'value="'. escapeHTML($_[1] || 1) .'"' };

  return { uri => $self->uri,
           host => $ENV{HTTP_HOST},
           fill => $fill,
           fill_orig => $fill_orig,
           hidden => $hidden,
           hidden_uri => $hidden_uri,
           catch_uri => ( 'catch='. escape($page_uri) ),
           cookie_uri => ( 'ENV_HTTP_COOKIE='. escape(&CGI::Cookie::get_raw_cookie( MP2 ? $self->{'apache_request'} : undef ) || '') ),
           paused_process => MVC::Simple::ContextWrap->new([$self, 'paused_process'], $self->context),
           session_ro => MVC::Simple::ContextWrap->new([$self, 'session_ro'], $self->context),
           session    => MVC::Simple::ContextWrap->new([$self, 'session'], $self->context),
           user    => scalar($self->user),
           action => $self->{'page_action'},
           %area_extra,
         };
}

sub fill {
  my $self = shift;
  return $self->{'fill'} unless @_;
  my ( $to_add, $replace ) = @_;

  $self->{'fill'} = { %{ $replace ? {} : ($self->{'fill'} || {}) },
                      %$to_add
                      };

  return $self->{'fill'};
}


#########################
###  Process-Pause System

###  System to pause a form that is half-filled out, jump 
###    to another URL, and be able to come back and restore
sub catch_process_pause {
  my $self = shift;
  my ( $form ) = @_;
  $form ||= $self->form;
  return unless $self->{'session_setup'};

  ###  If a pause request is in the form
  if ( $form->{'process_pause_to'} ) {
    ###  Get things ready for cold storage
    my %cold_form = %$form;
    delete $cold_form{'catch'};

    ###  Determine Pause Chain ID
    my $pause_chains = $self->session->get('pause_chains') || [];

    my $pause_chain_id = $form->{'pause_chain_id'};
    $pause_chain_id = @$pause_chains if ! defined $pause_chain_id || ! defined $pause_chains->[$pause_chain_id];
    
    ###  Add to the chain
    $pause_chains->[$pause_chain_id] ||= [];
    my $process_title = $form->{'paused_process_title'} || 'Error, no Paused Process Title';
    my $resume_url = $self->{'this_uri'} .'?pause_chain_id='. $pause_chain_id .'&resume_process='. @{ $pause_chains->[$pause_chain_id] };
    push @{ $pause_chains->[$pause_chain_id] },
      { uri => $self->{'this_uri'},
        chain_id => $pause_chain_id,
        process_title => $process_title,
        resume_url => ('http://'. $self->hostname . $resume_url),
        resume_rel_url => $resume_url,
        fill => \%cold_form,
      };
    $self->session->set(pause_chains => $pause_chains);

    ###  Create URI to location bounce to
    my $process_pause_to = $form->{'process_pause_to'};
    $process_pause_to =~ s/\?$//g if ( $process_pause_to =~ /\?/g ) == 1;
    $process_pause_to .= ( ( ($process_pause_to =~ /\?/) ? '&' : '?' )
                           . 'pause_chain_id='.$pause_chain_id
                           );

    ###  Setup the bounce
    $self->do_location_redirect($process_pause_to);

    return 1; # signal, "Yes, I caught a process-pause, catch handler should just return 1"
  }
  return 0;
}

sub pause_chain {
  my $self = shift;
  my ( $form ) = @_;
  $form ||= $self->form;
  return unless $self->{'session_setup'};
  return unless defined $form->{'pause_chain_id'};

  my $pause_chains = $self->session_ro->get('pause_chains');
  return $pause_chains->[ $form->{'pause_chain_id'} ] if $pause_chains;
}
sub paused_process { ${ shift()->pause_chain(@_) || [] }[-1] || {} } # undef = empty hashref for ContextWrap

###  For use at the end of a catch handler, just does Location bounce
sub catch_process_resume {
  my $self = shift;
  my ( $form ) = @_;
  $form ||= $self->form;
  return unless $self->{'session_setup'};

  ###  If a pause request is in the form
  if ( defined $form->{'resume_pause_chain'}
       && $form->{'resume_pause_chain'} =~ /^\d+$/
       ) {
    my $pause_chains = $self->session_ro->get('pause_chains');
    if ( $pause_chains
         && $pause_chains->[ $form->{'resume_pause_chain'} ]
         && @{ $pause_chains->[ $form->{'resume_pause_chain'} ] }
         ) {
      ###  Setup the bounce
      $self->do_location_redirect($pause_chains->[ $form->{'resume_pause_chain'} ][-1]{'resume_url'});
      return 1; # signal, "Yes, I caught a process-resume, catch handler should just return 1"
    }
  }
  return 0;
}

###  For use in the page step after we're location-bounced back
###    to the original paused-process
sub process_resume { 
  my $self = shift;
  my ( $form ) = @_;
  $form ||= $self->form;
  return unless $self->{'session_setup'};

  ###  If a pause request is in the form
  if ( defined $form->{'pause_chain_id'}
       && $form->{'pause_chain_id'} =~ /^\d+$/
       && defined $form->{'resume_process'}
       && $form->{'resume_process'} =~ /^\d+$/
       ) {
    ###  Get the restore_queue
    my $restore_queue = $self->session_ro->get('restore_queue');
    $restore_queue ||= [];
    my $pause_chains = $self->session_ro->get('pause_chains');

    ###  Skip out if there's nothing to restore...
    return 0 if ( ( ! $pause_chains
                    || ! $pause_chains->[ $form->{'pause_chain_id'} ]
                    || ! @{ $pause_chains->[ $form->{'pause_chain_id'} ] }
                    )
                  && ( ! $restore_queue
                       || ! $restore_queue->[ $form->{'pause_chain_id'} ]
                       )
                  );

    ###  Move the chain step to the restore queue, if it's
    ###    still in the chain
    if ( $pause_chains &&
         $pause_chains->[ $form->{'pause_chain_id'} ][ $form->{'resume_process'} ]
         ) {
      my $process = $pause_chains->[ $form->{'pause_chain_id'} ][ $form->{'resume_process'} ];
      ###  Remove from chain
      splice( @{ $pause_chains->[ $form->{'pause_chain_id'} ] }, $form->{'resume_process'} );
      ###  Add to restore queue
      $restore_queue->[ $form->{'pause_chain_id'} ] = { process_id => $form->{'resume_process'}, process => $process };
      ###  Update the session
      $self->session->set(restore_queue => $restore_queue);
      if ( $form->{'resume_process'} == 0 ) {
        ###  Clean up pause_chains as we go...
        delete $pause_chains->[ $form->{'pause_chain_id'} ];
        if ( @$pause_chains 
             ) { $self->session->set(pause_chains => $pause_chains); }
        else { $self->session->remove('pause_chains'); }
      }
      else { $self->session->set(pause_chains => $pause_chains); }
    }
    
    ###  Skip out if the restore_queue doesn't have the right stuff
    return 0 if ( ! $restore_queue->[ $form->{'pause_chain_id'} ]
                  || $restore_queue->[ $form->{'pause_chain_id'} ]{'process_id'} != $form->{'resume_process'}
                  );

    ###  Get the process fill stuff and add it to fill
    $self->fill( $restore_queue->[ $form->{'pause_chain_id'} ]{'process'}{'fill'} );
    
    return 1; # signal, "Yes, I resumed a process and stuck stuff in $r->fill()"
  }
  return 0;
}


#########################
###  Sessions and Persistance

sub session_ro { $_[0]->get_session(1) }

sub session { $_[0]->get_session(0) }

sub define_session_setup {
  my $self = shift;
  my ( $filename ) = @_;

  $self->{'session_setup'} = { filename => $filename,
                               do_mkpath => 1,
                             };

  $self->get_session(1);
}

sub get_session {
  my $self = shift;
  my ( $read_only ) = @_;
  return unless $self->{'session_setup'};

  ###  If already got a session object but they want
  ###    it to have write-access, then change modes
  if ( $self->{'session'} && ! $read_only && $self->{'session'}->read_only ) {
    $self->{'session'}->read_only(0);
  }

  ###  Otherwise, if no session, create it!
  elsif ( ! $self->{'session'} ) {
    $self->{'session'} = 
      Session::Simple->new({ blocking_timeout => 10,
                             %{ $self->{'session_setup'} },
                             read_only => $read_only,
                           });
  }

  return $self->{'session'};
}

sub cleanup {
  my $self = shift;

  $self->{'session'}->release if $self->{'session'};
  delete $self->{'session'};

  return 1;
}


#########################
###  Session-centered Utilities

sub generate_form_id {
  my $self = shift;

  my $form_inc = $self->session->get('form_inc') || 1;
  $form_inc++;
  $self->session->set(form_inc => $form_inc);

  $self->{'generated_form_id'} = $form_inc;
}

sub form_success {
  my $self = shift;
  my ( $form_id ) = @_;
  $form_id = $self->form->{'form_id'};
  return unless $form_id;

  my $form_success = $self->session->get('form_success') || [];
  push @$form_success, $form_id;
  shift @$form_success if @$form_success > 3; # only keep track of the last 3 form successes
  $self->session->set(form_success => $form_success);

  return 1;
}

sub form_already_succeeded {
  my $self = shift;
  my ( $form_id, $yes_i_will_immediately_return ) = @_;
  $form_id = $self->form->{'form_id'};
  return unless $form_id;

  my $form_success = $self->session_ro->get('form_success');
  if ( $form_success
       && grep {$_ eq $form_id} @$form_success
       ) {
    ###  Call catch_process_resume for them if they 
    ###    signal that they are going to return immediately
    if ( $yes_i_will_immediately_return ) {
      $self->catch_process_resume;
    }
    ###  Return, "Yes, the form in question has already been successfully proccessed"
    return 1;
  }

  return 0;
}


#########################
###  General Utility Methods

1;
