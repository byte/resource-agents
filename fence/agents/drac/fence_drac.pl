#!/usr/bin/perl

# The following agent has been tested on:
#
#  Model 		DRAC Version	Firmware
#  -------------------	--------------	----------------------
#  PowerEdge 750	DRAC III/XT	3.20 (Build 10.25)
#  Dell Remote Access Controller - ERA and DRAC III/XT, v.3.20, A00
#  
#  PowerEdge 1855	DRAC/MC		1.1  (Build 03.03)
#  PowerEdge 1855	DRAC/MC		1.2  (Build 03.03)
#  PowerEdge 1855	DRAC/MC		1.3  (Build 06.12)
#  PowerEdge 1850	DRAC 4/I	1.35 (Build 09.27)
#  PowerEdge 1850	DRAC 4/I	1.40 (Build 08.24)
#  PowerEdge 1950	DRAC 5		1.0  (Build 06.05.12)
#

use Getopt::Std;
use Net::Telnet ();

# Get the program name from $0 and strip directory names
$_=$0;
s/.*\///;
my $pname = $_;

my $telnet_timeout = 10;      # Seconds to wait for matching telent response
my $power_timeout = 20;      # time to wait in seconds for power state changes
$action = 'reboot';          # Default fence action.  

my $logged_in = 0;
my $quiet = 0;

my $t = new Net::Telnet;

my $DRAC_VERSION_UNKNOWN	= '__unknown__';
my $DRAC_VERSION_III_XT		= 'DRAC III/XT';
my $DRAC_VERSION_MC			= 'DRAC/MC';
my $DRAC_VERSION_4I			= 'DRAC 4/I';
my $DRAC_VERSION_4P			= 'DRAC 4/P';
my $DRAC_VERSION_5			= 'DRAC 5';

my $PWR_CMD_SUCCESS			= "/^OK/";
my $PWR_CMD_SUCCESS_DRAC5	= "/^Server power operation successful$/";

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
	print "  -a <ip>          IP address or hostname of DRAC\n";
	print "  -c <cmd_prompt>  force DRAC command prompt\n";
	print "  -d <dracversion> force DRAC version to use\n";
	print "  -D <debugfile>   debugging output file\n";
	print "  -h               usage\n";
	print "  -l <name>        Login name\n";
	print "  -m <modulename>  DRAC/MC module name\n";
	print "  -o <string>      Action: reboot (default), off or on\n";
	print "  -p <string>      Login password\n";
	print "  -S <path>        Script to run to retrieve password\n";
	print "  -q               quiet mode\n";
	print "  -V               version\n";
	print "\n";
	print "CCS Options:\n";
	print "  action = \"string\"      Action: reboot (default), off or on\n";
	print "  debug  = \"debugfile\"   debugging output file\n";
	print "  ipaddr = \"ip\"          IP address or hostname of DRAC\n";
	print "  login  = \"name\"        Login name\n";
	print "  passwd = \"string\"      Login password\n";
	print "  passwd_script = \"path\" Script to run to retrieve password\n";

	exit 0;
}

sub msg
{
	($msg)=@_;
	print $msg."\n" unless $quiet;
}

