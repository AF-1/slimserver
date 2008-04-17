package Slim::Control::Jive;

# SqueezeCenter Copyright 2001-2007 Logitech
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX;
use Scalar::Util qw(blessed);
use File::Spec::Functions qw(:ALL);
use File::Basename;
use URI;

use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Player::Playlist;
use Slim::Buttons::Information;
use Slim::Buttons::Synchronize;
use Slim::Buttons::AlarmClock;
use Slim::Player::Sync;
use Slim::Player::Client;
use Data::Dump;


=head1 NAME

Slim::Control::Jive

=head1 SYNOPSIS

CLI commands used by Jive.

=cut

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'player.jive',
	'defaultLevel' => 'ERROR',
	'description'  => getDisplayName(),
});

# additional top level menus registered by plugins
my %itemsToDelete      = ();
my @pluginMenus        = ();

=head1 METHODS

=head2 init()

=cut
sub init {
	my $class = shift;

	# register our functions
	
#        |requires Client
#        |  |is a Query
#        |  |  |has Tags
#        |  |  |  |Function to call
#        C  Q  T  F

    Slim::Control::Request::addDispatch(['menu', '_index', '_quantity'], 
        [0, 1, 1, \&menuQuery]);

    Slim::Control::Request::addDispatch(['alarmsettings', '_index', '_quantity'], [1, 1, 1, \&alarmSettingsQuery]);
    Slim::Control::Request::addDispatch(['alarmweekdays', '_index', '_quantity'], [1, 1, 1, \&alarmWeekdayMenu]);
    Slim::Control::Request::addDispatch(['alarmweekdaysettings', '_day'], [1, 1, 1, \&alarmWeekdaySettingsQuery]);
    Slim::Control::Request::addDispatch(['syncsettings', '_index', '_quantity'], [1, 1, 1, \&syncSettingsQuery]);
    Slim::Control::Request::addDispatch(['sleepsettings', '_index', '_quantity'], [1, 1, 1, \&sleepSettingsQuery]);
    Slim::Control::Request::addDispatch(['crossfadesettings', '_index', '_quantity'], [1, 1, 1, \&crossfadeSettingsQuery]);
    Slim::Control::Request::addDispatch(['replaygainsettings', '_index', '_quantity'], [1, 1, 1, \&replaygainSettingsQuery]);
    Slim::Control::Request::addDispatch(['playerinformation', '_index', '_quantity'], [1, 1, 1, \&playerInformationQuery]);
	Slim::Control::Request::addDispatch(['jivefavorites', '_cmd' ], [1, 0, 1, \&jiveFavoritesCommand]);
	Slim::Control::Request::addDispatch(['jiveplaylists', '_cmd' ], [1, 0, 1, \&jivePlaylistsCommand]);

	Slim::Control::Request::addDispatch(['date'],
		[0, 1, 0, \&dateQuery]);
	Slim::Control::Request::addDispatch(['firmwareupgrade'],
		[0, 1, 1, \&firmwareUpgradeQuery]);

	Slim::Control::Request::addDispatch(['jiveapplets'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivewallpapers'], [0, 1, 0, \&downloadQuery]);
	Slim::Control::Request::addDispatch(['jivesounds'], [0, 1, 0, \&downloadQuery]);
	
	Slim::Web::HTTP::addRawDownload('^jive(applet|wallpaper|sound)/', \&downloadFile, 'binary');

	# setup the menustatus dispatch and subscription
	Slim::Control::Request::addDispatch( ['menustatus', '_data', '_action'], [0, 0, 0, sub { warn "menustatus query\n" }]);
	Slim::Control::Request::subscribe( \&menuNotification, [['menustatus']] );
	
	# setup a cli command for jive that returns nothing; can be useful in some situations
	Slim::Control::Request::addDispatch( ['jiveblankcommand'], [0, 0, 0, sub { return 1; }]);

	# Load memory caches to help with menu performance
	buildCaches();
	
	# Re-build the caches after a rescan
	Slim::Control::Request::subscribe( \&buildCaches, [['rescan', 'done']] );
}

sub buildCaches {
	$log->info("Begin function");
	# Pre-cache albums query
	if ( my $numAlbums = Slim::Schema->rs('Album')->count ) {
		$log->debug( "Pre-caching $numAlbums album items." );
		Slim::Control::Request::executeRequest( undef, [ 'albums', 0, $numAlbums, 'menu:track', 'cache:1' ] );
	}
	
	# Artists
	if ( my $numArtists = Slim::Schema->rs('Contributor')->browse->search( {}, { distinct => 'me.id' } )->count ) {
		# Add one since we may have a VA item
		$numArtists++;
		$log->debug( "Pre-caching $numArtists artist items." );
		Slim::Control::Request::executeRequest( undef, [ 'artists', 0, $numArtists, 'menu:album', 'cache:1' ] );
	}
	
	# Genres
	if ( my $numGenres = Slim::Schema->rs('Genre')->browse->search( {}, { distinct => 'me.id' } )->count ) {
		$log->debug( "Pre-caching $numGenres genre items." );
		Slim::Control::Request::executeRequest( undef, [ 'genres', 0, $numGenres, 'menu:artist', 'cache:1' ] );
	}
}

=head2 getDisplayName()

Returns name of module

=cut
sub getDisplayName {
	return 'JIVE';
}

######
# CLI QUERIES

# handles the "menu" query
sub menuQuery {

	my $request = shift;

	$log->info("Begin menuQuery function");

	if ($request->isNotQuery([['menu']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client        = $request->client() || 0;

	# send main menu notification
	mainMenu($client);

	# a single dummy item to keep jive happy with _merge
	my $upgradeText = 
	"Please upgrade your firmware at:\n\nSettings->\nController Settings->\nAdvanced->\nSoftware Update\n\nThere have been updates to better support the communication between your remote and SqueezeCenter, and this requires a newer version of firmware.";
        my $upgradeMessage = {
		text      => 'READ ME',
		weight    => 1,
                offset    => 0,
                count     => 1,
                window    => { titleStyle => 'settings' },
                textArea =>  $upgradeText,
        };

        $request->addResult("count", 1);
	$request->addResult("offset", 0);
	$request->setResultLoopHash('item_loop', 0, $upgradeMessage);
	$request->setStatusDone();

}

sub mainMenu {

	$log->info("Begin function");
	my $client = shift;

	unless ($client->isa('Slim::Player::Client')) {
		# if this isn't a player, no menus should get sent
		return;
	}
 
	$log->info("Begin Function");
 
	# as a convention, make weights => 10 and <= 100; Jive items that want to be below all SS items
	# then just need to have a weight > 100, above SS items < 10

	# for the notification menus, we're going to send everything over "flat"
	# as a result, no item_loops, all submenus (setting, myMusic) are just elements of the big array that get sent

	my @menu = (
		{
			text           => $client->string('MY_MUSIC'),
			weight         => 11,
			displayWhenOff => 0,
			id             => 'myMusic',
			isANode        => 1,
			node           => 'home',
			window         => { titleStyle => 'mymusic', },
		},
		{
			text           => $client->string('FAVORITES'),
			id             => 'favorites',
			node           => 'home',
			displayWhenOff => 0,
			weight         => 40,
			actions => {
				go => {
					cmd => ['favorites', 'items'],
					params => {
						menu     => 'favorites',
					},
				},
			},
			window        => {
					titleStyle => 'favorites',
			},
		},

		@pluginMenus,
		@{playerPower($client, 1)},
		@{
			# The Digital Input plugin could be disabled
			if( Slim::Utils::PluginManager->isEnabled('Slim::Plugin::DigitalInput::Plugin')) {
				Slim::Plugin::DigitalInput::Plugin::digitalInputItem($client);
			} else {
				[];
			}
		},
		@{internetRadioMenu($client)},
		@{musicServicesMenu($client)},
		@{playerSettingsMenu($client, 1)},
		@{myMusicMenu(1, $client)},
	);

	_notifyJive(\@menu, $client);
}

# allow a plugin to add a node to the menu
sub registerPluginNode {
	$log->info("Begin function");
	my $nodeRef = shift;
	my $client = shift || undef;
	unless (ref($nodeRef) eq 'HASH') {
		$log->error("Incorrect data type");
		return;
	}

	$nodeRef->{'isANode'} = 1;
	$log->info("Registering node menu item from plugin");

	# notify this menu to be added
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $nodeRef, 'add', $id ] );

	# but also remember this structure as part of the plugin menus
	push @pluginMenus, $nodeRef;

}

# send plugin menus array as a notification to Jive
sub refreshPluginMenus {
	$log->info("Begin function");
	my $client = shift || undef;
	_notifyJive(\@pluginMenus, $client);
}

#allow a plugin to add an array of menu entries
sub registerPluginMenu {
	my $menuArray = shift;
	my $node = shift;
	my $client = shift || undef;

	unless (ref($menuArray) eq 'ARRAY') {
		$log->error("Incorrect data type");
		return;
	}

	if ($node) {
		my @menuArray = @$menuArray;
		for my $i (0..$#menuArray) {
			if (!$menuArray->[$i]{'node'}) {
				$menuArray->[$i]{'node'} = $node;
			}
		}
	}

	$log->info("Registering menus from plugin");

	# notify this menu to be added
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $menuArray, 'add', $id ] );

	# now we want all of the items in $menuArray to go into @pluginMenus, but we also
	# don't want duplicate items (specified by 'id'), 
	# so we want the ids from $menuArray to stomp on ids from @pluginMenus, 
	# thus getting the "newest" ids into the @pluginMenus array of items
	# we also do not allow any hash without an id into the array, and will log an error if that happens

	my %seen; my @new;

	for my $href (@$menuArray, reverse @pluginMenus) {
		my $id = $href->{'id'};
		my $node = $href->{'node'};
		if ($id) {
			if (!$seen{$id}) {
				$log->info("registering menuitem " . $id . " to " . $node );
				push @new, $href;
			}
			$seen{$id}++;
		} else {
			$log->error("Menu items cannot be added without an id");
		}
	}

	# @new is the new @pluginMenus
	# we do this in reverse so we get previously initialized nodes first 
	# you can't add an item to a node that doesn't exist :)
	@pluginMenus = reverse @new;

}

# allow a plugin to delete an item from the Jive menu based on the id of the menu item
sub deleteMenuItem {
	my $menuId = shift;
	my $client = shift || undef;
	return unless $menuId;
	$log->warn($menuId . " menu id slated for deletion");
	# send a notification to delete
	my @menuDelete = ( { id => $menuId } );
	my $id = _clientId($client);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', \@menuDelete, 'remove', $id ] );
	# but also remember that this id is not to be sent
	$itemsToDelete{$menuId}++;
}

sub _purgeMenu {
	my $menu = shift;
	my @menu = @$menu;
	my @purgedMenu = ();
	for my $i (0..$#menu) {
		my $menuId = defined($menu[$i]->{id}) ? $menu[$i]->{id} : $menu[$i]->{text};
		last unless (defined($menu[$i]));
		if ($itemsToDelete{$menuId}) {
			$log->warn("REMOVING " . $menuId . " FROM Jive menu");
		} else {
			push @purgedMenu, $menu[$i];
		}
	}
	return \@purgedMenu;
}

sub alarmSettingsQuery {

	$log->info("Begin function");
	my $request = shift;
	my $client = $request->client();

	# alarm clock, display for slim proto players
	# still need to pick up saved playlists as list items
	# need to figure out how to handle 24h vs. 12h clock format

	# array ref with 5 elements, each of which is a hashref
	my $day0 = populateAlarmElements($client, 0);

	my @weekDays;

	my $weekDayAlarms = {
		text      => $client->string("ALARM_WEEKDAYS"),
		window    => { titleStyle => 'settings' },
		actions => {
			go => {
				player => 0,
				cmd    => [ 'alarmweekdays' ],
			},
		},
	};

	# one item_loop to rule them all
	my @menu = ( @$day0, $weekDayAlarms );

	sliceAndShip($request, $client, \@menu);

}

sub alarmWeekdayMenu {
	$log->info("Begin function");
	my $request = shift;
	my $client = $request->client();

	# setup the individual calls to weekday alarms
	my @menu;
	for my $weekday (1..7) {
		# @weekDays becomes an array of arrayrefs of hashrefs, one element per weekday
		my $string = "ALARM_DAY$weekday";
		my $day = {
			text      => $client->string($string),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'alarmweekdaysettings', $weekday ],
				},
			},
		};
		push @menu, $day;
	}
	sliceAndShip($request, $client, \@menu);
	$request->setStatusDone();

}

