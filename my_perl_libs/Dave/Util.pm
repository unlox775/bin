package Dave::Util;

#########################
###  Dave/Util.pm
###  Version : $Id: Util.pm,v 1.4 2010/11/01 23:37:35 dave Exp $
###
###  Main Lib for useful misc functions
#########################

use strict;
use Dave::Bug qw(:common);

#########################
###  Package Config

use CGI::Util qw(&escape &unescape);

# use Apache2::Reload;

######  Exporter Parameters
###  Get the Library and use it
use Exporter;
use vars qw( @ISA @EXPORT_OK);
@ISA = ('Exporter');

###  Define the Exported Symbols
@EXPORT_OK = qw( &taint_safe_env
                 &split_delim_line
                 &join_delim_line
                 &nested_join
                 &read_conf
                 &write_conf
                 &do_validation
                 &luhn_10
                 &get_sql_date
                 &get_utc_date
                 &get_epoch_date
                 &get_mdy_date
                 &last_dom
                 &good_regdom_format
                 &good_hostname_format
                 &binary_search
                 &gva
                 &ungva
                 &gvs
                 &uniq
                 &css_parse_words
                 &css_parse_stuff
                 &css_encode_stuff
                 &patterns_match
                 );

my %MONTH_HASH = ( jan => 1, feb => 2, mar => 3, apr => 4, may => 5, jun => 6, jul => 7, aug => 8, sep => 9, 'oct' => 10, nov => 11, dec => 12 );

###  Un-taint some Environment vars
sub taint_safe_env {
  $ENV{PATH} = '/bin:/sbin:/usr/bin:/usr/sbin';
}


#########################
###  Util Functions

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
      $delim_quote_value_q([^$delim_quote_value_q\\]*(?:\\.[^$delim_quote_value_q\\]*)*)$delim_quote_value_q$delim_value_q?  ###  Groups the phrase inside the quotes
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

sub join_delim_line {
  my ( $delim_value, @items ) = @_;
  my $delim_quote_value;
  if ( UNIVERSAL::isa($items[0], 'ARRAY') ) {
    $delim_quote_value = $items[1];
    @items = @{ $items[0] };
  }
  $delim_quote_value = '"' unless defined $delim_quote_value;

  my $delim_value_q = quotemeta( $delim_value );
  my $delim_quote_value_q = quotemeta( $delim_quote_value );
  
  my @joinme;
  foreach ( @items ) {
    if ( /[$delim_value_q$delim_quote_value_q\n\\]/ ) {
      s/([$delim_quote_value_q\\])/\\$1/g;
      s/\n/\\n/g;
      $_ = $delim_quote_value.$_.$delim_quote_value;
    }
    push @joinme, $_;
  }
  return join( $delim_value, @joinme );
}

