package Slim::Hardware::IR;

# $Id: IR.pm,v 1.27 2005/01/04 03:38:52 dsully Exp $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Time::HiRes qw(gettimeofday);

use Slim::Buttons::Common;
use Slim::Utils::Misc;

my %irCodes = ();
my %irMap   = ();

my @queuedBytes = ();
my @queuedTime = ();
my @queuedClient = ();

my @buttonPressStyles = ( '','.single','.double','.repeat','.hold','.hold_release');
my $defaultMapFile;

my $eggseq = 'up,down,up,down,left,right,left,right';

# If time between IR commands is greater than this, then the code is considered a new button press
$Slim::Hardware::IR::IRMINTIME  = 0.140;

# 512 ms
$Slim::Hardware::IR::IRHOLDTIME  = 0.512;

# 256 ms
$Slim::Hardware::IR::IRSINGLETIME = 0.256;

# and more things for diagnostics.  Define d_irtm to turn diagnostics on.
my ($serverStartSeconds, $serverStartMicros);

# queued variables used for diagnostics.
my @queuedClientTime = ();
my @queuedServerTime = ();

{
	if ($::d_irtm) {
		($serverStartSeconds, $serverStartMicros) = gettimeofday();
	}
}

sub enqueue {
	my $client = shift;
	my $irCodeBytes = shift;
	my $clientTime = shift;

	my $irTime = $clientTime / $client->ticspersec;
	assert($client);
	assert($irCodeBytes);
	assert($irTime);
	
	push @queuedBytes, $irCodeBytes;
	push @queuedTime, $irTime;
	push @queuedClient, $client;

	if ($::d_irtm) {

		# we can start profiling here
		if ($DB::profile == 0) {
			msg("IRTM starting profiler\n");
			$DB::profile=1;
		}

		# record information so the client can time each response
		my ($serverSeconds, $serverMicros) = gettimeofday();
		my $serverTime = ($serverSeconds - $serverStartSeconds) * 1000000;
		$serverTime += $serverMicros;
		push @queuedClientTime, $clientTime;
		push @queuedServerTime, $serverTime;
	}
}

sub idle {
	if (scalar(@queuedBytes)) {

		my $client = shift @queuedClient;		
		Slim::Control::Command::execute($client, ['ir', (shift @queuedBytes), (shift @queuedTime)]);
		
		if ($::d_irtm) {
			# compute current time in microseconds
			my ($nowSeconds, $nowMicros) = gettimeofday();
			my $nowTime = ($nowSeconds - $serverStartSeconds) * 1000000;
			$nowTime += $nowMicros;
			# pop diagnostic info off stack
			my $clientTime = shift(@queuedClientTime);
			my $serverReceivedTime = shift(@queuedServerTime);
			my $clientCount = Slim::Player::Client::clientCount();
			# send a message to the client that the IR has been processed.
			# note that during execute() above, the client's display may have been updated a number of times.  So the deltaT we return here may be longer than what the client experienced.  However, a pending command from another client could have been waiting all that time.
			if ($client->isa("Slim::Player::Squeezebox")) {
				my $serverDeltaT = $nowTime - $serverReceivedTime;
				my $msg = "<irtm clientSentTime=$clientTime serverReceivedTime=$serverReceivedTime serverDeltaT=$serverDeltaT clientCount=$clientCount>";
				$client->sendFrame('irtm', \$msg);
			}
		}
	}
}

sub init {

	%irCodes = ();
	%irMap = ();
	
	for my $irfile (keys %{irfiles()}) {
		loadIRFile($irfile);
	}

	for my $mapfile (keys %{mapfiles()}) {
		loadMapFile($mapfile);
	}
}

sub IRFileDirs {
	my @dirs = catdir($Bin,"IR");

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/IR/";
		push @dirs, "/Library/SlimDevices/IR/";
	}

	return @dirs;
}

#returns a reference to a hash of filenames/external names
sub irfiles {
	my %irfilelist = ();

	for my $irfiledir (IRFileDirs()) {

		opendir(DIR, $irfiledir) or next;

		for my $irfile ( sort(readdir(DIR)) ) {

			next unless $irfile =~ /(.+)\.ir$/;

			$::d_ir && msg(" irfile entry: $irfile\n");
			$irfilelist{catdir($irfiledir, $irfile)} = $1;
		}

		closedir(DIR);
	}

	return \%irfilelist;
}