sub alarmWeekdaySettingsQuery {
	$log->info("Begin function");
	my $request = shift;
	my $client = $request->client();
	my $day = $request->getParam('_day');
	my $dayMenu = populateAlarmElements($client, $day);
	$request->addResult('count', scalar(@$dayMenu));
	$request->addResult('offset', 0);
	my $cnt = 0;
	for my $menu (@$dayMenu) {
		$request->setResultLoopHash('item_loop', $cnt, $menu);
		$cnt++;
	}
	
}

sub playerInformationQuery {
	return;
}

sub syncSettingsQuery {

	$log->info("Begin function");
	my $request           = shift;
	my $client            = $request->client();
	my $playersToSyncWith = getPlayersToSyncWith($client);

	my @menu = @$playersToSyncWith;

	sliceAndShip($request, $client, \@menu);

}

sub sleepSettingsQuery {

	$log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $val     = $client->currentSleepTime();
	my @menu;

	if ($val > 0) {
		my $sleepString = $client->string( 'SLEEPING_IN_X_MINUTES', $val );
		push @menu, { text => $sleepString, style => 'itemNoAction' };
	}
	push @menu, sleepInXHash($client, $val, 0);
	push @menu, sleepInXHash($client, $val, 15);
	push @menu, sleepInXHash($client, $val, 30);
	push @menu, sleepInXHash($client, $val, 45);
	push @menu, sleepInXHash($client, $val, 60);
	push @menu, sleepInXHash($client, $val, 90);

	sliceAndShip($request, $client, \@menu);
}

