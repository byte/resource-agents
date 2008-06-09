#!/usr/bin/perl

# This works on the following firmware versions:
#   01.03.00
#   02.00.00
#   04.01.00
#   04.01.02

use Getopt::Std;
use Net::Telnet ();

# Get the program name from $0 and strip directory names
$_=$0;
s/.*\///;
my $pname = $_;

$opt_o = 'disable';        # Default fence action

# WARNING!! Do not add code bewteen "#BEGIN_VERSION_GENERATION" and 
# "#END_VERSION_GENERATION"  It is generated by the Makefile

#BEGIN_VERSION_GENERATION
$RELEASE_VERSION="";
$REDHAT_COPYRIGHT="";
$BUILD_DATE="";
#END_VERSION_GENERATION


sub usage
{
    print "Usage:\n";
    print "\n";
    print "$pname [options]\n";
    print "\n";
    print "Options:\n";
    print "  -a <ip>          IP address or hostname of switch\n";
    print "  -h               usage\n";
    print "  -l <name>        Login name\n";
    print "  -n <num>         Port number to disable\n";
    print "  -o <string>      Action:  disable (default) or enable\n";
    print "  -p <string>      Password for login\n";
    print "  -S <path>        Script to run to retrieve login password\n";
    print "  -q               quiet mode\n";
    print "  -V               version\n";

    exit 0;
}

sub fail
{
  ($msg) = @_;
  print $msg."\n" unless defined $opt_q;
  $t->close if defined $t;
  exit 1;
}

sub fail_usage
{
  ($msg)=@_;
  print STDERR $msg."\n" if $msg;
  print STDERR "Please use '-h' for usage.\n";
  exit 1;
}

sub version
{
  print "$pname $RELEASE_VERSION $BUILD_DATE\n";
  print "$REDHAT_COPYRIGHT\n" if ( $REDHAT_COPYRIGHT );

  exit 0;
}

sub get_options_stdin
{
    my $opt;
    my $line = 0;
    while( defined($in = <>) )
    {
        $_ = $in;
        chomp;

	# strip leading and trailing whitespace
        s/^\s*//;
        s/\s*$//;

	# skip comments
        next if /^#/;

        $line+=1;
        $opt=$_;
        next unless $opt;

        ($name,$val)=split /\s*=\s*/, $opt;

        if ( $name eq "" )
        {  
           print STDERR "parse error: illegal name in option $line\n";
           exit 2;
	}
	
        # DO NOTHING -- this field is used by fenced
	elsif ($name eq "agent" ) { } 

        elsif ($name eq "ipaddr" ) 
	{
            $opt_a = $val;
        } 
	elsif ($name eq "login" ) 
	{
            $opt_l = $val;
        } 
        elsif ($name eq "option" )
        {
            $opt_o = $val;
        }
	elsif ($name eq "passwd" ) 
	{
            $opt_p = $val;
        }
	elsif ($name eq "passwd_script" )
	{
		$opt_S = $val;
	}
	elsif ($name eq "port" ) 
	{
            $opt_n = $val;
        } 
    }
}

sub telnet_error
{ 
  fail "failed: telnet returned: ".$t->errmsg;
}

######################################################################33
# MAIN

if (@ARGV > 0) {
   getopts("a:hl:n:o:p:S:qV") || fail_usage ;

   usage if defined $opt_h;
   version if defined $opt_V;

   fail_usage "Unknown parameter." if (@ARGV > 0);

   fail_usage "No '-a' flag specified." unless defined $opt_a;
   fail_usage "No '-n' flag specified." unless defined $opt_n;
   fail_usage "No '-l' flag specified." unless defined $opt_l;

   if (defined $opt_S) {
     $pwd_script_out = `$opt_S`;
     chomp($pwd_script_out);
     if ($pwd_script_out) {
        $opt_p = $pwd_script_out;
     }
   }

   fail_usage "No '-p' or '-S' flag specified." unless defined $opt_p;
   fail_usage "Unrecognised action '$opt_o' for '-o' flag"
      unless $opt_o =~ /^(disable|enable)$/i;

} else {
   get_options_stdin();

   fail "failed: no IP address" unless defined $opt_a;
   fail "failed: no plug number" unless defined $opt_n;
   fail "failed: no login name" unless defined $opt_l;

   if (defined $opt_S) {
     $pwd_script_out = `$opt_S`;
     chomp($pwd_script_out);
     if ($pwd_script_out) {
        $opt_p = $pwd_script_out;
     }
   }

   fail "failed: no password" unless defined $opt_p;
   fail "failed: unrecognised action: $opt_o"
      unless $opt_o =~ /^(disable|enable)$/i;
}


my $block=1;
$_=$opt_o;
if(/disable/)
{
    $block=1
}
elsif(/enable/)
{
    $block=0
}
else
{
    fail "failed: unrecognised action: $opt_o"
}

#
# Set up and log in
#

$t = new Net::Telnet;

$t->errmode(\&telnet_error);
$t->open($opt_a);

$t->waitfor('/sername:/');

# Send Username
$t->print($opt_l);

# Send Password
$t->waitfor('/assword:/');
$t->print($opt_p);
$t->waitfor('/\>/');

#> # Set switch to comma delimited output
#> $t->print("commadelim 1");
#> $t->waitfor('/\>/');

# Block/Unblock the desired port
$t->print("config port blocked $opt_n $block");
($text, $match) = $t->waitfor('/\>/');

# Verfiy that the port has been blocked/unblocked
$t->print("config port show $opt_n");
($text, $match) = $t->waitfor('/\>/');

# scan the port configurations to make sure that
# the port is in the state we told it to be in
#
# Output from the prvious command will look like:
# 
# Root> config port show 0
#
# Port Information
# Port Number:          0
# Name:                 name
# Blocked:              true
# Extended Distance:    false
# Type:                 gPort
# 
my $fail=1;

@lines = split /\n/,$text;
foreach my $line (@lines)
{
   my $field = "";
   my $b_state = "";

   if ( $line =~ /^(.*):\s*(\S*)/ )
   {
      $field = $1;
      $b_state = $2;
   }
   next unless ( $field eq "Blocked" );
   if ( ($block && $b_state eq "true") ||
        (!$block && $b_state eq "false") )
   {
      $fail = 0;
   }
   last;
}

# log out of the switch
$t->print("logout");
$t->close();

if($fail)
{
   print "failed: unexpected port state\n" unless $opt_q;
}
else
{
   print "success: port $opt_n ".($block?"disabled":"enabled")."\n" 
      unless defined $opt_q;
}

exit $fail;


