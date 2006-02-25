package Slim::Buttons::Synchronize;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use File::Spec::Functions qw(:ALL);
use File::Spec::Functions qw(updir);
use Slim::Display::Display;

our %functions = ();

sub init {
	Slim::Buttons::Common::addMode('synchronize', {}, \&setMode);
}

sub loadList {
	my $client = shift;
	
	@{$client->syncSelections} = Slim::Player::Sync::canSyncWith($client);
	
	# add ourselves (for unsyncing) if we're already part of a synced.
	if (Slim::Player::Sync::isSynced($client)) { push @{$client->syncSelections}, $client };

	if (!defined($client->syncSelection()) || $client->syncSelection >= @{$client->syncSelections}) {
		$client->syncSelection(0);
	}
}

sub lines {
	my $client = shift;

	my $line1;

	loadList($client);
	
	if (scalar @{$client->syncSelections} < 1) {

		warn "Can't sync without somebody to sync with!";
		Slim::Buttons::Common::popMode($client);

	} else {
			# get the currently selected client
			my $selectedClient = $client->syncSelections($client->syncSelection);
			
			if (Slim::Player::Sync::isSyncedWith($client, $selectedClient) || $selectedClient eq $client) {
				$line1 = $client->string('UNSYNC_WITH');
			} else {
				$line1 = $client->string('SYNC_WITH');
			}
	}

	return $line1;
}

sub buddies {
	my $client = shift;
	my $selectedClient = shift || $client->syncSelections($client->syncSelection);;

	my @buddies = ();
	my $list = '';
	
	foreach my $buddy (Slim::Player::Sync::syncedWith($selectedClient)) {
		if ($buddy ne $client) {
			push @buddies, $buddy;	
		}
	}
	
	if ($selectedClient ne $client) {
		push @buddies, $selectedClient;
	}
	
	while (scalar(@buddies) > 2) {
		my $buddy = pop @buddies;
		$list .= $buddy->name() . ", ";
	}
	
	if (scalar(@buddies) > 1) {
		my $buddy = pop @buddies;
		$list .= $buddy->name() . " " . $client->string('AND') . " ";		
	}

	my $buddy = pop @buddies;
	$list .= $buddy->name();
	
	return $list;
}

sub setMode {
	my $client = shift;
	my $method = shift;
	if ($method eq 'pop') {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	loadList($client);
	
	my %params = (
		'header'         => \&lines,
		'headerArgs'     => 'C',
		'listRef'        => \@{$client->syncSelections},
		'externRef'      => sub {
								return buddies($_[0], undef);
							},
		'externRefArgs'  => 'CV',
		'overlayRef'     => sub { return (undef, Slim::Display::Display::symbol('rightarrow')) },
		'overlayRefArgs' => '',
		'callback'       => \&syncExitHandler,
		'onChange'       => sub { $_[0]->syncSelection($_[1]); },
		'onChangeArgs'   => 'CI'
	);
	
	Slim::Buttons::Common::pushMode($client, 'INPUT.List', \%params);
}

sub syncExitHandler {
	my ($client,$exittype) = @_;
	$exittype = uc($exittype);
	if ($exittype eq 'LEFT') {
		Slim::Buttons::Common::popModeRight($client);
		
	} elsif ($exittype eq 'RIGHT') {
		my $selectedClient = $client->syncSelections($client->syncSelection);
	
		my @oldlines = Slim::Display::Display::curLines($client);
	
		if (Slim::Player::Sync::isSyncedWith($client, $selectedClient) || ($client eq $selectedClient)) {
			Slim::Player::Sync::unsync($client);
		} else {
			Slim::Player::Sync::sync($client, $selectedClient);
		}

		$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	} else {
		return;
	}
}

1;

__END__
