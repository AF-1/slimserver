package Slim::Control::Command;

# $Id$
#
# SlimServer Copyright (C) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use File::Basename;
use File::Spec::Functions qw(:ALL);
use FileHandle;
use IO::Socket qw(:DEFAULT :crlf);
use Scalar::Util qw(blessed);
use Time::HiRes;

use Slim::DataStores::Base;
use Slim::Display::Display;
use Slim::Music::Info;
use Slim::Utils::Misc;
use Slim::Utils::Scan;
use Slim::Utils::Strings qw(string);

our %executeCallbacks = ();

our %searchMap = (

	'artist' => 'contributor.namesearch',
	'genre'  => 'genre.namesearch',
	'album'  => 'album.titlesearch',
	'track'  => 'track.titlesearch',
);

#############################################################################
# execute - does all the hard work.  Use it.
# takes:
#   a client reference
#   a reference to an array of parameters
#   a reference to a callback function
#   a list of callback function args
#
# returns an array containing the given parameters

sub execute {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

	my $p0 = $parrayref->[0];
	my $p1 = $parrayref->[1];
	my $p2 = $parrayref->[2];
	my $p3 = $parrayref->[3];
	my $p4 = $parrayref->[4];
	my $p5 = $parrayref->[5];
	my $p6 = $parrayref->[6];
	my $p7 = $parrayref->[7];

	my $callcallback = 1;
	my @returnArray = ();
	my $pushParams = 1;

	$::d_command && msg(" Executing command " . ($client ? $client->id() : "no client") . ": $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ") (" .
			(defined $p7 ? $p7 : "") . ")\n");

# The first parameter is the client identifier to execute the command. Column C in the
# table below indicates if a client is required (Y) or not (N) for the command.
#
# If a parameter is "?" it is replaced by the current value in the array
# returned by the function
#
# COMMAND LIST #
  
# C     P0             P1                          P2                            P3            P4         P5        P6
    
# GENERAL
# N    debug           <debugflag>                 <0|1|?|>
# N    pref            <prefname>                  <prefvalue|?>

# PLAYERS
# Y    sleep           <0..n|?>
# Y    sync            <playerindex|playerid|-|?>
# Y    power           <0|1|?|>
# Y    signalstrength  ?
# Y    connected       ?
# Y    mixer           volume                      <0..100|-100..+100|?>
# Y    mixer           balance                     (not implemented)
# Y    mixer           bass                        <0..100|-100..+100|?>
# Y    mixer           treble                      <0..100|-100..+100|?>
# Y    mixer           pitch                       <80..120|-100..+100|?>
# Y    mixer           muting
# Y    display         <line1>                     <line2>                       <duration>
# Y    display         ?                           ?
# Y    displaynow      ?                           ?
# Y    playerpref      <prefname>                  <prefvalue|?>
# Y    button          <buttoncode>
# Y    ir              <ircode>                    <time>
# Y    rate            <rate|?>

#DATABASE    
# N    rescan          <?>    	
# N    rescan          playlists
# N    wipecache

#PLAYLISTS
# Y    mode            <play|pause|stop|?>    
# Y    play        
# Y    pause           <0|1|>    
# Y    stop
# Y    time|gototime   <0..n|-n|+n|?>
# Y    genre           ?
# Y    artist          ?
# Y    album           ?
# Y    title           ?
# Y    duration        ?
# Y    path|url        ?
 
# Y    playlist        playtracks                  <searchterms>    
# Y    playlist        loadtracks                  <searchterms>    
# Y    playlist        addtracks                   <searchterms>    
# Y    playlist        inserttracks                <searchterms>    
# Y    playlist        deletetracks                <searchterms>   
# Y    playlistcontrol <params>

# Y    playlist        play|load                   <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        add|append                  <item>                       [<title>] (item can be a song, playlist or directory)
# Y    playlist        insert|insertlist           <item> (item can be a song, playlist or directory)
# Y    playlist        deleteitem                  <item> (item can be a song, playlist or directory)
# Y    playlist        move                        <fromindex>                 <toindex>    
# Y    playlist        delete                      <index>
# Y    playlist        resume                      <playlist>    
# Y    playlist        save                        <playlist>    
# Y    playlist        loadalbum|playalbum         <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        addalbum                    <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        insertalbum                 <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        deletealbum                 <genre>                     <artist>         <album>        <songtitle>
# Y    playlist        clear    
# Y    playlist        zap                         <index>
# Y    playlist        name                        ?
# Y    playlist        url                         ?
# Y    playlist        modified                    ?
# Y    playlist        index|jump                  <index|?>    
# Y    playlist        genre                       <index>                     ?
# Y    playlist        artist                      <index>                     ?
# Y    playlist        album                       <index>                     ?
# Y    playlist        title                       <index>                     ?
# Y    playlist        duration                    <index>                     ?
# Y    playlist        tracks                      ?
# Y    playlist        shuffle                     <0|1|2|?|>
# Y    playlist        repeat                      <0|1|2|?|>

	my $ds   = Slim::Music::Info::getCurrentDataStore();
	my $find = {};

	if (!defined($p0)) {

		# ignore empty commands

	} elsif ($p0 eq "pref") {

		if (defined($p2) && $p2 ne '?' && !$::nosetup) {
			Slim::Utils::Prefs::set($p1, $p2);
		}

		$p2 = Slim::Utils::Prefs::get($p1);

		$client = undef;

	} elsif ($p0 eq "rescan") {
	
		if (defined $p1 && $p1 eq '?') {

			$p1 = Slim::Utils::Misc::stillScanning() ? 1 : 0;

		} elsif (!Slim::Utils::Misc::stillScanning()) {

			if (defined $p1 && $p1 eq 'playlists') {

				Slim::Music::Import::scanPlaylistsOnly(1);

			} else {

				Slim::Music::Import::cleanupDatabase(1);
			}

			Slim::Music::Info::clearPlaylists();
			Slim::Music::Import::resetImporters();
			Slim::Music::Import::startScan();
		}

		$client = undef;

	} elsif ($p0 eq "wipecache") {

		if (!Slim::Utils::Misc::stillScanning()) {

			# Clear all the active clients's playlists
			for my $client (Slim::Player::Client::clients()) {

				$client->execute([qw(playlist clear)]);
			}

			Slim::Music::Info::clearPlaylists();
			Slim::Music::Info::wipeDBCache();
			Slim::Music::Import::resetImporters();
			Slim::Music::Import::startScan();
		}
		
		$client = undef;

	} elsif ($p0 eq "debug") {

		if ($p1 =~ /^d_/) {

			my $debugsymbol = "::" . $p1;
			no strict 'refs';

			if (!defined($p2)) {

				$$debugsymbol = ($$debugsymbol ? 0 : 1);

			} elsif ($p2 eq "?")  {

				$p2 = $$debugsymbol;
				$p2 ||= 0;

			} else {

				$$debugsymbol = $p2;
			}
		}

 		$client = undef;
 		
 		
################################################################################
# The following commands require a valid client to be specified
################################################################################

	} elsif ($client) {

		if ($p0 eq "playerpref") {

			if (defined($p2) && $p2 ne '?' && !$::nosetup) {
				$client->prefSet($p1, $p2);
			}

			$p2 = $client->prefGet($p1);

		} elsif ($p0 eq "play") {

			Slim::Player::Source::playmode($client, "play");
			Slim::Player::Source::rate($client,1);
			$client->update();

		} elsif ($p0 eq "pause") {

			if (defined($p1)) {
				if ($p1 && Slim::Player::Source::playmode($client) eq "play") {
					$client->rate(1);
					Slim::Player::Source::playmode($client, "pause");
				} elsif (!$p1 && Slim::Player::Source::playmode($client) eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				} elsif (!$p1 && Slim::Player::Source::playmode($client) eq "stop") {
					Slim::Player::Source::playmode($client, "play");
				}
			} else {
				if (Slim::Player::Source::playmode($client) eq "pause") {
					Slim::Player::Source::playmode($client, "resume");
				} elsif (Slim::Player::Source::playmode($client) eq "play") {
					$client->rate(1);
					Slim::Player::Source::playmode($client, "pause");
				} elsif (Slim::Player::Source::playmode($client) eq "stop") {
					Slim::Player::Source::playmode($client, "play");
				}
			}
			$client->update();

		} elsif ($p0 eq "rate") {

			if ($client->directURL() || $client->audioFilehandleIsSocket) {
				Slim::Player::Source::rate($client, 1);
			} elsif (!defined($p1) || $p1 eq "?") {
				$p1 = Slim::Player::Source::rate($client);
			} else {
				Slim::Player::Source::rate($client,$p1);
			}

		} elsif ($p0 eq "stop") {

			Slim::Player::Source::playmode($client, "stop");
			# Next time we start, start at normal playback rate
			$client->rate(1);
			$client->update();

		} elsif ($p0 eq "mode") {

			if (!defined($p1) || $p1 eq "?") {
				$p1 = Slim::Player::Source::playmode($client);
			} else {
				if (Slim::Player::Source::playmode($client) eq "pause" && $p1 eq "play") {
					Slim::Player::Source::playmode($client, "resume");
				} else {
					Slim::Player::Source::playmode($client, $p1);
				}
				$client->update();
			}

		} elsif ($p0 eq "sleep") {
			if ($p1 eq "?") {
				$p1 = $client->sleepTime() - Time::HiRes::time();
				if ($p1 < 0) {
					$p1 = 0;
				}
			} else {
				Slim::Utils::Timers::killTimers($client, \&sleepStartFade);
				Slim::Utils::Timers::killTimers($client, \&sleepPowerOff);
				
				if ($p1 != 0) {
					my $fadeTime = 0;
					$fadeTime = $p1 - 40 if ($p1>40);
					my $offTime = $p1;
				
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $offTime, \&sleepPowerOff);
					Slim::Utils::Timers::setTimer($client, Time::HiRes::time() + $fadeTime, \&sleepStartFade);


					$client->sleepTime(Time::HiRes::time() + $offTime);
					$client->currentSleepTime($offTime / 60);
				} else {
					$client->sleepTime(0);
					$client->currentSleepTime(0);
				}
			}

		} elsif ($p0 eq "gototime" || $p0 eq "time") {
			if ($p1 eq "?") {
				$p1 = Slim::Player::Source::songTime($client);
			} else {
				Slim::Player::Source::gototime($client, $p1);
			}

		} elsif ($p0 =~ /^(duration|artist|album|title|genre)$/) {

			my $method = $1;
			my $url    = Slim::Player::Playlist::song($client);
			my $track  = $ds->objectForUrl(Slim::Player::Playlist::song($client));

			if (blessed($track) && $track->can('secs')) {

				if ($p0 eq 'duration') {
				
					$p1 = $track->secs() || 0;
					
				} else {

					$p1 = $track->$method() || 0;
				}

			} else {

				msg("Couldn't fetch object for URL: [$url] - skipping track\n");
				bt();
			}

		} elsif ($p0 eq "path") {

			$p1 = Slim::Player::Playlist::song($client) || 0;

		} elsif ($p0 eq "connected") {

			$p1 = $client->connected() || 0;

		} elsif ($p0 eq "signalstrength") {

			$p1 = $client->signalStrength() || 0;

		} elsif ($p0 eq "power") {

			if (!defined $p1) {
				
				my $newPower = $client->power() ? 0 : 1;

				if (Slim::Player::Sync::isSynced($client)) {

					syncFunction($client, $newPower, "power", undef);
				}

				$client->power($newPower);

				# send xpl message when power toggles
				if (Slim::Utils::Prefs::get('xplsupport')) {
					Slim::Control::xPL::sendXplHBeatMsg($client,1);
                }

			} elsif ($p1 eq "?") {

				$p1 = $client->power();

			} else {

				if (Slim::Player::Sync::isSynced($client)) {

					syncFunction($client, $p1, "power", undef);
				}

				$client->power($p1);

				# send xpl message when power toggles
				if (Slim::Utils::Prefs::get('xplsupport')) {
					Slim::Control::xPL::sendXplHBeatMsg($client,1);
				}
				
				if ($p1 eq "0") {
					# Powering off cancels sleep...
					Slim::Utils::Timers::killTimers($client, \&sleepStartFade);
					Slim::Utils::Timers::killTimers($client, \&sleepPowerOff);
					$client->sleepTime(0);
					$client->currentSleepTime(0);
				}
			}

		} elsif ($p0 eq "sync") {

			if (!defined $p1) {

			} elsif ($p1 eq "?") {

				$p1 = Slim::Player::Sync::syncIDs($client)

			} elsif ($p1 eq "-") {

				Slim::Player::Sync::unsync($client);

			} else {

				my $buddy;

				if (Slim::Player::Client::getClient($p1)) {

					$buddy = Slim::Player::Client::getClient($p1);

				} else {

					my @clients = Slim::Player::Client::clients();
					if (defined $clients[$p1]) {
						$buddy = $clients[$p1];
					}
				}
				Slim::Player::Sync::sync($buddy, $client) if defined $buddy;
			}

		} elsif ($p0 eq "playlistcontrol") {
		
 			$pushParams = 0;
 	
 			my $ds     = Slim::Music::Info::getCurrentDataStore();
 			my %params = parseParams($parrayref, \@returnArray);
 			my @songs;
 			my $size = 0;
 			
 			if (Slim::Utils::Misc::stillScanning()) {
 				push @returnArray, "rescan:1";
 			}

			if (defined $params{'cmd'}) {

				my $load = ($params{'cmd'} eq 'load');
				my $insert = ($params{'cmd'} eq 'insert');
				my $add = ($params{'cmd'} eq 'add');
				my $delete = ($params{'cmd'} eq 'delete');
	
				Slim::Player::Source::playmode($client, "stop") if $load;
				Slim::Player::Playlist::clear($client) if $load;
				
				if (defined $params{'playlist_id'}){
					# Special case...

					my $obj = $ds->objectForId('track', $params{'playlist_id'});

					if (blessed($obj) && $obj->can('tracks')) {

						# We want to add the playlist name to the client object.
						$client->currentPlaylist($obj) if $load;

						@songs = $obj->tracks;
					}
				}
				else {
					if (defined $params{'genre_id'}){
						$find->{'genre'} = $params{'genre_id'};
					}
					if (defined $params{'artist_id'}){
						$find->{'artist'} = $params{'artist_id'};
					}
					if (defined $params{'album_id'}){
						$find->{'album'} = $params{'album_id'};
					}
					if (defined $params{'track_id'}){
						$find->{'id'} = $params{'track_id'};
					}
					if (defined $params{'year_id'}){
						$find->{'year'} = $params{'year_id'};
					}
						
					my $sort = exists $find->{'album'} ? 'tracknum' : 'track';

					if ($load || $add || $insert || $delete){

						@songs = @{ $ds->find({
							'field'   => 'lightweighttrack',
							'find'    => $find,
							'sortyBy' => $sort,
						}) };
					}
				}
				
				$size  = scalar(@songs);
				my $playListSize = Slim::Player::Playlist::count($client);
				
				push(@{Slim::Player::Playlist::playList($client)}, @songs) if ($load || $add || $insert);
				Slim::Player::Playlist::removeMultipleTracks($client, \@songs) if $delete;
				
				insert_done($client, $playListSize, $size) if $insert;
				
				Slim::Player::Playlist::reshuffle($client,$load?1:0) if ($load || $add);
				Slim::Player::Source::jumpto($client, 0) if $load;
	
				$client->currentPlaylistModified(1) if ($add || $insert || $delete);
				$client->currentPlaylistChangeTime(time()) if ($load || $add || $insert || $delete);
				#$client->currentPlaylist(undef) if $load;
			}			

	 		push @returnArray, "count:$size";

		} elsif ($p0 eq "playlist") {

			my $results;

			# This should be undef - see bug 2085
			my $jumpToIndex;

			# Query for the passed params
			if ($p1 =~ /^(play|load|add|insert|delete)album$/) {

				my $sort = 'track';
				# XXX - FIXME - searching for genre.name with
				# anything else kills the database. As a
				# stop-gap, don't add the search for
				# genre.name if we have a more specific query.
				if (specified($p2) && !specified($p3)) {
					$find->{'genre.name'} = singletonRef($p2);
				}

				if (specified($p3)) {
					$find->{'contributor.name'} = singletonRef($p3);
				}

				if (specified($p4)) {
					$find->{'album.title'} = singletonRef($p4);
					$sort = 'tracknum';
				}

				if (specified($p5)) {
					$find->{'track.title'} = singletonRef($p5);
				}

				$results = $ds->find({
					'field'  => 'lightweighttrack',
					'find'   => $find,
					'sortBy' => $sort,
				});
			}

			# here are all the commands that add/insert/replace songs/directories/playlists on the current playlist
			if ($p1 =~ /^(play|load|append|add|resume|insert|insertlist)$/) {
			
				my $path = $p2;

				if ($path) {

					if (!-e $path && !(Slim::Music::Info::isPlaylistURL($path))) {

						my $easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename ($p2) . ".m3u");

						if (-e $easypath) {

							$path = $easypath;

						} else {

							$easypath = catfile(Slim::Utils::Prefs::get('playlistdir'), basename ($p2) . ".pls");

							if (-e $easypath) {
								$path = $easypath;
							}
						}
					}
					
					if ($p1 =~ /^(play|load|resume)$/) {

						Slim::Player::Source::playmode($client, "stop");
						Slim::Player::Playlist::clear($client);

						my $fixpath = Slim::Utils::Misc::fixPath($path);

						$client->currentPlaylist($fixpath);

						Slim::Music::Info::setTitle($fixpath, $p3) if defined $p3;

						$client->currentPlaylistModified(0);

					} elsif ($p1 =~ /^(add|append)$/) {

						my $fixpath = Slim::Utils::Misc::fixPath($path);

						Slim::Music::Info::setTitle($fixpath, $p3) if defined $p3;

						$client->currentPlaylistModified(1);

					} else {

						$client->currentPlaylistModified(1);
					}
					
					$path = Slim::Utils::Misc::virtualToAbsolute($path);
					
					if ($p1 =~ /^(play|load)$/) { 

						$jumpToIndex = 0;

					} elsif ($p1 eq "resume" && Slim::Music::Info::isM3U($path)) {

						$jumpToIndex = Slim::Formats::Parse::readCurTrackForM3U($path);
					}
					
					if ($p1 =~ /^(insert|insertlist)$/) {

						my $playListSize = Slim::Player::Playlist::count($client);
						my @dirItems     = ();

						Slim::Utils::Scan::addToList({
							'listRef'      => \@dirItems,
							'url'          => $path,
						});

						Slim::Utils::Scan::addToList({
							'listRef'      => Slim::Player::Playlist::playList($client),
							'url'          => $path,
							'recursive'    => 1,
							'callback'     => \&insert_done,
							'callbackArgs' => [
								$client,
								$playListSize,
								scalar(@dirItems),
								$callbackf,
								$callbackargs,
							],
						});

					} else {

						Slim::Utils::Scan::addToList({
							'listRef'      => Slim::Player::Playlist::playList($client),
							'url'          => $path,
							'recursive'    => 1,
							'callback'     => \&load_done,
							'callbackArgs' => [
								$client,
								$jumpToIndex,
								$callbackf,
								$callbackargs,
							],
						});
					}
					
					$callcallback = 0;
					$p2 = $path;
				}

				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "loadalbum" || $p1 eq "playalbum") {

				Slim::Player::Source::playmode($client, "stop");
				Slim::Player::Playlist::clear($client);

				push(@{Slim::Player::Playlist::playList($client)}, @$results);

				Slim::Player::Playlist::reshuffle($client, 1);
				Slim::Player::Source::jumpto($client, 0);
				$client->currentPlaylist(undef);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "addalbum") {

				push(@{Slim::Player::Playlist::playList($client)}, @$results);

				Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "insertalbum") {

				my $playListSize = Slim::Player::Playlist::count($client);
				my $size = scalar(@$results);

				push(@{Slim::Player::Playlist::playList($client)}, @$results);
					
				insert_done($client, $playListSize, $size);
				#Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "loadtracks" || $p1 eq "playtracks") {
				Slim::Player::Source::playmode($client, "stop");
				Slim::Player::Playlist::clear($client);

				if ($p2 =~ /listref/i) {
					push(@{Slim::Player::Playlist::playList($client)}, parseListRef($client,$p2,$p3));
				} else {
					push(@{Slim::Player::Playlist::playList($client)}, parseSearchTerms($client, $p2));
				}

				Slim::Player::Playlist::reshuffle($client, 1);

				# The user may have stopped in the middle of a
				# saved playlist - resume if we can. Bug 1582
				my $playlistObj = $client->currentPlaylist;

				if ($playlistObj && ref($playlistObj) && $playlistObj->content_type =~ /^(?:ssp|m3u)$/) {

					$jumpToIndex = Slim::Formats::Parse::readCurTrackForM3U( $client->currentPlaylist->path );

					# And set a callback so that we can
					# update CURTRACK when the song changes.
					setExecuteCallback(\&Slim::Player::Playlist::newSongPlaylistCallback);
				}

				Slim::Player::Source::jumpto($client, $jumpToIndex);

				$client->currentPlaylistModified(0);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "addtracks") {

				if ($p2 =~ /listref/i) {
					push(@{Slim::Player::Playlist::playList($client)}, parseListRef($client,$p2,$p3));
				} else {
					push(@{Slim::Player::Playlist::playList($client)}, parseSearchTerms($client, $p2));
				}

				Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "inserttracks") {
					
				my @songs = $p2 =~ /listref/i ? parseListRef($client,$p2,$p3) : parseSearchTerms($client, $p2);
				my $size  = scalar(@songs);

				my $playListSize = Slim::Player::Playlist::count($client);
					
				push(@{Slim::Player::Playlist::playList($client)}, @songs);

				insert_done($client, $playListSize, $size);
				#Slim::Player::Playlist::reshuffle($client);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "deletetracks") {

				my @listToRemove = $p2 =~ /listref/i ? parseListRef($client,$p2,$p3) : parseSearchTerms($client, $p2);
 
				Slim::Player::Playlist::removeMultipleTracks($client, \@listToRemove);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());

			} elsif ($p1 eq "save") {

				my $title = $p2;

				my $playlistObj = $ds->updateOrCreate({
					'url'        => Slim::Utils::Misc::fileURLFromPath(
						catfile(Slim::Utils::Prefs::get('playlistdir'), $title . '.m3u')
					),
					'attributes' => {
						'TITLE' => $title,
						'CT'    => 'ssp',
					},
				});

				my $annotatedList;

				if (Slim::Utils::Prefs::get('saveShuffled')) {
				
					for my $shuffleitem (@{Slim::Player::Playlist::shuffleList($client)}) {
						push (@$annotatedList, @{Slim::Player::Playlist::playList($client)}[$shuffleitem]);
					}
				
				} else {

					$annotatedList = Slim::Player::Playlist::playList($client);
				}

				$playlistObj->setTracks($annotatedList);
				$playlistObj->update();

				Slim::Player::Playlist::scheduleWriteOfPlaylist($client, $playlistObj);

				# Pass this back to the caller.
				$p0 = $playlistObj;

			} elsif ($p1 eq "deletealbum") {

				Slim::Player::Playlist::removeMultipleTracks($client, $results);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "deleteitem") {
 
				if (defined($p2) && $p2 ne '') {

					$p2 = Slim::Utils::Misc::virtualToAbsolute($p2);

					my $contents;

					if (!Slim::Music::Info::isList($p2)) {

						Slim::Player::Playlist::removeMultipleTracks($client,[$p2]);

					} elsif (Slim::Music::Info::isDir($p2)) {

						Slim::Utils::Scan::addToList({
							'listRef' => \@{$contents},
							'url' => $p2,
							'recursive'    => 1
						});

						Slim::Player::Playlist::removeMultipleTracks($client,\@{$contents});

					} else {

						$contents = Slim::Music::Info::cachedPlaylist($p2);

						if (!defined $contents) {

							my $playlist_filehandle;

							if (!open($playlist_filehandle, Slim::Utils::Misc::pathFromFileURL($p2))) {

								errorMsg("Couldn't open playlist file $p2 : $!\n");

								$playlist_filehandle = undef;

							} else {

								$contents = [Slim::Formats::Parse::parseList($p2,$playlist_filehandle,dirname($p2))];
							}
						}
			 
						if (defined($contents)) {
							Slim::Player::Playlist::removeMultipleTracks($client,$contents);
						}
					}

					$client->currentPlaylistModified(1);
					$client->currentPlaylistChangeTime(time());
				}
			
			} elsif ($p1 eq "repeat") {

				# change between repeat values 0 (don't repeat), 1 (repeat the current song), 2 (repeat all)
				if (!defined($p2)) {

					Slim::Player::Playlist::repeat($client, (Slim::Player::Playlist::repeat($client) + 1) % 3);

				} elsif ($p2 eq "?") {

					$p2 = Slim::Player::Playlist::repeat($client);

				} else {

					Slim::Player::Playlist::repeat($client, $p2);
				}
			
			} elsif ($p1 eq "shuffle") {

				if (!defined($p2)) {

					my $nextmode = (1,2,0)[Slim::Player::Playlist::shuffle($client)];
					Slim::Player::Playlist::shuffle($client, $nextmode);
					Slim::Player::Playlist::reshuffle($client);

				} elsif ($p2 eq "?") {

					$p2 = Slim::Player::Playlist::shuffle($client);

				} else {

					Slim::Player::Playlist::shuffle($client, $p2);
					Slim::Player::Playlist::reshuffle($client);
				}

				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "clear") {

				Slim::Player::Playlist::clear($client);
				Slim::Player::Source::playmode($client, "stop");
				$client->currentPlaylist(undef);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "move") {

				Slim::Player::Playlist::moveSong($client, $p2, $p3);
				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif ($p1 eq "delete") {

				if (defined($p2)) {
					Slim::Player::Playlist::removeTrack($client,$p2);
				}

				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			
			} elsif (($p1 eq "jump") || ($p1 eq "index")) {

				if ($p2 eq "?") {
					$p2 = Slim::Player::Source::playingSongIndex($client);
				} else {
					Slim::Player::Source::jumpto($client, $p2, $p3);
				}

			} elsif ($p1 eq "name") {

				$p2 = Slim::Music::Info::standardTitle($client,$client->currentPlaylist());

			} elsif ($p1 eq "url") {

				$p2 = $client->currentPlaylist();

			} elsif ($p1 eq "tracks") {

				$p2 = Slim::Player::Playlist::count($client);

			} elsif ($p1 =~ /(?:duration|artist|album|title|genre)/) {

				my $url = Slim::Player::Playlist::song($client, $p2);
				my $obj = $ds->objectForUrl($url, 1, 1);

				if (blessed($obj) && $obj->can('secs')) {

					# Just call the method on Track
					if ($p1 eq 'duration') {
						$p3 = $obj->secs();
					}
					else {
						$p3 = $obj->$p1();
					}
				}

			} elsif ($p1 eq "path") {

				$p3 = Slim::Player::Playlist::song($client,$p2) || 0;
			
			} elsif ($p1 eq "zap") {

				my $zapped   = string('ZAPPED_SONGS');
				my $zapsong  = Slim::Player::Playlist::song($client,$p2);
				my $zapindex = defined $p2 ? $p2 : Slim::Player::Source::playingSongIndex($client);
 
				#  Remove from current playlist
				if (Slim::Player::Playlist::count($client) > 0) {

					# Callo ourselves.
					execute($client, ["playlist", "delete", $zapindex]);
				}

				my $playlistObj = $ds->updateOrCreate({
					'url'        => "playlist://$zapped",
					'attributes' => {
						'TITLE' => $zapped,
						'CT'    => 'ssp',
					},
				});

				my @list = $playlistObj->tracks;
				push @list,$zapsong;

				$playlistObj->setTracks(\@list);
				$playlistObj->update();

				$client->currentPlaylistModified(1);
				$client->currentPlaylistChangeTime(time());
			}

			Slim::Player::Playlist::refreshPlaylist($client) if $client->currentPlaylistModified();

		} elsif ($p0 eq "mixer") {

			if ($p1 eq "volume") {
				my $newvol;
				my $oldvol = $client->volume();

				if ($p2 eq "?") {

					$p2 = $oldvol;

				} else {

					if ($oldvol < 0) {
						# volume was previously muted
						$oldvol *= -1;      # un-mute volume
					} 
					
					if ($p2 =~ /^[\+\-]/) {
						$newvol = $oldvol + $p2;
					} else {
						$newvol = $p2;
					}
					
					$newvol = $client->volume($newvol);
					
					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newvol, "volume",\&setVolume);
					}
				}

			} elsif ($p1 eq "muting") {
				my $vol = $client->volume();
				my $fade;
				
				if ($vol < 0) {
					# need to un-mute volume
					$::d_command && msg("Unmuting, volume is $vol.\n");
					$client->prefSet("mute", 0);
					$fade = 0.3125;
				} else {
					# need to mute volume
					$::d_command && msg("Muting, volume is $vol.\n");
					$client->prefSet("mute", 1);
					$fade = -0.3125;
				}
 
				$client->fade_volume($fade, \&mute, [$client]);
 
				if (Slim::Player::Sync::isSynced($client)) {
					syncFunction($client, $fade, "mute", undef);
				}

			} elsif ($p1 eq "balance") {

				# unsupported yet

			} elsif ($p1 eq "treble") {

				my $newtreb;
				my $oldtreb = $client->treble();
				if ($p2 eq "?") {
					$p2 = $oldtreb;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newtreb = $oldtreb + $p2;
					} else {
						$newtreb = $p2;
					}

					$newtreb = $client->treble($newtreb);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newtreb, "treble",\&setTreble);
					}
				}

			} elsif ($p1 eq "bass") {

				my $newbass;
				my $oldbass = $client->bass();

				if ($p2 eq "?") {
					$p2 = $oldbass;
				} else {
				
					if ($p2 =~ /^[\+\-]/) {
						$newbass = $oldbass + $p2;
					} else {
						$newbass = $p2;
					}

					$newbass = $client->bass($newbass);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newbass, "bass",\&setBass);
					}
				}

			} elsif ($p1 eq "pitch") {

				my $newpitch;
				my $oldpitch = $client->pitch();

				if ($p2 eq "?") {

					$p2 = $oldpitch;

				} else {

					if ($p2 =~ /^[\+\-]/) {
						$newpitch = $oldpitch + $p2;
					} else {
						$newpitch = $p2;
					}

					$newpitch = $client->pitch($newpitch);

					if (Slim::Player::Sync::isSynced($client)) {
						syncFunction($client, $newpitch, "pitch",\&setPitch);
					}
				}
			}

		} elsif ($p0 eq "displaynow") {

			if ($p1 eq "?" && $p2 eq "?") {
				$p1 = $client->prevline1();
				$p2 = $client->prevline2();
			} 

		} elsif ($p0 eq "linesperscreen") {

			$p1 = $client->linesPerScreen();

		} elsif ($p0 eq "display") {

			if ($p1 eq "?" && $p2 eq "?") {
				my $parsed = $client->parseLines(Slim::Display::Display::curLines($client));
				$p1 = $parsed->{line1} || '';
				$p2 = $parsed->{line2} || '';
			} else {
				Slim::Buttons::ScreenSaver::wakeup($client);
				$client->showBriefly($p1, $p2, $p3, $p4);
			}

		} elsif ($p0 eq "button") {

			# all buttons now go through execute()
			Slim::Hardware::IR::executeButton($client, $p1, $p2, undef, defined($p3) ? $p3 : 1);

		} elsif ($p0 eq "ir") {

			# all ir signals go through execute()
			Slim::Hardware::IR::processIR($client, $p1, $p2);
	
 		# Extended CLI API STATUS		
 		} elsif ($p0 eq "status") {

 			$pushParams = 0;
 
 			my $tags = "gald";
 			
 			my %params = parseParams($parrayref, \@returnArray);
 			
 			$tags = $params{'tags'} if defined($params{'tags'});
 			
 			my $connected = $client->connected() || 0;
 			my $power     = $client->power();
 			my $repeat    = Slim::Player::Playlist::repeat($client);
 			my $shuffle   = Slim::Player::Playlist::shuffle($client);
			my $songCount = Slim::Player::Playlist::count($client);
			my $idx = 0;
 		    	
 			if (Slim::Utils::Misc::stillScanning()) {
 				push @returnArray, "rescan:1";
 			}
 			
 			push @returnArray, "player_name:" . $client->name();
 			push @returnArray, "player_connected:" . $connected;
 			push @returnArray, "power:".$power;
 			
 			if ($client->model() eq "squeezebox" || $client->model() eq "squeezebox2") {
 				push @returnArray, "signalstrength:".($client->signalStrength() || 0);
 			}
 			
 			if ($power) {
 			
 				#push @returnArray, "player_mode:".Slim::Buttons::Common::mode($client);
 		    	push @returnArray, "mode:". Slim::Player::Source::playmode($client);

 				if (Slim::Player::Playlist::song($client)) { 
					my $track = $ds->objectForUrl(Slim::Player::Playlist::song($client));

 					my $dur   = 0;

 					if (blessed($track) && $track->can('secs')) {

						$dur = $track->secs;
					}

 					if ($dur) {
						push @returnArray, "rate:".Slim::Player::Source::rate($client); #(>1 ffwd, <0 rew else norm)
						push @returnArray, "time:".Slim::Player::Source::songTime($client);
						push @returnArray, "duration:".$dur;
 					}
 				}
 				
 				if ($client->currentSleepTime()) {

 					my $sleep = $client->sleepTime() - Time::HiRes::time();
					push @returnArray, "sleep:" . $client->currentSleepTime() * 60;
					push @returnArray, "will_sleep_in:" . ($sleep < 0 ? 0 : $sleep);
 				}
 				
 				if (Slim::Player::Sync::isSynced($client)) {

 					my $master = Slim::Player::Sync::masterOrSelf($client);

 					push @returnArray, "sync_master:" . $master->id();

 					my @slaves = Slim::Player::Sync::slaves($master);
 					my @sync_slaves = map { $_->id } @slaves;

 					push @returnArray, "sync_slaves:" . join(" ", @sync_slaves);
 				}
 			
				push @returnArray, "mixer volume:".$client->volume();
				push @returnArray, "mixer treble:".$client->treble();
				push @returnArray, "mixer bass:".$client->bass();

				if ($client->model() ne "slimp3") {
					push @returnArray, "mixer pitch:".$client->pitch();
				}

				#push @returnArray, "mixer balance:";
				push @returnArray, "playlist repeat:".$repeat; #(0 no, 1 title, 2 all)
				push @returnArray, "playlist shuffle:".$shuffle; #(0 no, 1 title, 2 albums)
 		    
 				if ($songCount > 0) {
 					$idx = Slim::Player::Source::playingSongIndex($client);
 					push @returnArray, "playlist_cur_index:".($idx);
 				}

 		    		push @returnArray, "playlist_tracks:".$songCount;
 			}
 			
 			if ($songCount > 0 && $power) {
 			
 				# we can return playlist data.
 				# which mode are we in?
 				my $modecurrent = 0;

 				if (defined($p1) && ($p1 eq "-")) {
 					$modecurrent = 1;
 				}
 				
 				# if repeat is 1 (song) and modecurrent, then show the current song
 				if ($modecurrent && ($repeat == 1) && $p2) {

 					push @returnArray, "playlist index:".($idx);
 					push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);	

 				} else {

 					my ($valid, $start, $end);
 					
 					if ($modecurrent) {
 						($valid, $start, $end) = normalize(($idx), scalar($p2), $songCount);
 					} else {
 						($valid, $start, $end) = normalize(scalar($p1), scalar($p2), $songCount);
 					}
 		
 					if ($valid) {
 						my $count = 0;
 	
 						for ($idx = $start; $idx <= $end; $idx++){
 							$count++;
 							push @returnArray, "playlist index:".($idx);
 							push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);
 							::idleStreams() ;
 						}
 						
 						my $repShuffle = Slim::Utils::Prefs::get('reshuffleOnRepeat');
 						my $canPredictFuture = ($repeat == 2)  			# we're repeating all
 												&& 						# and
 												(	($shuffle == 0)		# either we're not shuffling
 													||					# or
 													(!$repShuffle));	# we don't reshuffle
 						
 						if ($modecurrent && $canPredictFuture && ($count < scalar($p2))) {

 							# wrap around the playlist...
 							($valid, $start, $end) = normalize(0, (scalar($p2) - $count), $songCount);		

 							if ($valid) {

 								for ($idx = $start; $idx <= $end; $idx++){
 									push @returnArray, "playlist index:".($idx);
 									push @returnArray, pushSong(Slim::Player::Playlist::song($client, $idx), $tags);
 									::idleStreams() ;
 								}
 							}						
 						}
 					}
 				}
 			}

 		} else {

 			#treat anything we don't know as a query so that we don't bcast it!
 			# ${$pcmdIsQuery} = 1;
  		}
 	}				
 		
 	# extended CLI API calls do push their return values directly
 	if ($pushParams) {
 		if (defined($p0)) { push @returnArray, $p0 };
 		if (defined($p1)) { push @returnArray, $p1 };
 		if (defined($p2)) { push @returnArray, $p2 };
 		if (defined($p3)) { push @returnArray, $p3 };
 		if (defined($p4)) { push @returnArray, $p4 };
 		if (defined($p5)) { push @returnArray, $p5 };
 		if (defined($p6)) { push @returnArray, $p6 };
 		if (defined($p7)) { push @returnArray, $p7 };
  	}

	$callcallback && $callbackf && (&$callbackf(@$callbackargs, \@returnArray));

	executeCallback($client, \@returnArray);
	
	$::d_command && msg(" Returning array: $p0 (" .
			(defined $p1 ? $p1 : "") . ") (" .
			(defined $p2 ? $p2 : "") . ") (" .
			(defined $p3 ? $p3 : "") . ") (" .
			(defined $p4 ? $p4 : "") . ") (" .
			(defined $p5 ? $p5 : "") . ") (" .
			(defined $p6 ? $p6 : "") . ") (" .
			(defined $p7 ? $p7 : "") . ")\n");
	
	return @returnArray;
}