sub nested_join {
  my ( $delim_values, @items ) = @_;
  $delim_values = &gva( $delim_values );
  $delim_values->[0] = ',' if ! defined $delim_values->[0];

  ###  Do the subjoins first
  foreach my $i ( 0..$#items ) {
    if ( UNIVERSAL::isa($items[$i], 'ARRAY') ) {
      $items[$i] = &nested_join([( @$delim_values )[1..$#{ $delim_values }]], @{ $items[$i] } );
    }
  }

  return join $delim_values->[0], @items;
}

#########################
###  Reading Conf Files

sub read_conf {
  my ( $file, $prefs ) = @_;
  $prefs ||= {};

  ###  Check file existence
  if ( ! -e $file ) {
    if ( $prefs->{'no_file_is_ok'} ) {
      return {};
    }
    else { die "read_conf: file does not exist: $file"; }
  }

  ###  Check file readablity
  if ( ! -r $file ) { die "read_conf: could not read file $file: permission demied"; }

  ###  Open and read
  my %conf_hash;
  open(FILE, "<$file") or die "read_conf: could not read file $file: $!";
  my ( $field_name, $field_type, $field_value, $here_to_match );
  my $type_op_regex = join('|',map {quotemeta($_)} qw(= %= != <<));
  while (<FILE>) {
    chomp;
    ###  Handle Here-To document operator content lines
    if ( ( $field_name ) && ( $field_type eq '<<' ) && ( $here_to_match ) ) {
      ###  Close the field if we reached the token
      if ( $_ eq $here_to_match ) {
        $conf_hash{ $field_name } = $field_value;
        undef $field_name; undef $field_type; undef $field_value;
      }
      ###  Content line, add it to the value
      else {
        if ( defined $field_value ) { $field_value .= "\n$_"; }
        else                        { $field_value  = $_; }
      }
    }
    ###  Skip comments if they are anchored to the front of the line
    elsif ( ( /^\#/ ) || ( $_ eq '' ) ) { next; }
    ###  Syntax Error, non-field-definition line when expected
    elsif ( ( ! $field_name ) && ( !/^([\w\-]+)\s*($type_op_regex)\s*(\S.*?|)$/ ) ) {
      warn "read_conf: Syntax error in $file at line $.: expected field definition : $_";
    }
    ###  Field-definition line
    elsif ( /^([\w\-]+)\s*($type_op_regex)\s*(\S.*?|)$/ ) {
      my ( $n, $op, $stuff ) = ( $1, $2, $3);
      ###  Close the last field
      if ( $field_name ) {
        $conf_hash{ $field_name } = $field_value;
        undef $field_name; undef $field_type; undef $field_value; undef $here_to_match;
      }
      ###  Start the new field parsing
      $field_name = $n;
      $field_type = $op;
      $field_value = $stuff || '';

      ###  Type Handling
      if ( ( $field_type eq '!=' ) && ( $field_value eq '' ) ) {
        $field_value = undef;
      }
      elsif ( $field_type eq '<<' ) {
        $here_to_match = $stuff;
        $field_value = undef;
      }
      elsif ( $field_type eq '%=' ) {
        $field_value = &unescape($field_value);
      }
    }
    ###  Content Line
    elsif ( /^(\s+)(\S.*|)$/ ) {
      my ( $space, $stuff ) = ( $1, $2 );
      $space = '' if $space eq ' ';
      
      ###  Type Handling
      if ( $field_type eq '%=' ) {
        $field_value = '' unless defined $field_value;
        $field_value .= &unescape($stuff);
      }
      else {
        if ( ( defined $field_value ) 
             && ( $field_value ne '') ) { $field_value .= "\n$space$stuff"; }
        else                            { $field_value = "$space$stuff"; }
      }
    }
  }
  ###  Close the last field
  if ( $field_name ) {
    $conf_hash{ $field_name } = $field_value;
    undef $field_name; undef $field_type; undef $field_value;
  }
  close FILE;

  ###  Expand CSS Format values if triggered
  if ( $prefs->{'css_parse_all_values'} ) {
    foreach my $field ( sort keys %conf_hash ) {
      die "Bad field definition in conf value: \"$field = ".$conf_hash{$field}."\", definition must be bound by curly braces"
        unless $conf_hash{$field} =~ /^\s*\{\s*(.*?)\s*\}\s*$/s;
      my @words = &css_parse_words(defined($1) ? $1 : '');
      my $stuff = &css_parse_stuff(\@words, $field);

      $conf_hash{ $field } = $stuff;
    }
  }

  return \%conf_hash;
}

sub css_parse_stuff {
  my ( $words, $field ) = @_;

  my %stuff;
  FIELD : while ( my ($subfield, $colon, $value, $semicolon) = splice(@$words, 0, 4) ) {
    ###  If we are at the end of the block
    if ( $subfield eq '}' ) {
      unshift(@$words, $colon, $value, $semicolon) if defined($colon);
      ###  Ignore a semicolon (':') trailing after the end of a block ('}')
      shift @$words if $words->[0] && $words->[0] eq ';';
      last FIELD;
    }

    unless ( defined($subfield) && $subfield =~ /^[\w\-]+$/
               && defined($colon) && $colon eq ':'
               && defined($value) && $value ne '}'
               && ( $value eq '{'
                    || !defined($semicolon)
                    || $semicolon eq ';'
                    || $semicolon eq '}'
                    )
             ) {
      die "Bad subfield definition in $field schema: \"$subfield$colon $value$semicolon\", syntax: sub-field-name: \"value\";";
    }
    ###  Change dashes to underscores in subfield
    $subfield =~ tr/\-/\_/;
    ###  If value is an associative array definition
    if ( $value eq '{' )    {
      ###  $semicolon is really the first word of the definintion
      unshift( @$words, $semicolon ) if defined $semicolon;
      my ( $new_value ) = &css_parse_stuff($words, "$field.$subfield");
      $stuff{$subfield} = $new_value;
      ### &css_parse_stuff modified our passed-by-ref @words
    }
    ###  If bound by double-quotes
    elsif ( $value =~ /^\"(.*?)\"$/s )    { ($stuff{$subfield} = $1) =~ s/\\(.)/$1/g; }
    ###  If bound by single-quotes
    elsif ( $value =~ /^\'(.*?)\'$/s ) { $stuff{$subfield} = $1; }
    ###  Otherwise, take it literally
    else                             { $stuff{$subfield} = $value; }

    ###  If we are at the end of the block
    if ( $semicolon eq '}' ) {
      ###  Ignore a semicolon (':') trailing after the end of a block ('}')
      shift @$words if $words->[0] eq ';';
      last FIELD;
    }
  }

  return( \%stuff );
}

sub css_parse_words {
  my ( $string ) = @_;

  my @words;
  push(@words, $+) while $string =~ m{
    (\;)
      | (\:)
      | (\{)
      | (\})
      | (\"[^\"\\]*(?:\\.[^\"\\]*)*\")
      | (\'[^\']*\')
      | ([^\"\;\:\s]+)
    }gx;
  
  return @words;
}

sub css_encode_stuff {
  my ( $hashref, $seen ) = @_;
  $seen ||= [];

  my @words;
  
  ###  Aavoid infinite loops
  my $strobj = $hashref.'';
  return '{}' if grep { $strobj eq $_ } @$seen;
  push @$seen, $strobj;

  ###  Quote each value
  foreach my $key ( sort keys %$hashref ) {
    ###  Change underscores back to dashes in subfield names
    (my $dash_key = $key) =~ tr/\_/\-/;

    if ( UNIVERSAL::isa( $hashref->{ $key }, 'HASH') ) {
      ###  Recurse
      push @words, "$dash_key:", &css_encode_stuff($hashref->{ $key }, $seen);
    }
    ###  Undefined, empty, or Non-HASH ref
    elsif ( ! defined($hashref->{ $key })
            || length($hashref->{ $key }) == 0
            || ref( $hashref->{ $key } ) 
            ) {
      push @words, "$dash_key:", ("'". ($hashref->{ $key } || '') ."';");
    }
    elsif ( $hashref->{ $key } !~ /\W/ ) {
      push @words, "$dash_key:", ($hashref->{ $key }.";");
    }
    elsif ( $hashref->{ $key } !~ /[\']/ ) {
      push @words, "$dash_key:", ("'".$hashref->{ $key }."';");
    }
    else {
      ( my $value = $hashref->{ $key } ) =~ s/[\\\"]/\\$&/g;
      push @words, "$dash_key:", ('"'.$hashref->{ $key }.'";');
    }
  }

  return '{ '. join(' ', @words) .' }';
}


#########################
###  Writing Conf Files

sub write_conf {
  my ( $file, $hash, $prefs ) = @_;
  die 'Syntax, write_conf($filename, $data_hash, {});'
    unless UNIVERSAL::isa($hash, 'HASH');

  ###  Open the file
  open( CONF, ">$file" ) or return;

  foreach my $key (sort keys %$hash) {
    ###  If undef: != (nullable)
    if ( ! defined $hash->{$key} ) { print CONF "$key != \n"; }
    ###  If value has funky chars: %= (URL escape)
    elsif ( $hash->{$key} =~ /[\000-\010\013-\037\177-\377]/ ) { print CONF "$key %= ". &escape($hash->{$key}) ."\n"; }
    ###  If value doesn't start with space or contain newlines: = (normal one-liner)
    elsif ( $hash->{$key} !~ /^\s|\n/ ) { print CONF "$key = ". $hash->{$key} ."\n"; }
    ###  If value has at least one instance of /^ (\S|$)/m: <<ETX (Here-to Doc)
    elsif ( $hash->{$key} =~ m'^ (\S|$)'m ) {
      my $token = 'ETX';
      while ( $hash->{$key} =~ /$token/ ) { $token .= '_ETX'; }
      print CONF "$key <<$token\n". $hash->{$key} ."\n$token\n";
    }
    ###  If value starts with whitespace: = (normal multi-liner starting on second line)
    elsif ( $hash->{$key} =~ /^\s/ ) {
      ( my $value = $hash->{$key} ) =~ s/\n(\S)/\n $1/sg;
      print CONF "$key =\n". $value ."\n";
    }
    ###  All other, default: = (normal multi-liner starting on first line)
    else {
      ( my $value = $hash->{$key} ) =~ s/\n(\S)/\n $1/sg;
      print CONF "$key = ". $value ."\n";
    }
  }

  close CONF;

  1;
}

sub do_validation {
  my ( $col, $setting, $valhash, $hash ) = @_;

  ###  Strip off whitespace unless 'no_strip_ws'
  $setting =~ s/^\s+|\s+$//g if ! $valhash->{'no_strip_ws'} && defined( $setting );
  ###  Strip off optional '+' for format=decimal
  $setting =~ s/^\+// if $valhash->{'format'} && $valhash->{'format'} eq 'decimal' && defined( $setting );
  ###  Fix bool 'false' value
  $setting = 0 if ($valhash->{'format'}) && ($valhash->{'format'} =~ /^bool(ean)?$/) && (! defined($setting));
  ###  Scrub off spaces and dashes in 'credit_card_number' types
  $setting =~ s/[\s\-]//g if ($valhash->{'format'}) && ($valhash->{'format'} =~ /^credit_?card_?number$/) && (! defined($setting));

  ###  If the valhash has a pre_scrub coderef, run it
  if ( $valhash->{'pre_scrub'} 
       && UNIVERSAL::isa($valhash->{'pre_scrub'}, 'CODE') 
       ) {
    ###  Pass it a ref to our setting so they can modify it
    &{ $valhash->{'pre_scrub'} }($col, \$setting, $valhash, $hash);
  }

  ###  No-Edit
  if ( $valhash->{'noedit'} && ! $hash->{'ignore_noedit'}
       ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." cannot be edited",'noedit']} ); }

  ###  If there is NO value
  if ( ! defined( $setting ) || $setting eq '') {
    ###  Required
    if    ( $valhash->{'rq'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is required",'required']} ); }
  }
  ###  If there IS a value, validate it...
  else {
    ###  Max length
    if    ( $valhash->{'maxl'} && length($setting) > $valhash->{'maxl'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." may not be longer than $valhash->{maxl} characters",'too_long']} ); }
    ###  Min length
    elsif ( $valhash->{'minl'} && length($setting) < $valhash->{'minl'}
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." must be at least $valhash->{minl} characters",'too_short']} ); }
    ###  Regular Expression
    elsif ( $valhash->{'rxp'} && $setting !~ $valhash->{'rxp'} # NOTE, we need qr//'d value here
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not valid",'invalid_rxp']} ); }
    ###  Negative Match Regular Expression
    elsif ( $valhash->{'nrxp'} && $setting =~ $valhash->{'nrxp'} # NOTE, we need qr//'d value here
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not valid",'invalid_rxp']} ); }
    ###  Format : email
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'email'
            && $setting !~ /^[a-z0-9][a-z0-9\.\-\+]*\@([a-z0-9\-]+\.)+[a-z]{2,}$/
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid email address",'invalid_email']} ); }
    ###  Format : boolean
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} =~ /^bool(ean)?$/
            && $setting !~ /^(t|true|y|yes|1|f|false|n|no|0|1)$/
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid boolean value",'invalid_boolean']} ); }
    ###  Format : decimal
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'decimal'
            && $setting !~ /^\-?(\d+(\.\d+)?|\.\d+)$/
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid number",'invalid_decimal']} ); }
    ###  Format : integer
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'integer'
            && $setting !~ /^\-?\d+$/
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid number",'invalid_integer']} ); }
    ###  Format : date
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'date'
            && ( $setting !~ /^\d{4}\-\d{2}\-\d{2}$/
                 || ! &get_epoch_date( $setting )
               )
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid date",'invalid_date']} ); }
    ###  Format : datetime
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'datetime'
            && ( $setting !~ /^\d{4}\-\d{2}\-\d{2}( \d{2}:\d{2}:\d{2})?$/
                 || ! &get_epoch_date( $setting )
               )
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid date",'invalid_date']} ); }
    ###  Format : credit_card_number
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} =~ /^credit_?card_?number$/
            && ( $setting !~ /^\d{13,16}$/
                 || ! &luhn_10( $setting )
               )
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid credit card number",'invalid_cc_number']} ); }
    ###  Format : ip
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'ip'
            && ( $setting !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}?$/
                 || ( ! grep {$_ > 255} split(/\./, $setting) )
               )
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." is not a valid IP address",'invalid_ip_address']} ); }
    ###  Format : hostname
    elsif ( $valhash->{'format'}
            && $valhash->{'format'} eq 'hostname'
            && ! &good_hostname_format($setting)
            ) {
      my @result = &good_hostname_format($setting);
      return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'}).": $result[2]",$result[1]]} );
    }
    ###  Greater Than
    elsif ( defined $valhash->{'gt'}  && $setting <= $valhash->{'gt'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." may not be less than or equal to $valhash->{gt}",'greater_than']} ); }
    ###  Greater Than or Equal To
    elsif ( defined $valhash->{'ge'} && $setting < $valhash->{'ge'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." may not be less than $valhash->{ge}",'greater_than_or_eq']} ); }
    ###  Less Than
    elsif ( defined $valhash->{'lt'}  && $setting >= $valhash->{'lt'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." may not be greater than or equal to $valhash->{lt}",'less_than']} ); }
    ###  Less Than or Equal To
    elsif ( defined $valhash->{'le'} && $setting > $valhash->{'le'} 
            ) { return( 0, $setting, { "${col}_error" => [ucfirst($valhash->{'name'})." may not be greater than $valhash->{le}",'less_than_or_eq']} ); }
  }

  ###  If the valhash has a post_scrub coderef, run it
  if ( $valhash->{'post_scrub'} 
       && UNIVERSAL::isa($valhash->{'post_scrub'}, 'CODE') 
       ) {
    ###  Pass it a ref to our setting so they can modify it
    &{ $valhash->{'post_scrub'} }($col, \$setting, $valhash, $hash);
  }

  return( 1, $setting, {} );
}

