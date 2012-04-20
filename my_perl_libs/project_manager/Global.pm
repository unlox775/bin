package Global;

#########################
###  DAVE/Global.pm
###  Version : $Id: Global.pm,v 1.1 2010/11/17 23:34:19 dave Exp $
###
###  Central lib for all system-global values
#########################

use strict;

#########################
###  Package Config

######  Exporter Parameters
###  Get the Library and use it
use Exporter;
use vars qw( @ISA
             @EXPORT_OK
             %EXPORT_TAGS

             $env_mode
             );
@ISA = ('Exporter');

###  Define the Exported Symbols
@EXPORT_OK = qw( &onAlpha &onBeta &onLive &isDave

                 &taint_safe_env

                 $env_mode
                 );
%EXPORT_TAGS = ( sys_context => [qw(&onAlpha &onBeta &onLive &isDave)],
                 );

#########################
###  Filesystem Globals

###  Read in the local environment settings
BEGIN {
    our $env_mode;
    if ( $ENV{DAVE_ENV_MODE}
         && $ENV{DAVE_ENV_MODE} =~ /^(alpha|beta|live)$/s
         ) {
        $env_mode = $ENV{DAVE_ENV_MODE};
    }
    elsif ( open(ENV_FILE, '/etc/dave/dave.env') ) {
        my $env_file = join('',<ENV_FILE>);
        close ENV_FILE;

        ###  Right now, this is the only (or the first) thing int the file
        ( $env_mode ) = ( $env_file =~ /^(alpha|beta|live)\b/s );

#     ###  The eventual syntax with name, value pairs
#     ( $env_mode ) = ( $env_file =~ /^mode\s*=\s*(alpha|beta|live)\s*$/m );
    }
    $env_mode ||= 'alpha';
}


#########################
###  System-wide state functions

sub onAlpha {
    return 1 if $env_mode eq 'alpha';
}

sub onBeta {
    return 1 if $env_mode eq 'beta';
}

sub onLive {
    return 1 if $env_mode eq 'live';
}

sub isDave {
    ###  Dave's machine's IP address, or manually set ENV var
    return 1 if ( $ENV{REMOTE_ADDR}
                  && ( $ENV{REMOTE_ADDR} eq '209.90.78.19'
                       && $ENV{ERROR_SYSTEM_OBJ_ID} =~ /dbuchanan/
                       )
                  ) || $ENV{IS_DAVE}; # hack until we get sandboxes working...
}

1;



__END__


=head1 NAME

Global - Central lib for all system-global values

=head1 SYNOPSIS

    use Global qw(:sys_context); # gets &onAlpha &onBeta &onLive
    use Global qw(       &onAlpha
                         &onBeta
                         &onLive
                         );


=head1 ABSTRACT

=over 4

This library is the place to store all absolute system-wide
global variables.  This way if all places reference these
definitions, we can re-architect storage locations, and more with
ease in the future.

Also, in here is some basic functionality to allow our developers
to have their own Alpha Environments based on a few ENV
parameters set in their .bashrc.

Functions for determining system context are also in here.  The
functions &onAlpha(), &onBeta(), and &onLive() allow us to change
code where absolutely necessary to define the differences between
our Alpha, Beta and Live environments.  These should be used as
little as possible because it defeats Quality assurance somewhat
whenever code chooses to do different behaviors per environment.

All the exportable symbols are not documented here yet because as
of the time of this writing we are currently writing the system
and the sets are bound to be changing.

=back

=head1 FUNCTIONS

=item &onAlpha(), &onBeta(), &onLive()

returns 1 or 0 whether it is detected that we are currently
running on Alpha, Beta, or Live development platforms
respectively.  It will make this determination off HOSTNAME or
other ENV parameters.

=back

=head1 DEPENDENCIES

Only Perl internals.

=back
