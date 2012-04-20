package Dave::Bug;

#########################
###  Dave/Bug.pm
###  Version : $Id: Bug.pm,v 1.1 2008/04/15 20:38:16 dave Exp $
###
###  Lib for shared debug functions
#########################

use strict;

#########################
###  Package Config

use CGI qw( &escapeHTML );
use Time::HiRes qw( gettimeofday tv_interval );

###  Load all require()'s if Mod-Perl 
BEGIN {
  if ( $ENV{MOD_PERL} ) {
    require Data::Dumper;
  }
}

######  Exporter Parameters
###  Get the Library and use it
use Exporter;
use vars qw( @ISA @EXPORT_OK %EXPORT_TAGS $bug_on $caller_level $force_filename );
@ISA = ('Exporter');

###  Define the Exported Symbols
@EXPORT_OK = qw( &bug &bug_warn &bugw &bug_stack &bugs &bug_stack_warn &bugsw
                 &BUG &BUG_WARN &BUGW &BUG_STACK &BUGS &BUG_STACK_WARN &BUGSW
                 &START_TIMER &END_TIMER &PAUSE_TIMER &RESUME_TIMER &reset_timers &report_timers
                 
                 $bug_on );
%EXPORT_TAGS = (common => [qw(&bug &bug_warn &bugw &bug_stack &bugs &bug_stack_warn &bugsw
                              &BUG &BUG_WARN &BUGW &BUG_STACK &BUGS &BUG_STACK_WARN &BUGSW
                              &START_TIMER &END_TIMER &PAUSE_TIMER &RESUME_TIMER &reset_timers &report_timers
                              )]);


###  Det default flag
$bug_on = 1;
$caller_level = 1;
$force_filename = 0;

&reset_timers();


#########################
###  Bug Functions

###  Respoect $bug_on
sub bug {
  local $_;
  return 1 unless $bug_on;
  &opt_content_type;
  print &bug_out( @_ );
}

sub bug_warn {
  local $_;
  return 1 unless $bug_on;
  local $ENV{REQUEST_METHOD} = 0;
  warn &bug_out( @_ );
}
*bugw = *bug_warn;

sub bug_stack {
  local $_;
  return 1 unless $bug_on;
  &opt_content_type;
  print &bug_out( @_, &get_stack );
}
*bugs = *bug_stack;

sub bug_stack_warn {
  local $_;
  return 1 unless $bug_on;
  local $ENV{REQUEST_METHOD} = 0;
  warn &bug_out( @_, &get_stack );
}
*bugsw = *bug_stack_warn;


###  Disregard $bug_on
sub BUG {
  local $_;
  &opt_content_type;
  print &bug_out( @_ );
}

sub BUG_WARN {
  local $_;
  local $ENV{REQUEST_METHOD} = 0;
  warn &bug_out( @_ );
}
*BUGW = *BUG_WARN;

sub BUG_STACK {
  local $_;
  &opt_content_type;
  print &bug_out( @_, &get_stack );
}
*BUGS = *BUG_STACK;

sub BUG_STACK_WARN {
  local $_;
  local $ENV{REQUEST_METHOD} = 0;
  warn &bug_out( @_, &get_stack );
}
*BUGSW = *BUG_STACK_WARN;



#########################
###  Helper Functions

sub opt_content_type {
  if ( $ENV{REQUEST_METHOD} && ! $ENV{CONTENT_TYPED} ) {
    print "Content-type: text/html\n\n";
    $ENV{CONTENT_TYPED} = 1;
  }
}

sub get_stack {
  my @stack;  my $i = 1;
  while ( caller($i+1) ) { $i++;  push @stack, [ caller($i) ]; }

  ###  Format Stack
  my @formatted_stack;
  foreach my $call ( @stack ) {
    (my $file = $call->[0].'.pm') =~ s@::@/@g;
    $file = $call->[1] if $call->[1] !~ /\Q$file\E$/;
    (my $shortsub = $call->[3]) =~ s/^.*?([^\:]+)$/$1/;
    my $format = "$shortsub called at $file line $call->[2]";
    push @formatted_stack, $format;
  }
  return \@formatted_stack
}