###  LUHN(10) algorithm
sub luhn_10 {
  my ($i, $sum) = (1,0);
  $sum += $_ foreach ( map {($i++%2) ? $_ : (split('',$_*2)) } reverse split('',$_[0]) );
  return ($sum % 10) ? 0 : 1;
}


#########################
###  Date/Time Functions

sub get_parsed_date {
  my ( $year, $month, $mday, $hour, $min, $sec, $am_pm, $tz ) = @_;

  return undef if ( @_ <= 1 ) && ( not defined $year );

  ###  Fudge over...
  if ( @_ == 1 ) {
    ###  If they give us a UTC date
    if ( $year =~ /^(\d{4})-(\d{2})-(\d{2})(?: (\d{1,2}):(\d{2}):(\d{2}(?:\.\d+)?)([\+\-]\d{1,2}(?::\d{2})?)?)?$/s
         ) { ( $year, $month, $mday, $hour, $min, $sec, $tz ) = ( $1, $2, $3, $4 || 0, $5 || 0, $6 || 0, $7 ); }
    ###  If they give us an date in the format (mm/dd/yyyy)
    elsif ( $year =~ /^(\d{1,2})\/(\d{1,2})\/(\d{2,4})$/s 
            ) { ( $month, $mday, $year ) = ( $1, $2, $3  ); }
    ###  If they give us an Epoch date
    elsif ( $year =~ /^\d{5,}$/s 
            ) { ( $sec, $min, $hour, $mday, $month, $year ) = localtime($year);  $month++; }
    ###  If they give us a "Tue, 26 Oct 2004 15:53:37 GMT" date
    elsif ( $year =~ /^\w{3}, (\d{1,2}) (\w{3}) (\d{4}) (\d{1,2}):(\d{2}):(\d{2}) ([A-Z]{3})$/s 
            ) { ( $mday, $month, $year, $hour, $min, $sec, $tz ) = ( $1, $2, $3, $4, $5, $6, $7 ); }
  }

  ###  Handle AM/PM
  if ( $am_pm ) {
    $hour += 12 if ( $am_pm =~ /PM/i ) && ( $hour != 12 );
    $hour -= 12 if ( $am_pm =~ /AM/i ) && ( $hour == 12 );
  }
  ###  Switch signs if the TZ is numeric offset
  if ($tz && $tz =~ /[\+\-]\d{1,2}(?::\d{2})?/) {
      $tz =~ tr/\+\-/\-\+/;
      $tz = "GMT $tz";
  }

  if ( exists($MONTH_HASH{lc($month)}) ) {
    $month = $MONTH_HASH{lc($month)};
  }

  ###  Final Adjustments
  $year += 1900 if $year < 1900;
  $year += 100 if $year < 1970;
  $mday ||= 1;

  return( $year, $month, $mday, $hour, $min, $sec, $tz )
}

