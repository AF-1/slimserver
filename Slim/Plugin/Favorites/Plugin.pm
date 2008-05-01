package Slim::Plugin::Favorites::Plugin;

# $Id$

# A Favorites implementation which stores favorites as opml files and allows
# the favorites list to be edited from the web interface

# Includes code from the MyPicks plugin by Adrian Smith and Bryan Alton

# This code is derived from code with the following copyright message:
#
# SqueezeCenter Copyright 2005-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use base qw(Slim::Plugin::Base);

use Tie::Cache::LRU;

use Slim::Buttons::Common;
use Slim::Web::XMLBrowser;
use Slim::Utils::Favorites;
use Slim::Utils::Log;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Music::Info;
use Slim::Utils::Prefs;

use Slim::Plugin::Favorites::Opml;
use Slim::Plugin::Favorites::OpmlFavorites;
use Slim::Plugin::Favorites::Settings;
use Slim::Plugin::Favorites::Playlist;

my $log = logger('favorites');

my $prefs = preferences('plugin.favorites');

# support multiple edditing sessions at once - indexed by sessionId.  [Default to favorites editting]
my $nextSession = 2; # session id 1 = favorites
tie my %sessions, 'Tie::Cache::LRU', 4;

sub initPlugin {
	my $class = shift;

	$class->SUPER::initPlugin(@_);

	Slim::Plugin::Favorites::Settings->new;

	# register opml based favorites handler
	Slim::Utils::Favorites::registerFavoritesClassName('Slim::Plugin::Favorites::OpmlFavorites');

	# register handler for playing favorites by remote hot button
	Slim::Buttons::Common::setFunction('playFavorite', \&playFavorite);

	# register cli handlers
	Slim::Control::Request::addDispatch(['favorites', 'items', '_index', '_quantity'], [0, 1, 1, \&cliBrowse]);
	Slim::Control::Request::addDispatch(['favorites', 'add'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'addlevel'], [0, 0, 1, \&cliAdd]);
	Slim::Control::Request::addDispatch(['favorites', 'delete'], [0, 0, 1, \&cliDelete]);
	Slim::Control::Request::addDispatch(['favorites', 'rename'], [0, 0, 1, \&cliRename]);
	Slim::Control::Request::addDispatch(['favorites', 'move'], [0, 0, 1, \&cliMove]);
	Slim::Control::Request::addDispatch(['favorites', 'playlist', '_method' ],[1, 1, 1, \&cliBrowse]);
	
	# register notifications
	Slim::Control::Request::addDispatch(['favorites', 'changed'], [0, 0, 0, undef]);

	# register new mode for deletion of favorites	
	Slim::Buttons::Common::addMode( 'favorites.delete', {}, \&deleteMode );
}


sub modeName { 'FAVORITES' };

sub setMode {
	my $class = shift;
	my $client = shift;
	my $method = shift;

	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}

	# use INPUT.Choice to display the list of feeds
	my %params = (
		header   => 'PLUGIN_FAVORITES_LOADING',
		modeName => 'Favorites.Browser',
		url      => Slim::Plugin::Favorites::OpmlFavorites->new($client)->fileurl,
		title    => $client->string('FAVORITES'),
	);

	Slim::Buttons::Common::pushMode($client, 'xmlbrowser', \%params);

	# we'll handle the push in a callback
	$client->modeParam('handledTransition',1)
}

