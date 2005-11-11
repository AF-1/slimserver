package Slim::Web::Pages::Playlist;

# $Id: Pages.pm 5121 2005-11-09 17:07:36Z dsully $

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use File::Spec::Functions qw(:ALL);
use POSIX ();
use Scalar::Util qw(blessed);

use Slim::DataStores::Base;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Web::Pages;

sub init {
	
	Slim::Web::HTTP::addPageFunction(qr/^playlist\.(?:htm|xml)/,\&playlist);
}

sub playlist {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	if (!defined($client)) {

		# fixed faster rate for noclients
		$params->{'playercount'} = 0;
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	
	} elsif ($client->needsUpgrade()) {

		$params->{'player_needs_upgrade'} = '1';
		return Slim::Web::HTTP::filltemplatefile("playlist_needs_upgrade.html", $params);
	}

	$params->{'playercount'} = Slim::Player::Client::clientCount();
	
	my $songcount = Slim::Player::Playlist::count($client);

	$params->{'playlist_items'} = '';
	$params->{'skinOverride'} ||= '';
	
	my $count = Slim::Utils::Prefs::get('itemsPerPage');

	unless (defined($params->{'start'}) && $params->{'start'} ne '') {

		$params->{'start'} = (int(Slim::Player::Source::playingSongIndex($client)/$count)*$count);
	}

	if ($client->currentPlaylist() && !Slim::Music::Info::isRemoteURL($client->currentPlaylist())) {
		$params->{'current_playlist'} = $client->currentPlaylist();
		$params->{'current_playlist_modified'} = $client->currentPlaylistModified();
		$params->{'current_playlist_name'} = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());
	}

	if ($::d_playlist && $client->currentPlaylistRender() && ref($client->currentPlaylistRender()) eq 'ARRAY') {

		msg("currentPlaylistChangeTime : " . localtime($client->currentPlaylistChangeTime()) . "\n");
		msg("currentPlaylistRender     : " . localtime($client->currentPlaylistRender()->[0]) . "\n");
		msg("currentPlaylistRenderSkin : " . $client->currentPlaylistRender()->[1] . "\n");
		msg("currentPlaylistRenderStart: " . $client->currentPlaylistRender()->[2] . "\n");

		msg("skinOverride: $params->{'skinOverride'}\n");
		msg("start: $params->{'start'}\n");
	}

	# Only build if we need to.
	# Check to see if we're newer, and the same skin.
	if ($songcount > 0 && 
		defined $params->{'skinOverride'} &&
		defined $params->{'start'} &&
		$client->currentPlaylistRender() && 
		ref($client->currentPlaylistRender()) eq 'ARRAY' && 
		$client->currentPlaylistChangeTime() && 
		$client->currentPlaylistRender()->[1] eq $params->{'skinOverride'} &&
		$client->currentPlaylistRender()->[2] eq $params->{'start'} &&
		$client->currentPlaylistChangeTime() < $client->currentPlaylistRender()->[0]) {

		if (Slim::Utils::Prefs::get("playlistdir")) {
			$params->{'cansave'} = 1;
		}

		$::d_playlist && msg("Skipping playlist build - not modified.\n");

		$params->{'playlist_header'}  = $client->currentPlaylistRender()->[3];
		$params->{'playlist_pagebar'} = $client->currentPlaylistRender()->[4];
		$params->{'playlist_items'}   = $client->currentPlaylistRender()->[5];

		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}

	if (!$songcount) {
		return Slim::Web::HTTP::filltemplatefile("playlist.html", $params);
	}

	my %listBuild = ();
	my $item;
	my %list_form;

	$params->{'cansave'} = 1;
	
	my ($start, $end);
	
	if (defined $params->{'nopagebar'}) {

		($start, $end) = Slim::Web::Pages->simpleHeader(
			$songcount,
			\$params->{'start'},
			\$params->{'playlist_header'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'},
			0
		);

	} else {

		($start, $end) = Slim::Web::Pages->pageBar(
			$songcount,
			$params->{'path'},
			Slim::Player::Source::playingSongIndex($client),
			"player=" . Slim::Utils::Misc::escape($client->id()) . "&", 
			\$params->{'start'}, 
			\$params->{'playlist_header'},
			\$params->{'playlist_pagebar'},
			$params->{'skinOverride'},
			$params->{'itemsPerPage'}
		);
	}

	$listBuild{'start'} = $start;
	$listBuild{'end'}   = $end;

	$listBuild{'offset'} = $listBuild{'start'} % 2 ? 0 : 1; 

	$listBuild{'currsongind'}   = Slim::Player::Source::playingSongIndex($client);
	$listBuild{'item'}          = $listBuild{'start'};

	my $itemCount    = 0;
	my $itemsPerPass = Slim::Utils::Prefs::get('itemsPerPass');
	my $itemsPerPage = Slim::Utils::Prefs::get('itemsPerPage');
	my $composerIn   = Slim::Utils::Prefs::get('composerInArtists');
	my $starttime    = Time::HiRes::time();

	my $ds           = Slim::Music::Info::getCurrentDataStore();

	$params->{'playlist_items'} = [];
	$params->{'myClientState'}  = $client;

	my $needIdleStreams = Slim::Player::Client::needIdleStreams();

	# This is a hot loop.
	# But it's better done all at once than through the scheduler.
	while ($listBuild{'item'} < ($listBuild{'end'} + 1) && $itemCount < $itemsPerPage) {

		# These should all be objects - but be safe.
		my $objOrUrl = Slim::Player::Playlist::song($client, $listBuild{'item'});
		my $track    = $objOrUrl;

		if (!blessed($objOrUrl) || !$objOrUrl->can('id')) {

			$track = $ds->objectForUrl($objOrUrl) || do {
				msg("Couldn't retrieve objectForUrl: [$objOrUrl] - skipping!\n");
				$listBuild{'item'}++;
				$itemCount++;
				next;
			};
		}

		my %list_form = ();
		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
		my $levelInfo = $fieldInfo->{'track'};

		&{$levelInfo->{'listItem'}}($ds, \%list_form, $track);

		$list_form{'num'} = $listBuild{'item'};
		$list_form{'odd'} = ($listBuild{'item'} + $listBuild{'offset'}) % 2;

		if ($listBuild{'item'} == $listBuild{'currsongind'}) {
			$list_form{'currentsong'} = "current";
			$list_form{'title'}    = Slim::Music::Info::isRemoteURL($track) ? Slim::Music::Info::standardTitle(undef, $track) : Slim::Music::Info::getCurrentTitle(undef, $track);
		} else {
			$list_form{'currentsong'} = undef;
			$list_form{'title'}    = Slim::Music::Info::standardTitle(undef, $track);
		}

		$list_form{'nextsongind'} = $listBuild{'currsongind'} + (($listBuild{'item'} > $listBuild{'currsongind'}) ? 1 : 0);

		push @{$params->{'playlist_items'}}, \%list_form;

		$listBuild{'item'}++;
		$itemCount++;

		# don't neglect the streams for over 0.25 seconds
		if ($needIdleStreams && $itemCount > 1 && !($itemCount % $itemsPerPass) && (Time::HiRes::time() - $starttime) > 0.25) {

			main::idleStreams();
		}
	}

	$::d_playlist && msg("End playlist build. $itemCount items\n");

	undef %listBuild;

	# Give some player time after the loop, but before rendering.
	main::idleStreams();

	if ($client) {

		# Stick the rendered data into the client object as a stopgap
		# solution to the cpu spike issue.
		$client->currentPlaylistRender([
			time(),
			($params->{'skinOverride'} || ''),
			($params->{'start'}),
			$params->{'playlist_header'},
			$params->{'playlist_pagebar'},
			$params->{'playlist_items'}
		]);
	}

	return Slim::Web::HTTP::filltemplatefile("playlist.html", $params),
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
