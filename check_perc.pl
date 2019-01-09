#!/usr/bin/perl -wT
#
# Matt Stanford
# 2007.02.14
#
# check_perc.pl
#
#
# It is supposed to check the status of dell Perc arrays
# and report their status to nagios
#
# You can use and distribute this script under terms of the GNU 
# GENERAL PUBLIC LICENSE Version 2 later.
#

use strict;

use Net::SNMP;
use Getopt::Long;
&Getopt::Long::config('auto_abbrev');

my $debug			= 0;
my $status;
my $response 			= "";
my $timeout 			= 10;
my $community 			= "public";
my $port 			= 161;
my $hostname;

my @DellStorage 		= qw(1.3.6.1.4.1.674.10893.1.1 1.3.6.1.4.1.674.10893.1.20);
my @ChannelState		= qw(.130.2.1.3);
my @ChannelSeverity 		= qw(.130.2.1.4);
my @GlobalState 		= qw(1.3.6.1.4.1.674.10893.1.20.2.0);
my $DiskState	 		= qw(.130.4.1.4);
my $DiskSeverity 		= qw(.130.4.1.5);
my $DiskRollUpStatus 		= qw(.130.4.1.23);
my $BatteryState		= qw(.130.15.1.4.1);

my @DiskStateValues;

my $currentOID;
my $oidPrefix;

my $vMSG = "";
my $vDiskMSG = "";
my $vGlobalMSG = "";
my $vBatteryMSG = "";
my $tmpStatus = "";

my $currentState;
my $diskNumber;

my $maxDisks			= 100;

my $WorstState;

# NAGIOS EXIT CODE!
my %STATUSCODE 			= (	'UNKNOWN' 	=> '-1',
					'OK' 		=> '0',
					'WARNING' 	=> '1', 
					'CRITICAL' 	=> '2');

# Dell Definitions for the results
my @DellChannelState 		= qw(UNKNOWN READY FAILED ONLINE OFFLINE ? DEGRADED);
my @DellChannelSeverity		= qw(OK WARNING ERROR FAILURE);
my @DellDiskState 		= qw(UNKNOWN READY FAILED ONLINE OFFLINE ? DEGRADED RECOVERING ? ? ? REMOVED
						? ? ? RESYNCHING ? ? ? ? ? ? ? ? REBUILDING NOMEDIA FORMATTING ? DIAGNOSTICS
						? ? ? ? ? ? INITIALIZING ? ? ? ? ? ? ? ? FAILING);
my @DellDiskSeverity 		= qw(OK WARNING ERROR FAILURE);

my @DellGlobalState 		= qw(UNKNOWN CRITICAL WARNING NORMAL UNKNOWN);

my @DellBatteryState		= qw(UNKNOWN OK FAILED ? ? ? ? RECONDITIONING ? HIGH LOW ? CHARGING ? ? ? ? ? ? ? ? MISSING);

my @DellDiskRollUpStatus	= qw(? OTHER UNKNOWN OK NON-CRITICAL CRITICAL NON-RECOVERABLE);

my $state 			= "UNKNOWN";


####################
# DEFINE FUNCTIONS #
####################

$SIG{'ALRM'} = sub {
    	print "ERROR: No snmp response from $hostname (sigALRM)\n";
    	exit($STATUSCODE{"UNKNOWN"});
};

