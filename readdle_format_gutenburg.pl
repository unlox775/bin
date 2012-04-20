#!/usr/bin/perl -w

###  Read everything into memory
my $file = join '', <>;

###  A Common alternate to chapter headings
$file =~ s/^Chapter (\d+)\n([^\n]+?)\.$/"$1   ". uc($2)/iegm;

###  Add line breaks and paragraph tags
$file =~ s/(\S)\n(\d)/$1<br\/>\n$2/mg; # Targeting the Table of Contents!
$file =~ s/(\S)\n\n(\S)/$1\n<\/p>\n<p>\n$2/mg; # normal paragraphs

###  Auto detect Chapter Headings (things that are in ALL-CAPS)
$file =~ s/^(?:([0-9]+) +([0-9A-Z][0-9A-Z\"\-\:\ \,\'\.]+?(?:\n[0-9A-Z][0-9A-Z\"\-\:\ \,\'\.]+?)*)|(Contents|[0-9A-Z\-\:\ \,\'\"]{5,}))$/{ $1 ? ( "<!--SPLIT--NAME:Chapter $1: ". titleify($2) ."--><h3>". titleify("Chapter $1: $2") ."<\/h3>")
                                                                                            : ( "<!--SPLIT--NAME:".             titleify($3) ."--><h3>". titleify($3)               ."<\/h3>")
                                                                        }/emg;

###  Any remaning line breaks 2 or more together...
$file =~ s/\n\n/<br\/>\n<br\/>\n/mg;

###  Print it all out
print $file;



###  Helper to re-capitalize Chapter titles properly...
sub titleify {
    join('', map {ucfirst($_)} split(/\b/, lc(join(' ',split(/\n/,$_[0])))));
}