sub crossfadeSettingsQuery {

	$log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('transitionType');
	my @strings = (
		'TRANSITION_NONE', 'TRANSITION_CROSSFADE', 
		'TRANSITION_FADE_IN', 'TRANSITION_FADE_OUT', 
		'TRANSITION_FADE_IN_OUT'
	);
	my @menu;

	push @menu, transitionHash($client, $val, $prefs, \@strings, 0);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 1);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 2);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 3);
	push @menu, transitionHash($client, $val, $prefs, \@strings, 4);

	sliceAndShip($request, $client, \@menu);

}

sub replaygainSettingsQuery {

	$log->info("Begin function");
	my $request = shift;
	my $client  = $request->client();
	my $prefs   = preferences("server");
	my $val     = $prefs->client($client)->get('replayGainMode');
	my @strings = (
		'REPLAYGAIN_DISABLED', 'REPLAYGAIN_TRACK_GAIN', 
		'REPLAYGAIN_ALBUM_GAIN', 'REPLAYGAIN_SMART_GAIN'
	);
	my @menu;

	push @menu, replayGainHash($client, $val, $prefs, \@strings, 0);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 1);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 2);
	push @menu, replayGainHash($client, $val, $prefs, \@strings, 3);

	sliceAndShip($request, $client, \@menu);
}


sub sliceAndShip {
	my ($request, $client, $menu) = @_;
	my $numitems = scalar(@$menu);
	my $index    = $request->getParam('_index');
	my $quantity = $request->getParam('_quantity');

	$request->addResult("count", $numitems);
	my ($valid, $start, $end) = $request->normalize(scalar($index), scalar($quantity), $numitems);

	if ($valid) {
		my $cnt = 0;
		$request->addResult('offset', $start);

		for my $eachmenu (@$menu[$start..$end]) {
			$request->setResultLoopHash('item_loop', $cnt, $eachmenu);
			$cnt++;
		}
	}
	$request->setStatusDone()
}

