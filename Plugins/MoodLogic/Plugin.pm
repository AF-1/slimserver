package Plugins::MoodLogic::Plugin;

#$Id: MoodLogic.pm 1757 2005-01-18 21:22:50Z dsully $
use strict;

use File::Spec::Functions qw(catfile);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Plugins::MoodLogic::VarietyCombo;
use Plugins::MoodLogic::InstantMix;
use Plugins::MoodLogic::MoodWheel;

my $conn;
my $rs;
my $auto;
my $playlist;

my $mixer;
my $browser;
my $isScanning = 0;
my $initialized = 0;
our @mood_names;
our %mood_hash;
our %artwork;
my $last_error = 0;
my $isauto = 1;
my %genre_hash = ();

my $lastMusicLibraryFinishTime = undef;

sub strings {
	return '';
}

sub getFunctions {
	return '';
}

sub useMoodLogic {
	my $newValue = shift;
	my $can = canUseMoodLogic();
	
	if (defined($newValue)) {
		if (!$can) {
			Slim::Utils::Prefs::set('moodlogic', 0);
		} else {
			Slim::Utils::Prefs::set('moodlogic', $newValue);
		}
	}
	
	my $use = Slim::Utils::Prefs::get('moodlogic');
	
	if (!defined($use) && $can) { 
		Slim::Utils::Prefs::set('moodlogic', 1);
	} elsif (!defined($use) && !$can) {
		Slim::Utils::Prefs::set('moodlogic', 0);
	}
	
	$use = Slim::Utils::Prefs::get('moodlogic') && $can;
	Slim::Music::Import::useImporter('MOODLOGIC',$use);
	
	$::d_moodlogic && msg("MoodLogic: using moodlogic: $use\n");
	
	return $use;
}

sub canUseMoodLogic {
	return (Slim::Utils::OSDetect::OS() eq 'win' && initPlugin());
}

sub playlists {
	return Slim::Music::Info::playlists;
}

sub getDisplayName {
	return 'SETUP_MOODLOGIC';
}

sub enabled {
	return ($::VERSION !~/^5/) && Slim::Utils::OSDetect::OS() eq 'win' && initPlugin();
}

sub disablePlugin {
	# turn off checker
	Slim::Utils::Timers::killTimers(0, \&checker);
	
	# remove playlists
	
	# disable protocol handler
	#Slim::Player::Source::registerProtocolHandler("itunesplaylist", "0");
	
	# reset last scan time

	$lastMusicLibraryFinishTime = undef;


	$initialized = 0;
	
	# delGroups, categories and prefs
	Slim::Web::Setup::delCategory('moodlogic');
	Slim::Web::Setup::delGroup('server','moodlogic',1);
	
	# set importer to not use
	Slim::Utils::Prefs::set('moodlogic', 0);
	Slim::Music::Import::useImporter('MOODLOGIC',0);
}