sub show_help {
    	printf("\nPerl PERC disk array plugin for Nagios\n");
    	printf("Usage:\n");
    	printf("
  check_perc.pl [options] <hostname>
  Options:
    -C snmp-community
    -p snmp-port
    --debug

");
    exit($STATUSCODE{"UNKNOWN"});
}

sub GetOIDValue($$$$;$)
{
	my $h = shift;
	my $c = shift;
	my $p = shift;
	my $OID = shift;

	my $HR = shift;

	my $retMsg;

	my $val;
	my $r;

	my ($s,$e) = Net::SNMP->session(
		Hostname	=>	$h,
		Community       =>      $c,
		Port            =>      $p
	);

	if(!defined($s)) {
		print $e."\n" if ($debug);
		$val = undef;
		$retMsg = $e;
		return ($val,$retMsg);
    	}

	# Get the response
	$r = $s->get_request($OID);

    	if(!defined($r)) {
		$val = undef;
        	$retMsg = $s->error();
        	$s->close();
		return ($val,$retMsg);
    	}

    	$s->close();
	
	$val = $r->{$OID};

	if ($val eq 'NULL') {
		$val = undef;

	} elsif (defined($HR->[$val])) {
		$val = $HR->[$val];
	}
    	return ($val,undef);
}


sub TestThisOID($$$$)
{
	my $h = shift;
	my $c = shift;
	my $p = shift;
	my $TestOID = shift;

	my $val;
	my $r;

	my ($s,$e) = Net::SNMP->session(
		Hostname	=>	$h,
		Community       =>      $c,
		Port            =>      $p
	);

	if (!defined($s)) {
		# trouble with the host
		print "Trouble with the host\n" if ($debug);
		$val = 0;
	} else {
		if (!defined($r = $s->get_request($TestOID))) {
			# no response
			print "No Response\n" if ($debug);
			$val = 0;
		} else {
			# response
			if ($e eq "") {
				# response with no error
				$val = 1;
			} else {
				# response with error
				print "Response with error\n" if ($debug);
				$val = 0;
			}
		}
	}

	return $val;
}
		

##############
# MAIN BLOCK #
##############

# Get the stuff from the command line
Getopt::Long::Configure('bundling');
$status = GetOptions
	("community=s", \$community,
	 "C=s",         \$community,
	 "H=s",         \$hostname,
	 "hostname=s",  \$hostname,
	 "port=i",      \$port,
	 "timeout=i",   \$timeout,
 	 "debug=i",	\$debug);
                     
if($status == 0) {
    &show_help;
}

unless (defined($hostname)) {
    $hostname = shift || &show_help;
}

alarm($timeout);

#########################################################################################

# Test to see if we should use the old style or the new style
# This OID should only work with the new style
$GlobalState[2] = TestThisOID($hostname,$community,$port,$GlobalState[0]);

# If the test failed, set the OID to the old-style, if it was OK then set it to new-style
$oidPrefix = $DellStorage[$GlobalState[2]];

# Get the Global State of the "Storage" section in OpenManage
if ($GlobalState[2] == 1) {
	($GlobalState[1],undef) = GetOIDValue($hostname,$community,$port,$GlobalState[0],\@DellGlobalState);
	# Get the battery state
	($GlobalState[3],undef) = GetOIDValue($hostname,$community,$port,$DellStorage[$GlobalState[2]].$BatteryState,\@DellBatteryState);

	$vBatteryMSG = 'PERC Battery is '. $GlobalState[3] . '; ';

	print $vBatteryMSG."\n" if ($debug);
} else {
	# If its old-style then just call it normal
	$GlobalState[1] = 'NORMAL';
}

# Check the ChannelState
($ChannelState[1],$vMSG) = GetOIDValue($hostname,$community,$port,$oidPrefix.$ChannelState[0].'.1',\@DellChannelState);

# Check for an OK status (1 or 3) from channelState MIB
if (defined($ChannelState[1])) {
	if(($ChannelState[1] ne "READY") && ($ChannelState[1] ne "ONLINE")) {

		# Create an informative message to send to nagios
		$vMSG = "The Channel State is ".$ChannelState[1];

		$currentOID = $oidPrefix.$ChannelSeverity[0].".1";
		($ChannelSeverity[1],undef) = GetOIDValue($hostname,$community,$port,$currentOID,\@DellChannelSeverity);

		$vMSG .= ", Severity is ".$ChannelSeverity[1];
	
		print $vMSG."\n" if ($debug);
	
		if ($GlobalState[1] ne 'NORMAL') {
			$vMSG .= '; Global Storage alarm **'.$GlobalState[1];
		}
	
		print $vMSG."\n";
		exit($STATUSCODE{'CRITICAL'});
	} else {
		# Returned 1 or 3
	
		$diskNumber = 1;
		($currentState, undef) = GetOIDValue($hostname,$community,$port,$oidPrefix.$DiskState.'.'.$diskNumber,\@DellDiskState);
		
		$vMSG = "PERC Channel is OK; ";

		$WorstState = 'OK';
	
		# Check each disk
		while ((defined($currentState)) && ($diskNumber < $maxDisks)) {
			# Save the disk state
			$DiskStateValues[$diskNumber][0] = $currentState;
			print $currentState."\t".$diskNumber."\n" if ($debug);
	
			$vDiskMSG .= "Disk #".$diskNumber." is ".$currentState;
	
			# Get the disk severity
			if (($currentState ne 'ONLINE') && ($currentState ne 'READY')) {
				($DiskStateValues[$diskNumber][1],undef) = GetOIDValue($hostname,$community,$port,$oidPrefix.$DiskSeverity.'.'.$diskNumber,\@DellDiskSeverity);
				$WorstState = 'CRITICAL';
			}
			elsif ($GlobalState[2] == 1)
			{
				($tmpStatus,undef) = GetOIDValue($hostname,$community,$port,$oidPrefix.$DiskRollUpStatus.'.'.$diskNumber,\@DellDiskRollUpStatus);
				if ($tmpStatus ne 'OK')
				{
					$vDiskMSG .= " but has a status of ".$tmpStatus."; ";
					$WorstState = 'WARNING';
				}
			}
			
	
			if (defined($DiskStateValues[$diskNumber][1])) {
				$vDiskMSG .= " with a severity of ".$DiskStateValues[$diskNumber][1]."; ";
			} else {
				$vDiskMSG .= "; ";
			}
		
			# Get the next disk state
			$diskNumber++;
			($currentState, undef) = GetOIDValue($hostname,$community,$port,$oidPrefix.$DiskState.'.'.$diskNumber,\@DellDiskState);
		}

		if ($WorstState eq 'OK')
		{
			$vDiskMSG = "All Disks are OK; ";
		}
		
	}
} else {
	print "Host does not understand the Dell Storage OID\n";
	exit ($STATUSCODE{'CRITICAL'});
}
	
if ($GlobalState[1] ne 'NORMAL') {

	if ($GlobalState[3] eq 'OK')
	{	
		$WorstState = 'CRITICAL';
	}
	# Battery State Check
	elsif ((($GlobalState[3] eq 'RECONDITIONING') || ($GlobalState[3] eq 'CHARGING') || ($GlobalState[3] eq 'LOW')) && ($GlobalState[1] ne 'CRITICAL'))
	{
		$WorstState = 'WARNING';
	}
	else
	{
		$WorstState = 'CRITICAL';
	}

	$vGlobalMSG = '** Global Storage Alarm '.$GlobalState[1].' ** ';
}
else
{
	$vGlobalMSG = "";
}

print $vGlobalMSG.$vMSG.$vBatteryMSG.$vDiskMSG."\n";

# Exit with the right status
exit ($STATUSCODE{$WorstState});