###  Get SQL date
sub get_sql_date {
  my ( $year, $month, $mday, $hour, $min, $sec, $tz ) = &get_parsed_date( @_ );
  return undef if not defined $year;

  ###  Return the formatted date (Might cause warnings)
  local $^W = 0;
  return sprintf( "%.4d-%.2d-%.2d %.2d:%.2d:%.2d", 
                  $year, $month, $mday, $hour, $min, $sec
                  );
}
###  Clone the sub
*get_utc_date = *get_sql_date;

###  Get Epoch date
sub get_epoch_date {
  ###  Skip ahead if it's already an epoch_date
  return $_[0] if ( @_ == 1 ) && ( $_[0] =~ /^\d{5,}$/s );
  my ( $year, $month, $mday, $hour, $min, $sec, $tz ) = &get_parsed_date( @_ );
  return undef if not defined $year;

  ###  Format the year for the timelocal() call
  $year -= 1900 if $year > 1900;

  ###  Get a lib
  require Time::Local;

  ###  Return the formatted date (Might cause warnings)
  local $^W = 0;
  local $ENV{TZ} = $tz if $tz;
  my $return = eval { &Time::Local::timelocal($sec, $min, $hour, $mday, ($month-1), $year); } || 0;
  if ( $@ ) {
    require Carp;
    &Carp::cluck( $@ );
  }
  $return;
}