sub initPlugin {
	return 1 if $initialized; 
	return 0 if Slim::Utils::OSDetect::OS() ne 'win';
	
	checkDefaults();
	
	require Win32::OLE;
	import Win32::OLE qw(EVENTS);
	
	Win32::OLE->Option(Warn => \&OLEError);
	my $name = "mL_MixerCenter";
	
	$mixer = Win32::OLE->new("$name.MlMixerComponent");
	
	if (!defined $mixer) {
		$name = "mL_Mixer";
		$mixer = Win32::OLE->new("$name.MlMixerComponent");
	}
	
	if (!defined $mixer) {
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic mixer component\n");
		return 0;
	}
	
	$browser = Win32::OLE->new("$name.MlMixerFilter");
	
	if (!defined $browser) {
		$::d_moodlogic && msg("MoodLogic: could not find moodlogic filter component\n");
		return 0;
	}
	
	Win32::OLE->WithEvents($mixer, \&event_hook);
	
	$mixer->{JetPwdMixer} = 'C393558B6B794D';
	$mixer->{JetPwdPublic} = 'F8F4E734E2CAE6B';
	$mixer->{JetPwdPrivate} = '5B1F074097AA49F5B9';
	$mixer->{UseStrings} = 1;
	$mixer->Initialize();
	$mixer->{MixMode} = 0;
	
	if ($last_error != 0) {
		$::d_moodlogic && msg("MoodLogic: rebuilding mixer db\n");
		$mixer->MixerDb_Create();
		$last_error = 0;
		$mixer->Initialize();
		if ($last_error != 0) {
			return 0;
		}
	}
	
	my $i = 0;
	
	push @mood_names, string('MOODLOGIC_MOOD_0');
	push @mood_names, string('MOODLOGIC_MOOD_1');
	push @mood_names, string('MOODLOGIC_MOOD_2');
	push @mood_names, string('MOODLOGIC_MOOD_3');
	push @mood_names, string('MOODLOGIC_MOOD_4');
	push @mood_names, string('MOODLOGIC_MOOD_5');
	push @mood_names, string('MOODLOGIC_MOOD_6');
	
	map { $mood_hash{$_} = $i++ } @mood_names;

	#Slim::Utils::Strings::addStrings($strings);
	Slim::Player::Source::registerProtocolHandler("moodlogicplaylist", "0");

	Slim::Music::Import::addImporter('MOODLOGIC', {
		'scan'      => \&startScan,
		'mixer'     => \&mixerFunction,
		'setup'     => \&addGroups,
		'mixerlink' => \&mixerlink,
	});

	Slim::Music::Import::useImporter('MOODLOGIC',Slim::Utils::Prefs::get('moodlogic'));
	addGroups();

	Plugins::MoodLogic::InstantMix::init();
	Plugins::MoodLogic::MoodWheel::init();
	Plugins::MoodLogic::VarietyCombo::init();

	$initialized = 1;
	checker($initialized);

	return $initialized;
}

sub addGroups {
	my ($groupRef,$prefRef) = &setupUse();
	Slim::Web::Setup::addGroup('server','moodlogic',$groupRef,2,$prefRef);
	Slim::Web::Setup::addChildren('server','moodlogic');
	Slim::Web::Setup::addCategory('moodlogic',&setupCategory);
}

sub isMusicLibraryFileChanged {
	my $file = $mixer->{JetFilePublic};

	my $fileMTime = (stat $file)[9];
	
	# Only say "yes" if it has been more than one minute since we last finished scanning
	# and the file mod time has changed since we last scanned. Note that if we are
	# just starting, $lastMusicLibraryDate is undef, so both $fileMTime
	# will be greater than 0 and time()-0 will be greater than 180 :-)
	if ($file && $fileMTime > Slim::Utils::Prefs::get('lastMoodLogicLibraryDate')) {
		my $moodlogicscaninterval = Slim::Utils::Prefs::get('moodlogicscaninterval');
		
		$::d_moodlogic && msg("MoodLogic: music library has changed!\n");
		
		unless ($moodlogicscaninterval) {
			
			# only scan if moodlogicscaninterval is non-zero.
			$::d_moodlogic && msg("MoodLogic: Scan Interval set to 0, rescanning disabled\n");

			return 0;
		}

		return 1 if (!$lastMusicLibraryFinishTime);
		
		if (time() - $lastMusicLibraryFinishTime > $moodlogicscaninterval) {
			return 1;
		} else {
			$::d_moodlogic && msg("MoodLogic: waiting for $moodlogicscaninterval seconds to pass before rescanning\n");
		}
	}
	
	return 0;
}

sub checker {
	my $firstTime = shift || 0;

	return unless (Slim::Utils::Prefs::get('moodlogic'));
	
	if (!$firstTime && !stillScanning() && isMusicLibraryFileChanged()) {
		startScan();
	}

	# make sure we aren't doing this more than once...
	Slim::Utils::Timers::killTimers(0, \&checker);

	# Call ourselves again after 5 seconds
	Slim::Utils::Timers::setTimer(0, (Time::HiRes::time() + 5.0), \&checker);
}

sub startScan {
	
	if (!useMoodLogic()) {
		return;
	}
		
	$::d_moodlogic && msg("MoodLogic: start export\n");
	
	stopScan();
	
	Slim::Utils::Scheduler::add_task(\&exportFunction);
} 

sub stopScan {
	
	if (stillScanning()) {
		Slim::Utils::Scheduler::remove_task(\&exportFunction);
		doneScanning();
	}
}

sub stillScanning {
	return $isScanning;
}

