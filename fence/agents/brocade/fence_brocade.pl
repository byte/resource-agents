#!/usr/bin/perl

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
    print "  -n <num>         Port number to operate on\n";
    print "  -o <string>      Action:  disable (default) or enable\n";
    print "  -p <string>      Password for login\n";
    print "  -S <path>        Script to run to retrieve password\n";
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


if (@ARGV > 0) {
   getopts("a:hl:n:o:p:S:qV") || fail_usage ;

   usage if defined $opt_h;
   version if defined $opt_V;

   fail_usage "Unknown parameter." if (@ARGV > 0);

   if (defined $opt_S) {
     $pwd_script_out = `$opt_S`;
     chomp($pwd_script_out);
     if ($pwd_script_out) {
       $opt_p = $pwd_script_out;
     }
   }

   fail_usage "No '-a' flag specified." unless defined $opt_a;
   fail_usage "No '-n' flag specified." unless defined $opt_n;
   fail_usage "No '-l' flag specified." unless defined $opt_l;
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

if ( $opt_o =~ /^(disable|enable)$/i )
{
  $opt_o = "port".$1;
}


#
# Set up and log in
#

$t = new Net::Telnet;

$t->open($opt_a);

$t->waitfor('/login:/');

$t->print($opt_l);

$t->waitfor('/assword:/');

$t->print($opt_p);

$t->waitfor('/\>/');



#
# Do the command
#

$cmd = "$opt_o $opt_n";
$t->print($cmd);


#
# Assume here that the word "error" will appear after errors (bad assumption! see next check)
#

($text, $match) = $t->waitfor('/\>/');
if ($text =~ /error/)
{
  fail "failed: error from switch\n";
}


#
# Do a portshow on the port and look for the DISABLED string to verify success
#

$t->print("portshow $opt_n");
($text, $match) = $t->waitfor('/\>/');

if ( $opt_o eq "portdisable" && !($text =~ /DISABLED/) )
{
  fail "failed: portshow $opt_n does not show DISABLED\n";
}
elsif ( $opt_o eq "portenable" && ($text =~ /DISABLED/) )
{
  fail "failed: portshow $opt_n shows DISABLED\n";
}


print "success: $opt_o $opt_n\n" unless defined $opt_q;
exit 0;

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

	# FIXME -- depricated.  use "port" instead.
        elsif ($name eq "fm" ) 
	{
            (my $dummy,$opt_n) = split /\s+/,$val;
	    print STDERR "Depricated \"fm\" entry detected.  refer to man page.\n";
	}

        elsif ($name eq "ipaddr" ) 
	{
            $opt_a = $val;
        } 
	elsif ($name eq "login" ) 
	{
            $opt_l = $val;
        } 

	# FIXME -- depreicated residue of old fencing system
	elsif ($name eq "name" ) { } 

        elsif ($name eq "option" )
        {
            $opt_o = $val;
        }
	elsif ($name eq "passwd" ) 
	{
            $opt_p = $val;
        } 
	elsif ($name eq "passwd_script") {
		$opt_S = $val;
	}
	elsif ($name eq "port" ) 
	{
            $opt_n = $val;
        } 
	# elsif ($name eq "test" ) 
	# {
        #    $opt_T = $val;
        # } 
    }
}
