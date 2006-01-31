package Slim::Buttons::TrackInfo;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# Displays the extra track information screen that is got into by pressing right on an item 
# in the now playing screen.

use strict;
use Scalar::Util qw(blessed);

use Slim::Buttons::Common;
use Slim::Buttons::Playlist;
use Slim::Player::TranscodingHelper;
use Slim::Utils::Misc;
use Slim::Utils::Favorites;

our %functions = ();

# button functions for track info screens
sub init {

	Slim::Buttons::Common::addMode('trackinfo', getFunctions(), \&setMode);

	%functions = (

		'play' => sub  {
			my $client = shift;

			my $curItem = $client->trackInfoContent->[currentLine($client)];

			unless ($curItem) {
				Slim::Buttons::Common::popModeRight($client);
				$client->execute(["button", "play", undef]);
				return;
			}

			my ($string, $line1);

			if (Slim::Player::Playlist::shuffle($client)) {
				$string = 'PLAYING_RANDOMLY_FROM';
			} else {
				$string = 'NOW_PLAYING_FROM';
			}
			
			my ($line2, $termlist) = _trackDataForCurrentItem($client, $curItem);

			if ($client->linesPerScreen == 1) {
				$line2 = $client->doubleString($string);
			} else {
				$line1 = $client->string($string);
			}
			
			$client->showBriefly( {
				'line1' => $line1,
				'line2' => $line2,
				'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute(['playlist', 'loadtracks', $termlist]);
			$client->execute(['playlist', 'jump', 0]);
		},
		
		'add' => sub  {
			my $client = shift;

			my $curItem = $client->trackInfoContent->[currentLine($client)];

			unless ($curItem) {
				Slim::Buttons::Common::popModeRight($client);
				$client->execute(["button", "add", undef]);
				return;
			}

			my ($line1, $string);

			$string = 'ADDING_TO_PLAYLIST';

			my ($line2, $termlist) = _trackDataForCurrentItem($client, $curItem);

			if ($client->linesPerScreen == 1) {
				$line2 = $client->doubleString($string);
			} else {
				$line1 = $client->string($string);
			}

			$client->showBriefly( {
				'line1' => $line1,
				'line2' => $line2,
				'overlay2' => $client->symbols('notesymbol'),
			});

			$client->execute(["playlist", "addtracks", $termlist]);
		},
		
		'up' => sub  {
			my $client = shift;

			my $newpos = Slim::Buttons::Common::scroll($client, -1, $#{$client->trackInfoLines} + 1, currentLine($client));
			if ($newpos != 	currentLine($client)) {
				currentLine($client, $newpos);
				$client->pushUp;
			}
		},

		'down' => sub  {
			my $client = shift;
			my $newpos = Slim::Buttons::Common::scroll($client, +1, $#{$client->trackInfoLines} + 1, currentLine($client));
			if ($newpos != 	currentLine($client)) {
				currentLine($client, $newpos);
				$client->pushDown;
			}
		},

		'left' => sub  {
			my $client = shift;
			Slim::Buttons::Common::popModeRight($client);
		},

		'right' => sub  {
			my $client = shift;

			my $push     = 1;
			# Look up if this is an artist, album, year etc
			my $curitem  = $client->trackInfoContent->[currentLine($client)];
			my @oldlines = Slim::Display::Display::curLines($client);

			if (!defined($curitem)) {
				$curitem = "";
			}

			# Get object for currently being browsed song from the datasource
			# This probably isn't necessary as track($client) is already an object!
			my $ds      = Slim::Music::Info::getCurrentDataStore();
			my $track   = $ds->objectForUrl(track($client));

			if (!blessed($track) || !$track->can('album') || !$track->can('artist')) {

				errorMsg("Unable to fetch valid track object for currently selected item!\n");
				return 0;
			}

			my $album  = $track->album;
			my $artist = $track->artist;

			# Bug: 2528
			#
			# Only check to see if album & artist are valid
			# objects if we're going to be performing a method
			# call on them. Otherwise it's ok to not have them for
			# Internet Radio streams which can be saved to favorites.
			if ($curitem =~ /^(?:ALBUM|ARTIST|COMPOSER|CONDUCTOR|BAND|YEAR|GENRE)$/) {

				if (!blessed($album) || !blessed($artist) || !$album->can('id') || !$artist->can('id')) {

					errorMsg("Unable to fetch valid album or artist object for currently selected track!\n");
					return 0;
				}
			}

			if ($curitem eq 'ALBUM') {

				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'    => 'track',
					'level'        => 0,
					'findCriteria' => { 'album' => $album->id },
					'selectionCriteria' => {
						'track'  => $track->id,
						'album'  => $album->id,
						'artist' => $artist->id,
					},
				});

			} elsif ($curitem =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {

				my $lcItem = lc($curitem);

				my ($contributor) = $track->$lcItem();

				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'    => 'album,track',
					'level'        => 0,
					'findCriteria' => { 'artist' => $contributor->id },
					'selectionCriteria' => {
						'track'  => $track->id,
						'album'  => $album->id,
						'artist' => $artist->id,
					},
				});

			} elsif ($curitem eq 'GENRE') {

				my $genre = $track->genre;
				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'  => 'artist,album,track',
					'level'      => 0,
					'findCriteria' => { 'genre' => $genre->id,},
					'selectionCriteria' => {
						'track'  => $track->id,
						'album'  => $album->id,
						'artist' => $artist->id,
					},
				});

			} elsif ($curitem eq 'YEAR') {

				my $year = $track->year;

				Slim::Buttons::Common::pushMode($client, 'browsedb', {
					'hierarchy'  => 'album,track',
					'level'      => 0,
					'findCriteria' => { 'year' => $year,},
					'selectionCriteria' => {
						'track'  => $track->id,
						'album'  => $album->id,
						'artist' => $artist->id,
					},
				});

			} elsif ($curitem eq 'FAVORITE') {

				my $num = $client->param('favorite');

				if ($num < 0) {

					my $num = Slim::Utils::Favorites->clientAdd($client, track($client), $track->title);

					$client->showBriefly($client->string('FAVORITES_ADDING'), $track->title);

					$client->param('favorite', $num);

				} else {

					Slim::Utils::Favorites->deleteByClientAndURL($client, track($client));

					$client->showBriefly($client->string('FAVORITES_DELETING'), $track->title);

					$client->param('favorite', -1);
				}

				$push = 0;

			} else {

				$push = 0;
				$client->bumpRight;
			}

			if ($push) {
				$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
			}
		},

		'numberScroll' => sub  {
			my ($client, $button, $digit) = @_;

			currentLine($client, Slim::Buttons::Common::numberScroll($client, $digit, $client->trackInfoLines, 0));
			$client->update;
		}
	);
}

