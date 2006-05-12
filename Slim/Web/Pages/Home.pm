package Slim::Web::Pages::Home;

# $Id$

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;

use POSIX ();

use base qw(Slim::Web::Pages);

sub init {
	my $class = shift;
	
	Slim::Web::HTTP::addPageFunction(qr/^$/, sub {$class->home(@_)});
	Slim::Web::HTTP::addPageFunction(qr/^home\.(?:htm|xml)/, sub {$class->home(@_)});
	Slim::Web::HTTP::addPageFunction(qr/^index\.(?:htm|xml)/, sub {$class->home(@_)});

	$class->addPageLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
	$class->addPageLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
	$class->addPageLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
	$class->addPageLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
	$class->addPageLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
	$class->addPageLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
	$class->addPageLinks("help",{'FAQ' => "http://faq.slimdevices.com/"});
	$class->addPageLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
	$class->addPageLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
}

sub home {
	my ($class, $client, $params) = @_;
	
	my %listform = %$params;

	$params->{'nosetup'}  = 1 if $::nosetup;
	$params->{'noserver'} = 1 if $::noserver;
	$params->{'newVersion'} = $::newVersion if $::newVersion;

	if (!exists $Slim::Web::Pages::additionalLinks{"browse"}) {
		$class->addPageLinks("browse",{'BROWSE_BY_ARTIST' => "browsedb.html?hierarchy=artist,album,track&level=0"});
		$class->addPageLinks("browse",{'BROWSE_BY_GENRE'  => "browsedb.html?hierarchy=genre,artist,album,track&level=0"});
		$class->addPageLinks("browse",{'BROWSE_BY_ALBUM'  => "browsedb.html?hierarchy=album,track&level=0"});
		$class->addPageLinks("browse",{'BROWSE_BY_YEAR'   => "browsedb.html?hierarchy=year,album,track&level=0"});
		$class->addPageLinks("browse",{'BROWSE_NEW_MUSIC' => "browsedb.html?hierarchy=age,track&level=0"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"search"}) {
		$class->addPageLinks("search", {'SEARCHMUSIC' => "livesearch.html"});
		$class->addPageLinks("search", {'ADVANCEDSEARCH' => "advanced_search.html"});
	}

	if (!exists $Slim::Web::Pages::additionalLinks{"help"}) {
		$class->addPageLinks("help",{'GETTING_STARTED' => "html/docs/quickstart.html"});
		$class->addPageLinks("help",{'PLAYER_SETUP' => "html/docs/ipconfig.html"});
		$class->addPageLinks("help",{'USING_REMOTE' => "html/docs/interface.html"});
		$class->addPageLinks("help",{'HELP_REMOTE' => "html/help_remote.html"});
		$class->addPageLinks("help",{'HELP_RADIO' => "html/docs/radio.html"});
		$class->addPageLinks("help",{'REMOTE_STREAMING' => "html/docs/remotestreaming.html"});
		$class->addPageLinks("help",{'FAQ' => "html/docs/faq.html"});
		$class->addPageLinks("help",{'SOFTSQUEEZE' => "html/softsqueeze/index.html"});
		$class->addPageLinks("help",{'TECHNICAL_INFORMATION' => "html/docs/index.html"});
	}

	if (Slim::Utils::Prefs::get('lookForArtwork')) {
		my $sort = Slim::Utils::Prefs::get('sortBrowseArt');
		$class->addPageLinks("browse",{'BROWSE_BY_ARTWORK' => "browsedb.html?hierarchy=artwork,track&level=0&sort=$sort"});
	} else {
		$class->addPageLinks("browse",{'BROWSE_BY_ARTWORK' => undef});
		$params->{'noartwork'} = 1;
	}
	
	if (Slim::Utils::Prefs::get('audiodir')) {
		$class->addPageLinks("browse",{'BROWSE_MUSIC_FOLDER'   => "browsetree.html"});
	} else {
		$class->addPageLinks("browse",{'BROWSE_MUSIC_FOLDER' => undef});
		$params->{'nofolder'}=1;
	}

	# Always show Browse Playlists, as it's stored in the db now.
	$class->addPageLinks("browse",{'SAVED_PLAYLISTS' => "browsedb.html?hierarchy=playlist,playlistTrack&level=0"});

	# fill out the client setup choices
	for my $player (sort { $a->name() cmp $b->name() } Slim::Player::Client::clients()) {

		# every player gets a page.
		# next if (!$player->isPlayer());
		$listform{'playername'}   = $player->name();
		$listform{'playerid'}     = $player->id();
		$listform{'player'}       = $params->{'player'};
		$listform{'skinOverride'} = $params->{'skinOverride'};
		$params->{'player_list'} .= ${Slim::Web::HTTP::filltemplatefile("homeplayer_list.html", \%listform)};
	}

	Slim::Utils::PluginManager::addSetupGroups();
	$params->{'additionalLinks'} = \%Slim::Web::Pages::additionalLinks;

	$class->addPlayerList($client, $params);
	
	$class->addLibraryStats($params);

	my $template = $params->{"path"}  =~ /home\.(htm|xml)/ ? 'home.html' : 'index.html';
	
	return Slim::Web::HTTP::filltemplatefile($template, $params);
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