# returns a single item for the homeMenu if radios is a valid command
sub internetRadioMenu {
	$log->info("Begin function");
	my $client = shift;
	my @command = ('radios', 0, 200, 'menu:radio');

	my $test_request = Slim::Control::Request::executeRequest($client, \@command);
	my $validQuery = $test_request->isValidQuery();

	my @menu = ();
	
	if ($validQuery) {
		push @menu,
		{
			text           => $client->string('RADIO'),
			id             => 'radio',
			node           => 'home',
			displayWhenOff => 0,
			weight         => 20,
			actions        => {
				go => {
					cmd => ['radios'],
					params => {
						menu => 'radio',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		};
	}

	return \@menu;

}

# returns a single item for the homeMenu if music_services is a valid command
sub musicServicesMenu {
	$log->info("Begin function");
	my $client = shift;
	my @command = ('music_services', 0, 200, 'menu:music_services');

	my $test_request = Slim::Control::Request::executeRequest($client, \@command);
	my $validQuery = $test_request->isValidQuery();

	my @menu = ();
	
	if ($validQuery) {
		push @menu, 
		{
			text           => $client->string('MUSIC_SERVICES'),
			id             => 'ondemand',
			node           => 'home',
			weight         => 30,
			displayWhenOff => 0,
			actions => {
				go => {
					cmd => ['music_services'],
					params => {
						menu => 'music_services',
					},
				},
			},
			window        => {
					menuStyle => 'album',
					titleStyle => 'internetradio',
			},
		};
	}

	return \@menu;

}

sub playerSettingsMenu {

	$log->info("Begin function");
	my $client = shift;
	my $batch = shift;

	my @menu = ();
	return \@menu unless $client;
 
	# always add repeat
	push @menu, repeatSettings($client, 1);

	# always add shuffle
	push @menu, shuffleSettings($client, 1);

	# add alarm only if this is a slimproto player
	if ($client->isPlayer()) {
		push @menu, {
			text           => $client->string("ALARM"),
			id             => 'settingsAlarm',
			node           => 'settings',
			displayWhenOff => 0,
			weight         => 30,
			actions        => {
				go => {
					cmd    => ['alarmsettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};
	}

	# sleep setting (always)
	push @menu, {
		text           => $client->string("PLAYER_SLEEP"),
		id             => 'settingsSleep',
		node           => 'settings',
		displayWhenOff => 0,
		weight         => 40,
		actions        => {
			go => {
				cmd    => ['sleepsettings'],
				player => 0,
			},
		},
		window         => { titleStyle => 'settings' },
	};	

	# synchronization. only if numberOfPlayers > 1
	my $synchablePlayers = howManyPlayersToSyncWith($client);
	if ($synchablePlayers > 0) {
		push @menu, {
			text           => $client->string("SYNCHRONIZE"),
			id             => 'settingsSync',
			node           => 'settings',
			displayWhenOff => 0,
			weight         => 70,
			actions        => {
				go => {
					cmd    => ['syncsettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};	
	}

	# information, always display
	my $playerInfoText = $client->string( 'INFORMATION_SPECIFIC_PLAYER', $client->name() );
	my $playerInfoTextArea = 
			$client->string("INFORMATION_PLAYER_NAME_ABBR") . ": " . 
			$client->name() . "\n\n" . 
			$client->string("INFORMATION_PLAYER_MODEL_ABBR") . ": " .
			Slim::Buttons::Information::playerModel($client) . "\n\n" .
			$client->string("INFORMATION_FIRMWARE_ABBR") . ": " . 
			$client->revision() . "\n\n" .
			$client->string("INFORMATION_PLAYER_IP_ABBR") . ": " .
			$client->ipport() . "\n\n" .
			$client->string("INFORMATION_PLAYER_MAC_ABBR") . ": " .
			uc($client->macaddress()) . "\n\n" .
			($client->signalStrength ? $client->string("INFORMATION_PLAYER_SIGNAL_STRENGTH") . ": " .
			$client->signalStrength . "\n\n" : '') .
			($client->voltage ? $client->string("INFORMATION_PLAYER_VOLTAGE") . ": " .
			$client->voltage . "\n\n" : '');
	push @menu, {
		text           => $playerInfoText,
		id             => 'settingsPlayerInformation',
		node           => 'advancedSettings',
		displayWhenOff => 0,
		textArea       => $playerInfoTextArea,
		weight         => 4,
		window         => { titleStyle => 'settings' },
		actions        => {
				go =>	{
						# this is a dummy command...doesn't do anything but is required
						cmd    => ['playerinformation'],
						player => 0,
					},
				},
	};


	# player name change, always display
	push @menu, {
		text           => $client->string('INFORMATION_PLAYER_NAME'),
		id             => 'settingsPlayerNameChange',
		node           => 'advancedSettings',
		displayWhenOff => 0,
		input          => {	
			initialText  => $client->name(),
			len          => 1, # For those that want to name their player "X"
			allowedChars => $client->string('JIVE_ALLOWEDCHARS_WITHCAPS'),
			help         => {
				           text => $client->string('JIVE_CHANGEPLAYERNAME_HELP')
			},
			softbutton1  => $client->string('INSERT'),
			softbutton2  => $client->string('DELETE'),
		},
                actions        => {
                                do =>   {
                                                cmd    => ['name'],
                                                player => 0,
						params => {
							playername => '__INPUT__',
						},
                                        },
                                  },
		window         => { titleStyle => 'settings' },
	};


	# transition only for Sb2 and beyond (aka 'crossfade')
	if ($client->isa('Slim::Player::Squeezebox2')) {
		push @menu, {
			text           => $client->string("SETUP_TRANSITIONTYPE"),
			id             => 'settingsXfade',
			node           => 'advancedSettings',
			displayWhenOff => 0,
			actions        => {
				go => {
					cmd    => ['crossfadesettings'],
					player => 0,
				},
			},
			window         => { titleStyle => 'settings' },
		};	
	}

	# replay gain (aka volume adjustment)
	if ($client->canDoReplayGain(0)) {
		push @menu, {
			displayWhenOff => 0,
			text           => $client->string("REPLAYGAIN"),
			id             => 'settingsReplayGain',
			node           => 'advancedSettings',
			actions        => {
				  go => {
					cmd    => ['replaygainsettings'],
					player => 0,
				  },
			},
			window         => { titleStyle => 'settings' },
		};	
	}


	if ($batch) {
		return \@menu;
	} else {
		_notifyJive(\@menu, $client);
	}
}

sub browseMusicFolder {
	$log->info("Begin function");
	my $client = shift;
	my $batch = shift;

	# first we decide if $audiodir has been configured. If not, don't show this
	my $prefs    = preferences("server");
	my $audiodir = $prefs->get('audiodir');

	my $return = 0;
	if (defined($audiodir) && -d $audiodir) {
		$log->info("Adding Browse Music Folder");
		$return = {
				text           => $client->string('BROWSE_MUSIC_FOLDER'),
				id             => 'myMusicMusicFolder',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 70,
				actions        => {
					go => {
						cmd    => ['musicfolder'],
						params => {
							menu => 'musicfolder',
						},
					},
				},
				window        => {
					titleStyle => 'musicfolder',
				},
			};
	} else {
		# if it disappeared, send a notification to get rid of it if it exists
		$log->info("Removing Browse Music Folder from Jive menu via notification");
		deleteMenuItem('myMusicMusicFolder', $client);
	}

	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}

sub repeatSettings {
	my $client = shift;
	my $batch = shift;

	my $repeat_setting = Slim::Player::Playlist::repeat($client);
	my @repeat_strings = ('OFF', 'SONG', 'PLAYLIST',);
	my @translated_repeat_strings = map { ucfirst($client->string($_)) } @repeat_strings;
	my @repeatChoiceActions;
	for my $i (0..$#repeat_strings) {
		push @repeatChoiceActions, 
		{
			player => 0,
			cmd    => ['playlist', 'repeat', "$i"],
		};
	}
	my $return = {
		text           => $client->string("REPEAT"),
		id             => 'settingsRepeat',
		node           => 'settings',
		displayWhenOff => 0,
		weight         => 20,
		choiceStrings  => [ @translated_repeat_strings ],
		selectedIndex  => $repeat_setting + 1, # 1 is added to make it count like Lua
		actions        => {
			do => { 
				choices => [ 
					@repeatChoiceActions 
				], 
			},
		},
	};
	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}

sub shuffleSettings {
	my $client = shift;
	my $batch = shift;

	my $shuffle_setting = Slim::Player::Playlist::shuffle($client);
	my @shuffle_strings = ( 'OFF', 'SONG', 'ALBUM',);
	my @translated_shuffle_strings = map { ucfirst($client->string($_)) } @shuffle_strings;
	my @shuffleChoiceActions;
	for my $i (0..$#shuffle_strings) {
		push @shuffleChoiceActions, 
		{
			player => 0,
			cmd => ['playlist', 'shuffle', "$i"],
		};
	}
	my $return = {
		text           => $client->string("SHUFFLE"),
		id             => 'settingsShuffle',
		node           => 'settings',
		selectedIndex  => $shuffle_setting + 1,
		displayWhenOff => 0,
		weight         => 10,
		choiceStrings  => [ @translated_shuffle_strings ],
		actions        => {
			do => {
				choices => [
					@shuffleChoiceActions
				],
			},
		},
		window         => { titleStyle => 'settings' },
	};

	if ($batch) {
		return $return;
	} else {
		_notifyJive( [ $return ], $client);
	}
}

sub _clientId {
	my $client = shift;
	my $id = 'all';
	if ( blessed($client) && $client->id() ) {
		$id = $client->id();
	}
	return $id;
}
	
sub _notifyJive {
	my $menu = shift;
	my $client = shift || undef;
	my $id = _clientId($client);
	my $menuForExport = _purgeMenu($menu);
	Slim::Control::Request::notifyFromArray( $client, [ 'menustatus', $menuForExport, 'add', $id ] );
}

sub howManyPlayersToSyncWith {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my $synchablePlayers = 0;
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		$synchablePlayers++;
	}
	return $synchablePlayers;
}

sub getPlayersToSyncWith() {
	my $client = shift;
	my @playerSyncList = Slim::Player::Client::clients();
	my @return = ();
	for my $player (@playerSyncList) {
		# skip ourself
		next if ($client eq $player);
		# we only sync slimproto devices
		next if (!$player->isPlayer());
		my $val = Slim::Player::Sync::isSyncedWith($client, $player); 
		push @return, { 
			text => $player->name(), 
			checkbox => ($val == 1) + 0,
			actions  => {
				on  => {
					player => 0,
					cmd    => ['sync', $player->id()],
				},
				off => {
					player => $player->id(),
					cmd    => ['sync', '-'],
				},
			},		
		};
	}
	return \@return;
}

sub dateQuery {
	my $request = shift;

	if ( $request->isNotQuery([['date']]) ) {
		$request->setStatusBadDispatch();
		return;
	}
	
	# Calculate the time zone offset, taken from Time::Timezone
	my $time = time();
	my @l    = localtime($time);
	my @g    = gmtime($time);

	my $off 
		= $l[0] - $g[0]
		+ ( $l[1] - $g[1] ) * 60
		+ ( $l[2] - $g[2] ) * 3600;

	# subscript 7 is yday.

	if ( $l[7] == $g[7] ) {
		# done
	}
	elsif ( $l[7] == $g[7] + 1 ) {
		$off += 86400;
	}
	elsif ( $l[7] == $g[7] - 1 ) {
			$off -= 86400;
	} 
	elsif ( $l[7] < $g[7] ) {
		# crossed over a year boundry!
		# localtime is beginning of year, gmt is end
		# therefore local is ahead
		$off += 86400;
	}
	else {
		$off -= 86400;
	}

	my $hour = int($off / 3600);
	if ( $hour > -10 && $hour < 10 ) {
		$hour = "0" . abs($hour);
	}
	else {
		$hour = abs($hour);
	}

	my $tzoff = ( $off >= 0 ) ? '+' : '-';
	$tzoff .= sprintf( "%s:%02d", $hour, int( $off % 3600 / 60 ) );

	# Return time in http://www.w3.org/TR/NOTE-datetime format
	$request->addResult( 'date', strftime("%Y-%m-%dT%H:%M:%S", localtime) . $tzoff );

	$request->setStatusDone();
}

sub firmwareUpgradeQuery {
	my $request = shift;

	if ( $request->isNotQuery([['firmwareupgrade']]) ) {
		$request->setStatusBadDispatch();
		return;
	}

	my $firmwareVersion = $request->getParam('firmwareVersion');
	
	# always send the upgrade url this is also used if the user opts to upgrade
	if ( my $url = Slim::Utils::Firmware->jive_url() ) {
		# Bug 6828, Send relative firmware URLs for Jive versions which support it
		my ($cur_rev) = $firmwareVersion =~ m/\sr(\d+)/;
		if ( $cur_rev >= 1659 ) {
			$request->addResult( relativeFirmwareUrl => URI->new($url)->path );
		}
		else {
			$request->addResult( firmwareUrl => $url );
		}
	}
	
	if ( Slim::Utils::Firmware->jive_needs_upgrade( $firmwareVersion ) ) {
		# if this is true a firmware upgrade is forced
		$request->addResult( firmwareUpgrade => 1 );
	}
	else {
		$request->addResult( firmwareUpgrade => 0 );
	}

	# manage the subscription
	if (defined(my $timeout = $request->getParam('subscribe'))) {
		$request->registerAutoExecute($timeout, \&firmwareUpgradeQuery);
	}

	$request->setStatusDone();

}

sub alarmOnHash {
	my ($client, $prefs, $day) = @_;
	my $val = $prefs->client($client)->get('alarm')->[ $day ];
	my %return = (
		text     => $client->string("ENABLED"),
		checkbox => ($val == 1) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'update',
					dow     => $day,
					enabled => 1,
				},
			},
			off => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'update',
					dow     => $day,
					enabled => 0,
				},
			},
		},
	);
	return \%return;
}

sub alarmSetHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmtime')->[ $day ];
	my %return = 
	( 
		text    => $client->string("ALARM_SET"),
		input   => {
			initialText  => $current_setting, # this will need to be formatted correctly
			_inputStyle  => 'time',
			len          => 1,
			help         => {
				text => $client->string('JIVE_ALARMSET_HELP')
			},
		},
		actions => {
			do => {
				player => 0,
				cmd    => ['alarm'],
				params => {
					cmd => 'update',
					dow =>	$day,
					time => '__TAGGEDINPUT__',	
				},
			},
		},
		nextWindow => 'refreshOrigin',
	);
	return \%return;
}

sub alarmPlaylistHash {
	my ($client, $prefs, $day) = @_;
	my $alarm_playlist = $prefs->client($client)->get('alarmplaylist')->[ $day ];
	my @allPlaylists = (
		{
			text    => $client->string("CURRENT_PLAYLIST"),
			radio	=> ($alarm_playlist ne '' && 
				$Slim::Utils::Alarms::possibleSpecialPlaylistsIDs{$alarm_playlist} == -1) + 0, # 0 is added to force the data type to number
			
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd         => 'update',
						playlist_id => '-1',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => $client->string("PLUGIN_RANDOM_TRACK"),
			radio	=> ($alarm_playlist ne '' && 
				$Slim::Utils::Alarms::possibleSpecialPlaylistsIDs{$alarm_playlist} == -2) + 0, # 0 is added to force the data type to number
			
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd         => 'update',
						playlist_id => '-2',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => $client->string("PLUGIN_RANDOM_ALBUM"),
			radio	=> ($alarm_playlist ne '' && 
				$Slim::Utils::Alarms::possibleSpecialPlaylistsIDs{$alarm_playlist} == -3) + 0, # 0 is added to force the data type to number
			
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd         => 'update',
						playlist_id => '-3',
						dow         => $day,
					},
				},
			},
		},
		{
			text    => $client->string("PLUGIN_RANDOM_CONTRIBUTOR"),
			radio	=> ($alarm_playlist ne '' && 
				$Slim::Utils::Alarms::possibleSpecialPlaylistsIDs{$alarm_playlist} == -4) + 0, # 0 is added to force the data type to number
			
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd         => 'update',
						playlist_id => '-4',
						dow         => $day,
					},
				},
			},
		},
	);
	## here we need to figure out how to populate the remaining playlist items from saved playlists
	push @allPlaylists, getCustomPlaylists($client,$alarm_playlist,$day);

	my %return = 
	( 
		text => $client->string("ALARM_SELECT_PLAYLIST"),
		count     => scalar @allPlaylists,
		offset    => 0,
		item_loop => \@allPlaylists,
	);
	return \%return;
}