sub doneScanning {
	$::d_moodlogic && msg("MoodLogic: done Scanning\n");

	$isScanning = 0;
	%genre_hash = ();
	
	$lastMusicLibraryFinishTime = time();

	Slim::Utils::Prefs::set('lastMoodLogicLibraryDate',(stat $mixer->{JetFilePublic})[9]);
	
	Slim::Music::Info::generatePlaylists();
	
	Slim::Music::Import::endImporter('MOODLOGIC');
}

sub getPlaylistItems {
	my $playlist = shift;
	my $item = $playlist->Fields('name')->value;
	my @list;
	
	while (!$playlist->EOF && defined($playlist->Fields('name')->value) && ($playlist->Fields('name')->value eq $item)) {
		push @list,Slim::Utils::Misc::fileURLFromPath(catfile($playlist->Fields('volume')->value.$playlist->Fields('path')->value,$playlist->Fields('filename')->value));
		$playlist->MoveNext;
	}
	$::d_moodlogic && msg("MoodLogic: adding ". scalar(@list)." items\n");
	return \@list;
}

sub exportFunction {
	
	my $ds    = Slim::Music::Info::getCurrentDataStore();

	my $prefix = Slim::Utils::Prefs::get('MoodLogicplaylistprefix');
	my $suffix = Slim::Utils::Prefs::get('MoodLogicplaylistsuffix');

	if (!$isScanning) {
		$conn = Win32::OLE->new("ADODB.Connection");
		$rs   = Win32::OLE->new("ADODB.Recordset");
		$playlist   = Win32::OLE->new("ADODB.Recordset");
		$auto   = Win32::OLE->new("ADODB.Recordset");

		$::d_moodlogic && msg("MoodLogic: Opening Object Link...\n");
		$conn->Open('PROVIDER=MSDASQL;DRIVER={Microsoft Access Driver (*.mdb)};DBQ='.$mixer->{JetFilePublic}.';UID=;PWD=F8F4E734E2CAE6B;');
		$rs->Open('SELECT tblSongObject.songId, tblSongObject.profileReleaseYear, tblAlbum.name, tblSongObject.tocAlbumTrack, tblMediaObject.bitrate FROM tblAlbum,tblMediaObject,tblSongObject WHERE tblAlbum.albumId = tblSongObject.tocAlbumId AND tblSongObject.songId = tblMediaObject.songId ORDER BY tblSongObject.songId', $conn, 1, 1);
		#PLAYLIST QUERY
		$playlist->Open('Select tblPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename  From "tblPlaylist", "tblPlaylistSong", "tblMediaObject" where "tblPlaylist"."playlistId" = "tblPlaylistSong"."playlistId" AND "tblPlaylistSong"."songId" = "tblMediaObject"."songId" order by tblPlaylist.playlistId,tblPlaylistSong.playOrder', $conn, 1, 1);
		{
			# AUTO PLAYLIST QUERY: 
			local $Win32::OLE::Warn = 0;
			$auto->Open('Select tblAutoPlaylist.name, tblMediaObject.volume, tblMediaObject.path, tblMediaObject.filename From "tblAutoPlaylist", "tblAutoPlaylistSong", "tblMediaObject" where "tblAutoPlaylist"."playlistId" = tblAutoPlaylistSong.playlistId AND tblAutoPlaylistSong.songId = tblMediaObject.songId order by tblAutoPlaylist.playlistId,tblAutoPlaylistSong.playOrder', $conn, 1, 1);
			if (Win32::OLE->LastError) {
				$isauto = 0;
				$::d_moodlogic && Slim::Utils::Misc::msg("No AutoPlaylists Found\n");
			};
		}
		
		$browser->filterExecute();
		
		my $count = $browser->FLT_Genre_Count();
		
		for (my $i = 1; $i <= $count; $i++) {
			my $genre_id = $browser->FLT_Genre_MGID($i);
			$mixer->{Seed_MGID} = -$genre_id;
			my $genre_name = $mixer->Mix_GenreName(-1);
			$mixer->{Seed_MGID} = $genre_id;
			my $genre_mixable = $mixer->Seed_MGID_Mixable();
			$genre_hash{$genre_id} = [$genre_name, $genre_mixable];
		}
		$isScanning = 1;
		$::d_moodlogic && msg("MoodLogic: Begin song scan\n");
		
		return 1;
	}

	if ($isScanning <= $browser->FLT_Song_Count()) {
		my @album_data = (-1, undef, undef);
	
		my $url;
		my %cacheEntry = ();
		my $song_id = $browser->FLT_Song_SID($isScanning);
		
		$mixer->{Seed_SID} = -$song_id;
		$url = Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile(-1));

		# merge album info, from query ('cause it is not available via COM)
		while (defined $rs && !$rs->EOF && $album_data[0] < $song_id && defined $rs->Fields('songId')) {

			@album_data = (
				$rs->Fields('songId')->value,
				$rs->Fields('name')->value,
				$rs->Fields('tocAlbumTrack')->value,
				$rs->Fields('bitrate')->value,
				$rs->Fields('profileReleaseYear')->value,
			);
			$rs->MoveNext;
		}
		
		if (defined $album_data[0] && $album_data[0] == $song_id && $album_data[1] ne "") {
			$cacheEntry{'ALBUM'} = $album_data[1];
			$cacheEntry{'TRACKNUM'} = $album_data[2];
			$cacheEntry{'BITRATE'} = $album_data[3];
			$cacheEntry{'YEAR'} = $album_data[4];
		}

		$cacheEntry{'CT'}         = Slim::Music::Info::typeFromPath($url,'mp3');
		$cacheEntry{'TAG'}        = 1;
		$cacheEntry{'VALID'}      = 1;
		
		$cacheEntry{'TITLE'}      = $mixer->Mix_SongName(-1);
		$cacheEntry{'ARTIST'}     = $mixer->Mix_ArtistName(-1);
		$cacheEntry{'GENRE'}      = $genre_hash{$browser->FLT_Song_MGID($isScanning)}[0] if (defined $genre_hash{$browser->FLT_Song_MGID($isScanning)});
		$cacheEntry{'SECS'}       = int($mixer->Mix_SongDuration(-1) / 1000);
		
		$cacheEntry{'MOODLOGIC_ID'} = $mixer->{'Seed_SID'} = $song_id;
		$cacheEntry{'MOODLOGIC_MIXABLE'} = $mixer->Seed_SID_Mixable();

		if ($] > 5.007) {

			for my $key (qw(ALBUM ARTIST GENRE TITLE)) {
				$cacheEntry{$key} = Encode::encode('utf8', $cacheEntry{$key}, Encode::FB_QUIET()) if defined $cacheEntry{$key};
			}
		}

		$::d_moodlogic && msg("MoodLogic: Creating entry for: $url\n");

		# that's all for the track
		my $track = $ds->updateOrCreate({

			'url' => $url,
			'attributes' => \%cacheEntry,
			'readTags'   => 1,

		}) || do {

			$::d_moodlogic && Slim::Utils::Misc::msg("Couldn't create track for: $url\n");

			return 0;
		};

		# Now add to the contributors and genres
		for my $contributor ($track->contributors()) {
			$mixer->{'Seed_AID'} = $browser->FLT_Song_AID($isScanning);

			$contributor->moodlogic_id($mixer->{'Seed_AID'});
			$contributor->moodlogic_mixable($mixer->Seed_AID_Mixable());
			$contributor->update();
		}

		for my $genre ($track->genres()) {

			$genre->moodlogic_id($browser->FLT_Song_MGID($isScanning));

			if (defined $genre_hash{$browser->FLT_Song_MGID($isScanning)}) {
				$genre->moodlogic_mixable($genre_hash{$browser->FLT_Song_MGID($isScanning)}[1]);
			}

			$genre->update();
		}

		my $albumObj = $track->album();

		if (Slim::Utils::Prefs::get('lookForArtwork') && $albumObj) {

			if (!Slim::Music::Import::artwork($albumObj) && !defined $track->thumb()) {

				Slim::Music::Import::artwork($albumObj, $track);
			}
		}
		
		$isScanning++;
		
		return 1;
	}
	
	$::d_moodlogic && msg("MoodLogic: Song scan complete, checking playlists\n");


	while (defined $playlist && !$playlist->EOF) {

		my $name = $playlist->Fields('name')->value;
		my %cacheEntry = ();
		my $url = 'moodlogicplaylist:' . Slim::Web::HTTP::escape($name);

		if (!defined($Slim::Music::Info::playlists[-1]) || $Slim::Music::Info::playlists[-1] ne $name) {
			$::d_moodlogic && msg("MoodLogic: Found MoodLogic Playlist: $url\n");
		}

		# add this playlist to our playlist library
		$cacheEntry{'TITLE'} =  $prefix . $name . $suffix;
		$cacheEntry{'LIST'} = getPlaylistItems($playlist);
		$cacheEntry{'CT'} = 'mlp';
		$cacheEntry{'TAG'} = 1;
		$cacheEntry{'VALID'} = '1';

		Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

		$playlist->MoveNext unless $playlist->EOF;
	}
	
	#TODO find a way to prevent a crash if no auto playlists exist.  they don't for old versions of moodlogic.
	if ($isauto) {

		while (defined $auto && !$auto->EOF) {

			my $name= $auto->Fields('name')->value;
			
			my %cacheEntry = ();
			my $url = 'moodlogicplaylist:' . Slim::Web::HTTP::escape($name);
			$url = Slim::Utils::Misc::fixPath($url);

			if (!defined($Slim::Music::Info::playlists[-1]) || $Slim::Music::Info::playlists[-1] ne $name) {
				$::d_moodlogic && msg("MoodLogic: Found MoodLogic Auto Playlist: $url\n");
			}

			# add this playlist to our playlist library
			$cacheEntry{'TITLE'} =  $prefix . $name . $suffix;
			$cacheEntry{'LIST'} = getPlaylistItems($auto);
			$cacheEntry{'CT'} = 'mlp';
			$cacheEntry{'TAG'} = 1;
			$cacheEntry{'VALID'} = '1';

			Slim::Music::Info::updateCacheEntry($url, \%cacheEntry);

			$auto->MoveNext unless $auto->EOF;
		}
	}

	$rs->Close;
	$playlist->Close;
	$auto->Close if $isauto;
	$conn->Close;
	
	doneScanning();
	$::d_moodlogic && msg("MoodLogic: finished export ($isScanning records, ".scalar @{Slim::Music::Info::playlists()}." playlists)\n");
	return 0;
}

