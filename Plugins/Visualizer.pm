# $Id: $

# SlimServer Copyright (c) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#

package Plugins::Visualizer;

use Slim::Player::Squeezebox2;

use vars qw($VERSION);
$VERSION = substr(q$Revision: 1.0 $,10);

my $VISUALIZER_NONE = 0;
my $VISUALIZER_VUMETER = 1;
my $VISUALIZER_SPECTRUM_ANALYZER = 2;
my $VISUALIZER_WAVEFORM = 3;

my $textontime = 5;
my $textofftime = 30;
my $initialtextofftime = 5;

my %client_context = ();
my @visualizer_screensavers = ( 'SCREENSAVER.visualizer_spectrum', 
								'SCREENSAVER.visualizer_digital_vumeter', 
								'SCREENSAVER.visualizer_analog_vumeter' );
my %screensaver_info = ( 
	'SCREENSAVER.visualizer_spectrum' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER',
		params => [$VISUALIZER_SPECTRUM_ANALYZER, 0, 0, 0x10000, 0, 160, 0, 4, 1, 1, 1, 3, 160, 160, 1, 4, 1, 1, 1, 3],
		showtext => 1,
	},
	'SCREENSAVER.visualizer_analog_vumeter' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER',
		params => [$VISUALIZER_VUMETER, 0, 1, 0, 160, 160, 160],
		showtext => 0,
	},
	'SCREENSAVER.visualizer_digital_vumeter' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER',
		params => [$VISUALIZER_VUMETER, 0, 0, 20, 130, 170, 130],
		showtext => 1,
	},
	'screensaver' => {
		name => 'PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT',
	}
);

sub getDisplayName {
	return 'PLUGIN_SCREENSAVER_VISUALIZER';
}

sub strings { return '
PLUGIN_SCREENSAVER_VISUALIZER
	DE	Visualizer Bildschirmschoner
	EN	Visualizer Screensaver
	ES	Salvapantallas de Visualizador

PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2
	DE	Benötigt Squeezebox2
	EN	Needs Squeezebox2
	ES	Requiere Squeezebox2

PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER
	EN	Spectrum Analyzer
	ES	Analizador de Espectro

PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER
	DE	Analoger VU Meter
	EN	Analog VU Meter
	ES	VUmetro análogo

PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER
	DE	Digitaler VU Meter
	EN	Digital VU Meter
	ES	VUmetro digital

PLUGIN_SCREENSAVER_VISUALIZER_PRESS_RIGHT_TO_CHOOSE
	DE	RIGHT drücken zum Aktivieren des Bildschirmschoners
	EN	Press -> to enable this screensaver 
	ES	Presionar -> para activar este salvapantallas

PLUGIN_SCREENSAVER_VISUALIZER_ENABLED
	DE	Bildschirmschoner aktiviert
	EN	This screensaver is enabled
	ES	Este salvapantallas está activo

PLUGIN_SCREENSAVER_VISUALIZER_DEFAULT
	DE	Standard Bildschirmschoner
	EN	Default screenaver
	ES	Salvapantallas por defecto

'};

##################################################
### Screensaver configuration mode
##################################################

our %configFunctions = (
	'up' => sub  {
		my $client = shift;
		my $newpos = Slim::Buttons::Common::scroll(
								$client,
								-1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		if ($client_context{$client}->{position} != $newpos) {
			$client_context{$client}->{position} = $newpos;
			$client->pushUp();
		}
	},
	'down' => sub  {
		my $client = shift;
		my $newpos = Slim::Buttons::Common::scroll(
								$client,
								1,
								scalar(@{$client_context{$client}->{list}}),
								$client_context{$client}->{position},
								);
		if ($client_context{$client}->{position} != $newpos) {
			$client_context{$client}->{position} = $newpos;
			$client->pushDown();
		}
	},
	'left' => sub  {
		my $client = shift;
		Slim::Buttons::Common::popModeRight($client);
	},
	'right' => sub  {
		my $client = shift;

		my $screensaver = $client_context{$client}->{list}->[$client_context{$client}->{position}];
		$client_context{$client}->{screensaver} = $screensaver;
		Slim::Utils::Prefs::clientSet($client,'screensaver',$screensaver);
		$client->update();
	}
);

sub configLines {
	my $client = shift;
	
	my ($line1, $line2, $select);
	my $item = $client_context{$client}->{list}->[$client_context{$client}->{position}];
	if ($item eq $client_context{$client}->{screensaver}) {
		$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER_ENABLED');
		$select = '[x]';
	}
	else {
		$line1 = $client->string('PLUGIN_SCREENSAVER_VISUALIZER_PRESS_RIGHT_TO_CHOOSE');
		$select = '[ ]';
	}

	$line2 = $client->string($screensaver_info{$item}->{name});

	return ($line1, $line2, undef, $select);
}

sub getFunctions {
	return \%configFunctions;
}

sub setMode {
	my $client = shift;

	my $cursaver = Slim::Utils::Prefs::clientGet($client,'screensaver');
	$client_context{$client}->{screensaver} = $cursaver;
	if (grep $_ eq $cursaver, @visualizer_screensavers) {
		$client_context{$client}->{list} = [ @visualizer_screensavers, 'screensaver' ];
	}
	else {
		$client_context{$client}->{list} = [ @visualizer_screensavers ];
	}
	unless (defined($client_context{$client}->{position}) &&
			$client_context{$client}->{position} < scalar(@{$client_context{$client}->{list}})) {
		$client_context{$client}->{position} = 0;
	}

	$client->lines(\&configLines);
}


##################################################
### Screensaver display mode
##################################################

our %screensaverFunctions = (
	'done' => sub  {
		my ($client ,$funct ,$functarg) = @_;

		Slim::Buttons::Common::popMode($client);
		$client->update();

		# pass along ir code to new mode if requested
		if (defined $functarg && $functarg eq 'passback') {
			Slim::Hardware::IR::resendButton($client);
		}
	},
);

sub screensaverLines {
	my $client = shift;
	if( $client->isa( "Slim::Player::Squeezebox2")) {
	}
	else {
		return( $client->string('PLUGIN_SCREENSAVER_VISUALIZER'),
				$client->string('PLUGIN_SCREENSAVER_VISUALIZER_NEEDS_SQUEEZEBOX2'));
	}
}

sub screenSaver {
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_spectrum',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_SPECTRUM_ANALYZER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_analog_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_ANALOG_VUMETER',
	);
	Slim::Buttons::Common::addSaver(
		'SCREENSAVER.visualizer_digital_vumeter',
		\%screensaverFunctions,
		\&setVisualizerMode,
		\&leaveVisualizerMode,
		'PLUGIN_SCREENSAVER_VISUALIZER_DIGITAL_VUMETER',
	);
}

sub leaveVisualizerMode() {
	my $client = shift;
	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);
}