sub deleteMode {
	my ( $client, $method ) = @_;
	
	if ( $method eq 'pop' ) {
		Slim::Buttons::Common::popMode($client);
		return;
	}
	
	my $title = $client->modeParam('title'); # title to display
	my $index = $client->modeParam('index'); # favorite index to delete
	my $hotkey= $client->modeParam('hotkey');# favorite hotkey
	my $depth = $client->modeParam('depth'); # number of levels to pop out of when done
	
	# Bug 6177, Menu to confirm favorite removal
	Slim::Buttons::Common::pushMode( $client, 'INPUT.Choice', {
		header   => '{FAVORITES_FAVORITE} ' . (defined $hotkey ? $hotkey : ''),
		title    => $title,
		favorite => $index,
		listRef  => [
			{
				name    => "{PLUGIN_FAVORITES_CANCEL}",
				onRight => sub {
					Slim::Buttons::Common::popModeRight(shift);
				},
			},
			{
				name    => "{FAVORITES_RIGHT_TO_DELETE}",
				onRight => sub {
					my $client = shift;
					my $index  = $client->modeParam('favorite');
					
					my $favorites = Slim::Utils::Favorites->new($client);					
					$favorites->deleteIndex($index);
					
					$client->modeParam( 'favorite', undef );
					
					$client->showBriefly( {
						line => [ $client->string('FAVORITES_DELETING'), $title ],
					},
					{
						callback     => sub {
							my $client = shift || return;
							
							# Pop back until we're out of Favorites
							for ( 1 .. $depth ) {
								Slim::Buttons::Common::popModeRight($client);
							}
							
							$client->update;
						},
						callbackargs => $client,
					} );
				},
			},
		],
		overlayRef => [ undef, $client->symbols('rightarrow') ],
	} );
}

sub playFavorite {
	my $client = shift;
	my $button = shift;
	my $digit  = shift;

	my $favs  = Slim::Utils::Favorites->new($client);

	# play the favorite with the hotkey of $digit, or if not set the favorite with index $digit
	my $index = $favs->hasHotkey($digit);
	my $entry = defined $index ? $favs->entry($index) : $favs->entry($digit ? $digit-1 : 9);

	if (defined $entry && $entry->{'type'} && $entry->{'type'} eq 'audio') {

		my $url   = $entry->{'URL'} || $entry->{'url'};
		my $title = $entry->{'title'};

		$log->info("Playing favorite number $digit $title $url");

		Slim::Music::Info::setTitle($url, $title);

		$client->execute(['playlist', 'play', $url]);

		$client->showBriefly($client->currentSongLines(undef, Slim::Buttons::Common::suppressStatus($client)));

	} else {

		$log->info("Can't play favorite number $digit - not an audio entry");

		$client->showBriefly({
			 'line' => [ sprintf($client->string('FAVORITES_NOT_DEFINED'), $digit) ],
		});
	}
}

sub webPages {
	my $class = shift;

	Slim::Web::HTTP::addPageFunction('plugins/Favorites/favcontrol.html', \&toggleButtonHandler);
	Slim::Web::HTTP::addPageFunction('plugins/Favorites/index.html', \&indexHandler);

	Slim::Web::Pages->addPageLinks('browse', { 'FAVORITES' => 'plugins/Favorites/index.html' });

	addEditLink();
}

sub addEditLink {
	my $enabled = $prefs->get('opmleditor');

	Slim::Web::Pages->addPageLinks('plugins', {	'PLUGIN_FAVORITES_PLAYLIST_EDITOR' => $enabled ? 'plugins/Favorites/index.html?new' : undef });
}

sub toggleButtonHandler {
	my $client = shift;
	my $params = shift;

	my $favs = Slim::Utils::Favorites->new($client);

	$params->{favoritesEnabled} = 1;
	$params->{itemobj} = {
		url => $params->{url}, 
		title => $params->{title},
	};

	if ($favs && $params->{url}) {

		if ($favs->findUrl($params->{url})) {

			$favs->deleteUrl( $params->{'url'} );
			$params->{item}->{isFavorite} = 0;
		}

		else {

			$favs->add( $params->{url}, $params->{title} || $params->{url} );
			$params->{item}->{isFavorite} = $favs->findUrl($params->{url});
		}
	}

	return Slim::Web::HTTP::filltemplatefile('plugins/Favorites/favcontrol.html', $params);
}