sub getMoodWheel {
	my $id = shift @_;
	my $for = shift @_;
	my @enabled_moods = ();
	
	if ($for eq "genre") {
		$mixer->{Seed_MGID} = $id;
		$mixer->{MixMode} = 3;
	} elsif ($for eq "artist") {
		$mixer->{Seed_AID} = $id;
		$mixer->{MixMode} = 2;
	} else {
		$::d_moodlogic && msg('MoodLogic: no/unknown type specified for mood wheel');
		return undef;
	}
	
	push @enabled_moods, $mood_names[1] if ($mixer->{MF_1_Enabled});
	push @enabled_moods, $mood_names[3] if ($mixer->{MF_3_Enabled});
	push @enabled_moods, $mood_names[4] if ($mixer->{MF_4_Enabled});
	push @enabled_moods, $mood_names[6] if ($mixer->{MF_6_Enabled});
	push @enabled_moods, $mood_names[0] if ($mixer->{MF_0_Enabled});

	return \@enabled_moods;
}

sub mixerFunction {
	my $client = shift;
	
	# look for parentParams (needed when multiple mixers have been used)
	my $paramref = defined $client->param('parentParams') ? $client->param('parentParams') : $client->modeParameterStack(-1);
	my $listIndex = $paramref->{'listIndex'};

	my $items = $paramref->{'listRef'};
	my $hierarchy = $paramref->{'hierarchy'};
	my $level	   = $paramref->{'level'} || 0;
	my $descend   = $paramref->{'descend'};
	
	my $currentItem = $items->[$listIndex];
	my $all = !ref($currentItem);
	
	my @levels = split(",", $hierarchy);
	
	my @oldlines    = Slim::Display::Display::curLines($client);

	my $ds          = Slim::Music::Info::getCurrentDataStore();
	my $mix;

	# if we've chosen a particular song
	if ($levels[$level] eq 'track' && $currentItem && $currentItem->moodlogic_mixable()) {
			Slim::Buttons::Common::pushMode($client, 'moodlogic_variety_combo', {'song' => $currentItem});
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	# if we've picked an artist 
	} elsif ($levels[$level] eq 'artist' && $currentItem && $currentItem->moodlogic_mixable()) {
			Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'artist' => $currentItem});
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	# if we've picked a genre 
	} elsif ($levels[$level] eq 'genre' && $currentItem && $currentItem->moodlogic_mixable()) {
			Slim::Buttons::Common::pushMode($client, 'moodlogic_mood_wheel', {'genre' => $currentItem});
			$client->pushLeft(\@oldlines, [Slim::Display::Display::curLines($client)]);
	# don't do anything if nothing is mixable
	} else {
			$client->bumpRight();
	}
}