sub fail
{
	($msg)=@_;
	print $msg."\n" unless $quiet;

	if (defined $t)
	{
		# make sure we don't get stuck in a loop due to errors
		$t->errmode('return');  

		logout() if $logged_in;
		$t->close 
	}
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


sub login
{
	$t->open($address) or 
		fail "failed: telnet open failed: ". $t->errmsg."\n";
  
	# Expect 'Login: ' 
	($_) = $t->waitfor(Match => "/[Ll]ogin: /", Timeout=>15) or
		fail "failed: telnet failed: ". $t->errmsg."\n" ;

	# Determine DRAC version
  if (/Dell Embedded Remote Access Controller \(ERA\)\nFirmware Version/m)
  {
    $drac_version = $DRAC_VERSION_III_XT;
  } else {
	if (/.*\((DRAC[^)]*)\)/m)
	{
		print "detected drac version '$1'\n" if $verbose;
		$drac_version = $1 unless defined $drac_version;
		
		print "WARNING: detected drac version '$1' but using "
			. "user defined version '$drac_version'\n"
			if ($drac_version ne $1);
	}
	else
	{
		$drac_version = $DRAC_VERSION_UNKNOWN;
	}
  }

	# Setup prompt
	if ($drac_version =~ /$DRAC_VERSION_III_XT/)
	{
		$cmd_prompt = "/\\[$login\\]# /" 
			unless defined $cmd_prompt;
	}
	elsif ($drac_version =~ /$DRAC_VERSION_MC/)
	{
		$cmd_prompt = "/DRAC\\/MC:/" 
			unless defined $cmd_prompt;
	}	
	elsif ($drac_version =~ /$DRAC_VERSION_4I/)
	{
		$cmd_prompt = "/\\[$login\\]# /" 
			unless defined $cmd_prompt;
	}
  elsif ($drac_version =~ /$DRAC_VERSION_4P/)
  {
        $cmd_prompt = "/\\[$login\\]# /"
          unless defined $cmd_prompt;
  } 
	else
	{
		$drac_version = $DRAC_VERSION_UNKNOWN;
	}

	# Take a guess as to what the prompt might be if not already defined
	$cmd_prompt="/(\\[$login\\]# |DRAC\\/MC:|\\\$ )/" unless defined $cmd_prompt;
	

	# Send login
	$t->print($login);

	# Expect 'Password: ' 
	$t->waitfor("/Password: /") or 
		fail "failed: timeout waiting for password";

	# Send password
	$t->print($passwd);  

	# DRAC5 prints version controller version info
	# only after you've logged in.
	if ($drac_version eq $DRAC_VERSION_UNKNOWN) {
		if ($t->waitfor(Match => "/.*\($DRAC_VERSION_5\)/m")) {
			$drac_version = $DRAC_VERSION_5;
			$cmd_prompt = "/\\\$ /";
			$PWR_CMD_SUCCESS = $PWR_CMD_SUCCESS_DRAC5;
		} else {
			print "WARNING: unable to detect DRAC version '$_'\n";
		}
	}

	$t->waitfor($cmd_prompt) or
		fail "failed: invalid username or password";

	if ($drac_version eq $DRAC_VERSION_UNKNOWN) {
		print "WARNING: unsupported DRAC version '$drac_version'\n";
	}

	$logged_in = 1;
}