sub getCustomPlaylists {
	my ($client, $alarm_playlist, $day) = @_;
	
	my @return = ();
	
	for my $playlist (Slim::Schema->rs('Playlist')->getPlaylists) {
		push @return,{
			text    => Slim::Music::Info::standardTitle($client,$playlist->url),
			radio	=> ($alarm_playlist ne '' && $alarm_playlist eq $playlist->url) + 0, # 0 is added to force the data type to number
			
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd         => 'update',
						playlist_id => $playlist->id,
						dow         => $day,
					},
				},
			},
		};
	}
	
	return @return;
}

sub alarmVolumeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmvolume')->[ $day ];
	my @vol_settings;
	for (my $i = 10; $i <= 100; $i = $i + 10) {
		my %hash = (
			text    => $i,
			radio   => ($i == $current_setting) + 0,
			actions => {
				do => {
					player => 0,
					cmd    => ['alarm'],
					params => {
						cmd => 'update',
						volume => $i,
						dow => $day,
					},
				},
			},
		);
		push @vol_settings, \%hash;
	}
	my %return = 
	( 
		text      => $client->string("ALARM_SET_VOLUME"),
		count     => 10,
		offset    => 0,
		item_loop => \@vol_settings,
	);
	return \%return;
}

sub alarmFadeHash {
	my ($client, $prefs, $day) = @_;
	my $current_setting = $prefs->client($client)->get('alarmfadeseconds');
	my %return = 
	( 
		text     => $client->string("ALARM_FADE"),
		checkbox => ($current_setting > 0) + 0,
		actions  => {
			on  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'update',
					dow     => 0,
					fade    => 1,
				},
			},
			off  => {
				player => 0,
				cmd    => ['alarm'],
				params => { 
					cmd     => 'update',
					dow     => 0,
					fade    => 0,
				},
			},
		},
	);
	return \%return;
}

