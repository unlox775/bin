#!/usr/bin/perl -w

use lib qw(/Users/dave/bin/my_perl_libs);
use Dave::Bug qw(:common);
use CGI;
use CGI::Util qw(&escape);
# use CGI::Auth::Basic;
use LWP;
use LWP::UserAgent;

# BUGW(\%ENV);

# $cauth = CGI::Auth::Basic->new(cgi_object=>CGI->new, password => crypt('123qwe','ae') );
# BUGW($cauth);

$query = new CGI;

# BUGW($query);

my $ua = LWP::UserAgent->new;
$ua->timeout(10);
$ua->env_proxy;
# $ua->credentials('192.168.2.1:80','Linksys RVS4000 ', $query->param('u'), $query->param('p'));
$ua->credentials('192.168.2.100:80','Linksys WAP 2000', $query->param('u'), $query->param('p'));

# my $response = $ua->get('http://192.168.2.1/');
my $response = $ua->get('http://192.168.2.100/');
# BUGW($response);
# BUGW($response->content);

if ($response->is_success) {
    BUGW('GOOD !!!!!!!!!!!!!!!!!!!!!!');
    print "Content-type: text/html\n\n";
    print "Success";  # or whatever
}
else {
    BUGW('BAD');
#    print "Status: ". $response->{_rc} .' '. $response->{_msg} ."\n";
    print "Content-type: text/html\n\n";
    print "Invalid";  # or whatever
}
