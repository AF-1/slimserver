package Slim::Buttons::ScreenSaver;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Buttons::ScreenSaver

=head1 DESCRIPTION

Module to register basic core screensavers and to handle moving the player in
and out of screensaver modes.

=cut

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::Prefs;

my $prefs = preferences('server');

our %functions = ();

sub init {

	Slim::Buttons::Common::addSaver('screensaver', getFunctions(), \&setMode, undef, 'SCREENSAVER_JUMP_BACK_NAME');
	Slim::Buttons::Common::addSaver('nosaver', undef, undef, undef, 'SCREENSAVER_NONE');

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
	my $display = $client->display;

	my $now  = Time::HiRes::time();
	my $log  = logger('server.timers');
	my $mode = Slim::Buttons::Common::mode($client);

	assert($mode);

	if ($log->is_info) {

		my $diff = $now - Slim::Hardware::IR::lastIRTime($client) - $prefs->client($client)->get('screensavertimeout');

		$log->info("screenSaver idle display [$diff] (mode: [$mode])");
	}

	# some variables, so save us calling the same functions multiple times.
	my $saver   = $prefs->client($client)->get(Slim::Player::Source::playmode($client) eq 'play' ? 'screensaver' : 'idlesaver');
	my $dim     = $prefs->client($client)->get('idleBrightness');
	my $timeout = $prefs->client($client)->get('screensavertimeout');
	my $irtime  = Slim::Hardware::IR::lastIRTime($client);
	
	# if we are already in now playing, jump back screensaver is redundant and confusing
	if ($saver eq 'screensaver' && $mode eq 'playlist') {
		$saver = 'playlist'; 
	}
	
	# automatically control brightness if set to do so.
	if ($prefs->client($client)->get('autobrightness') && defined $display->brightness()) {
		
		# dim the screen if we're not playing...  will restore brightness on next IR input.
		# only need to do this once, but its hard to ensure all cases, so it might be repeated.
		if ( $timeout && 
				$irtime && $irtime < $now - $timeout && 
				$mode ne 'block' && $client->power()) {
	
			$display->brightness($dim) if $display->brightness() != $dim;
		
		} elsif ($client->power && $display->brightness() != $prefs->client($client)->get('powerOnBrightness')) {
			$display->brightness($prefs->client($client)->get('powerOnBrightness'));
		
		} elsif (!$client->power && $display->brightness() != $prefs->client($client)->get('powerOffBrightness')) {
			$display->brightness($prefs->client($client)->get('powerOffBrightness'));
		}
	}

	if ($display->updateMode() == 2 || $display->animateState() ) {

		# don't change whilst updates blocked or animating (non scrolling)

	} elsif ($mode eq 'block') {

		# blocked mode handles its own updating of the screen.

	} elsif ($saver eq 'nosaver' && $client->power()) {

		# don't change modes when none (just dim) is the screensaver.

	} elsif ($timeout && 
			
			# no ir for at least the screensaver timeout
			$irtime < $now - $timeout && 
			
			# make sure it's not already in a valid saver mode.
			( ($mode ne $saver && Slim::Buttons::Common::validMode($saver)) || 
				# in case the saver is 'now playing' and we're browsing another song
				($mode eq 'playlist' && !Slim::Buttons::Playlist::showingNowPlaying($client)) ||
				# just in case it falls into default, we dont want recursive pushModes
				($mode ne 'screensaver' && !Slim::Buttons::Common::validMode($saver)) ) &&
			
			# not blocked and power is on
			$mode ne 'block' && $client->power()) {
		
		# we only go into screensaver mode if we've timed out 
		# and we're not off or blocked
		if ($saver eq 'playlist') {

			if ($mode eq 'playlist') {

				Slim::Buttons::Playlist::browseplaylistindex($client, Slim::Player::Source::playingSongIndex($client));

			} else {

				Slim::Buttons::Common::pushMode($client,'playlist');
			}

		} else {

			if (Slim::Buttons::Common::validMode($saver)) {

				Slim::Buttons::Common::pushMode($client, $saver);

			} else {

				logger('player.ui.screensaver')->warn("Mode [$saver] not found, using default");

				Slim::Buttons::Common::pushMode($client, 'screensaver');
			}
		}

		$display->update();

	} elsif (!$client->power()) {

		$saver = $prefs->client($client)->get('offsaver');
		$saver =~ s/^SCREENSAVER\./OFF\./;

		if ($saver eq 'nosaver') {

			# do nothing

		} elsif ($mode ne $saver) {

			if (Slim::Buttons::Common::validMode($saver)) {

				Slim::Buttons::Common::pushMode($client, $saver);

			} else {

				logger('player.ui.screensaver')->warn("Mode [$saver] not found, using default");

				if ($mode ne 'off') {
					Slim::Buttons::Common::setMode($client, 'off');
				}
			}

			$display->update();
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
	
	my $display = $client->display;
	
	return if ($button && ($button =~ "brightness" || $button eq "dead"));
	
	Slim::Hardware::IR::setLastIRTime($client, Time::HiRes::time());

	if (!$prefs->client($client)->get('autobrightness')) { return; };
	
	my $curBrightnessPref;
	
	if (Slim::Buttons::Common::mode($client) eq 'off' || !$client->power()) {
		$curBrightnessPref = $prefs->client($client)->get('powerOffBrightness');
	} else {
		$curBrightnessPref = $prefs->client($client)->get('powerOnBrightness');
	} 
	
	if ($curBrightnessPref != $display->brightness()) {
		$display->brightness($curBrightnessPref);
	}
	
	# Bug 2293: jump to now playing index if we were showing the current song before the screensaver kicked in
	if (Slim::Buttons::Playlist::showingNowPlaying($client) || (Slim::Player::Playlist::count($client) < 1)) {
		Slim::Buttons::Playlist::jump($client);
	}

	# wake up our display if it is off and the player isn't in standby and we're not adjusting the 
	# brightness
	if ($button && 
		$button ne 'brightness_down' &&
		$button ne 'brightness_up' && 
		$button ne 'brightness_toggle' &&
		$display->brightness() == 0 &&
		$client->power()) { 
			$prefs->client($client)->set('powerOnBrightness', 1);
			$display->brightness(1);
	}
} 

sub setMode {
	my $client = shift;

	logger('player.ui.screensaver')->debug("Going into screensaver mode.");

	$client->lines( $client->customPlaylistLines() || \&Slim::Buttons::Playlist::lines );

	# update client every second in this mode
	$client->modeParam('modeUpdateInterval', 1); # seconds
	$client->modeParam('screen2', 'screensaver');
}

=head1 SEE ALSO

L<Slim::Buttons::Common>

L<Slim::Hardware::IR>

=cut

1;

__END__