sub mixerlink {
	my $item = shift;
	my $form = shift;
	my $descend = shift;
	
	if ($descend) {
		$form->{'mixable_descend'} = 1;
	} else {
		$form->{'mixable_not_descend'} = 1;
	}
	
	if ($item->can('moodlogic_mixable') && $item->moodlogic_mixable() && canUseMoodLogic() && Slim::Utils::Prefs::get('moodlogic')) {
		#set up a musicmagic link
		Slim::Web::Pages::addLinks("mixer", {'MOODLOGIC' => "plugins/MoodLogic/mixerlink.html"},1);
	} else {
		Slim::Web::Pages::addLinks("mixer", {'MOODLOGIC' => undef});
	}
	
	return $form;
}

sub getMix {
	my $id = shift @_;
	my $mood = shift @_;
	my $for = shift @_;
	my @instant_mix = ();
	
	$mixer->{VarietyCombo} = 0; # resets mixer
	if (defined $mood) {$::d_moodlogic && msg("MoodLogic: Create $mood mix for $for $id\n")};
	
	if ($for eq "song") {
		$mixer->{Seed_SID} = $id;
		$mixer->{MixMode} = 0;
	} elsif (defined $mood && defined $mood_hash{$mood}) {
		$mixer->{MoodField} = $mood_hash{$mood};
		if ($for eq "artist") {
			$mixer->{Seed_AID} = $id;
			$mixer->{MixMode} = 2;
		} elsif ($for eq "genre") {
			$mixer->{Seed_MGID} = $id;
			$mixer->{MixMode} = 3;
		} else {
			$::d_moodlogic && msg("MoodLogic: no valid type specified for instant mix");
			return undef;
		}
	} else {
		$::d_moodlogic && msg("MoodLogic: no valid mood specified for instant mix");
		return undef;
	}

	$mixer->Process();	# the VarietyCombo property can only be set
						# after an initial mix has been created
	my $count = Slim::Utils::Prefs::get('instantMixMax');
	my $variety = Slim::Utils::Prefs::get('varietyCombo');

	while ($mixer->Mix_PlaylistSongCount() < $count && $mixer->{VarietyCombo} > $variety)
	{
		# $mixer->{VarietyCombo} = 0 causes a mixer reset, so we have to avoid it.
		$mixer->{VarietyCombo} = $mixer->{VarietyCombo} == 10 ? $mixer->{VarietyCombo} - 9 : $mixer->{VarietyCombo} - 10;
		$mixer->Process(); # recreate mix
	}

	$count = $mixer->Mix_PlaylistSongCount();

	for (my $i=1; $i<=$count; $i++) {
		push @instant_mix, Slim::Utils::Misc::fileURLFromPath($mixer->Mix_SongFile($i));
	}

	return \@instant_mix;
}