###  Get MDY date
sub get_mdy_date {
  my ( $year, $month, $mday, $hour, $min, $sec, $tz ) = &get_parsed_date( @_ );
  return undef if not defined $year;

  ###  Return the formatted date (Might cause warnings)
  local $^W = 0;
  return ($month+0) ."/". ($mday+0) ."/". $year;
}

###  Get the last day of the month for the given month
sub last_dom {
  my ( $year, $mon ) = @_; # month is 1-based

  return ( (0, 31,0,31, 30,31,30, 31,31,30, 31,30,31)[ $mon ]
           ###  February Algorithm
           || (localtime(&get_epoch_date($year + int($mon/12), ($mon%12)+1, 1) - 12*3600) )[3]
           );
}


#########################
###  Domain RFC Syntax checkers

###  Check some structure things for any hostname
sub good_hostname_format {
  my ($my_domain) = @_;

  ###  Ends in a . followed by 2 to 4 chars
  if ( $my_domain !~ /\.[a-z]{2,4}$/i
       ) { return( wantarray ? (0,'bad_extension','Invalid domain extension') : 0); }
  ###  Can't have .'s or -'s in unacceptable tandem
  if ( $my_domain =~ /^[\.\-]|\.\.|\-\.|\.\-|[\.\-]$/
       ) { return( wantarray ? (0,'dot_dash_position','Illegal decimal or dash positioning') : 0); }
  ###  No nonstandard chars
  if ( $my_domain =~ /[^a-z0-9A-Z\-\.]/
       ) { return( wantarray ? (0,'bad_chars','Illegal charactar(s)') : 0); }
  ###  No piece may be longer than 60 chars
  if ( grep { length($_) >= 60 } split( /\./, $my_domain )
       ) { return( wantarray ? (0,'piece_too_long','More than 60 charactars between decimals') : 0); }

  return 1;
}