sub populateAlarmElements {
	my $client = shift;
	my $day = shift;
	my $prefs = preferences("server");

	my $alarm_on       = alarmOnHash($client, $prefs, $day);
	my $alarm_set      = alarmSetHash($client, $prefs, $day);
	my $alarm_playlist = alarmPlaylistHash($client, $prefs, $day);
	my $alarm_volume   = alarmVolumeHash($client, $prefs, $day);
	my $alarm_fade     = alarmFadeHash($client, $prefs, $day);

	my @return = ( 
		$alarm_on,
		$alarm_set,
		$alarm_playlist,
		$alarm_volume,
	);
	push @return, $alarm_fade if $day == 0;
	#Data::Dump::dump(@return) if $day == 1;
	return \@return;
}

sub populateAlarmHash {
	my $client = shift;
	my $day = shift;
	my $elements = populateAlarmElements($client, $day);
	my $string = 'ALARM_DAY' . $day;
	my %return = (
		text      => $client->string($string),
		count     => scalar(@$elements),
		offset    => 0,
		item_loop => $elements,
	);
	return \%return;
}

sub playerPower {

	my $client = shift;
	my $batch = shift;

	return [] unless blessed($client)
		&& $client->isPlayer() && $client->canPowerOff();

	my $name  = $client->name();
	my $power = $client->power();
	my @return; 
	my ($text, $action);

	if ($power == 1) {
		$text = sprintf($client->string('JIVE_TURN_PLAYER_OFF'), $name);
		$action = 0;
	} else {
		$text = sprintf($client->string('JIVE_TURN_PLAYER_ON'), $name);
		$action = 1;
	}

	push @return, {
		text           => $text,
		id             => 'playerpower',
		node           => 'home',
		displayWhenOff => 1,
		weight         => 100,
		actions        => {
			do  => {
				player => 0,
				cmd    => ['power', $action],
				},
			},
	};

	if ($batch) {
		return \@return;
	} else {
		# send player power info by notification
		_notifyJive(\@return, $client);
	}

}

sub sleepInXHash {
	$log->info("Begin function");
	my ($client, $val, $sleepTime) = @_;
	my $minutes = $client->string('MINUTES');
	my $text = $sleepTime == 0 ? 
		$client->string("SLEEP_CANCEL") :
		$sleepTime . " " . $minutes;
	my %return = ( 
		text    => $text,
		radio	=> ($val == ($sleepTime*60)) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['sleep', $sleepTime*60 ],
			},
		},
	);
	return \%return;
}

sub transitionHash {
	
	my ($client, $val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => $client->string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playerpref', 'transitionType', "$thisValue" ],
			},
		},
	);
	return \%return;
}

sub replayGainHash {
	
	my ($client, $val, $prefs, $strings, $thisValue) = @_;
	my %return = (
		text    => $client->string($strings->[$thisValue]),
		radio	=> ($val == $thisValue) + 0, # 0 is added to force the data type to number
		actions => {
			do => {
				player => 0,
				cmd => ['playerpref', 'replayGainMode', "$thisValue"],
			},
		},
	);
	return \%return;
}

sub myMusicMenu {
	$log->info("Begin function");
	my $batch = shift;
	my $client = shift || undef;
	my @myMusicMenu = (
			{
				text           => $client->string('BROWSE_BY_ARTIST'),
				id             => 'myMusicArtists',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 10,
				actions        => {
					go => {
						cmd    => ['artists'],
						params => {
							menu => 'album',
						},
					},
				},
				window        => {
					titleStyle => 'artists',
				},
			},		
			{
				text           => $client->string('BROWSE_BY_ALBUM'),
				id             => 'myMusicAlbums',
				node           => 'myMusic',
				weight         => 20,
				displayWhenOff => 0,
				actions        => {
					go => {
						cmd    => ['albums'],
						params => {
							menu     => 'track',
						},
					},
				},
				window         => {
					menuStyle => 'album',
					menuStyle => 'album',
					titleStyle => 'albumlist',
				},
			},
			{
				text           => $client->string('BROWSE_BY_GENRE'),
				id             => 'myMusicGenres',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 30,
				actions        => {
					go => {
						cmd    => ['genres'],
						params => {
							menu => 'artist',
						},
					},
				},
				window        => {
					titleStyle => 'genres',
				},
			},
			{
				text           => $client->string('BROWSE_BY_YEAR'),
				id             => 'myMusicYears',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 40,
				actions        => {
					go => {
						cmd    => ['years'],
						params => {
							menu => 'album',
						},
					},
				},
				window        => {
					titleStyle => 'years',
				},
			},
			{
				text           => $client->string('BROWSE_NEW_MUSIC'),
				id             => 'myMusicNewMusic',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 50,
				actions        => {
					go => {
						cmd    => ['albums'],
						params => {
							menu => 'track',
							sort => 'new',
						},
					},
				},
				window        => {
					menuStyle => 'album',
					titleStyle => 'newmusic',
				},
			},
			{
				text           => $client->string('SAVED_PLAYLISTS'),
				id             => 'myMusicPlaylists',
				node           => 'myMusic',
				displayWhenOff => 0,
				weight         => 80,
				actions        => {
					go => {
						cmd    => ['playlists'],
						params => {
							menu => 'track',
						},
					},
				},
				window        => {
					titleStyle => 'playlist',
				},
			},
			{
				text           => $client->string('SEARCH'),
				id             => 'myMusicSearch',
				node           => 'myMusic',
				isANode        => 1,
				displayWhenOff => 0,
				weight         => 90,
				window         => { titleStyle => 'search', },
			},
		);
	# add the items for under mymusicSearch
	my $searchMenu = searchMenu(1, $client);
	@myMusicMenu = (@myMusicMenu, @$searchMenu);

	if (my $browseMusicFolder = browseMusicFolder($client, 1)) {
		push @myMusicMenu, $browseMusicFolder;
	}

	if ($batch) {
		return \@myMusicMenu;
	} else {
		_notifyJive(\@myMusicMenu, $client);
	}

}