sub irfileName {
	my $file = shift;
	my %files = %{irfiles()};
	return $files{$file};
}

sub defaultMap {
	return "Default";
}

sub defaultMapFile {
	unless (defined($defaultMapFile)) {
		$defaultMapFile = catdir((IRFileDirs())[0],defaultMap() . '.map');
	}
	return $defaultMapFile;
}

# returns a reference to a hash of filenames/external names
sub mapfiles {
	my %maplist = ();

	for my $irfiledir (IRFileDirs()) {

		opendir(DIR, $irfiledir) or next;

		for my $mapfile ( sort(readdir(DIR)) ) {

			next unless $mapfile =~ /(.+)\.map$/;

			$::d_ir && msg(" key mapping file entry: $mapfile\n");
			my $path = catdir($irfiledir,$mapfile);

			if ($1 eq defaultMap()) {
				$maplist{$path} = Slim::Utils::Strings::string('DEFAULT_MAP');
				$defaultMapFile = $path
			} else {
				$maplist{$path} = $1;
			}
		}

		closedir DIR;
	}

	return \%maplist;
}

sub addModeDefaultMapping {
	my ($mode,$mapref) = @_;

	if (exists $irMap{$defaultMapFile}{$mode}) {
		#don't overwrite existing mappings
		return;
	}

	if (ref $mapref eq 'HASH') {
		$irMap{$defaultMapFile}{$mode} = $mapref;
	}
}

sub loadMapFile {
	my $mapfile = shift;
	my $mode;

	$::d_ir && msg("opening map file $mapfile\n");
	
	if (-r $mapfile) {
		delete $irMap{$mapfile};
		open(MAP, $mapfile);
		while (<MAP>) {
			if (/\[(.+)\]/) {
				$mode = $1;
				next;
			}
			chomp; 			# no newline
			s/^\s+//;		# no leading white
			s/\s+$//;		# no trailing white
			s/\s*#.*$//;		# trim comments (note, no #'s or ='s allowed in button names)
			next unless length;	#anything left?
			my ($buttonName, $function) = split(/\s*=\s*/, $_, 2);
			unless ($buttonName =~ /(.+)\.\*/) {
				$irMap{$mapfile}{$mode}{$buttonName} = $function;
			} else {
				for my $style (@buttonPressStyles) {
					$irMap{$mapfile}{$mode}{$1 . $style} = $function unless exists($irMap{$mapfile}{$mode}{$1 . $style}) ;
				}
			}
		}
		close(MAP);
		
	} else {
		$::d_ir && msg("failed to open $mapfile\n");
	}
}

sub loadIRFile {
	my $irfile = shift;

	$::d_ir && msg("opening IR file $irfile\n");
	
	if (-r $irfile) {
		delete $irCodes{$irfile};
		open(IRCODES, $irfile);
		while (<IRCODES>) {
			chomp; 			# no newline
			s/^\s+//;		# no leading white
			s/\s+$//;		# no trailing white
			s/\s*#.*$//;		# trim comments (note, no #'s or ='s allowed in button names)
			next unless length;	#anything left?
			my ($buttonName, $irCode) = split(/\s*=\s*/, $_, 2);
			
			$irCodes{$irfile}{$irCode} = $buttonName;
		}
		close(IRCODES);
		
	} else {
		$::d_ir && msg("failed to open $irfile\n");
	}
}	

#
# Look up an IR code by hex value for enabled remotes, then look up the function for the current
# mode, and return the name of the function, eg "play"
#
sub lookup {
	my $client = shift;
	my $code = shift;
	my $modifier = shift;

	if (defined $code) {
	
		my %enabled = %{irfiles()};
		for (Slim::Utils::Prefs::clientGetArray($client,'disabledirsets')) {delete $enabled{$_}};
		
		for my $irset (keys %enabled) {
			if (defined $irCodes{$irset}{$code}) {
				$::d_ir && msg("found button $irCodes{$irset}{$code} for $code\n");
				$code = $irCodes{$irset}{$code};
				last;
			}
		}
		
		if (defined $modifier) {
			$code .= '.' . $modifier;
		}
		$client->lastirbutton($code);
		return lookupFunction($client,$code);
	} else {
		$::d_ir && msg("irCode not present\n");
		return '';
	}
}