###  Check the format of a Registered Domain
sub good_regdom_format {
  my ($my_domain) = @_;

  ###  Check good_hostname_format() first
  my @good_hostname_format = &good_hostname_format(@_);
  return(wantarray ? @good_hostname_format : $good_hostname_format[0]) if ! $good_hostname_format[0];

  ###  Non .name format checker
  if ( ( $my_domain !~ /\.name$/ ) &&
       ( $my_domain !~ /^[a-z0-9\-]+
                         \.
         ( [a-z]{2,} |
           [a-z]{2,}\.[a-z]{2}
                           )$
                        /six )
       ) { return( wantarray ? (0,'bad_registered_domain','Illegal registered domain name format') : 0); }
  ###  Separate .name format checker
  if ( ( $my_domain =~ /\.name$/ ) &&
       ( $my_domain !~ /^[a-z]+
                         \.
                         [a-z]+
                         \.name$
                        /six )
       ) { return( wantarray ? (0,'bad_dot_name_domain','Illegal .name registered domain format') : 0); }

  return 1;
}


#########################
###  Simple Binary Search Algorithm

sub binary_search {
  my ($goal, $fh, $fsize, $prefs) = @_;
  $prefs ||= {};

  my $debug = 0;

  ###  Do a binary search through the file
  my $result_line;
  my ( $rstart, $rend ) = (0, $fsize);
  my ( $last_value, $higher ) = ( undef, 1);
  my ( $closest_value, $cval_position ) = (undef, 0);
#  print STDERR "Binary Search:\n" if $debug;
  BINARY : while ( $rstart < $rend
                   && $rstart >= 0 # just for failsafe
                   && $rend >= 0 # just for failsafe
                 ) {
    ###  Find the point in the middle of the range
    my $middle = int((($rend - $rstart) / 2) + $rstart);
    last BINARY if $middle == $rstart;
    print STDERR sprintf("At %.4f percent (%.0f, range is %.0f)...\n", $middle / $fsize, $middle, $rend - $rstart) if $debug;

    ###  If we are down to the last little bit, 
    ###  then just read the whole range
    my $read_whole_range = 0;
    if ( ($middle - $rstart) < ($prefs->{'average_line_length'} ? ($prefs->{'average_line_length'} * 10) : 40960) ) {
      $middle = $rstart;
      $read_whole_range = 1;
    }

    ###  Seek and find the next line
    seek($fh, $middle, 0) or die "Seek failed: $!";
    my $drop = <$fh>; # drop the partial line

    ###  Read the lines
    my $tell = $middle;
    my $first_line = 1;
    READ : while ( $tell < $rend ) {
      my $line = <$fh>;

      ###  Check the value
      my ($value) = ($line =~ /(^\d+)/);
#      bug [$value, $goal, $read_whole_range, $tell];
      if ( defined $value ) {
        ###  Keep track of which value was the closest so far
        ###    to the goal without going over it, and it's position
        if ( $prefs->{'seek_to_closest'} 
             && ( $value <= $goal
                  && ( ! defined $closest_value
                       || $value > $closest_value
                       )
                  )
             ) {
          $closest_value = $value;
          my $currpos = tell($fh) or die "Tell failed: $!";
          $cval_position = $currpos - length( $line );
#          bug [$currpos, length( $line ), $cval_position];
        }

        ###  We are done if this value == the goal
        if ( $value == $goal ) {
            $result_line = $line;
            last BINARY;
        }

        ###  At the beginning of each seek (check first line of a block only...)
        ###    check that things still seem sequential...
        if ( $first_line && ! $prefs->{'ignore_sequence_errors'} ) {
          die "File is not sorted, expected lower value than $last_value, got $value" if !$higher && defined $last_value && $value > $last_value;
          die "File is not sorted, expected higher value than $last_value, got $value" if $higher && defined $last_value && $value < $last_value;
        }

        ###  Skip to the next section unless reading the whole range
        if ( ! $read_whole_range ) {
          ###  Seek ahead
          if ( $goal > $value ) {
            $rstart = $middle;
            $higher = 1;
            $last_value = $value;
            last READ;
          }
          ###  Seek backwards
          else { # ( $goal < $value )
            $rend = $middle;
            $higher = 0;
            $last_value = $value;
            last READ;
          }
        }
      }

      
      $tell = tell($fh) or die "Tell failed: $!";
      die "Tell error: $!" if $tell == -1;
      $first_line = 0;
    }

    ###  If we read the whole range, but got to here
    ###    then it means the value is not found.
    last if $read_whole_range;
  }

  ###  Do a final seek to the closest line if asked for
  if ( $prefs->{'seek_to_closest'} ) {
    seek($fh, $cval_position, 0) or die "Seek failed: $!";
  }

  return $result_line;
}