sub searchMenu {
	$log->info("Begin function");
	my $batch = shift;
	my $client = shift || undef;
	my @searchMenu = (
	{
		text           => $client->string('ARTISTS'),
		id             => 'myMusicSearchArtists',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 10,
		input => {
			len  => 1, #bug 5318
			processingPopup => {
				text => $client->string('SEARCHING'),
			},
			help => {
				text => $client->string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['artists'],
				params => {
					menu     => 'album',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'artists',
				},
                        },
		},
                window => {
                        text => $client->string('SEARCHFOR_ARTISTS'),
                        titleStyle => 'search',
                },
	},
	{
		text           => $client->string('ALBUMS'),
		id             => 'myMusicSearchAlbums',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 20,
		input => {
			len  => 1, #bug 5318
			processingPopup => {
				text => $client->string('SEARCHING'),
			},
			help => {
				text => $client->string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['albums'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
					_searchType => 'albums',
				},
			},
		},
		window => {
			text => $client->string('SEARCHFOR_ALBUMS'),
			titleStyle => 'search',
			menuStyle  => 'album',
		},
	},
	{
		text           => $client->string('SONGS'),
		id             => 'myMusicSearchSongs',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 30,
		input => {
			len  => 1, #bug 5318
			processingPopup => {
				text => $client->string('SEARCHING'),
			},
			help => {
				text => $client->string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['tracks'],
				params => {
					menu     => 'track',
					menuStyle => 'album',
					menu_all => '1',
					search   => '__TAGGEDINPUT__',
					_searchType => 'tracks',
				},
                        },
		},
		window => {
			text => $client->string('SEARCHFOR_SONGS'),
			titleStyle => 'search',
			menuStyle => 'album',
		},
	},
	{
		text           => $client->string('PLAYLISTS'),
		id             => 'myMusicSearchPlaylists',
		node           => 'myMusicSearch',
		displayWhenOff => 0,
		weight         => 40,
		input => {
			len  => 1, #bug 5318
			processingPopup => {
				text => $client->string('SEARCHING'),
			},
			help => {
				text => $client->string('JIVE_SEARCHFOR_HELP')
			},
		},
		actions => {
			go => {
				cmd => ['playlists'],
				params => {
					menu     => 'track',
					search   => '__TAGGEDINPUT__',
				},
                        },
		},
		window => {
			text => $client->string('SEARCHFOR_PLAYLISTS'),
			titleStyle => 'search',
		},
	},
	);

	if ($batch) {
		return \@searchMenu;
	} else {
		_notifyJive(\@searchMenu, $client);
	}

}

# send a notification for menustatus
sub menuNotification {
	$log->warn("Menustatus notification sent.");
	# the lines below are needed as menu notifications are done via notifyFromArray, but
	# if you wanted to debug what's getting sent over the Comet interface, you could do it here
	my $request  = shift;
	my $dataRef          = $request->getParam('_data')   || return;
	my $action   	     = $request->getParam('_action') || 'add';
#	$log->warn(Data::Dump::dump($dataRef));
}

sub jivePlaylistsCommand {

	$log->info("Begin function");
	my $request    = shift;
	my $client     = $request->client || return;
	my $title      = $request->getParam('title');
	my $url        = $request->getParam('url');
	my $command    = $request->getParam('_cmd');
	my $playlistID = $request->getParam('playlist_id');
	my $token      = uc($command); 
	my @delete_menu= (
		{
			text    => $client->string('CANCEL'),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'jiveblankcommand' ],
				},
			},
			nextWindow => 'parent',
		}
	);
	my $actionItem = {
		text    => $client->string($token) . ' ' . $title,
		actions => {
			go => {
				player => 0,
				cmd    => ['playlists', 'delete'],
				params => {
					playlist_id    => $playlistID,
					title          => $title,
					url            => $url,
				},
			},
		},
		nextWindow => 'grandparent',
	};
	push @delete_menu, $actionItem;

	$request->addResult('offset', 0);
	$request->addResult('count', 2);
	$request->addResult('item_loop', \@delete_menu);
	$request->addResult('window', { titleStyle => 'playlist' } );

	$request->setStatusDone();

}

sub jiveFavoritesCommand {

	$log->info("Begin function");
	my $request = shift;
	my $client  = $request->client || shift;
	my $title   = $request->getParam('title');
	my $url     = $request->getParam('url');
	my $command = $request->getParam('_cmd');
	my $token   = uc($command); # either ADD or DELETE
	my $action = $command eq 'add' ? 'parent' : 'grandparent';
	my $favIndex = defined($request->getParam('item_id'))? $request->getParam('item_id') : undef;
	my @favorites_menu = (
		{
			text    => $client->string('CANCEL'),
			actions => {
				go => {
					player => 0,
					cmd    => [ 'jiveblankcommand' ],
				},
			},
			nextWindow => 'parent',
		}
	);
	my $actionItem = {
		text    => $client->string($token) . ' ' . $title,
		actions => {
			go => {
				player => 0,
				cmd    => ['favorites', $command ],
				params => {
						title => $title,
						url   => $url,
				},
			},
		},
		nextWindow => $action,
	};
	$actionItem->{'actions'}{'go'}{'params'}{'item_id'} = $favIndex if defined($favIndex);
	push @favorites_menu, $actionItem;

	$request->addResult('offset', 0);
	$request->addResult('count', 2);
	$request->addResult('item_loop', \@favorites_menu);
	$request->addResult('window', { titleStyle => 'favorites' } );


	$request->setStatusDone();

}