sub event_hook {
	my ($mixer,$event,@args) = @_;
	return if ($event eq "TaskProgress");
	$last_error = $args[0]->Value();
	print "MoodLogic Error Event triggered: '$event',".join(",", $args[0]->Value())."\n";
	print $mixer->ErrorDescription()."\n";
}

sub OLEError {
	$::d_moodlogic && msg(Win32::OLE->LastError() . "\n");
}

sub DESTROY {
	Win32::OLE->Uninitialize();
}

sub setupUse {
	my $client = shift;
	my %setupGroup = (
		'PrefOrder' => ['moodlogic']
		,'Suppress_PrefLine' => 1
		,'Suppress_PrefSub' => 1
		,'GroupLine' => 1
		,'GroupSub' => 1
	);
	my %setupPrefs = (
		'moodlogic' => {
			'validate' => \&Slim::Web::Setup::validateTrueFalse
			,'changeIntro' => ""
			,'options' => {
				'1' => string('USE_MOODLOGIC')
				,'0' => string('DONT_USE_MOODLOGIC')
			}
			,'onChange' => sub {
					my ($client,$changeref,$paramref,$pageref) = @_;
					
					foreach my $client (Slim::Player::Client::clients()) {
						Slim::Buttons::Home::updateMenu($client);
					}
					Slim::Music::Import::useImporter('MOODLOGIC',$changeref->{'moodlogic'}{'new'});
					Slim::Music::Info::clearPlaylists('moodlogicplaylist:');
					Slim::Music::Import::startScan('MOODLOGIC');
				}
			,'optionSort' => 'KR'
			,'inputTemplate' => 'setup_input_radio.html'
		}
	);
	return (\%setupGroup,\%setupPrefs);
}