sub lookupFunction {
	my $client = shift;
	my $code = shift;
	my $mode = shift;

	$mode = Slim::Buttons::Common::mode($client) unless defined($mode);
	my $map = Slim::Utils::Prefs::clientGet($client,'irmap');
	assert($client);
	assert($map);
	assert($mode);
#	assert($code); # FIXME: somhow we keep getting here with no $code.

	if (defined $irMap{$map}{$mode}{$code}) {
		$::d_ir && msg("found function " . $irMap{$map}{$mode}{$code} . " for button $code in mode $mode from map $map\n");
		return $irMap{$map}{$mode}{$code};
	} elsif (defined $irMap{$defaultMapFile}{$mode}{$code}) {
		$::d_ir && msg("found function " . $irMap{$defaultMapFile}{$mode}{$code} . " for button $code in mode $mode from map " . defaultMap() . "\n");
		return $irMap{$defaultMapFile}{$mode}{$code};
	} elsif ($mode =~ /(.+)\..+/ && defined $irMap{$map}{lc($1)}{$code}) {
		$::d_ir && msg("found function " . $irMap{$map}{lc($1)}{$code} . " for button $code in mode class ".lc($1)." from map $map\n");
		return $irMap{$map}{lc($1)}{$code};
	} elsif ($mode =~ /(.+)\..+/ && defined$irMap{$defaultMapFile}{lc($1)}{$code}) {
		$::d_ir && msg("found function " . $irMap{$defaultMapFile}{lc($1)}{$code} . " for button $code in mode class ".lc($1)." from map " . defaultMap() . "\n");
		return $irMap{$defaultMapFile}{lc($1)}{$code};			
	} elsif (defined $irMap{$map}{'common'}{$code}) {
		$::d_ir && msg("found function " . $irMap{$map}{'common'}{$code} . " for button $code in mode common from map $map\n");
		return $irMap{$map}{'common'}{$code};
	} elsif (defined $irMap{$defaultMapFile}{'common'}{$code}) {
		$::d_ir && msg("found function " . $irMap{$defaultMapFile}{'common'}{$code} . " for button $code in mode common from map " . defaultMap() . "\n");
		return $irMap{$defaultMapFile}{'common'}{$code};
	}
	
	$::d_ir && msg("irCode not defined: $code\n");
	return '';
}

#
# Checks to see if a button has been released, this sub is executed through timers
sub checkRelease {
	my $client = shift;
	my $releaseType = shift;
	my $startIRTime = shift;
	my $startIRCodeBytes = shift;
	my $estIRTime = shift; #estimated IR Time
	my $now = Time::HiRes::time();
	
	if ($startIRCodeBytes ne $client->lastircodebytes) {
		# a different button was pressed, so the original must have been released
		if ($releaseType ne 'hold_check') {
			releaseCode($client,$startIRCodeBytes,$releaseType, $estIRTime);
			return 0; #should check for single press release
		}
	} elsif ($startIRTime != $client->startirhold) {
		# a double press possibly occurred
		if ($releaseType eq 'hold_check') {
			#not really a double press
			return 0;
		} elsif ($releaseType eq 'hold_release') {
			releaseCode($client,$startIRCodeBytes,$releaseType, $estIRTime);
			return 0;
		} else {
			releaseCode($client,$startIRCodeBytes,'double',$estIRTime);
			#reschedule to check for whether to fire hold_release
			Slim::Utils::Timers::setTimer($client,$now+($Slim::Hardware::IR::IRHOLDTIME),\&checkRelease
						,'hold_check',$client->startirhold,$startIRCodeBytes
						,$client->startirhold + $Slim::Hardware::IR::IRHOLDTIME);
			return 1; #don't check for single press release
		}
	} elsif ($estIRTime - $client->lastirtime < $Slim::Hardware::IR::IRMINTIME) {
		# still holding button down, so reschedule
		my $nexttime;
		if ($estIRTime >= ($startIRTime + $Slim::Hardware::IR::IRHOLDTIME)) {
			$releaseType = 'hold_release';
			# check for hold release every 1/2 hold time
			$nexttime = $Slim::Hardware::IR::IRHOLDTIME /2;
		} elsif (($estIRTime + $Slim::Hardware::IR::IRSINGLETIME) > ($startIRTime + $Slim::Hardware::IR::IRHOLDTIME)) {
			$nexttime = $startIRTime + $Slim::Hardware::IR::IRHOLDTIME - $estIRTime;
		} else {
			$nexttime = $Slim::Hardware::IR::IRSINGLETIME;
		}
		Slim::Utils::Timers::setTimer($client,$now+($nexttime),\&checkRelease
					,$releaseType,$startIRTime,$startIRCodeBytes,$estIRTime + $nexttime);
		return 1;
	} else {
		#button released
		if ($releaseType ne 'hold_check') {
			releaseCode($client,$startIRCodeBytes,$releaseType, $estIRTime);
		}
		return 0;
	}
}