sub syncFunction {
	my $client = shift;
	my $newval = shift;
	my $setting = shift;
	my $controlRef = shift;
	
	my @buddies = Slim::Player::Sync::syncedWith($client);

	if (scalar(@buddies) > 0) {

		for my $eachclient (@buddies) {

			if ($eachclient->prefGet('syncVolume')) {

				if ($setting eq "mute") {
					$eachclient->fade_volume($newval, \&mute, [$eachclient]);
				} else {
					$eachclient->prefSet($setting, $newval);
					&$controlRef($eachclient, $newval) if ($controlRef);
				}

				if ($setting eq "volume") {
					Slim::Display::Display::volumeDisplay($eachclient);
				}
			}

			if ($client->prefGet('syncPower')) {

				if ($setting eq "power") {
					$eachclient->power($newval);
				}
			}
		}
	}
}

sub setVolume {
	my $client = shift;
	my $volume = shift;
	$client->volume($volume);
}

sub setBass {
	my $client = shift;
	my $bass = shift;
	$client->bass($bass);
}

sub setPitch {
	my $client = shift;
	my $pitch = shift;
	$client->pitch($pitch);
}

sub setTreble {
	my $client = shift;
	my $treble = shift;
	$client->treble($treble);
}

sub setExecuteCallback {
	my $callbackRef = shift;
	$executeCallbacks{$callbackRef} = $callbackRef;
}