#########################
###  Miscellaneous Functions

###  Get value as an array ref
sub gva { return( ( $_[0] && UNIVERSAL::isa($_[0], 'ARRAY') ) ? $_[0] : [ $_[0] ] ) }

###  Return first value if only 1 element, and the ref if more
sub ungva { return( ( $_[0] && UNIVERSAL::isa($_[0], 'ARRAY') && @{$_[0]} == 1 ) ? $_[0]->[0] : $_[0] ) }

###  Get value as a scalar ref
sub gvs { return( ( $_[0] && UNIVERSAL::isa($_[0], 'SCALAR') ) ? $_[0] : \$_[0] ) }

###  Simple uniq function
sub uniq {
  local $_;
  my %hash;

  my @ret = map {
    $_ ||= '';
    my $__ = $hash{$_};
    $hash{$_} = 1;
    ($__) ? () : $_;
  } @_;

  @ret;
}

###  Try a test string against a list of patterns
sub patterns_match {
  my ( $test_str, @patterns ) = @_;

  ###  Test against patterns.  Allow just * and ? wildcards
  foreach my $pattern ( @patterns ) {
    $pattern =~ s/\s//g;
    $pattern =~ s/([^\w\/\-\*\?])/\\$1/g;
    $pattern =~ s/\*/.*/g;
    $pattern =~ s/\?/./g;
    
    return 1 if $test_str =~ $pattern;
  }

  return 0;
}

1;



__END__

=head1 NAME

Dave::Util - Lib for shared utility functions

=head1 SYNOPSIS

    use Dave::Util qw(&split_delim_line &join_delim_line);

    # quoting char defaults to double-quotes
    my @vals = ('a','b','"complex"');
    my $csv_format = &join_delim_line(',', @vals);
    # with specified quoting char
    my $csv_format2 = &join_delim_line(',', \@vals, '"');
    # parse apart the values
    my @vals_back = &split_delim_line(',', $csv_format, '"');


    use Dave::Util qw(&read_conf &write_conf);

    my %hash = ( field_one => 'value1',
                 field_two => 'value2',
                 );
    &write_conf('/tmp/test.conf',\%hash);
    my $hashref = &read_conf('/tmp/test.conf');


    use Dave::Util qw(&do_validation);

    my ( $ok, $newval, $error ) = 
      &do_validation( 'password',
                      $myhash{'password'},
                      $Dave::User::data_topo{usert}{'password'},
                      $hash );
    if ( ! $ok ) {
      # handle bad value
      # error details are in $error hashref
    }
    $myhash{'password'} = $newval;


=head1 ABSTRACT

=over 4

This library is the place to stick non-object methods that are
general-purpose and will be used be many modules.  As this file
grows and new miscellaneous functions are added, logical groups
should be split out into their own modules.

=back

=head1 FUNCTIONS

=item join_delim_line()

This takes a list of values and returns them joined in CSV
format.  To pass in a quoting character to override the default
(double-quote), pass the list of values in an array ref as the
second param, and pass the quoting char as the third param.
Please don't attempt to use a quoting char that is longer than 1
char, you won't like the results.