sub _trackDataForCurrentItem {
	my $client = shift;
	my $item   = shift || return;

	# Pull directly from the datasource
	my $ds      = Slim::Music::Info::getCurrentDataStore();
	my $track   = $ds->objectForUrl(track($client));

	if (!blessed($track) || !$track->can('genre')) {

		errorMsg("_trackDataForCurrentItem: Unable to get objectForUrl!\n");
		return 0;
	}

	# genre is used by everything		
	my $genre   = $track->genre;
		
	my @search  = ();
	my $line2;
	
	if ($item eq 'GENRE') {

		$line2 = $genre;

		push @search, "genre=".$genre->id;

	# TODO make this work for other contributors
	#} elsif ($item =~ /^(?:ARTIST|COMPOSER|CONDUCTOR|BAND)$/) {
	} elsif ($item eq 'ARTIST') {

		my $lcItem = lc($item);

		$line2 = $track->artist;

		push @search, "artist=".$track->artist->id;

	} elsif ($item eq 'ALBUM') {

		$line2 = $track->album->title;

		push @search, "album=".$track->album->id;

	} elsif ($item eq 'YEAR') {

		$line2 = $track->year;

		push @search, "year=".$track->year;
	}

	return ($line2, join('&', @search));
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $item = shift;
	$client->lines(\&lines);
	preloadLines($client, track($client));
}

# get (and optionally set) the track URL
sub track {
	my $client = shift;
	return $client->param( 'track', shift);
}

# get (and optionally set) the track info scroll position
sub currentLine {
	my $client = shift;

	my $line = $client->param( 'line', shift) || 0;

	return $line
}

