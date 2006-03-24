# Plugin for Slimserver to monitor Server and Network Health
#
# Network Throughput Tests for Health Plugin
# Operated via Health web page or player user interface

# $Id$

# This code is derived from code with the following copyright message:
#
# SlimServer Copyright (C) 2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

package Plugins::Health::NetTest;

our @testRates = ( 64, 128, 192, 256, 320, 500, 1000, 1500, 2000, 2500, 3000, 4000, 5000);

our %functions = (
	'left' => sub  {
		my $client = shift;
		exitMode($client);
		Slim::Buttons::Common::popModeRight($client);
	},

	'down' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'down');

		my $params = $client->modeParam('Health.NetTest') || return;;
		setTest($client, $params->{'test'} + 1, undef, $params);
		Slim::Utils::Timers::killTimers($client, \&updateDisplay);
		updateDisplay($client, $params);
	},

	'up' => sub  {
		my $client = shift;
		my $button = shift;
		return if ($button ne 'up');

		my $params = $client->modeParam('Health.NetTest') || return;
		setTest($client, $params->{'test'} - 1, undef, $params);
		Slim::Utils::Timers::killTimers($client, \&updateDisplay);
		updateDisplay($client, $params);
	},
);

sub setMode {
	my $client = shift;

	if (!$client->isa("Slim::Player::SqueezeboxG")) {
		$client->lines(\&errorLines);
		return;
	} 

	$client->execute(["stop"]); # ensure this player is not streaming

	my $params = { 
		'test'   => 0,
		'rate'   => $testRates[0],
		'int'    => undef,
		'Qlen0'  => 0,
		'Qlen1'  => 0, 
		'log'    => Slim::Utils::PerfMon->new('Network Throughput', [10, 20, 30, 40, 50, 60, 70, 75, 80, 85, 90, 95, 100]),
		'header' => $client->scrollHeader(),
		'frameLen'=> length($client->scrollHeader()) + $client->screenBytes(),
		'refresh'=> Time::HiRes::time(), 
	};

	$client->modeParam('Health.NetTest', $params);

	$client->lines(\&lines);

	# start display functions after delay [to allow push animation to complete]
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 0.8, \&startDisplay, $params); 
}

sub exitMode {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&updateDisplay);
	Slim::Utils::Timers::killHighTimers($client, \&sendDisplay);
	Slim::Utils::Timers::killTimers($client, \&startDisplay);
	
	$client->modeParam('Health.NetTest', undef);
	$client->updateMode(0); # unblock screen updates
}

sub setTest {
	my $client = shift;
	my $test = shift;
	my $rate = shift;
	my $params = shift;

	if (defined($test)) {
		$rate = $testRates[$test];
	} elsif (defined($rate)) {
		foreach my $t (0..$#testRates) {
			if ($testRates[$t] eq $rate) {
				$test = $t;
				last;
			}
		}
	}

	if (!defined $test || $test < 0 || $test > $#testRates) {
		return;
	}

	$params->{'test'} = $test;
	$params->{'rate'} = $rate;
	$params->{'int'} = ($client->screenBytes() + 10) * 8 / $params->{'rate'} / 1000;
	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;
	$params->{'log'}->clear();
}

sub startDisplay {
	my $client = shift;
	my $params = shift;

	$client->killAnimation(); # kill any outstanding animation
	$client->updateMode(2);   # block screen updates
	updateDisplay($client, $params);
	sendDisplay($client, $params);
}

sub updateDisplay {
	my $client = shift;
	my $params = shift;

	if (Slim::Buttons::Common::mode($client) ne 'PLUGIN.Health::Plugin') {
		exitMode($client);
		return;
	}

	$client->render(lines($client, $params));

	$params->{'Qlen0'} = 0;
	$params->{'Qlen1'} = 0;

	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + 1.0, \&updateDisplay, $params);
}

sub sendDisplay {
	my $client = shift;
	my $params = shift;

	if (Slim::Buttons::Common::mode($client) ne 'PLUGIN.Health::Plugin') {
		exitMode($client);
		return;
	}

	my $frame = $params->{'header'} . ${$client->renderCache()->{'bitsref'}};

	my $slimprotoQLen = Slim::Networking::Select::writeNoBlockQLen($client->tcpsock);

	$slimprotoQLen ? $params->{'Qlen1'}++ : $params->{'Qlen0'}++;

	if (($slimprotoQLen == 0) && (length($frame) == $params->{'frameLen'})) {
		Slim::Networking::Select::writeNoBlock($client->tcpsock, \$frame);
	}

	if ($params->{'int'}) {
		my $timenow = Time::HiRes::time();
		# skip if running late [reduces actual rate sent, but avoids recording throughput drop when timers are late]
		do {
			$params->{'refresh'} += $params->{'int'};
		} while ($params->{'refresh'} < $timenow);
	} else {
		$params->{'refresh'} += 0.5;
	}
	
	Slim::Utils::Timers::setHighTimer($client, $params->{'refresh'}, \&sendDisplay, $params);
}

sub lines {
	my $client = shift;
	my $params = shift;

	my $test = $params->{'test'};
	my $rate = $params->{'rate'};
	my $inst = $params->{'Qlen0'} ? $params->{'Qlen0'} / ($params->{'Qlen1'} + $params->{'Qlen0'}) : 0;

	$params->{'log'}->log($inst * 100) if ($inst > 0);

	my $logTotal = defined($params->{'log'}) ? $params->{'log'}->count() : 0;
	my $avgPercent = $logTotal ? $params->{'log'}->{'sum'} / $logTotal : 0;

	return {
		'line1'    => $client->string('PLUGIN_HEALTH_NETTEST_SELECT_RATE'),
		'overlay1' => $client->symbols($client->progressBar(100, $inst)),
		'overlay2' => sprintf("%i kbps : %3i%% Avg: %3i%%", $rate, $inst * 100, $avgPercent),
		'fonts'    => {
			'graphic-320x32' => 'standard',
			'graphic-280x16' => 'medium',
		}
	};
}

sub errorLines {
	my $client = shift;
	return { 'line1' => $client->string('PLUGIN_HEALTH_NETTEST_NOT_SUPPORTED') };
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