Instances of newlines, backslashes and the quoting char you pass
will be escaped with a backslash.  These functions have been
tested using the source of this actual library, encapsulating the
entire contents in a CSV field and then extracting it with no
alteration of data.  So, I am *relatively* sure the encapsulation
is sound.  However I do not know for sure if my method of
encapsulation is RFC standard.

Only fields that require quoting will be quoted to reduce file
size.

=item split_delim_line()

Takes a string an splits it on the passed delimeter and using the
passed quoting char.  If no quoting char is passed it does not
assume double-quote.  Maybe I should change that.

=item read_conf()

Reads the specified conf file and returns a hashref of the
keys/values.

These are some examples of the conf file syntax that work:

        ### Comment's are ignored
        # <--  Must be start of line
        
        ###  Simple definition
        fieldone    = value one
        field-two=value two
        field_three = value three first line
         value three second line
         value three third line
        field_four =
                      value four first line
                      value four second line
                      value four third line
        
        ###  Subtle difference
        empty_string = 
        null_field   != 
        
        ###  URL Encoded
        url_encoded_1 %= This%20string%20is%20URL%20encoded%2C%20and%20see%20these%20funny%20chars%3A%20%2A%28%29_%3D
        
        ###  Hereto docs
        long_document << ETX
        as many lines as I want to put in here
        because I can say anything here as long 
        as I don't put ETX on a line all by itself.
        
        Even lines like:
        abc = 123
        will not get parsed becuase they are inside 
        this nifty container.

        ETX

The Operators are:

        =  Simple assignment

        != Assignment but empty means undef

        %= The value is URL encoded

        << TAG  The value is everything up to TAG

On subsequent content lines of the simple assignment operator, if
only one space is at the front of the line, then that space is
removed from the content.  Otherwise all leading spaces are kept.
That way you can write content like the text version of emails
and be able to have things all the way to the left, though
Here-To documents might suite you better for that.

=item write_conf()

Will determine which of the above encapsulation methods will work
best for the values of your hash and write the conf file out in a
format suitable to clone the given hash.  Nested structures are
not yet handled as the only way I can devise for that would not
be secure (Dumper and then eval to read).

=item do_validation($col, $value, $valhash, $prefs)

This function represents the atomic validation of a value to the
standard defined in the $valhash.  Also, the value is scrubbed to
the variable type.  All values have leading and trailing
whitespace clipped unless the 'no_strip_ws' key is set in the
valhash.  These are the validations currently suported:

    noedit - this is a quick way in the valhash to say "why are
      you even checking the format of this value, because you
      shouldn't be editing this variable in the first place".
      Even calling do_validation on a col with 'noedit' in the
      valhash is fails validation unless the 'ignore_noedit' key
      is passed in $prefs.

    rq - a value is required, undef, empty string and
      all-whitespace are illegal values (though all-whitespace is
      allowed if 'no_strip_ws' is set)

    maxl - value maximum length

    minl - value minimum length

    rxp - must match the supplied regular expression

    format - must match the preset format pattern specified.
      Formats include: email, bool, datetime, ip, hostname.
      These formats usually come with their own data-scrubbing to
      format the value for typical database insert.

Validations get run in the above order and the first failed
validation is returned in a the errors hashref.  The return
values in order are 1) boolean value of pass or fail of
validation, 2) new scrubbed value to use in place of the passed
value, 3) the errors hashref.

The format of the errors hashref deserves some explaination.  As
an example, if you validated an email address field 'myemail'
which had the value 'test@bad@value.com', and passed the valhash
{ name => 'my email address', format => 'email' }, validation
would fail, and the errors hashref would be:

    { myemail_error => 
        [ 'My email address is not a valid email address',
          'invalid_email'
          ]
    }

The value of the hashref is an arrayref, and will be for ALL
types of validation.  The first item is a string in ENGLISH that
can be used as an output which can be displayed to the user.
However, since the Dave system has been planned from the
beginning to be translate-able into other languages, the standard
is set here that we will not rely on any to-be-shown-to-the-user
phrase embedded in a Perl library.  But, since we don't want to
spend time going down the language abstraction path yet, this is
an acceptable kludge in the meantime.

Until we go down the language abstraction path, the first item of
the arrayref will be used in the [%error.myemail_error%] type
Template Toolkit swaps.  Eventually, we will be able to make that
smart enough to check for a language override for that specific
error.  That will most likely be done in a conf file in the rsc
directory for the reseller in the same place that the other
general language abstraction will take place.

Note, that setting a 'name' for your field in the valhash is
required for the ENGLISH error string, or you will get a funky
looking string (as we will NOT be adding sloppy auto-behavior to
try to fudge the column name into a human-readable name).

=back

=head1 DEPENDENCIES

This module loads these libs every time:

=over 4

    Dave::Util
    CGI::Util

=back