sub bug_out {
  local $_;
  my ( @bug_stuff ) = @_;
  push @bug_stuff,'' unless @bug_stuff;

  require Data::Dumper;  $Data::Dumper::Sortkeys = 1;  $Data::Dumper::Quotekeys = 0;

  my $bug_out = '';
  foreach my $param ( @bug_stuff ) {
    my $param_bug = ( 'BUG: '. 
                      ( ( ! $force_filename
                          && ( caller($caller_level + 1) )[3]
                          ) || 
                        ( caller($caller_level) )[1]
                        ) .
                      ', line ' .
                      ( caller($caller_level) )[2] .
                      "\n" . 
                      Data::Dumper::Dumper( $param ).
                      "\n"
                      );
    $param_bug =~ s/([\[\{\(])\s*?\n +/$1 /sg;
#    my $param_bug = Data::Dumper::Dumper( $param );
#    $param_bug =~ s/;\n$/' from '. ( caller($caller_level + 1) )[3] .', line '. ( caller($caller_level) )[2] ."\n\n"/es;

    $bug_out .= $param_bug    
  }

  if ( $ENV{REQUEST_METHOD} ) {
    $bug_out = &escapeHTML( $bug_out );
    $bug_out =~ s/\</&lt;/g;
    $bug_out =~ s/\>/&gt;/g;
    $bug_out =~ s/(?<!<br>)\n/<br>\n/g;
    $bug_out =~ s/\t/    /g;
    $bug_out =~ s/ /&nbsp;/g;
  }

  return $bug_out;
}


#########################
###  Benchmarking / Timer functions

my $time_i = 0;
my ( %timers, %timeseq, %timex );

sub reset_timers {
  return 1 unless $bug_on;
  ( %timers, %timeseq, %timex ) = ();
  &START_TIMER('all_global');
}

sub START_TIMER (*) {
  return 1 unless $bug_on;
  return if UNIVERSAL::isa($timers{$_[0]} , 'ARRAY');
  local $_[0] = $_[0];
  $_[0] =~ s/^.+\://g;
  $timers{$_[0]} = [($timers{$_[0]} || 0), [gettimeofday]];
  $timeseq{$_[0]} = $time_i++ if ! exists $timeseq{$_[0]};
  $timex{$_[0]} = [0,0] unless exists( $timex{$_[0]} );
  $timex{$_[0]}[0]++;
}
sub END_TIMER (*) {
  return 1 unless $bug_on;
  return unless UNIVERSAL::isa($timers{$_[0]} , 'ARRAY');
  local $_[0] = $_[0];
  $_[0] =~ s/^.+\://g;
  $timers{$_[0]} = $timers{$_[0]}[0] + tv_interval($timers{$_[0]}[1]);
  $timex{$_[0]}[1]++;
}

sub PAUSE_TIMER (*) {
  return 1 unless $bug_on;
  return unless UNIVERSAL::isa($timers{$_[0]} , 'ARRAY');
  local $_[0] = $_[0];
  $_[0] =~ s/^.+\://g;
  $timers{$_[0]} = $timers{$_[0]}[0] + tv_interval($timers{$_[0]}[1]);
}
sub RESUME_TIMER (*) {
  return 1 unless $bug_on;
  return if UNIVERSAL::isa($timers{$_[0]} , 'ARRAY');
  local $_[0] = $_[0];
  $_[0] =~ s/^.+\://g;
  $timers{$_[0]} = [($timers{$_[0]} || 0), [gettimeofday]];
}

sub report_timers {
  return 1 unless $bug_on;
  my ( $fh ) = @_;
  $fh ||= \*STDOUT;

  unless ( ! %timers
           || ( keys( %timers ) == 1
                && exists $timers{'all_global'}
                )
           ) {
    END_TIMER all_global;
    my $nl = ( $ENV{REQUEST_METHOD} ) ? "</td></tr><tr><td>\n" : "\n";
    my $sp = ( $ENV{REQUEST_METHOD} ) ? "&nbsp;" : " ";
    my @ary = ( map { [$_,
                       ( sprintf("%.6f",$timers{$_}) ."s" ),
                       ( "x$sp". $timex{$_}[0]
                         . ( ($timex{$_}[1] != $timex{$_}[0]) ? ("$sp/$sp". $timex{$_}[1]) : '' ) . "$sp$sp"
                         ),
                       ( "averaging${sp}" . sprintf("%.6f",$timers{$_} / $timex{$_}[0]) ."s" ),
                       ( "which${sp}is${sp}" . sprintf("%.6d",1 / ($timers{$_} / $timex{$_}[0])) . "/s" ),
                       ( "totalling${sp}"
                         . ($timers{'all_global'} ? sprintf("%.2f",($timers{$_} / $timers{'all_global'}) * 100) : '' ) . "%${sp}of${sp}all_global"
                        )
                       ] }
                sort { $timeseq{$a} <=> $timeseq{$b} }
                keys %timers
                );

    ###  HTML table output
    if ( $ENV{REQUEST_METHOD} ) {
      print $fh "<table width=300><tr><td>" if $ENV{REQUEST_METHOD};
      print $fh (  "TIMERS:$nl"
                   . join("$nl",
                          map {join("</td><td>\n", @$_)}
                          @ary
                          )
                   );
      print $fh "</td></tr></table>" if $ENV{REQUEST_METHOD};
    }
    ###  Command-line output
    else {
      my @x;

      

#foo                     0.000061s   x 1        averaging 0.000061s  which is 016393/s totalling 0.01% of all_globa
      format TIMER_REPORT_FORMAT =
@<<<<<<<<<<<<<<<<<<<<<< @<<<<<<<<<< @<<<<<<<<< @<<<<<<<<<<<<<<<<<<< @<<<<<<<<<<<<<<<< @*
$x[0],                  $x[1],      $x[2],     $x[3],               $x[4],            $x[5]
.

      ###  Select our format for this filehandle (note: we don't restore...  :( )
      select((select($fh),
              $~ = "TIMER_REPORT_FORMAT",
              )[0]);

      print $fh "TIMERS:\n";

      foreach (@ary) {
        @x = @$_;
        write $fh;
      }
      print $fh "\n";
    }
  }
}

END {
  &report_timers;
}

1;


__END__


=head1 NAME

Dave::Bug - Lib for shared debug functions

=head1 SYNOPSIS

    use Dave::Bug qw(:common);
    use Dave::Bug qw(&bug &bug_warn &bug_stack &bug_stack_warn &BUG);

    bug \%foo, \@bar, $puck;
    bug_warn "See this: ". $a;
    bug_stack;
    bug_stack "and a var";
    bug_stack_warn "to STDERR";

=head1 ABSTRACT

=over 4

This library is the light-weight useful library to aid in
debugging code.  When you get to the point during debugging that
you would like to see the value of a certain parameter at a point
in your code, you can simply use:

     bug $whatever_var;
     bug \@whatever_var;
     bug \%whatever_var;

Data::Dumper is used to print out the nested structure in a
generic way.

The other main purpose for this library is to reduce the
likelyhood that an end-used will see a debugging message meant
for developers eyes.  The flag $bug_on is a global exported var
that by default set to 1.

=back

=head1 FUNCTIONS

=item bug()

Prints to STDOUT a simple Data::Dumper of the passed-in vars.  It
is context sentitive, so it prints HTML when printing to a
browser, and flat text to a command-line runtime.  Also in the
debug label, t prints the package name, subroutine name, and line
number.

Also, bug() will only print if $bug_on is true.

=item bug_warn(), bugw()

Same formatting as bug(), but prints using warn() to STDERR.
Only prints if $bug_on is true.

=item bug_stack(), bugs()

Same formatting as bug(), but it adds another arrayref to 'bug'
on the end which has stack trace information. Only prints if
$bug_on is true.  This is useful to see the entire trace back
through all the callers up to the bug call.

=item bug_stack_warn(), bugsw()

bug_stack_warn() is to bug_stack() as bug() is to bug_warn().
Prints to STDERR, only prints if $bug_on is true.

=item BUG(), BUG_WARN(), BUG_STACK_WARN()...

Same behavior as their lower-cased counterparts, but it will
print whether or not $bug_out is set.

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Data::Dumper
    Dave::Global
    CGI

=back
