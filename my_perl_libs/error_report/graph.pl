#!/usr/bin/perl -w

#########################
###  graph.i
#
# Version : $Id: graph.pl,v 1.1 2009/02/04 00:08:20 dave Exp $
#
#########################

###  Pragmas
use strict;
use Dave::Bug qw(:common);
use lib qw(..);

#########################
###  Configuration, Setup

use GD::Graph::bars;
use CGI qw(:standard);


#########################
###  Main Runtime

###  Get (or simulate) the dataset
#my @labels  = qw( under 10s  20s  30s  40s  50s  60s  70s over );
my @dataset = qw(
                  20   40   60   80   65   15   10   20    5   17
                  20   40   60   80   65   15   10   20    5   17
                  20   40   60   80
                                      65   15   10   20    5   17
                 );
@dataset = split(',',param('dataset')) if param('dataset');
my @data    = ( [map {'x'} @dataset], \@dataset);


###  Setup parameters
my $width  = param('width')  || 165;
my $height = param('height') || 50;
my $graph = GD::Graph::bars->new( $width, $height );
$graph->set( no_axes => 1,

             ###  Space things (designed best for 24 or 30 units)
             t_margin => -5,
             l_margin => -5,
             r_margin => -5,
             axis_space => -4,
             values_space => 0,
             bar_spacing => 1,
             legend_spacing => 0,
             );
#bug $graph;

###  Create the graph image
my $image = $graph->plot( \@data );
if ( !$image ) {
    bug $graph->error;
    die "Could not create graph: ". $graph->error;
}


###  Print it out to the browser
print "Content-type: image/png\n\n";

binmode STDOUT;
print $image->png();

exit 0;