sub setVisualizerMode() {
	my $client = shift;
	my $method = shift;

	# If we're popping back into this mode, it's because another screensaver
	# got stacked above us...so we really shouldn't be here.
	if (defined($method) && $method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	my $mode = Slim::Buttons::Common::mode($client);
	$client->modeParam('visu', $screensaver_info{$mode}->{params});

	$client->lines(\&screensaverLines);

	# do it again at the next period
	if ($screensaver_info{$mode}->{showtext}) {
		Slim::Control::Command::setExecuteCallback(\&_showsongtransition);
		Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $initialtextofftime,
									  \&_pushon,
									  $client);
	}
}

sub _showsongtransition {
	my $client = shift;
	my $paramsRef = shift;
	
	return if ($paramsRef->[0] ne 'newsong');
	
	my $mode = Slim::Buttons::Common::mode($client);
	return if (!$mode || $mode !~ /^SCREENSAVER.visualizer_/);
	return if (!$screensaver_info{$mode}->{showtext});
	
	_pushon($client);
}

sub _pushon {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);

	my $screen = {
			'fonts' => ['standard.1','high.2'],
			'line1' => '',
			'line2' => $client->string('NOW_PLAYING') . ': ' .
						Slim::Music::Info::getCurrentTitle($client, Slim::Player::Playlist::song($client)),
		};
	
	$client->pushLeft(undef, $screen);
	# do it again at the next period
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $textontime,
								  \&_pushoff,
								  $client);	
}

sub _pushoff {
	my $client = shift;

	Slim::Utils::Timers::killTimers($client, \&_pushoff);
	Slim::Utils::Timers::killTimers($client, \&_pushon);

	my $screen = {
			'line1' => '',
			'line2' => '' 
		};
	$client->pushRight(undef,$screen);
	# do it again at the next period
	Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $textofftime,
								  \&_pushon,
								  $client);	
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