sub indexHandler {
	my $client = shift;
	my $params = shift;

	# Debug:
	#for my $key (keys %$params) {
	#	print "Key: $key, Val: ".$params->{$key}."\n";
	#}

	my $opml;     # opml hash for current editing session
	my $deleted;  # any deleted sub tree which may be added back
	my $autosave; # save each change
	my $sessId;   # current editing session id

	my $edit;     # index of entry to edit if set
	my $changed;  # opml has been changed

	if ($params->{'sess'} && $sessions{ $params->{'sess'} }) {

		$sessId = $params->{'sess'};

		$log->info("existing editing session [$sessId]");

		$opml     = $sessions{ $sessId }->{'opml'};
		$deleted  = $sessions{ $sessId }->{'deleted'};
		$autosave = $sessions{ $sessId }->{'autosave'};

	} elsif ($params->{'sess'} && $params->{'sess'} > 1 || $params->{'new'}) {

		my $url   = $params->{'new'};

		$sessId   = $nextSession++;
		$deleted  = undef;
		$autosave = $params->{'autosave'};

		if (Slim::Music::Info::isURL($url)) {

			$log->info("new opml editting session [$sessId] - opening $url");

			$opml = Slim::Plugin::Favorites::Opml->new({ 'url' => $url });

		} else {

			$log->info("new opml editing session [$sessId]");

			$opml = Slim::Plugin::Favorites::Opml->new();
		}

	} else {

		$log->info("new favorites editing session");

		$opml = Slim::Plugin::Favorites::OpmlFavorites->new($client);
		$deleted  = undef;
		$autosave = 1;
		$sessId   = 1;
	}

	# get the level to operate on - this is the level containing the index if action is set, otherwise the level specified by index
	my ($level, $indexLevel, @indexPrefix) = $opml->level($params->{'index'}, defined $params->{'action'});

	if (!defined $level || $params->{'action'} =~ /^play|^add/) {

		if ($sessId == 1) {
			# favorites editor cannot follow remote links, so pass through to xmlbrowser as index does not appear to be edittable
			# also pass through play/add to reuse xmlbrowser handling of playall etc
			$log->info("passing through to xmlbrowser");
			
			return Slim::Web::XMLBrowser->handleWebIndex( {
				client => $client,
				feed   => $opml->xmlbrowser,
				args   => [$client, $params, @_],
			} );

		} else {
			# this is not the favorites session - if we pass through to xmlbrowser we loose session state, so dissable for now
			return;
		}
	}

	# if not editting favorites create favs class so we can add or delete urls from favorites
	my $favs = $opml->isa('Slim::Plugin::Favorites::OpmlFavorites') ? undef : Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if ($params->{'loadfile'}) {

		my $url = $params->{'filename'};

		if (Slim::Music::Info::isRemoteURL($url)) {

			if (!$params->{'fetched'}) {
				Slim::Networking::SimpleAsyncHTTP->new(
					\&asyncCBContent, \&asyncCBContent, { 'args' => [$client, $params, @_] }
				)->get( $url );
				return;
			}

			$opml->load({ 'url' => $url, 'content' => $params->{'fetchedcontent'} });

		} else {

			$opml->load({ 'url' => $url });
		}

		($level, $indexLevel, @indexPrefix) = $opml->level(undef, undef);
		$deleted = undef;
	}

	if ($params->{'savefile'} || $params->{'savechanged'}) {

		$opml->filename($params->{'filename'}) if $params->{'savefile'};

		$opml->save;

		$changed = undef unless $opml->error;

		if ($favs && $opml != $favs && $opml->filename eq $favs->filename) {
			# overwritten the favorites file - force favorites to be reloaded
			$favs->load;
		}
	}

	if ($params->{'importfile'}) {

		my $url = $params->{'filename'};
		my $playlist;

		if ($url =~ /\.opml$/) {

			if (Slim::Music::Info::isRemoteURL($url)) {

				if (!$params->{'fetched'}) {
					Slim::Networking::SimpleAsyncHTTP->new(
						\&asyncCBContent, \&asyncCBContent,	{ 'args' => [$client, $params, @_] }
					)->get( $url );
					return;
				}

				$playlist = Slim::Plugin::Favorites::Opml->new({ 'url' => $url, 'content' => $params->{'fetchedcontent'} })->toplevel;

			} else {

				$playlist = Slim::Plugin::Favorites::Opml->new({ 'url' => $url })->toplevel;
			}

		} else {

			$playlist = Slim::Plugin::Favorites::Playlist->read($url);
		}

		if ($playlist && scalar @$playlist) {

			for my $entry (@$playlist) {
				push @$level, $entry;
			}

			$changed = 1;

		} else {

			$params->{'errormsg'} = string('PLUGIN_FAVORITES_IMPORTERROR') . " " . $url;
		}
	}

	if ($params->{'title'}) {
		$opml->title( $params->{'title'} );
	}

	if (my $action = $params->{'action'}) {

		if ($action eq 'edit') {
			$edit = $indexLevel;
		}

		if ($action eq 'delete') {

			$deleted = splice @$level, $indexLevel, 1;

			$changed = 1;
		}

		if ($action eq 'move' && defined $params->{'to'} && $params->{'to'} < scalar @$level) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $params->{'to'}, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'movedown') {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel + 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'moveup' && $indexLevel > 0) {

			my $entry = splice @$level, $indexLevel, 1;

			splice @$level, $indexLevel - 1, 0, $entry;

			$changed = 1;
		}

		if ($action eq 'editset' && defined $params->{'index'}) {

			if ($params->{'cancel'} && $params->{'removeoncancel'}) {

				# cancel on a new item - remove it
				splice @$level, $indexLevel, 1;

			} elsif ($params->{'entrytitle'}) {

				# editted item - modify including possibly changing type
				my $entry = @$level[$indexLevel];

				$entry->{'text'} = $params->{'entrytitle'};

				if (defined $params->{'entryurl'} && $params->{'entryurl'} ne $entry->{'URL'}) {

					my $url = $params->{'entryurl'};

					if ($url !~ /^http:/) {

						if ($url !~ /\.(xml|opml|rss)$/) {
							
							$entry->{'type'} = 'audio';
							
						} else {
							
							delete $entry->{'type'};
						}
						
					} elsif (!$params->{'fetched'}) {
						
						$log->info("checking content type for $url");
						
						Slim::Networking::Async::HTTP->new()->send_request( {
							'request'     => HTTP::Request->new( GET => $url ),
							'onHeaders'   => \&asyncCBContentType,
							'onError'     => \&asyncCBContentTypeError,
							'passthrough' => [ $client, $params, @_ ],
						} );
						
						return;
						
					} else {

						my $mime = $params->{'fetchedtype'} || 'error';
						my $type = Slim::Music::Info::mimeToType($mime);

						if ($type) {

							$log->info("got mime type $mime");

						} else {

							$log->info("unknown mime type $mime, inferring from url");

							$type = Slim::Music::Info::typeFromPath($url);
						}

						if (Slim::Music::Info::isSong(undef, $type) || Slim::Music::Info::isPlaylist(undef, $type)) {
							
							$log->info("content type $type - treating as audio");
							
							$entry->{'type'} = 'audio';
							
						} else {
							
							$log->info("content type $type - treating as non audio");

							delete $entry->{'type'};
						}
					}

					$entry->{'URL'} = $url;
				}

				if (!$favs) {

					my $hotkey = $params->{'entryhotkey'};

					if (!defined $hotkey || $hotkey eq '') {

						$log->info("removing hotkey from entry");

						delete $entry->{'hotkey'};

					} else {

						my $oldindex = $opml->hasHotkey($hotkey);

						if (defined $oldindex) {

							$opml->setHotkey($oldindex, undef);
						}

						$log->info("setting hotkey for entry to $hotkey");

						$entry->{'hotkey'} = $hotkey;
					}
				}
			}

			$changed = 1;
		}

		if ($action eq 'favadd' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->add( $entry->{'URL'}, $entry->{'text'}, $entry->{'type'}, $entry->{'parser'} );
		}

		if ($action eq 'favdel' && defined $params->{'index'} && $favs) {

			my $entry = @$level[$indexLevel];

			$favs->deleteUrl( $entry->{'URL'} );
		}

		if ($action eq 'hotkey' && defined $params->{'index'} && $opml->isa('Slim::Plugin::Favorites::OpmlFavorites')) {

			$opml->setHotkey( $params->{'index'}, $params->{'hotkey'} ne '' ? $params->{'hotkey'} : undef );
		}
	}

	if ($params->{'forgetdelete'}) {

		$deleted = undef;
	}

	if ($params->{'insert'} && $deleted) {

		push @$level, $deleted;

		$deleted = undef;
		$changed = 1;
	}

	if ($params->{'newentry'}) {

		push @$level,{
			'text' => string('PLUGIN_FAVORITES_NAME'),
			'URL'  => string('PLUGIN_FAVORITES_URL'),
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	if ($params->{'newlevel'}) {

		push @$level, {
			'text'   => string('PLUGIN_FAVORITES_NAME'),
			'outline'=> [],
		};

		$edit = scalar @$level - 1;
		$params->{'removeoncancel'} = 1;
		$changed = 1;
	}

	# save session data for next call
	$sessions{ $sessId } = {
		'opml'     => $opml,
		'deleted'  => $deleted,
		'autosave' => $autosave,
	};

	# save each change if autosave set
	if ($changed && $opml && $autosave) {
		$opml->save;
	}

	# set params for page build
	$params->{'sess'}      = $sessId;
	$params->{'favorites'} = !$favs;
	$params->{'title'}     = $opml->title;
	$params->{'filename'}  = $opml->filename;
	$params->{'deleted'}   = defined $deleted ? $deleted->{'text'} : undef;
	$params->{'editmode'}  = defined $edit;
	$params->{'autosave'}  = $autosave;

	if ($opml && $opml->error) {
		$params->{'errormsg'} = string('PLUGIN_FAVORITES_' . $opml->error) . " " . $opml->filename;
		$opml->clearerror;
	}

	# add the entries for current level
	my @entries;
	my $i = 0;

	foreach my $opmlEntry (@$level) {
		my $entry = {
			'title'   => $opmlEntry->{'text'} || '',
			'url'     => $opmlEntry->{'URL'} || $opmlEntry->{'url'} || '',
			'audio'   => (defined $opmlEntry->{'type'} && $opmlEntry->{'type'} eq 'audio'),
			'outline' => $opmlEntry->{'outline'},
			'edit'    => (defined $edit && $edit == $i),
			'index'   => join '.', (@indexPrefix, $i++),
		};

		if ($favs && $entry->{'url'}) {
			$entry->{'favorites'} = $favs->hasUrl($entry->{'url'}) ? 2 : 1;
		}

		if (!$favs && defined $opmlEntry->{'hotkey'}) {
			$entry->{'hotkey'} = $opmlEntry->{'hotkey'};
		}

		push @entries, $entry;
	}

	$params->{'entries'}       = \@entries;
	$params->{'levelindex'}    = join '.', @indexPrefix;
	$params->{'indexOnLevel'}  = $indexLevel;

	# for favorites add the currently used hotkeys
	if (!$favs) {
		$params->{'hotkeys'}   = $opml->hotkeys;
	}

	# add the top level title to pwd_list
	push @{$params->{'pwd_list'}}, {
		'title' => $opml && $opml->title || string('PLUGIN_FAVORITES_EDITOR'),
		'href'  => 'href="index.html?index=&sess=' . $sessId . '"',
	};

	# add remaining levels up to current level to pwd_list
	for (my $i = 0; $i <= $#indexPrefix; ++$i) {

		my @ind = @indexPrefix[0..$i];
		push @{$params->{'pwd_list'}}, {
			'title' => $opml->entry(\@ind)->{'text'},
			'href'  => 'href="index.html?index=' . (join '.', @ind) . '&sess=' . $sessId . '"',
		};
	}

	# fill template and send back response
	my $callback = shift;
	my $output = Slim::Web::HTTP::filltemplatefile('plugins/Favorites/index.html', $params);

	$callback->($client, $params, $output, @_);
}

sub asyncCBContent {
	# callback for async http content fetching
	# causes indexHandler to be processed again with stored params + fetched content
	my $http = shift;
	my ($client, $params, $callback, $httpClient, $response) = @{ $http->params('args') };

	$params->{'fetched'}        = 1;
	$params->{'fetchedcontent'} = $http->content;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentType {
	# callback for establishing content type
	# causes indexHandler to be processed again with stored params + fetched content type
	my ($http, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;
	$params->{'fetchedtype'} = $http->response->content_type;

	$http->disconnect;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub asyncCBContentTypeError {
	# error callback for establishing content type - causes indexHandler to be processed again with stored params
	my ($http, $error, $client, $params, $callback, $httpClient, $response) = @_;

	$params->{'fetched'} = 1;

	indexHandler($client, $params, $callback, $httpClient, $response);
}

sub cliBrowse {
	my $request = shift;
	my $client  = $request->client;

	if ($request->isNotQuery([['favorites'], ['items', 'playlist']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	Slim::Buttons::XMLBrowser::cliQuery('favorites', $favs->xmlbrowser, $request);
}

sub cliAdd {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['add', 'addlevel']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $command= $request->getRequest(1);
	my $url    = $request->getParam('url');
	my $title  = $request->getParam('title');
	my $icon   = $request->getParam('icon');
	my $index  = $request->getParam('item_id');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	my ($level, $i) = $favs->level($index, 'contains');

	if ($level) {

		my $entry;

		if ($command eq 'add' && defined $title && defined $url) {

			$log->info("adding entry $title $url at index $index");

			$entry = {
				'text' => $title,
				'URL'  => $url,
				'type' => 'audio',
				'icon' => $icon || $favs->icon($url),
			};
			
			$request->addResult('count', 1);

		} elsif ($command eq 'addlevel' && defined $title) {

			$log->info("adding new level $title at index $index");

			$entry = {
				'text'    => $title,
				'outline' => [],
			};

			$request->addResult('count', 1);

		} else {

			$log->info("can't perform $command bad title or url");

			$request->setStatusBadParams();
			return;
		}

		if (defined $i) {

			splice @$level, $i, 0, $entry;

		} else { # with no specific index, place automatically at the end

			push @$level, $entry;
		}

		$favs->save;

		# show feedback if this action came from jive cometd session
		if ($request->source && $request->source =~ /\/slim\/request/) {
			$client->showBriefly({
				'jive' => { 
				'text' => [ $client->string('FAVORITES_ADDING'),
						$title,
					   ],
				}
			});
		}

		$request->setStatusDone();

	} else {

		$log->info("index $index invalid");

		$request->setStatusBadParams();
	}
}

sub cliDelete {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['delete']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $index  = $request->getParam('item_id');
	my $url    = $request->getParam('url');
	my $title  = $request->getParam('title');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if (!defined $index || !defined $favs->entry($index)) {
		$request->setStatusBadParams();
		return;
	}

	$favs->deleteIndex($index);

	# show feedback if this action came from jive cometd session
	if ($request->source && $request->source =~ /\/slim\/request/) {
		my $deleteMsg = $title?$title:$url;
		$client->showBriefly({
			'jive' => { 
			'text' => [ $client->string('FAVORITES_DELETING'),
						$deleteMsg ],
			}
		});
	}

	$request->setStatusDone();
}

sub cliRename {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['rename']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $index  = $request->getParam('item_id');
	my $title  = $request->getParam('title');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	if (!defined $index || !defined $favs->entry($index)) {
		$request->setStatusBadParams();
		return;
	}

	$log->info("rename index $index to $title");

	$favs->entry($index)->{'text'} = $title;
	$favs->save;

	$request->setStatusDone();
}

sub cliMove {
	my $request = shift;

	if ($request->isNotCommand([['favorites'], ['move']])) {
		$request->setStatusBadDispatch();
		return;
	}

	my $client = $request->client();
	my $from = $request->getParam('from_id');
	my $to   = $request->getParam('to_id');

	my $favs = Slim::Plugin::Favorites::OpmlFavorites->new($client);

	my ($fromLevel, $fromIndex) = $favs->level($from, 1);
	my ($toLevel,   $toIndex  ) = $favs->level($to, 1);

	if (!$fromLevel || !$toLevel) {
		$request->setStatusBadParams();
		return;
	}

	$log->info("moving item from index $from to index $to");

	splice @$toLevel, $toIndex, 0, (splice @$fromLevel, $fromIndex, 1);
	
	$favs->save;
	
	$request->setStatusDone();
}


1;
