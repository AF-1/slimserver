# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
package Slim::Player::SLIMP3;

use strict;
use Slim::Player::Player;
use Slim::Utils::Misc;

use base qw(Slim::Player::Player);

our $SLIMP3Connected = 0;

sub new {
	my $class    = shift;
	my $id       = shift;
	my $paddr    = shift;
	my $revision = shift;
	my $udpsock  = shift;
	
	my $client = $class->SUPER::new($id, $paddr, $revision);

	# defined only for Slimp3
	$client->udpsock($udpsock);

	# add the new client all the currently known clients so we can say hello to them later
	my $clientlist = Slim::Utils::Prefs::get("clients");

	my $newplayeraddr = $client->ipport();

	if (defined($clientlist)) {
		$clientlist .= ",$newplayeraddr";
	} else {
		$clientlist = $newplayeraddr;
	}

	my %seen = ();
	my @uniq = ();  

	foreach my $item (split( /,/, $clientlist)) {
		push(@uniq, $item) unless $seen{$item}++ || $item eq '';
	}

	Slim::Utils::Prefs::set("clients", join(',', @uniq));

	# Turn on readUDP in the select loop.
	$SLIMP3Connected = 1;

	# dsully - Mon Mar 21 20:17:44 PST 2005
	# Load these modules on the fly to save approx 700k of memory.
	for my $module (qw(Slim::Hardware::mas3507d Slim::Networking::Stream)) {

		$::d_protocol && Slim::Utils::Misc::msg("Loading module: $module\n");

		eval "use $module";

		if ($@) {
			Slim::Utils::Misc::msg("Couldn't load module: $module for SLIMP3: [$@] - THIS IS FATAL\n");
			Slim::Utils::Misc::bt();
			$@ = '';
		}
	}

	return $client;
}

sub connected {
	return 1;
}

sub model {
	return 'slimp3';
}

sub type {
	return 'player';
}

sub ticspersec {
	return 625000;
}

sub decoder {
	return 'mas3507d';
}

sub vfdmodel {
	my $client = shift;
	if ($client->revision >= 2.2) {
		my $mac = $client->macaddress();
		if ($mac eq '00:04:20:03:04:e0') {
			return 'futaba-latin1';
		} elsif ($mac eq '00:04:20:02:07:6e' ||
				$mac =~ /^00:04:20:04:1/ ||
				$mac =~ /^00:04:20:00:/	) {
			return 'noritake-european';
		} else {
			return 'noritake-katakana';
		}
	} else {
		return 'noritake-katakana';
	}		
}

sub play {
	my $client = shift;
	my $paused = shift;
	
	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(),
					defined($client->tempVolume()));

	$client->i2c(
		 Slim::Hardware::mas3507d::masWrite('config','00002')
		.Slim::Hardware::mas3507d::masWrite('loadconfig')
		.Slim::Hardware::mas3507d::masWrite('plloffset48','5d9e9')
		.Slim::Hardware::mas3507d::masWrite('plloffset44','cecf5')
		.Slim::Hardware::mas3507d::masWrite('setpll')
	);

	# sleep for .05 seconds
	# this little kludge is to prevent overflowing cs8900's RX buf because the client
	# is still processing the i2c commands we just sent.
	select(undef,undef,undef,.05);

	Slim::Networking::Stream::newStream($client, $paused);
	return 1;
}

#
# tell the client to unpause the decoder
#
sub resume {
	my $client = shift;
	# make sure volume is set, without changing temp setting
	$client->volume($client->volume(),
					defined($client->tempVolume()));
	Slim::Networking::Stream::unpause($client);
	$client->SUPER::resume();
	return 1;
}

#
# pause
#
sub pause {
	my $client = shift;
	Slim::Networking::Stream::pause($client);
	$client->SUPER::pause();
	return 1;
}

#
# does the same thing as pause
#
sub stop {
	my $client = shift;
	Slim::Networking::Stream::stop($client);
}

#
# playout - play out what's in the buffer
#
sub playout {
	my $client = shift;
	Slim::Networking::Stream::playout($client);
	return 1;
}

sub bufferFullness {
	my $client = shift;
	return Slim::Networking::Stream::fullness($client);
}

sub bufferSize {
	return 131072;
}

sub formats {
	return ('mp3');
}

sub refresh {
	shift->update(@_);
}

sub vfd {
	my $client = shift;
	my $data = shift;

	my $frame;
	assert($client->udpsock);
	$frame = 'l                 '.$data;
	send($client->udpsock, $frame, 0, $client->paddr()); 
}

sub udpstream {
	my ($client, $controlcode, $wptr, $seq, $chunk) = @_;
		        
	my $frame = pack 'aCxxxxn xxn xxxxxx', (
		'm',                            # 'm' == mp3 data
		$controlcode,                   # control code   
		$wptr,                          # wptr
		$seq);

        
	$frame .= $chunk;
        
	send($client->udpsock, $frame, 0, $client->paddr());
}

sub i2c {
	my ($client, $data) = @_;

	$::d_i2c && msg("i2c: sending ".length($data)." bytes\n");

	send($client->udpsock, '2                 '.$data, 0, $client->paddr);
}

sub volume {
	my $client = shift;
	my $newvolume = shift;

	my $volume = $client->SUPER::volume($newvolume, @_);

	if (defined($newvolume)) {
		# volume squared seems to correlate better with the linear scale.  
		# I'm sure there's something optimal, but this is better.
	
		my $level = sprintf('%05X', 0x80000 * (($volume / $client->maxVolume) ** 2));
	
		$client->i2c(
			 Slim::Hardware::mas3507d::masWrite('ll', $level)
			.Slim::Hardware::mas3507d::masWrite('rr', $level)
		);
	}

	return $volume;
}

sub bass {
	my $client = shift;
	my $newbass = shift;
	my $bass = $client->SUPER::bass($newbass);

	$client->i2c( Slim::Hardware::mas3507d::masWrite('bass', Slim::Hardware::mas3507d::getToneCode($bass,'bass'))) if (defined($newbass));

	return $bass;
}

sub treble {
	my $client = shift;
	my $newtreble = shift;
	my $treble = $client->SUPER::treble($newtreble);

	$client->i2c( Slim::Hardware::mas3507d::masWrite('treble', Slim::Hardware::mas3507d::getToneCode($treble,'treble'))) if (defined($newtreble));

	return $treble;
}

1;
