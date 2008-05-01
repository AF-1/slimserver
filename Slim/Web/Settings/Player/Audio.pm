package Slim::Web::Settings::Player::Audio;

# $Id: Basic.pm 10633 2006-11-09 04:26:27Z kdf $

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use base qw(Slim::Web::Settings);

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Utils::Strings qw(string);

my $prefs = preferences('server');

sub name {
	return Slim::Web::HTTP::protectName('AUDIO_SETTINGS');
}

sub page {
	return Slim::Web::HTTP::protectURI('settings/player/audio.html');
}

sub needsClient {
	return 1;
}

sub handler {
	my ($class, $client, $paramRef) = @_;

	my @prefs = qw(powerOnResume maxBitrate lameQuality);

	if (Slim::Player::Sync::isSynced($client) || (scalar(Slim::Player::Sync::canSyncWith($client)) > 0))  {
		push @prefs,qw(synchronize syncVolume syncPower syncBufferThreshold startDelay maintainSync playDelay packetLatency minSyncAdjust);
	} 
	
	if ($client->hasPowerControl()) {
		push @prefs,'powerOffDac';
	}
	
	if ($client->hasDisableDac()) {
		push @prefs,'disableDac';
	}

	if ($client->maxTransitionDuration()) {
		push @prefs,qw(transitionType transitionDuration);
	}
	
	if ($client->hasDigitalOut()) {
		push @prefs,qw(digitalVolumeControl mp3SilencePrelude);
	}

	if ($client->hasPreAmp()) {
		push @prefs,'preampVolumeControl';
	}
	
	if ($client->hasAesbeu()) {
		push @prefs,'digitalOutputEncoding';
	}

	if ($client->hasExternalClock()) {
		push @prefs,'clockSource';
	}

	if ($client->hasEffectsLoop()) {
		push @prefs,'fxloopSource';
	}

	if ($client->hasEffectsLoop()) {
		push @prefs,'fxloopClock';
	}

	if ($client->hasPolarityInversion()) {
		push @prefs,'polarityInversion';
	}
	
	if ($client->hasDigitalIn()) {
		push @prefs,'wordClockOutput';
	}

	
	if ($client->canDoReplayGain(0)) {
		push @prefs,'replayGainMode';
	}

	if ($client->isa('Slim::Player::Boom')) {
		push @prefs,'analogOutMode';
	}
	
	if ( $client->isa('Slim::Player::Squeezebox2') ) {
		push @prefs, 'mp3StreamingMethod';
	}
	
	# If this is a settings update
	if ($paramRef->{'saveSettings'}) {

		for my $pref (@prefs) {

			if ($pref eq 'synchronize') {
			
				if (my $otherClient = Slim::Player::Client::getClient($paramRef->{$pref})) {
					$otherClient->execute( [ 'sync', $client->id ] );
				} else {
					$client->execute( [ 'sync', '-' ] );
				}
			
			} else {

				$prefs->client($client)->set($pref, $paramRef->{$pref}) if defined $paramRef->{$pref};
			}
		}
	}

	# Load any option lists for dynamic options.
	$paramRef->{'syncGroups'} = syncGroups($client);
	$paramRef->{'lamefound'}  = Slim::Utils::Misc::findbin('lame');
	
	my @formats = $client->formats();

	if ($formats[0] ne 'mp3') {
		$paramRef->{'allowNoLimit'} = 1;
	}

	# Set current values for prefs
	# load into prefs hash so that web template can detect exists/!exists
	for my $pref (@prefs) {

		if ($pref eq 'synchronize') {

			$paramRef->{'prefs'}->{$pref} =  -1;

			if (Slim::Player::Sync::isSynced($client)) {

				$paramRef->{'prefs'}->{$pref} = $client->masterOrSelf->id();

			} elsif ( my $syncgroupid = $prefs->client($client)->get('syncgroupid') ) {

				# Bug 3284, we want to show powered off players that will resync when turned on
				my @players = Slim::Player::Client::clients();

				foreach my $other (@players) {

					next if $other eq $client;

					my $othersyncgroupid = $prefs->client($other)->get('syncgroupid');

					if ( $syncgroupid == $othersyncgroupid ) {

						$paramRef->{'prefs'}->{$pref} = $other->id;
					}
				}
			}

		} elsif ($pref eq 'maxBitrate') {
			
			$paramRef->{'prefs'}->{$pref} = Slim::Utils::Prefs::maxRate($client, 1);

		} else {

			$paramRef->{'prefs'}->{$pref} = $prefs->client($client)->get($pref);
		}
	}
	
	return $class->SUPER::handler($client, $paramRef);
}

# returns a hash reference to syncGroups available for a client
sub syncGroups {
	my $client = shift;

	my %clients = ();

	for my $eachclient (Slim::Player::Sync::canSyncWith($client)) {

		$clients{$eachclient->id} = Slim::Player::Sync::syncname($eachclient, $client);
	}

	if (Slim::Player::Sync::isMaster($client)) {

		$clients{$client->id} = Slim::Player::Sync::syncname($client, $client);
	}

	$clients{-1} = string('SETUP_NO_SYNCHRONIZATION');

	return \%clients;
}

1;

__END__