# The following allow download of applets, wallpaper and sounds from SC to jive
# Files may be packaged in a plugin or can be added individually via the api below.
#
# In the case of downloads packaged as a plugin, each downloadable file should be 
# available in the 'jive' folder of a plugin and the plugin install.xml file should refer
# to it in the following format:
#
# <jive>
#    <applet>
#       <version>0.1</version>
#       <name>Applet1</name>
#       <file>Applet1.zip</file>
#    </applet>
#    <wallpaper>
#       <name>Wallpaper1</name>
#       <file>Wallpaper1.png</file>
#    </wallpaper>			
#    <wallpaper>
#       <name>Wallpaper2</name>
#       <file>Wallpaper2.png</file>
#    </wallpaper>	
#    <sound>
#       <name>Sound1</name>
#       <file>Sound1.wav</file>
#    </sound>	
# </jive>
#
# Alternatively individual wallpaper and sound files may be registered by the 
# registerDownload and deleteDownload api calls.

# file types allowed for downloading to jive
my %filetypes = (
	applet    => qr/\.zip$/,
	wallpaper => qr/\.(bmp|jpg|jpeg|png)$|^http:\/\//,
	sound     => qr/\.wav$/,
);

# addditional downloads
my %extras = (
	wallpaper => {},
	sound     => {},
	applet    => {},
);

=head2 registerDownload()

Register a local file or url for downloading to jive as a wallpaper, sound file or applet
$type : either 'wallpaper', 'sound' or 'applet'
$name : description to show on jive
$path : fullpath for file on server or http:// url
$key  : (optional) unique key for this type to avoid using file's basename
$vers : version (applets only)

=cut

sub registerDownload {
	my $type = shift;
	my $name = shift;
	my $path = shift;
	my $key  = shift;
	my $vers = shift;

	my $file = $key || basename($path);

	if ($type =~ /wallpaper|sound|applet/ && $path =~ $filetypes{$type} && (-r $path || $path =~ /^http:\/\//)) {

		$log->info("registering download for $type $name $file $path");

		$extras{$type}->{$file} = {
			'name'    => $name,
			'path'    => $path,
			'file'    => $file,
		};

		if ($type eq 'applet') {
			$extras{$type}->{$file}->{'version'} = $vers;
		}

	} else {
		$log->warn("unable to register download for $name $type $file");
	}
}

=head2 deleteDownload()

Remove previously registered download entry.
$type : either 'wallpaper', 'sound' or 'applet'
$path : fullpath for file on server or http:// url
$key  : (optional) unique key for this type to avoid using file's basename

=cut

sub deleteDownload {
	my $type = shift;
	my $path = shift;
	my $key  = shift;

	my $file = $key || basename($path);

	if ($type =~ /wallpaper|sound|applet/ && $extras{$type}->{$file}) {

		$log->info("removing download for $type $file");
		delete $extras{$type}->{$file};

	} else {
		$log->warn("unable remove download for $type $file");
	}
}

# downloadable file info from the plugin instal.xml and any registered additions
sub _downloadInfo {
	my $type = shift;

	my $plugins = Slim::Utils::PluginManager::allPlugins();
	my $ret = {};

	for my $key (keys %$plugins) {

		if ($plugins->{$key}->{'jive'} && $plugins->{$key}->{'jive'}->{$type}) {

			my $info = $plugins->{$key}->{'jive'}->{$type};
			my $dir  = $plugins->{$key}->{'basedir'};

			if ($info->{'name'}) {

				my $file = $info->{'file'};

				if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

					if ($ret->{$file}) {
						$log->warn("duplicate filename for download: $file");
					}

					$ret->{$file} = {
						'name'    => $info->{'name'},
						'path'    => catdir($dir, 'jive', $file),
						'file'    => $file,
						'version' => $info->{'version'},
					};

				} else {
					$log->warn("unable to make $key:$file available for download");
				}

			} elsif (ref $info eq 'HASH') {

				for my $name (keys %$info) {

					my $file = $info->{$name}->{'file'};

					if ( $file =~ $filetypes{$type} && -r catdir($dir, 'jive', $file) ) {

						if ($ret->{$file}) {
							$log->warn("duplicate filename for download: $file [$key]");
						}

						$ret->{$file} = {
							'name'    => $name,
							'path'    => catdir($dir, 'jive', $file),
							'file'    => $file,
							'version' => $info->{$name}->{'version'},
						};

					} else {
						$log->warn("unable to make $key:$file available for download");
					}
				}
			}
		}
	}

	# add extra downloads as registered via api
	for my $key (keys %{$extras{$type}}) {
		$ret->{$key} = $extras{$type}->{$key};
	}

	return $ret;
}

# return all files available for download based on query type
sub downloadQuery {
	my $request = shift;
 
	my ($type) = $request->getRequest(0) =~ /jive(applet|wallpaper|sound)s/;

	if (!defined $type) {
		$request->setStatusBadDispatch();
		return;
	}

	my $prefs = preferences("server");

	my $cnt = 0;
	my $urlBase = 'http://' . Slim::Utils::Network::serverAddr() . ':' . $prefs->get('httpport') . "/jive$type/";

	for my $val ( sort { $a->{'name'} cmp $b->{'name'} } values %{_downloadInfo($type)} ) {

		my $url = $val->{'path'} =~ /^http:\/\// ? $val->{'path'} : $urlBase . $val->{'file'};

		my $entry = {
			$type     => $val->{'name'},
			'name'    => Slim::Utils::Strings::getString($val->{'name'}),
			'url'     => $url,
			'file'    => $val->{'file'},
		};

		if ($val->{'path'} !~ /^http:\/\//) {
			$entry->{'relurl'} = URI->new($url)->path;
		}

		if ($type eq 'applet') {
			$entry->{'version'} = $val->{'version'};
		}

		$request->setResultLoopHash('item_loop', $cnt++, $entry);
	}	

	$request->addResult("count", $cnt);

	$request->setStatusDone();
}

# convert path to location for download
sub downloadFile {
	my $path = shift;

	my ($type, $file) = $path =~ /^jive(applet|wallpaper|sound)\/(.*)/;

	my $info = _downloadInfo($type);

	if ($info->{$file}) {

		return $info->{$file}->{'path'};

	} else {

		$log->warn("unable to find file: $file for type: $type");
	}
}

1;