sub clearExecuteCallback {
	my $callbackRef = shift;
	delete $executeCallbacks{$callbackRef};
}

sub executeCallback {
	my $client = shift;
	my $paramsRef = shift;

	no strict 'refs';
		
	for my $executecallback (keys %executeCallbacks) {
		$executecallback = $executeCallbacks{$executecallback};
		&$executecallback($client, $paramsRef);
	}
}

sub load_done {
	my ($client, $index, $callbackf, $callbackargs) = @_;

	# dont' keep current song on loading a playlist
	Slim::Player::Playlist::reshuffle($client,
		(Slim::Player::Source::playmode($client) eq "play" || ($client->power && Slim::Player::Source::playmode($client) eq "pause")) ? 0 : 1
	);

	if (defined($index)) {
		Slim::Player::Source::jumpto($client, $index);
	}

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub insert_done {
	my ($client, $listsize, $size, $callbackf, $callbackargs) = @_;

	my $playlistIndex = Slim::Player::Source::streamingSongIndex($client)+1;
	my @reshuffled;

	if (Slim::Player::Playlist::shuffle($client)) {

		for (my $i = 0; $i < $size; $i++) {
			push @reshuffled, ($listsize + $i);
		};
			
		$client = Slim::Player::Sync::masterOrSelf($client);
		
		if (Slim::Player::Playlist::count($client) != $size) {	
			splice @{$client->shufflelist}, $playlistIndex, 0, @reshuffled;
		}
		else {
			push @{$client->shufflelist}, @reshuffled;
		}
	} else {

		if (Slim::Player::Playlist::count($client) != $size) {
			Slim::Player::Playlist::moveSong($client, $listsize, $playlistIndex,$size);
		}

		Slim::Player::Playlist::reshuffle($client);
	}

	Slim::Player::Playlist::refreshPlaylist($client);

	$callbackf && (&$callbackf(@$callbackargs));

	Slim::Control::Command::executeCallback($client, ['playlist','load_done']);
}

sub singletonRef {
	my $arg = shift;

	if (!defined($arg)) {
		return [];
	} elsif ($arg eq '*') {
		return [];
	} elsif ($arg) {
		# force stringification of a possible object.
		return [ "" . $arg ];
	} else {
		return [];
	}
}

sub sleepStartFade {
	my $client = shift;

	$::d_command && msg("sleepStartFade()\n");
	
	if ($client->isPlayer()) {
		$client->fade_volume(-60, undef, [$client]);
	}
}

sub sleepPowerOff {
	my $client = shift;
	
	$::d_command && msg("sleepPowerOff()\n");

	$client->sleepTime(0);
	$client->currentSleepTime(0);
	
	execute($client, ['stop', 0]);
	execute($client, ['power', 0]);
}

sub mute {
	my $client = shift;
	$client->mute();
}

sub parseSearchTerms {
	my $client = shift;
	my $terms  = shift;

	my $ds     = Slim::Music::Info::getCurrentDataStore();
	my %find   = ();
	my @fields = Slim::DataStores::Base->queryFields();
	my ($sort, $limit, $offset);

	for my $term (split '&', $terms) {

		if ($term =~ /(.*)=(.*)/ && grep $_ eq $1, @fields) {

			my $key   = URI::Escape::uri_unescape($1);
			my $value = URI::Escape::uri_unescape($2);

			$find{$key} = Slim::Utils::Text::ignoreCaseArticles($value);

		} elsif ($term =~ /^(fieldInfo)=(\w+)$/) {

			$find{$1} = $2;
		}

		# modifiers to the search
		$sort   = $2 if $1 eq 'sort';
		$limit  = $2 if $1 eq 'limit';
		$offset = $2 if $1 eq 'offset';
	}

	# default to a sort
	$sort ||= exists $find{'album'} ? 'tracknum' : 'track';

	# We can poke directly into the field info if requested - for more complicated queries.
	if ($find{'fieldInfo'}) {

		my $fieldInfo = Slim::DataStores::Base->fieldInfo;
		my $fieldKey  = $find{'fieldInfo'};

		return &{$fieldInfo->{$fieldKey}->{'find'}}($ds, 0, { 'audio' => 1 }, 1);

	} elsif ($find{'playlist'}) {

		# Treat playlists specially - they are containers.
		my $obj = $ds->objectForId('track', $find{'playlist'});

		if (blessed($obj) && $obj->can('tracks')) {

			# Side effect - (this would never fly in Haskell! :)
			# We want to add the playlist name to the client object.
			$client->currentPlaylist($obj);

			return $obj->tracks;
		}

		return ();

	} else {

		# Bug 2271 - allow VA albums.
		if ($find{'album.compilation'}) {

			delete $find{'artist'};
		}

		return @{ $ds->find({
			'field'  => 'lightweighttrack',
			'find'   => \%find,
			'sortBy' => $sort,
			'limit'  => $limit,
			'offset' => $offset,
		}) };
	}
}

sub parseListRef {
	my $client  = shift;
	my $term    = shift;
	my $listRef = shift;

	if ($term =~ /listref=(\w+)&?/i) {
		$listRef = $client->param($1);
	}

	if (defined $listRef && ref $listRef eq "ARRAY") {

		return @$listRef;
	}
}

# Extended CLI API helper subs
# ----------------------------

# This maps the extended CLI commands to methods on Track.
# Allocation map: capital letters are still free:
#  a b c d e f g h i j k l m n o p q r s t u v X y z

our %cliTrackMap = (
	'g' => 'genre',
	'a' => 'artist',
	'l' => 'album',
	't' => 'tracknum',
	'y' => 'year',
	'm' => 'bpm',
	'k' => 'comment',
	'v' => 'tagversion',
	'r' => 'bitrate',
	'z' => 'drm',
	'n' => 'modificationTime',
	'u' => 'url',
	'f' => 'filesize',
);

# Special cased:
#	'c' => 'composer',
#	'b' => 'band',
#	'h' => 'conductor',
# d duration
# i disc
# j Cover art
# o type
# q disc count
# e album_id
# p genre_id
# s artist_id

sub pushSong {
	my $pathOrObj = shift;
	my $tags      = shift;

	my $ds        = Slim::Music::Info::getCurrentDataStore();
	my $track     = ref $pathOrObj ? $pathOrObj : $ds->objectForUrl($pathOrObj);
	
	if (!blessed($track) || !$track->can('id')) {
		msg("Slim::Control::Command::pushSong called on undefined track!\n");
		return;
	}

	my @returnArray = (
		sprintf('id:%s', $track->id()),
		sprintf('title:%s', $track->title()),
	);

#			use Data::Dumper;
#			print Dumper($track);

	for my $tag (split //, $tags) {

		if (my $method = $cliTrackMap{$tag}) {

			my $value = $track->$method();

			if (defined $value && $value !~ /^\s*$/ && !(($tag eq 'c' || $tag eq 'b' || $tag eq 'h') && $value == 0)) {

				push @returnArray, sprintf('%s:%s', $method, $value);
			}

			next;
		}

		if ($tag eq 'd' && defined(my $duration = $track->secs())) {
			push @returnArray, "duration:$duration";
			next;
		}

		if ($tag eq 'c' && (my @composers = $track->composer())) {
			push @returnArray, "composer:" . $composers[0];
			next;
		}

		if ($tag eq 'b' && (my @bands = $track->band())) {
			push @returnArray, "band:" . $bands[0];
			next;
		}

		if ($tag eq 'h' && (my @conductors = $track->conductor())) {
			push @returnArray, "conductor:" . $conductors[0];
			next;
		}

		if ($tag eq 'p' && defined(my $genre = $track->genre())) {
			if (defined(my $id = $genre->id())) {
				push @returnArray, "genre_id:$id";
				next;
			}
		}

		if ($tag eq 's' && defined(my $artist = $track->artist())) {
			if ($tag eq 's' && defined(my $id = $artist->id())) {
				push @returnArray, "artist_id:$id";
				next;
			}
		}
		
		# Cover art!
		if ($tag eq 'j' && $track->coverArt()) {
			push @returnArray, "coverart:1";
			next;
		}
	
		if ($tag eq 'o' && defined(my $ct = $track->content_type())) {
			push @returnArray, sprintf('type:%s', string(uc($ct)));
			next;
		}

		if ($tag eq 'i' && defined(my $disc = $track->disc())) {
			push @returnArray, "disc:$disc";
			next;
		}

		# Handle album specifics
		if (defined(my $album = $track->album())) {
		
#			use Data::Dumper;
#			print Dumper($album);

			if ($tag eq 'e' && defined(my $id = $album->id())) {
				push @returnArray, "album_id:$id";
				next;
			}
	
			if ($tag eq 'q' && defined(my $discc = $album->discc())) {
				push @returnArray, "disccount:$discc";
				next;
			}
		}
	}

	return @returnArray;
}

sub normalize {
	my $from = shift;
	my $numofitems = shift;
	my $count = shift;
	
	my $start = 0;
	my $end   = 0;
	my $valid = 0;
	
	if ($numofitems && $count) {

		my $lastidx = $count - 1;

		if ($from > $lastidx) {
			return ($valid, $start, $end);
		}

		if ($from < 0) {
			$from = 0;
		}
	
		$start = $from;
		$end = $start + $numofitems - 1;
	
		if ($end > $lastidx) {
			$end = $lastidx;
		}

		$valid = 1;
	}

	return ($valid, $start, $end);
}

sub parseParams {
	my $parrayref = shift;
	my $preturnarrayref = shift;
	
	my %params = ();
	
	for my $p (@$parrayref) {

		if (defined $p && $p =~ /([^:]+):(.*)/) {

			$params{$1} = $2;
		}

		push @$preturnarrayref, $p;
	}
	
	return %params;
}

# defined, but does not contain a *
sub specified {
	my $i = shift;

	return 0 if ref($i) eq 'ARRAY';
	return 0 unless defined $i;
	return $i !~ /\*/;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
