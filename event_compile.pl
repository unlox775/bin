#!/usr/bin/perl -w

#########################
###  bin/event_compile.pl
###  Version: $Id: event_compile.pl,v 1.1 2007/10/24 02:20:45 dave Exp $
###  
###  Generate an event page
#########################

use strict;
use Odyc::Bug qw(:common);
select((select(STDOUT), $| = 1)[0]);
select((select(STDERR), $| = 1)[0]);

#########################
###  Libraries



#########################
###  Main Runtime

my @imgs = qw( /alpha/snape/BWE_Gavin_Birth/lg/P1220088.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220090.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220094.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220096.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220098.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220100.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220109.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220115.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220125.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220126.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220128.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220129.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220131.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220135.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220136.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1220138.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1230153.JPG
               /alpha/snape/BWE_Gavin_Birth/lg/P1230155.JPG
               );

my $filename = $ARGV[0];

###  Slurp in the template
my $template = join '', <>;

my ( $entry_template ) = ( $template =~ /<\!-- TEMPLATE START\s(.+)TEMPLATE END -->/s );

my $generated = "<tr>\n\n";
my $event = 'gavin_birth_2006';
foreach my $i ( 0.. $#imgs ) {
  my $entry = $entry_template;
  (my $file = $imgs[$i]) =~ s@.+/@@;

  $entry =~ s/\[file\]/$file/g;
  $entry =~ s/\[event\]/$event/g;

  $generated .= $entry;

  if ( ($i+1)%3 == 0 ) { $generated .= "\n\n</tr>\n<tr>\n\n"; }
}
$generated .= "\n\n</tr>\n";

$template =~ s/<\!-- GENERATED START -->\s.+<\!-- GENERATED END -->/<\!-- GENERATED START -->\n$generated<\!-- GENERATED END -->/s;

open FILE, ">$filename";
print FILE $template;
close FILE;

exit 0;
