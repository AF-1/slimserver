package Slim::Buttons::ScreenSaver;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

our %functions = ();

sub init {

	Slim::Buttons::Common::addSaver('screensaver', getFunctions(), \&setMode, undef, string('SCREENSAVER_JUMP_BACK_NAME'));
	Slim::Buttons::Common::addSaver('nosaver', undef, undef, undef, string('SCREENSAVER_NONE'));

	# Each button on the remote has a function:
	%functions = (
		'done' => sub  {
			my ($client ,$funct ,$functarg) = @_;

			Slim::Buttons::Common::popMode($client);
			$client->update();

			# pass along ir code to new mode if requested
			if (defined $functarg && $functarg eq 'passback') {
				Slim::Hardware::IR::resendButton($client);
			}
		}
	);
}

sub getFunctions {
	return \%functions;
}

sub screenSaver {
	my $client = shift;
	
	my $now = Time::HiRes::time();

	$::d_time && msg("screenSaver idle display " . (
		$now - Slim::Hardware::IR::lastIRTime($client) - 
			$client->prefGet("screensavertimeout")) . 
		"(mode:" . Slim::Buttons::Common::mode($client) . ")\n"
	);

	my $mode = Slim::Buttons::Common::mode($client);

	assert($mode);
	
	# some variables, so save us calling the same functions multiple times.
	my $saver = Slim::Player::Source::playmode($client) eq 'play' ? $client->prefGet('screensaver') : $client->prefGet('idlesaver');
	my $dim = $client->prefGet('idleBrightness');
	my $timeout = $client->prefGet("screensavertimeout");
	my $irtime = Slim::Hardware::IR::lastIRTime($client);
	
	# if we are already in now playing, jump back screensaver is redundant and confusing
	if ($saver eq 'screensaver' && $mode eq 'playlist') {
		$saver = 'playlist'; 
	}
	
	# dim the screen if we're not playing...  will restore brightness on next IR input.
	# only ned to do this once, but its hard to ensure all cases, so it might be repeated.
	if ( $timeout && $client->brightness() && 
			$client->brightness() != $dim &&
			$client->prefGet('autobrightness') &&
			$irtime &&
			$irtime < $now - $timeout && 
			$mode ne 'block' &&
			$client->power()) {
		$client->brightness($dim);
	}

	if ($client->updateMode() == 2 || $client->animateState() ) {
		# don't change whilst updates blocked or animating (non scrolling)
	} elsif ($mode eq 'block') {
		# blocked mode handles its own updating of the screen.
	} elsif ($saver eq 'nosaver' && $client->power()) {
		# don't change modes when none (just dim) is the screensaver.
	} elsif ($timeout && 
			$irtime < $now - $timeout && 
			$mode ne $saver &&
			$mode ne 'screensaver' && # just in case it falls into default, we dont want recursive pushModes
			$mode ne 'block' &&
			$client->power()) {
		
		# we only go into screensaver mode if we've timed out 
		# and we're not off or blocked
		if ($saver eq 'playlist') {
			if ($mode eq 'playlist') {
				Slim::Buttons::Playlist::jump($client);
			} else {
				Slim::Buttons::Common::pushMode($client,'playlist');
			}
		} else {
			if (Slim::Buttons::Common::validMode($saver)) {
				Slim::Buttons::Common::pushMode($client, $saver);
			} else {
				$::d_plugins && msg("Mode ".$saver." not found, using default\n");
				Slim::Buttons::Common::pushMode($client,'screensaver');
			}
		}
		$client->update();

	} elsif (!$client->power()) {
		$saver = $client->prefGet('offsaver');
		$saver =~ s/^SCREENSAVER\./OFF\./;
		if ($saver eq 'nosaver') {
			# do nothing
		} elsif ($mode ne $saver) {
			if (Slim::Buttons::Common::validMode($saver)) {
				Slim::Buttons::Common::pushMode($client, $saver);
			} else {
				$::d_plugins && msg("Mode ".$saver." not found, using default\n");
				Slim::Buttons::Common::setMode($client,'off') unless $mode eq 'off';
			}
			$client->update();
		}
	} else {
		# do nothing - periodic updates handled per client where required
	}
	# Call ourselves again after 1 second
	Slim::Utils::Timers::setTimer($client, ($now + 1.0), \&screenSaver);
}

sub wakeup {
	my $client = shift;
	my $button = shift;
	
	return if ($button && $button =~ "brightness");
	
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());

	if (!$client->prefGet('autobrightness')) { return; };
	
	my $curBrightnessPref;
	
	if (Slim::Buttons::Common::mode($client) eq 'off' || !$client->power()) {
		$curBrightnessPref = $client->prefGet('powerOffBrightness');
	} else {
		$curBrightnessPref = $client->prefGet('powerOnBrightness');
	} 
	
	if ($curBrightnessPref != $client->brightness()) {
		$client->brightness($curBrightnessPref);
	}
	# wake up our display if it is off and the player isn't in standby and we're not adjusting the 
	# brightness
	if ($button && 
		$button ne 'brightness_down' &&
		$button ne 'brightness_up' && 
		$button ne 'brightness_toggle' &&
		$client->brightness() == 0 &&
		$client->power()) { 
			$client->prefSet('powerOnBrightness', 1);
			$client->brightness(1);
	}
} 

sub setMode {
	my $client = shift;
	$::d_time && msg("going into screensaver mode");
	$client->lines(\&lines);
	# update client every second in this mode
	$client->param('modeUpdateInterval', 1); # seconds
}

sub lines {
	my $client = shift;
	$::d_time && msg("getting screensaver lines");
	return $client->currentSongLines();
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
