#!/usr/bin/perl -w

# Program: proxy
# Author:  Rob Brown
# Date:    Sep 19, 1998
# Purpose: View HTTP request and response headers for debugging assistance

use POSIX qw(WNOHANG);
use IO::Socket;
use IO::Select;

if ($^O!~/win32/i) {
  $SIG{CHLD} = sub {
    my $kid;
    while (($kid=waitpid(-1,WNOHANG)) > 0) {}
  };
}

{
  my ($m,$p) = $0 =~ m%^(.*)/([^/]+)$%;
  chdir $m;
}

$HTTP_PROXY=shift || 8888;
$timeout=1800;  # Wait half an hour before terminating a request

$server=IO::Socket::INET->new(
   Proto     => 'tcp',
   LocalPort => $HTTP_PROXY,
   Listen    => SOMAXCONN,
   Reuse     => 1);
die "can't setup server: $!" unless $server;
$|=1;

my %child = ();
my $LOGCOUNT = 1;

print "Proxy Server accepting connections on port $HTTP_PROXY\n";
while (1) {
  if ($^O=~/win32/i) {
    while (waitpid(-1,WNOHANG) > 0) {}
  }
  $client = $server->accept();
  if (!$client) {
    print "INTERNAL Accept error Caught!!!!\n";
    next;
  }
  $pid=fork;
  if (!defined $pid) {
    print $client "HTTP/1.1 500 OUCH\r
Server: WebH\@CK/1.0 (Windows98) FreeServers/0.7-beta6 PROXY\r
Connection: close\r
Content-Type: text/html\r
\r
<h1>OUCH! ERROR 610</h1>
The proxy server broke from being used to much.
";
    next;
  }

  if ($pid) {
    $LOGCOUNT++;
    $child{$pid} = $client->peerhost();
#    print "DEBUG: Parent forked process [$pid]\n";
    close $client;
    next;
  }
  if ($^O!~/win32/i) {
    alarm($timeout);
  }

  $client->autoflush(1);
  printf "%s [$LOGCOUNT] [Connection from %s]\n", (scalar localtime), $client->peerhost;
  print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
  open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
  print LOG sprintf("%s [$LOGCOUNT] [Connection from %s]\n", (scalar localtime), $client->peerhost);
  close LOG;
  $REQUEST="";
  while (1) {
    $append=<$client> || "";
    $REQUEST.=$append;
    last if length $append<3;
  }
  print "HEADER COMPLETE!-------------------\n$REQUEST";
  if ($REQUEST=~/^Content-length: (\d+)/im) {
    $bytes=$1;
    $CONTENT="";
    read($client,$CONTENT,$bytes);
    $REQUEST.=$CONTENT;
    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n<--------------------------[$LOGCOUNT]\n$REQUEST";
    close LOG;
  }
  print "DEBUG: REQUEST-------------------------------------------\n$REQUEST\n";
  if ($REQUEST=~s%^(\w+) http://([\w\-\.]+)%$1 %i) {
    $remotehost=$2;
    $remoteport=80;
    if ($REQUEST=~s%^(\w+ ):(\d+)%$1%i) {
      $remoteport=$2;
    }
    $REQUEST=~s%^(.*) HTTP/[\d\.]+%$1 HTTP/1.0%;
    print((scalar localtime)," [$LOGCOUNT] Resolving [$remotehost]...\n");
    my $remoteaddr=(gethostbyname $remotehost)[4]
      || error($client,"DNS ERROR: Cannot resolve ($remotehost)");
    $remoteaddr=join(".",(unpack("C4",$remoteaddr)));
    print((scalar localtime)," [$LOGCOUNT] Connecting to [$remoteaddr:$remoteport]...\n");
    $remote = IO::Socket::INET->new
      (Proto    => "tcp",
       PeerAddr => $remoteaddr,
       PeerPort => $remoteport)
        || error($client,"Cannot connect to port ($remoteport) on ($remotehost&nbsp;->&nbsp;$remoteaddr) <nobr>$!</nobr>");
    print((scalar localtime)," [$LOGCOUNT] Sending request for [$1]\n");
    $remote->autoflush(1);
    print $remote $REQUEST;
    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n<--------------------------[$LOGCOUNT]\n$REQUEST";
    close LOG;
    $RESULT="";
    while (1) {
      $append=<$remote>;
      $RESULT.=$append;
      last if length $append<3;
    }
    $HEAD=$RESULT;
    if ($RESULT=~/^Content-length: (\d+)/im) {
      $bytes=$1;
      $CONTENT="";
      print "CONTENTLENGTH FOUND! READING [$bytes] bytes...\n";
      read($remote,$CONTENT,$bytes);
      $RESULT.=$CONTENT;
    } else {
      print "CONTENTLENGTH MISSING! Reading everything...\n";
      while (<$remote>)
      {$RESULT.=$_;}
    }
    close $remote;
    print $client $RESULT;
    close $client;
    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n-------------------------->[$LOGCOUNT]\n$HEAD";
    close LOG;
    print((scalar localtime)," [$LOGCOUNT] Connection complete to [$remoteaddr:$remoteport]...\n");
  } elsif ($REQUEST=~m%^GET ftp://([\w\-\.]+)%i) {
    $remotehost=$1;
    $remoteport=21;
    if ($REQUEST=~m%^\w+ ftp://[\w\-\.]+:(\d+)%i) {
      $remoteport=$1;
    }
    error ($client,"PROXY ERROR: FTP not implemented! Not connecting to [$remotehost:$remoteport]");
    exit;
  } elsif ($REQUEST=~s%^(\w+) (/\S+)%$1 $2%i) {
    $remotehost="localhost";
    $remoteport=80;
    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n<--------------------------[$LOGCOUNT]\n$REQUEST";
    close LOG;
    if ($REQUEST=~s%^(\w+) :(\d+)%$1 %i)
    {$remoteport=$2;}
    $REQUEST=~s%^(.*) HTTP/[\d\.]+%$1 HTTP/1.0%;
    print "Connecting to [$remotehost:$remoteport]...\n";
    $remote = IO::Socket::INET->new(
                        Proto    => "tcp",
                        PeerAddr => $remotehost,
                        PeerPort => $remoteport)
      || error ($client,"Proxy ERROR! Can't connect to [$remotehost:$remoteport]");
    $remote->autoflush(1);
    print $remote $REQUEST;
    $RESULT="";
    while (1) {
      $append=<$remote>;
      $RESULT.=$append;
      last if length $append<3;
    }
    if ($RESULT=~/^Content-length: (\d+)/im) {
      $bytes=$1;
      $CONTENT="";
      print "CONTENTLENGTH FOUND! READING [$bytes] bytes...\n";
      read($remote,$CONTENT,$bytes);
      $RESULT.=$CONTENT;
    } else {
      print "CONTENTLENGTH MISSING! Reading everything...\n";
      while (<$remote>)
      {$RESULT.=$_;}
    }
    close $remote;
    print $client $RESULT;
    close $client;
#    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n-------------------------->[$LOGCOUNT]\n$RESULT";
    close LOG;
  } elsif ($REQUEST=~s%^(CONNECT) ([\w\-\.]+)%$1 %i) {
    $remotehost=$2;
    $remoteport=80;
    if ($REQUEST=~s%^(\w+ ):(\d+)%$1%i) {
      $remoteport=$2;
    }
#    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
    open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
    print LOG "\n----------PROXY------------[$LOGCOUNT]\n$REQUEST";
    close LOG;
    $REQUEST=~s%^(.*) HTTP/[\d\.]+%$1 HTTP/1.0%;

    print((scalar localtime)," [$LOGCOUNT] Connecting to [$remotehost:$remoteport]...\n");
    my $remote = IO::Socket::INET->new
      (Proto    => "tcp",
       PeerAddr => $remotehost,
       PeerPort => $remoteport)
        || error($client,"Cannot connect to port ($remoteport) on ($remotehost) <nobr>$!</nobr>");
    my $message = "HTTP/1.0 200 Connection established\r
Proxy-agent: Slappy-Proxy/1.1\r
\r\n";
    $client->syswrite($message, length $message);
    print((scalar localtime)," [$LOGCOUNT] Proxy established\n");
    my $sel = new IO::Select ($client, $remote);
    while (my ($reader) = $sel->can_read($timeout)) {
      my ($bytes,$buffer)=('','');
      if (fileno $reader eq fileno $client) {
        $bytes = $client -> sysread ($buffer, 4096);
        if ($bytes) {
          print((scalar localtime)," [$LOGCOUNT] Client said [$bytes] bytes.\n");
          $remote -> syswrite ($buffer, $bytes);
        } else {
          print((scalar localtime)," [$LOGCOUNT] Client closed connection.\n");
          last;
        }
      } else {
        $bytes = $remote -> sysread ($buffer, 4096);
        if ($bytes) {
          print((scalar localtime)," [$LOGCOUNT] Server said [$bytes] bytes.\n");
          $client -> syswrite ($buffer, $bytes);
        } else {
          print((scalar localtime)," [$LOGCOUNT] Server closed connection.\n");
          last;
        }
      }
      $buffer =~ s/([^\s\!-\[\]-\~])/sprintf("\\x%02X",ord $1)/eg;
#    print "=================Should be printing to ". $ENV{HOME} ."/PROXY.LOG=======================\n\n";
      open (LOG,">>". $ENV{HOME} ."/PROXY.LOG");
      print LOG "\n--------PROXY-PACKET-------[$LOGCOUNT]\n$buffer";
      close LOG;
    }
    print((scalar localtime)," [$LOGCOUNT] Shutting down proxy connection.\n");
    $client->close();
    $remote->close();
    exit;
  } else {
    error ($client,"PROXY ERROR: UNSUPPORTED PROTOCOL! Request:\n$REQUEST----------");
    exit;
  }
  close $client;
  exit;
}

exit;

sub error {
  my ($socket,$error)=@_;
  my $HTML="";
  open (OUT,"<error.html");
  while (<OUT>) {
    $HTML.=$_;
  }
  close OUT;
  $HTML=~s/\$error/$error/g;
  print $socket "HTTP/1.0 500 OUCH\r\nProxy-agent: Generic-Proxy/1.0\r\nContent-Type: text/html\r\nContent-length: ".(length $HTML)."\r\n\r\n$HTML";
  print((scalar localtime)," [$LOGCOUNT] Threw error [$error]!\n");
  close $socket;
  exit;
}
