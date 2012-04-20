#!/usr/bin/perl -w

use strict;
use File::Find qw(find);

### get files
my @FILES = ();
find( 
      ( sub {
        return if /^\./;
        return if ! -T;
        return if /\#/;
        return if /\~/;
        return if /.(h|ph|al|bs|ix|ld|pod)$/;
        return if $File::Find::name =~ m@/CVS@;
        push @FILES, "$File::Find::dir/$_";
      }
        ), 
      ( 
        "$ENV{HOME}/tsanet/lib",
        
#        '/usr/lib/perl5/5.8.8',
#        '/usr/lib/perl5/site_perl'
        )
      );
#print "@FILES\n";

### do args
my @A = ('--language=php',
         );
push @A, @ARGV;

### run the progs
system('gctags', @A, "--output=$ENV{HOME}/.tags", '--no-warn',@FILES) if `which gctags 2>&1` !~ / no /i;
system('etags',  @A, "--output=$ENV{HOME}/.TAGS", @FILES)             if `which etags  2>&1` !~ / no /i;
