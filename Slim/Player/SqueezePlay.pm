package Slim::Player::SqueezePlay;

# Squeezebox Server Copyright (c) 2001-2009 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

use strict;
use vars qw(@ISA);

use Slim::Utils::Log;

my $log = logger('network.protocol.slimproto');

BEGIN {
	if ( main::SLIM_SERVICE ) {
		require SDI::Service::Player::SqueezeNetworkClient;
		push @ISA, qw(SDI::Service::Player::SqueezeNetworkClient);
	}
	else {
		require Slim::Player::Squeezebox2;
		push @ISA, qw(Slim::Player::Squeezebox2);
	}
}

{
	
	__PACKAGE__->mk_accessor('rw', qw(
		_model modelName
		myFormats
		maxSupportedSamplerate
		accuratePlayPoints
		firmware
		canDecodeRhapsody
	));
}

sub new {
	my $class = shift;

	my $client = $class->SUPER::new(@_);
	
	$client->init_accessor(
		_model                  => 'squeezeplay',
		modelName               => 'SqueezePlay',
		myFormats               => [qw(ogg flc aif pcm mp3)],	# in order of preference
		maxSupportedSamplerate  => 48000,
		accuratePlayPoints      => 0,
		firmware                => 0,
		canDecodeRhapsody       => 0,
	);

	return $client;
}

# model=squeezeplay,modelName=SqueezePlay,ogg,flc,pcm,mp3,tone,MaxSampleRate=96000

my %CapabilitiesMap = (
	Model                   => '_model',
	ModelName               => 'modelName',
	MaxSampleRate           => 'maxSupportedSamplerate',
	AccuratePlayPoints      => 'accuratePlayPoints',
	Firmware                => 'firmware',
	Rhap                    => 'canDecodeRhapsody',

	# deprecated
	model                   => '_model',
	modelName               => 'modelName',
);

sub model {
	return shift->_model;
}

sub revision {
	return shift->firmware;
}

sub needsUpgrade {}

sub init {
	my $client = shift;
	my ($model, $capabilities) = @_;
	
	$client->updateCapabilities($capabilities);
	
	# Do this at end so that any resync that happens has the capabilities already set
	$client->SUPER::init(@_);
}


sub reconnect {
	my ($client, $paddr, $revision, $tcpsock, $reconnect, $bytes_received, $capabilities) = @_;
	
	$client->updateCapabilities($capabilities);
	
	$client->SUPER::reconnect($paddr, $revision, $tcpsock, $reconnect, $bytes_received);
}

sub updateCapabilities {
	my ($client, $capabilities) = @_; 
	
	if ($client && $capabilities) {
		
		# if we have capabilities then all CODECs must be declared that way
		my @formats;
		
		for my $cap (split(/,/, $capabilities)) {
			if ($cap =~ /^[a-z][a-z0-9]{1,3}$/) {
				push(@formats, $cap);
			} else {
				my $value;
				my $vcap;
				if ((($vcap, $value) = split(/=/, $cap)) && defined $value) {
					$cap = $vcap;
				} else {
					$value = 1;
				}
				
				if (defined($CapabilitiesMap{$cap})) {
					my $f = $CapabilitiesMap{$cap};
					$client->$f($value);
				
				} else {
					
					# It could be possible to have a completely generic mechanism here
					# but I have not does that for the moment
					$log->warn("unknown capability: $cap=$value, ignored");
				}
			}
		}
		
		$log->is_info && $log->info('formats: ', join(',', @formats));
		$client->myFormats([@formats]);
	}
}

sub hasIR() { return 0; }

sub formats {
	return @{shift->myFormats};
}

# Need to use weighted play-point?
sub needsWeightedPlayPoint { !shift->accuratePlayPoints(); }

sub playPoint {
	my $client = shift;
	
	return $client->accuratePlayPoints()
		? $client->SUPER::playPoint(@_)
		: Slim::Player::Client::playPoint($client, @_);
}

sub skipAhead {
	my $client = shift;
	
	my $ret = $client->SUPER::skipAhead(@_);
	
	$client->playPoint(undef);
	
	return $ret;
}
1;

__END__