sub preloadLines {
	my $client = shift;
	my $url    = shift;

	@{$client->trackInfoLines}   = ();
	@{$client->trackInfoContent} = ();

	my $ds    = Slim::Music::Info::getCurrentDataStore();
	my $track = $ds->objectForUrl($url);

	# Couldn't get a track or URL? How do people get in this state?
	if (!$url || !blessed($track) || !$track->can('title')) {
		push (@{$client->trackInfoLines}, "Error! url: [$url] is empty or a track could not be retrieved.\n");
		push (@{$client->trackInfoContent}, undef);

		return;
	}

	if (my $title = $track->title) {
		push (@{$client->trackInfoLines}, $client->string('TITLE') . ": $title");
		push (@{$client->trackInfoContent}, undef);
	}

	# Loop through the contributor types and append
	for my $role (sort $track->contributorRoles) {

		for my $contributor ($track->contributorsOfType($role)) {

			push (@{$client->trackInfoLines}, sprintf('%s: %s', $client->string(uc($role)), $contributor->name));
			push (@{$client->trackInfoContent}, uc($role));
		}
	}

	my $album = $track->album;

	if ($album) {
		push (@{$client->trackInfoLines}, $client->string('ALBUM') . ": $album");
		push (@{$client->trackInfoContent}, 'ALBUM');
	}

	if (my $tracknum = $track->tracknum) {
		push (@{$client->trackInfoLines}, $client->string('TRACK') . ": $tracknum");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $year = $track->year) {
		push (@{$client->trackInfoLines}, $client->string('YEAR') . ": $year");
		push (@{$client->trackInfoContent}, 'YEAR');
	}

	if (my $genre = $track->genre) {
		push (@{$client->trackInfoLines}, $client->string('GENRE') . ": $genre");
		push (@{$client->trackInfoContent}, 'GENRE');
	}

	if (my $ct = $ds->contentType($track)) {
		push (@{$client->trackInfoLines}, $client->string('TYPE') . ": " . $client->string(uc($ct)));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $comment = $track->comment) {
		push (@{$client->trackInfoLines}, $client->string('COMMENT') . ": $comment");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $duration = $track->duration) {
		push (@{$client->trackInfoLines}, $client->string('LENGTH') . ": $duration");
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $replaygain = $track->replay_gain) {
		push (@{$client->trackInfoLines}, $client->string('REPLAYGAIN') . ": " . sprintf("%2.2f",$replaygain) . " dB");
		push (@{$client->trackInfoContent}, undef);
	}
	
	if (blessed($album) && $album->can('replay_gain')) {
		if (my $albumreplaygain = $album->replay_gain) {
			push (@{$client->trackInfoLines}, $client->string('ALBUMREPLAYGAIN') . ": " . sprintf("%2.2f",$albumreplaygain) . " dB");
			push (@{$client->trackInfoContent}, undef);
		}
	}

	if (my $bitrate = $track->bitrate) {

		my $undermax = Slim::Player::TranscodingHelper::underMax($client, $url);

		my $rate = (defined $undermax && $undermax) ? $bitrate : Slim::Utils::Prefs::maxRate($client).$client->string('KBPS')." ABR";

		push (@{$client->trackInfoLines}, 
			$client->string('BITRATE').": $bitrate " .
				(($client->param( 'current') && (defined $undermax && !$undermax)) 
					? '('.$client->string('CONVERTED_TO').' '.$rate.')' : ''));

		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->samplerate) {
		push (@{$client->trackInfoLines}, $client->string('SAMPLERATE') . ": " . $track->prettySampleRate);
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $len = $track->filesize) {
		push (@{$client->trackInfoLines}, $client->string('FILELENGTH') . ": " . Slim::Utils::Misc::delimitThousands($len));
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $age = $track->modificationTime) {
		push (@{$client->trackInfoLines}, $client->string('MODTIME').": $age");
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($url)) {
		push (@{$client->trackInfoLines}, "URL: ". $url);
		push (@{$client->trackInfoContent}, undef);
	}

	if (my $tag = $track->tagversion) {
		push (@{$client->trackInfoLines}, $client->string('TAGVERSION') . ": $tag");
		push (@{$client->trackInfoContent}, undef);
	}

	if ($track->drm) {
		push (@{$client->trackInfoLines}, $client->string('DRM'));
		push (@{$client->trackInfoContent}, undef);
	}

	if (Slim::Music::Info::isURL($url)) {
		my $fav = Slim::Utils::Favorites->findByClientAndURL($client, $url);
		if ($fav) {
			$client->param('favorite', $fav->{'num'});
		} else {
			$client->param('favorite', -1);
		}
		push (@{$client->trackInfoLines}, 'FAVORITE'); # replaced in lines()
		push (@{$client->trackInfoContent}, 'FAVORITE');
	}
}

#
# figure out the lines to be put up to display the directory
#
sub lines {
	my $client = shift;

	# Show the title of the song
	my $line1 = Slim::Music::Info::getCurrentTitle($client, track($client));

	# add position string
	my $overlay1 = ' (' . (currentLine($client)+1)
				. ' ' . $client->string('OF') .' ' . scalar(@{$client->trackInfoLines}) . ')';
	# add note symbol
	$overlay1 .= Slim::Display::Display::symbol('notesymbol');
	
	# 2nd line's content is provided entirely by trackInfoLines, which returns an array of information lines
	my $line2 = $client->trackInfoLines->[currentLine($client)];
	
	# add right arrow symbol if current line can point to more info e.g. artist, album, year etc
	my $overlay2 = defined($client->trackInfoContent->[currentLine($client)]) ? Slim::Display::Display::symbol('rightarrow') : undef;

	# special case favorites line, which must be determined dynamically
	if ($line2 eq 'FAVORITE') {
		if ((my $num = $client->param('favorite')) < 0) {
			$line2 = $client->string('FAVORITES_RIGHT_TO_ADD');
		} else {
			$line2 = $client->string('FAVORITES_FAVORITE_NUM') . "$num " . $client->string('FAVORITES_RIGHT_TO_DELETE');
		}
		$overlay2 = undef;
	}

	return ($line1, $line2, $overlay1, $overlay2);
}

1;

__END__