#
# Set the power status of the node 
#
sub set_power_status
{
	my ($state,$dummy) = @_;
	my $cmd,$svr_action;

	if   ( $state =~ /^on$/)  { $svr_action = "powerup"   }
	elsif( $state =~ /^off$/) { $svr_action = "powerdown" }

	if ($drac_version eq $DRAC_VERSION_MC)
	{
		$cmd = "serveraction -m $modulename  -d 0 $svr_action";
	}
	elsif ($drac_version eq $DRAC_VERSION_5) {
		$cmd = "racadm serveraction $svr_action";
	} else
	{
		$cmd = "serveraction -d 0 $svr_action";
	}

	$t->print($cmd);

	# Expect /$cmd_prompt/
	($_) = $t->waitfor($cmd_prompt) or
		fail "failed: unexpected serveraction response"; 

	my @cmd_out = split /\n/;

	# discard command sent to DRAC
	$_ = shift @cmd_out;
        s/\e\[(([0-9]+;)*[0-9]+)*[ABCDfHJKmsu]//g; #strip ansi chars
        s/^.*\x0D//;

	fail "failed: unkown dialog exception: '$_'" unless (/^$cmd$/);

	# Additional lines of output probably means an error.  
	# Aborting to be safe.  Note: additional user debugging will be 
	# necessary,  run with -D and -v flags
	my $err;
	while (@cmd_out)
	{
		$_ = shift @cmd_out;
                #firmware vers 1.2 on DRAC/MC sends ansi chars - evil
                s/\e\[(([0-9]+;)*[0-9]+)*[ABCDfHJKmsu]//g;
                s/^.*\x0D//;

		next if (/^\s*$/); # skip empty lines
		if (defined $err)
		{
			$err = $err."\n$_";
		}
		else
		{
			next if ($PWR_CMD_SUCCESS);
			$err = $_;
		}
	}
	fail "failed: unexpected response: '$err'" if defined $err;
}


#
# get the power status of the node and return it in $status and $_
#
sub get_power_status
{
	my $status; 
	my $modname = $modulename;
	my $cmd;

	if ($drac_version eq $DRAC_VERSION_5) {
		$cmd = "racadm serveraction powerstatus";
	} else {
		$cmd = "getmodinfo";
	}

	$t->print($cmd);

	($_) = $t->waitfor($cmd_prompt);

	my $found_header = 0;
	my $found_module = 0;

	my @cmd_out = split /\n/;

	# discard command sent to DRAC
	$_ = shift @cmd_out;
        #strip ansi control chars
        s/\e\[(([0-9]+;)*[0-9]+)*[ABCDfHJKmsu]//g;
        s/^.*\x0D//;

	fail "failed: unkown dialog exception: '$_'" unless (/^$cmd$/);

	if ($drac_version ne $DRAC_VERSION_5) {
		#Expect:
		#  #<group>     <module>    <presence>  <pwrState>  <health>  <svcTag>
		#   1  ---->     chassis    Present         ON      Normal    CQXYV61
		#
		#  Note: DRAC/MC has many entries in the table whereas DRAC III has only
		#  a single table entry.

		while (1)
		{
			$_ = shift @cmd_out;
			if (/^#<group>\s*<module>\s*<presence>\s*<pwrState>\s*<health>\s*<svcTag>/)
			{
				$found_header = 1;
				last;
			}
		}
		fail "failed: invalid 'getmodinfo' header: '$_'" unless $found_header;
	}

	foreach (@cmd_out)
	{ 
		s/^\s+//g; #strip leading space
		s/\s+$//g; #strip training space

		if ($drac_version eq $DRAC_VERSION_5) {
			if(m/^Server power status: (\w+)/) {
				$status = lc($1);
			}
		} else {
			my ($group,$arrow,$module,$presence,$pwrstate,$health,
				$svctag,$junk) = split /\s+/;

			if ($drac_version eq  $DRAC_VERSION_III_XT || $drac_version eq $DRAC_VERSION_4I || $drac_version eq $DRAC_VERSION_4P)
			{
				fail "failed: extraneous output detected from 'getmodinfo'" if $found_module;
				$found_module = 1;
				$modname = $module;
			}

			if ($modname eq $module)
			{
				fail "failed: duplicate module names detected" if $status;
				$found_module = 1;

				fail "failed: module not reported present" unless ($presence =~ /Present/);
				$status = $pwrstate;
			}

		}
	}

	if ($drac_version eq $DRAC_VERSION_MC)
	{
		fail "failed: module '$modulename' not detected" unless $found_module;
	}

	$_=$status;
	if(/^(on|off)$/i)
	{
		# valid power states 
	}
	elsif ($status) 
	{
		fail "failed: unknown power state '$status'";
	}
	else
	{
		fail "failed: unable to determine power state";
	}
}


# Wait upto $power_timeout seconds for node power state to change to 
# $state before erroring out.
#
# return 1 on success
# return 0 on failure
#
sub wait_power_status
{
	my ($state,$dummy) = @_;
	my $status;

	$state = lc $state;

	for (my $i=0; $i<$power_timeout ; $i++)
	{
		get_power_status;
		$status = $_;
		my $check = lc $status;

		if ($state eq $check ) { return 1 }
		sleep 1;
	}
	$_ = "timed out waiting to power $state";
	return 0;
}

#
# logout of the telnet session
#
sub logout 
{
	$t->print("");
	$t->print("exit");
}

#
# error routine for Net::Telnet instance
#
sub telnet_error
{
	fail "failed: telnet returned: ".$t->errmsg."\n";
}

#
# execute the action.  Valid actions are 'on' 'off' 'reboot' and 'status'.
# TODO: add 'configure' that uses racadm rpm to enable telnet on the drac
#
sub do_action
{
	get_power_status;
	my $status = $_;

	if ($action =~ /^on$/i)
	{
		if ($status =~ /^on$/i)
		{
			msg "success: already on";
			return;
		}
			
		set_power_status on;
		fail "failed: $_" unless wait_power_status on;

		msg "success: powered on";
	}
	elsif ($action =~ /^off$/i)
	{
		if ($status =~ /^off$/i)
		{
			msg "success: already off";
			return;
		}

		set_power_status off;
		fail "failed: $_" unless wait_power_status off;
	
		msg "success: powered off";
	}
	elsif ($action =~ /^reboot$/i)
	{
		if ( !($status =~ /^off$/i) )
		{
			set_power_status off;
		}
		fail "failed: $_" unless wait_power_status off;

		set_power_status on;
		fail "failed: $_" unless wait_power_status on;

		msg "success: rebooted";
	}
	elsif ($action =~ /^status$/i)
	{
		msg "status: $status";
		return;
	}
	else 
	{
		fail "failed: unrecognised action: '$action'";
	}
}

#
# Decipher STDIN parameters
#
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
		elsif ($name eq "agent" ) 
		{
		} 
		elsif ($name eq "ipaddr" ) 
		{
			$address = $val;
		} 
		elsif ($name eq "login" ) 
		{
			$login = $val;
		} 
		elsif ($name eq "action" ) 
		{
			$action = $val;
		} 
		elsif ($name eq "passwd" ) 
		{
			$passwd = $val;
		}
		elsif ($name eq "passwd_script" )
		{
			$passwd_script = $val;
		}
		elsif ($name eq "debug" ) 
		{
			$debug = $val;
		} 
		elsif ($name eq "modulename" ) 
		{
			$modulename = $val;
		} 
		elsif ($name eq "drac_version" ) 
		{
			$drac_version = $val;
		} 
		elsif ($name eq "cmd_prompt" ) 
		{
			$cmd_prompt = $val;
		} 
		# Excess name/vals will fail
		else 
		{
			fail "parse error: unknown option \"$opt\"";
		}
	}
}


### MAIN #######################################################

#
# Check parameters
#
if (@ARGV > 0) {
	getopts("a:c:d:D:hl:m:o:p:S:qVv") || fail_usage ;
	
	usage if defined $opt_h;
	version if defined $opt_V;
	
	$quiet = 1 if defined $opt_q;
	$debug = $opt_D; 

	fail_usage "Unknown parameter." if (@ARGV > 0);

	fail_usage "No '-a' flag specified." unless defined $opt_a;
	$address = $opt_a;

	fail_usage "No '-l' flag specified." unless defined $opt_l;
	$login = $opt_l;

	$modulename = $opt_m if defined $opt_m;

	if (defined $opt_S) {
		$pwd_script_out = `$opt_S`;
		chomp($pwd_script_out);
		if ($pwd_script_out) {
			$opt_p = $pwd_script_out;
		}
	}

	fail_usage "No '-p' or '-S' flag specified." unless defined $opt_p;
	$passwd = $opt_p;

	$verbose = $opt_v if defined $opt_v;

	$cmd_prompt = $opt_c if defined $opt_c;
	$drac_version = $opt_d if defined $opt_d;

	if ($opt_o)
	{
		fail_usage "Unrecognised action '$opt_o' for '-o' flag"
		unless $opt_o =~ /^(Off|On|Reboot|status)$/i;
		$action = $opt_o;
	}

} else {
	get_options_stdin();

	fail "failed: no IP address" unless defined $address;
	fail "failed: no login name" unless defined $login;

	if (defined $passwd_script) {
		$pwd_script_out = `$passwd_script`;
		chomp($pwd_script_out);
		if ($pwd_script_out) {
			$passwd = $pwd_script_out;
		}
	}

	fail "failed: no password" unless defined $passwd;
	fail "failed: unrecognised action: $action"
		unless $action =~ /^(Off|On|Reboot|status)$/i;
} 


$t->timeout($telnet_timeout);
$t->input_log($debug) if $debug;
$t->errmode('return');  

login;

# Abort on failure beyond here
$t->errmode(\&telnet_error);  

if ($drac_version eq $DRAC_VERSION_III_XT)
{
	fail "failed: option 'modulename' not compatilble with DRAC version '$drac_version'" 
		if defined $modulename;
}
elsif ($drac_version eq $DRAC_VERSION_MC)
{
	fail "failed: option 'modulename' required for DRAC version '$drac_version'"
		unless  defined $modulename;
}

do_action;

logout;

exit 0;