sub processIR {
	my $client = shift;
	my $irCodeBytes = shift;
	my $irTime = shift;	
		
	my $timediff = $irTime - $client->lastirtime();
	if ($timediff < 0) {$timediff += (0xffffffff / $client->ticspersec());}

	if (($timediff < $Slim::Hardware::IR::IRMINTIME) && ($irCodeBytes ne $client->lastircodebytes)) {
		#received oddball code in middle of repeat sequence, drop it
		$::d_ir && msg("Received $irCodeBytes while expecting " . $client->lastircodebytes . ", dropping code\n");
		return;
	}
	
	if ($timediff == 0) { 
		$::d_ir && msg("Received duplicate IR timestamp: $irTime - ignoring\n");
		return;
	}
	
	$client->irtimediff($timediff);

	$client->lastirtime($irTime);

	if ($::d_ir) {
		msg("$irCodeBytes\t$irTime\t".Time::HiRes::time()."\n");
	}
	if ($irCodeBytes eq "00000000") {
		$::d_ir && msg("Ignoring spurious null repeat code.\n");
		return;
	} 

	if (($irCodeBytes eq ($client->lastircodebytes())) #same button press as last one
		&& ( ($client->irtimediff < $Slim::Hardware::IR::IRMINTIME) #within the minimum time to be considered a repeat
			|| (($client->irtimediff < $client->irrepeattime * 2.02) #or within 2% of twice the repeat time
				&& ($client->irtimediff > $client->irrepeattime * 1.98))) #indicating that a repeat code was missed
		) {
		holdCode($client,$irCodeBytes);
		repeatCode($client,$irCodeBytes);
		if (!$client->irrepeattime || ($client->irtimediff > 0 && $client->irtimediff < $client->irrepeattime)) {
			#repeat time not yet set or last time diff less than current estimate
			#of repeat time (excluding time diffs less than 0, from out of order packets)
			$client->irrepeattime($client->irtimediff)
		}
	} else {
		$client->startirhold($irTime);
		$client->lastircodebytes($irCodeBytes);
		$client->irrepeattime(0);
		my $noTimer = Slim::Utils::Timers::firePendingTimer($client,\&checkRelease);
		unless ($noTimer) {
			Slim::Utils::Timers::setTimer($client,Time::HiRes::time()+($Slim::Hardware::IR::IRSINGLETIME),\&checkRelease
						,'single',$irTime,$irCodeBytes,$irTime + $Slim::Hardware::IR::IRSINGLETIME)
		}
		my $irCode  = lookup($client,$irCodeBytes);
		$::d_ir && msg("irCode = [$irCode] timer = [$irTime] timediff = [" . $client->irtimediff . "] last = [".$client->lastircode()."]\n");
		processCode($client, $irCode, $irTime);

		# Notify the xPL module that an IR code has been received
		Slim::Control::xPL::processircode($client,$irCode,$irCodeBytes);    
	}
}

# utility functions used externally
sub resetHoldStart {
	my $client = shift;
	
	$client->startirhold($client->lastirtime);
}

sub resendButton {
	my $client = shift;
	my $ircode = lookup($client,$client->lastircodebytes);
	if (defined $ircode) {
		processCode($client,$ircode, $client->lastirtime);
	}
}

sub lastIRTime {
	my $client = shift;
	return $client->epochirtime;
}

sub setLastIRTime {
	my $client = shift;
	$client->epochirtime(shift);
}

#
#
sub releaseCode {
	my $client = shift;
	my $irCodeBytes = shift;
	my $releaseType = shift;
	my $irtime = shift;

	my $ircode = lookup($client,$irCodeBytes, $releaseType);
	if ($ircode) {
		processCode( $client, $ircode, $irtime);
	}
}