sub checkDefaults {

	if (!Slim::Utils::Prefs::isDefined('moodlogic')) {
		Slim::Utils::Prefs::set('moodlogic',0)
	}
	
	if (!Slim::Utils::Prefs::isDefined('moodlogicscaninterval')) {
		Slim::Utils::Prefs::set('moodlogicscaninterval',60)
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistprefix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistprefix','MoodLogic: ');
	}
	
	if (!Slim::Utils::Prefs::isDefined('MoodLogicplaylistsuffix')) {
		Slim::Utils::Prefs::set('MoodLogicplaylistsuffix','');
	}
	
	if (!Slim::Utils::Prefs::isDefined('instantMixMax')) {
		Slim::Utils::Prefs::set('instantMixMax',12);
	}
	
	if (!Slim::Utils::Prefs::isDefined('varietyCombo')) {
		Slim::Utils::Prefs::set('varietyCombo',50);
	}
}

sub setupCategory {
	my %setupCategory =(
		'title' => string('SETUP_MOODLOGIC')
		,'parent' => 'server'
		,'GroupOrder' => ['Default','MoodLogicPlaylistFormat']
		,'Groups' => {
			'Default' => {
					'PrefOrder' => ['instantMixMax','varietyCombo','moodlogicscaninterval']
				}
			,'MoodLogicPlaylistFormat' => {
					'PrefOrder' => ['MoodLogicplaylistprefix','MoodLogicplaylistsuffix']
					,'PrefsInTable' => 1
					,'Suppress_PrefHead' => 1
					,'Suppress_PrefDesc' => 1
					,'Suppress_PrefLine' => 1
					,'Suppress_PrefSub' => 1
					,'GroupHead' => string('SETUP_MOODLOGICPLAYLISTFORMAT')
					,'GroupDesc' => string('SETUP_MOODLOGICPLAYLISTFORMAT_DESC')
					,'GroupLine' => 1
					,'GroupSub' => 1
				}
			}
		,'Prefs' => {
			'MoodLogicplaylistprefix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'MoodLogicplaylistsuffix' => {
					'validate' => \&Slim::Web::Setup::validateAcceptAll
					,'PrefSize' => 'large'
				}
			,'moodlogicscaninterval' => {
					'validate' => \&Slim::Web::Setup::validateNumber
					,'validateArgs' => [0,undef,1000]
				}
			,'instantMixMax'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [1,undef,1]
				}
			,'varietyCombo'	=> {
					'validate' => \&Slim::Web::Setup::validateInt
					,'validateArgs' => [1,100,1,1]
				}
		}
	);
	return (\%setupCategory);
};

sub webPages {
	my %pages = (
		"instant_mix\.(?:htm|xml)" => \&instant_mix,
		"mood_wheel\.(?:htm|xml)" => \&mood_wheel,
	);

	return (\%pages);
}

