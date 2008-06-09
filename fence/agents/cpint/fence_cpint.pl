#!/usr/bin/perl

use Getopt::Std;

# Get the program name from $0 and strip directory names
$_=$0;
s/.*\///;
my $pname = $_;

$comm_prog = "hcp";

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
    print "  -h               usage\n";
    print "  -u <string>      userid of the virtual machine to fence\n";
    print "  -q               quiet mode\n";
    print "  -V               Version\n";

    exit 0;
}

sub fail
{
  ($msg)=@_;
  print "failed: " . $msg . "\n" unless defined $opt_q;
  exit 1;
}

sub fail_usage
{
  ($msg)=@_q;
  print stderr $msg."\n" if $msg;
  print stderr "Please use '-h' for usage.\n";
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
           print stderr "parse error: illegal name in option $line\n";
           exit 2;
        }

	      # DO NOTHING -- this field is used by fenced or stomithd
        elsif ($name eq "agent" ) { }

	      # FIXME -- depricated.  use "userid" and "password" instead.
        elsif ($name eq "fm" )
        {
            (my $dummy,$opt_u,$opt_p) = split /\s+/,$val;
	          print STDERR "Depricated \"fm\" entry detected.  refer to man page.\n";
        }

        # FIXME -- depreicated residue of old fencing system
      	elsif ($name eq "name" ) { }

	      elsif ($name eq "userid" )
        {
            $opt_u = $val;
        }

	else
        {
           print stderr "parse error: unknown option \"$opt\"\n";
           #> exit 2;
        }
    }
}

if (@ARGV > 0){
    getopts("hqu:V") || fail_usage;
    usage if defined $opt_h;
    version if defined $opt_V;

    fail_usage "Unkown parameter." if (@ARGV > 0);

    fail_usage "No '-u' flag specified." unless defined $opt_u;
} else {
    get_options_stdin();

    fail "no userid" unless defined $opt_u;
}

$ret_val = system("$comm_prog send cp $opt_u logoff > /dev/null 2>&1") >> 8;
fail "$comm_prog failed ($ret_val)" unless ($ret_val == 0 || $ret_val == 45);
$ret_val = system("$comm_prog send cp $opt_u > /dev/null 2>&1") >> 8;
fail "$userid isn't logged off. $comm_prog return ($ret_val)" unless ($ret_val == 45);

print "success: booted userid $opt_u\n" unless defined $opt_q;
exit 0;