#
# Some buttons should be handled once when held for a period of time
sub holdCode {
	my $client = shift;
	my $irCodeBytes = shift;
	
	my $holdtime = holdTime($client);
	if ($holdtime >= $Slim::Hardware::IR::IRHOLDTIME && ($holdtime - $Slim::Hardware::IR::IRHOLDTIME) < $client->irtimediff) {
		# the time for the hold firing took place within the last ir interval
		my $ircode = lookup($client,$irCodeBytes, 'hold');
		if ($ircode) {
			processCode( $client, $ircode, $client->lastirtime);
		}
	}
}

#
# Some buttons should be handled repeatedly if held down. This function is called
# when IR codes that are received repeatedly - we decide how to handle it.
#
sub repeatCode {
	my $client = shift;
	my $irCodeBytes = shift;

	my $ircode = lookup($client,$irCodeBytes, 'repeat');
	$::d_ir && msg("irCode = [$ircode] timer = [" . $client->lastirtime . "] timediff = [" . $client->irtimediff . "] last = [".$client->lastircode()."]\n");
	if ($ircode) {
		processCode( $client, $ircode, $client->lastirtime);
	}
}

sub repeatCount {
	my $client = shift;
	#my $minrate = shift; #not used currently, could be added for more complex behavior
	my $maxrate = shift;
	my $accel = shift;
	my $holdtime = holdTime($client);
	if (!$holdtime) { return 0;} #nothing on the initial time through
	if ($accel) {
		#calculate the number of repetitions we should have made by this time
		if ($maxrate && $maxrate < $holdtime * $accel) {
			#done accelerating, so number of repeats during the acceleration
			#plus the max repeat rate times the time since acceleration was finished
			my $flattime = $holdtime - $maxrate/$accel;
			return int($maxrate * $flattime) - int($maxrate * ($flattime - $client->irtimediff));
		} else {
			#number of repeats is the expected integer number of repeats for the current time
			#minus the expected integer number of repeats for the last ir time.
			return int(accelCount($holdtime,$accel)) - int(accelCount($holdtime - $client->irtimediff,$accel));
		}
	} else {
		return int($maxrate * $holdtime) - int($maxrate * ($holdtime - $client->irtimediff));
	}
}

sub accelCount {
	my $time = shift;
	my $accel = shift;
	
	return 0.5 * $accel * $time * $time;
}


sub holdTime {
	my $client = shift;

	if ($client->lastirtime ==  0) { return 0;}

	my $holdtime = $client->lastirtime - $client->startirhold;
	if ($holdtime < 0) {
		$holdtime += 0xffffffff / $client->ticspersec();
	}
	return $holdtime;
}


#
# calls the appropriate handler for the specified button.
#
sub executeButton {
	my $client = shift;
	my $button = shift;
	my $time = shift;
	my $mode = shift;
	my $orFunction = shift; #allow function names as $button

	my $irCode = lookupFunction($client, $button, $mode);
	
	if ($orFunction && (!defined $irCode || $irCode eq '')) {
		$irCode = $button;
	}
	
	$::d_ir && msg("trying to execute button: $irCode\n");

	if ($irCode ne "0" || !defined $time) {
		setLastIRTime($client, Time::HiRes::time());
	}

	if (!defined $time) {
		$client->lastirtime(0);
	}

	if (my ($subref,$subarg) = Slim::Buttons::Common::getFunction($client,$irCode,$mode) ) {

		unless (defined $subref or ref($subref)) {
			die "Subroutine for irCode: [$irCode] does not exist!";
		}
		
		Slim::Buttons::ScreenSaver::wakeup($client, $client->lastircode());
			
		no strict 'refs';
		$::d_ir && msg("executing button: $irCode\n");
		&$subref($client,$irCode,$subarg);

	} else {
		$::d_ir && msg("button $irCode not implemented in this mode\n");
	}
}

sub processCode {
	my ($client, $irCode, $irTime) = @_;

	$::d_ir && msg("irCode: $irCode, ".$client->id()."\n");

	$client->lastircode($irCode);
	$client->easteregg($client->easteregg ? ($client->easteregg . ',' . $irCode) : $irCode);

	my $eggsofar = $client->easteregg;
	if (!($eggseq=~/^$eggsofar/)) {
		$client->easteregg('');
	}

	if ($eggseq eq $eggsofar) {
		$client->easteregg('');
		$client->doEasterEgg();
	} else {
		Slim::Control::Command::execute($client, ['button', $irCode, $irTime, 1]);
	}
}

1;