sub mood_wheel {
	my ($client, $params) = @_;

	my $items = "";

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};

	my $ds = Slim::Music::Info::getCurrentDataStore();
	
	my $itemnumber = 0;
	
	if (defined $artist && $artist ne "") {

		$items = getMoodWheel($ds->objectForId('contributor', $artist)->moodlogic_id(), 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*") {

		$items = getMoodWheel($ds->objectForId('genre', $genre)->moodlogic_id(), 'genre');

	} else {

		$::d_moodlogic && msg('no/unknown type specified for mood wheel');
		return undef;
	}

	#$params->{'pwd_list'} = Slim::Web::Pages::generate_pwd_list($genre, $artist, $album, $player,$params->{'webroot'});
	
	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};

	for my $item (@$items) {

		my %list_form = %$params;

		$list_form{'mood'}     = $item;
		$list_form{'genre'}    = $genre;
		$list_form{'artist'}   = $artist;
		$list_form{'album'}    = $album;
		$list_form{'player'}   = $player;
		$list_form{'itempath'} = $item; 
		$list_form{'item'}     = $item; 
		$list_form{'odd'}      = ($itemnumber + 1) % 2;

		$itemnumber++;

		$params->{'mood_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_list.html", \%list_form)};
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel.html", $params);
}

sub instant_mix {
	my ($client, $params) = @_;

	my $output = "";
	my $items  = "";

	my $song   = $params->{'song'};
	my $artist = $params->{'artist'};
	my $album  = $params->{'album'};
	my $genre  = $params->{'genre'};
	my $player = $params->{'player'};
	my $mood   = $params->{'mood'};
	my $p0     = $params->{'p0'};

	my $itemnumber = 0;
	my $ds = Slim::Music::Info::getCurrentDataStore();

	#$params->{'pwd_list'} = Slim::Web::Pages::generate_pwd_list($genre, $artist, $album, $player);

	if (defined $mood && $mood ne "") {
		$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/mood_wheel_pwdlist.html", $params)};
	}

	if (defined $song && $song ne "") {
		$params->{'src_mix'} = Slim::Music::Info::standardTitle(undef, $song);
	} elsif (defined $mood && $mood ne "") {
		$params->{'src_mix'} = $mood;
	}

	$params->{'pwd_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix_pwdlist.html", $params)};

	my $track = $ds->objectForUrl($song);

	if (defined $song && $song ne "") {

		$items = getMix($track->moodlogic_id(), undef, 'song');

	} elsif (defined $artist && $artist ne "" && $artist ne "*" && $mood ne "") {

		$items = getMix($ds->objectForId('contributor', $artist)->moodlogic_id(), $mood, 'artist');

	} elsif (defined $genre && $genre ne "" && $genre ne "*" && $mood ne "") {

		# XXX - only grab the first genre. This may be wrong
		#my $genre = ($trackObj->genres())[0];

		$items = getMix($ds->objectForId('genre', $genre)->moodlogic_id(), $mood, 'genre');

	} else {

		$::d_moodlogic && msg('no/unknown type specified for instant mix');
		return undef;
	}

	for my $item (@$items) {

		my %list_form = %$params;
		my $webFormat = Slim::Utils::Prefs::getInd("titleFormat",Slim::Utils::Prefs::get("titleFormatWeb"));
		
		my $trackObj  = $ds->objectForUrl($item) || next;
		
		$list_form{'genre'}         = $genre;
		$list_form{'player'}        = $player;
		$list_form{'itempath'}      = $item; 
		$list_form{'item'}          = $item;
		$list_form{'itemobj'}       = $trackObj;
		$list_form{'title'}         = Slim::Music::Info::infoFormat($item, $webFormat, 'TITLE');
		$list_form{'includeArtist'} = ($webFormat !~ /ARTIST/);
		$list_form{'includeAlbum'}  = ($webFormat !~ /ALBUM/) ;
		$list_form{'odd'}           = ($itemnumber + 1) % 2;
		$list_form{'album'}         = $list_form{'includeArtist'} ? $trackObj->album() : undef;
		
		if ($list_form{'includeArtist'} && $trackObj) {

			if (Slim::Utils::Prefs::get('composerInArtists') && $trackObj) {
				if (my ($contributor) = $trackObj->contributors()) {
					$list_form{'artist'}   = $contributor->name();
					$list_form{'artistid'} = $contributor->id();
				}
			} else {
				$list_form{'artist'} = $trackObj->artist();
			}
		}
		$itemnumber++;

		$params->{'instant_mix_list'} .= ${Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix_list.html", \%list_form)};
	}

	if (defined $p0 && defined $client) {

		Slim::Control::Command::execute($client, ["playlist", $p0 eq "append" ? "append" : "play", $items->[0]]);
		
		for (my $i = 1; $i <= $#$items; $i++) {
			Slim::Control::Command::execute($client, ["playlist", "append", $items->[$i]]);
		}
	}

	return Slim::Web::HTTP::filltemplatefile("plugins/MoodLogic/instant_mix.html", $params);
}

1;

__END__
