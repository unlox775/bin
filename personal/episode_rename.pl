#!/usr/bin/perl -w

#########################
###  procs/extent_query2cvs
#########################
#
# Version : $Id: episode_rename.pl,v 1.1 2008/03/10 19:37:10 dave Exp $
#
#########################

use strict;

#########################
###  Initialization / Libraries
#########################

###  Declare vars
use vars qw( @DB
             );
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
sub bug { print Data::Dumper->Dump([$_[0]],[qw(var)])."\n\n"; $_[0] }

my $test_mode = 0;



#########################
###  Read Episode Name Files
#########################

my @data;

if ( -d '/Users/dave/episode_names' ) {
  local $^W = 0;
  opendir(EPS, '/Users/dave/episode_names');
  foreach my $file ( grep {!/^\./} readdir(EPS) ) {
    my $ffile = '/Users/dave/episode_names/'.$file;
    next unless -f $ffile && -r $ffile;
    unless ( open(EFILE, "<$ffile") ) {warn "Could not open Episodes File $ffile: $!"; next; }
    my @lines = map { chomp($_);  
                      [map { s/^\s+|\s+$//sg; $_ } &split_delim_line(',',$_,'"')] 
                      } split(/[\x0a\x0d]+/,join('',<EFILE>));
#    bug \@lines;

    (my $show = lc($file)) =~ s/.csv$//;
    foreach my $line ( @lines ) {
      ###  Format 1 = 1x01,EpisodeName
      if ( $line->[0] =~ /^(\d+)x(\d+)$/ ) {
        push @data, [ $show,
                      (map {$_*1} (shift(@$line) =~ /^(\d+)x(\d+)$/)),
                      join(' ', @$line)
                      ];
      }
      ###  Format 2 = 1,1,EpisodeName
      if ( $line->[0] =~ /^(\d+)$/ ) {
        push @data, [ $show,
                      shift(@$line),
                      shift(@$line),
                      join(' ', @$line)
                      ];
      }
    }
  }
}


my %ep_names;
foreach my $line (@data) {
  ($line->[3] = lc($line->[3])) =~ s/\(\d+\)//g;
  $line->[3] =~ s/\s\s+/ /g;
  $line->[3] =~ s/[\(\)\?\!\,\"\']//g;
  $line->[3] =~ s/\&/and/g;
  $line->[3] =~ s/^\s+|\s+$//sg;

  $ep_names{$line->[0].'_'.$line->[1].'x'.$line->[2]} = $line->[3];
}


#########################
###  Main Runtime
#########################

while (<>) {
  chomp;
  next if -d;
  my ( $path, $file ) = ( m@(^.+/)(.+?)$@ );
  next if $file =~ /^(.DS_Store)$/i;

  ###  Match Pieces
  my ( $sname, $sn, $ep, $ename, $type ) = ( $file =~ /^(24.?|numb3rs.?|\D+?)s?0?(\d)([ex]?\d\d|[ex]\d+)(.*?)(\.avi|\.mpg)$/i );
  if ( !$sname ) {
    warn "File doesn't match: $path$file\n";
    next;
  }
  $ep =~ s/\D//g;
  $ep = sprintf("%.2d",$ep);

  ($sname = lc($sname)) =~ s/\W/_/g;
  $sname =~ s/_$//;

  if ( $ep_names{$sname.'_'.$sn.'x'.($ep*1)} ) {
    $ename = '_'.$ep_names{$sname.'_'.$sn.'x'.($ep*1)};
  }
  else {
    $ename =~ s/(^.WS|PROPER(-UMD)?|TvT|lol|BT|FIXED(-LOL)?|REPACK|REAL|NoTV|ws.dvdrip.xvid-river|XOR|\[[^\[\]]+\])//g;
    $ename =~ s/(HDTV|hdtv-(lol|fov)|yestv|notv|(ws[ _])?dvdrip|XVID(-\w{2,3}($|\.))?)//ig;
  }

  ###  Episode name formatting
  ($ename = lc($ename)) =~ s/\W/_/g;
  $ename =~ s/__+/_/g;
  $ename =~ s/^_|_$//g;
  $ename = "_$ename" if length $ename;

  my $new_file = "${sname}_${sn}x$ep$ename$type";
  warn "$file                            -->  $new_file". 
    (($new_file eq $file) ? '                       ---  NOT MOVING!!!' : '') ."\n";
  next if $test_mode;
  next if $new_file eq $file;
  if ( lc($new_file) eq lc($file) ) {
    die "Moving ${path}___$file...  FILE IS ALREADY NAMED THIS TEMP FILE!!!  Exiting...\n" if -e "${path}___$file";
    `mv -i "$path$file" "${path}___$file"`;
    `mv -i "${path}___$file" "$path$new_file"`;
  }
  else { 
    die "Moving $path$new_file...  FILE IS ALREADY NAMED THIS!!!  Exiting...\n" if -e "$path$new_file";
    `mv -i "$path$file" "$path$new_file"`;
  }
}
























sub split_delim_line {
  local $_;
  my ( $delim_value, $line, $delim_quote_value ) = @_;

  ###  Create the container we'll store the field values in
  my @field_values = ();


  ###  Set up the $delim_value_q and $delim_quote_value_q
  ###    NOTE: the below system does not work for delimiters
  ###      that are more than 1 characters in length
  my $delim_value_q = quotemeta( $delim_value );
  my $delim_quote_value_q = quotemeta( $delim_quote_value );


  ######  Split apart the delimeted fields
  ###  SPLIT DELIMITED-AND-QUOTED LINES
  if ( $delim_quote_value_q ) {
    ###  The Quoted Delimeted method
    push(@field_values, $+) while $line =~ m{
      $delim_quote_value_q([^$delim_quote_value_q\\]*(?:\\.[^$delim_quote_value_q\\]*)*)$delim_quote_value_q$\
delim_value_q?  ###  Groups the phrase inside the quotes
        | ([^$delim_value_q]+)$delim_value_q?
          | $delim_value_q
        }gx;
    push(@field_values, undef) if substr($line, -1, 1) eq $delim_value;

    ###  Unescape values
    foreach ( @field_values ) {
      next unless defined($_);
      s/\\([$delim_quote_value_q\\n])/($1 eq 'n' ? "\n" : $1)/eg;
    }
  }

  ###  SPLIT DELIMITED-AND-UNQUOTED LINES
  else {
    @field_values = split(/$delim_value_q/, $line);
  }

  ###  Return the values
  return @field_values;
}
