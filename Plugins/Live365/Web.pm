package Plugins::Live365::Web;

# ***** BEGIN LICENSE BLOCK *****
# Version: MPL 1.1/GPL 2.0/LGPL 2.1
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
# 
# The Original Code is the SlimServer Live365 Plugin.
# 
# The Initial Developer of the Original Code is Vidur Apparao.
# Portions created by the Initial Developer are Copyright (C) 2004
# the Initial Developer. All Rights Reserved.
# 
# Contributor(s):
# 
# Alternatively, the contents of this file may be used under the
# terms of the GNU General Public License Version 2 or later (the
# "GPL"), in which case the provisions of the GPL are applicable 
# instead of those above.  If you wish to allow use of your 
# version of this file only under the terms of the GPL and not to
# allow others to use your version of this file under the MPL,
# indicate your decision by deleting the provisions above and
# replace them with the notice and other provisions required by
# the GPL.	If you do not delete the provisions above, a recipient
# may use your version of this file under either the MPL or the
# GPL.
#
# ***** END LICENSE BLOCK ***** */

use strict;
use vars qw( $VERSION );
$VERSION = 1.20;

use FindBin qw($Bin);
use File::Spec::Functions qw(:ALL);

use Slim::Web::HTTP;
use Slim::Utils::Strings qw (string);
use Slim::Utils::Misc;
use Data::Dumper;

use Plugins::Live365::Live365API;

use constant ROWS_TO_RETRIEVE => 50;

my $API = new Plugins::Live365::Live365API();

#
#  Handle play or add actions on a station
#    Pretty straightforward... use the routine from Plugins::Live365::Plugin
#
sub handleAction {
	my ($client, $params) = @_;

	my $mode = $params->{'mode'};
	my $current = $params->{'current'} || 1;
	my $action = $params->{'action'};
	my $stationid = $params->{'id'};

	if (defined($client)) {
		my $play = ($action eq 'play');

		$API->setStationListPointer($current-1);
	
		my $stationURL = $API->getCurrentChannelURL();
		$::d_plugins && msg( "Live365.ChannelMode URL: $stationURL\n" );
	
		Slim::Music::Info::setContentType($stationURL, 'mp3');
		Slim::Music::Info::setTitle($stationURL, 
		   	$API->getCurrentStation()->{STATION_TITLE});
	
		$play and $client->execute([ 'playlist', 'clear' ] );
		$client->execute([ 'playlist', 'add', $stationURL ] );
		$play and $client->execute([ 'play' ] );
	}
	my $webroot = $params->{'webroot'};
	$webroot =~ s/(.*?)plugins.*$/$1/;
	return filltemplatefile("live365_redirect.html", $params);
}

#
#  Handle browsing genres or stations for a genre.
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request.
#
sub handleBrowseGenre {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $errcode = startBrowseGenre($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the browse is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {
		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		}
		return handleIndex($client,$params);
	}

	storeAsyncRequest("xxx","genre",{client => $client, params => $params, callback => $callback, httpClient => $httpClient, response => $response});
	return undef;
}

sub startBrowseGenre {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $genreid = $params->{'id'};

	if ($genreid eq 'root') {
		$API->loadGenreList($client, \&completeBrowseGenre, \&errorBrowseGenre);
	}
	else {
		# See startBrowseStations for how paging works
		my @optionalFirstParam;

		if ($params->{'start'}) {
			@optionalFirstParam = ( "first", $params->{'start'} + 1);
		}
		
		$API->clearStationDirectory();
		$API->loadStationDirectory(
			$genreid, $client, \&completeBrowseGenre, \&errorBrowseGenre, 0,
			genre			=> $genreid,
			sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			rows			=> ROWS_TO_RETRIEVE,
			searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
			@optionalFirstParam
		);
	}
	
	return 0;
}

sub completeBrowseGenre {
	my $client = shift;
	my $list = shift;

	my $body = "";

	my $fullparams = fetchAsyncRequest('xxx','genre');
	my $params = $fullparams->{'params'};

	my %pwd_form = %$params;
	$pwd_form{'genreid'} = 'root';
	delete $pwd_form{'id'};
	$pwd_form{'pwditem'} = $params->{'listname'} =
		string('PLUGIN_LIVE365_BROWSEGENRES');
	$params->{'pwd_list'} .=
		${filltemplatefile("live365_browse_pwdlist.html",
						   \%pwd_form)};

	my $genreid = $params->{'id'};

	if ($genreid eq 'root') {

		my @genreList = @$list;

		if ( !@genreList ) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
			$body = handleIndex($client,$params);
		} else {
			my %listform = %$params;
			my $i = 0;
			for my $genre (@genreList) {
				$listform{'genreid'} = @$genre[1];
				$listform{'genrename'} = @$genre[0];
				$listform{'genremode'} = 1;
				$listform{'odd'} = $i++ % 2;
				$params->{'browse_list'} .=
					${filltemplatefile("live365_browse_list.html",
								   \%listform)};
			}
		}
	} else {
		$pwd_form{'pwditem'} = $params->{'listname'} = $pwd_form{'genrename'} = 
			$params->{'name'};
		$pwd_form{'genreid'} = $params->{'id'};
		$params->{'pwd_list'} .=
			${filltemplatefile("live365_browse_pwdlist.html",
							   \%pwd_form)};

		$body = buildStationBrowseHTML($params);
	}

	if ($body eq "") {
		$body = filltemplatefile("live365_browse.html", $params);
	}
		
	createAsyncWebPage($client,$body,$fullparams);
}

sub errorBrowseGenre {
	my $client = shift;
	my $list = shift;

	my $body = "";

	my $fullparams = fetchAsyncRequest('xxx','genre');
	my $params = $fullparams->{'params'};


	my $genreid = $params->{'id'};

	if ($genreid eq 'root') {
		
		$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		$body = handleIndex($client,$params);
	} else {
		my %pwd_form = %$params;
		$pwd_form{'genreid'} = 'root';
		delete $pwd_form{'id'};
		$pwd_form{'pwditem'} = $params->{'listname'} =
			string('PLUGIN_LIVE365_BROWSEGENRES');
		$params->{'pwd_list'} .=
			${filltemplatefile("live365_browse_pwdlist.html",
						   \%pwd_form)};
		$params->{'errmsg'} = "PLUGIN_LIVE365_LOADING_GENRES_ERROR";
		$body = filltemplatefile("live365_browse.html", $params);
	}

	createAsyncWebPage($client,$body,$fullparams);
}

#
#  Handle browsing stations for by any method except by genre
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request.
#
sub handleBrowseStation {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $errcode = startBrowseStation($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the browse is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {
		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_LOGIN_ERROR_ACTION";
		}
		return handleIndex($client,$params);
	}

	storeAsyncRequest("xxx","station",{client => $client, params => $params, callback => $callback, httpClient => $httpClient, response => $response});
	return undef;
}

my %lookupStrings = (
	"presets" 		=> "PLUGIN_LIVE365_PRESETS",
	"picks"   		=> "PLUGIN_LIVE365_BROWSEPICKS",
	"pro"     		=> "PLUGIN_LIVE365_BROWSEPROS",
	"all"     		=> "PLUGIN_LIVE365_BROWSEALL",
	"tac"			=> "PLUGIN_LIVE365_SEARCH_TAC",
	"artist"		=> "PLUGIN_LIVE365_SEARCH_A",
	"track"			=> "PLUGIN_LIVE365_SEARCH_T",
	"cd"			=> "PLUGIN_LIVE365_SEARCH_C",
	"station"		=> "PLUGIN_LIVE365_SEARCH_E",
	"location"		=> "PLUGIN_LIVE365_SEARCH_L",
	"broadcaster"	=> "PLUGIN_LIVE365_SEARCH_H",
        );

my %lookupGenres = (
	"presets" => "N/A",  # Not used
	"picks"   => "ESP",
	"pro"     => "Pro",
	"all"     => "All"
        );

sub startBrowseStation {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $brtype = $params->{'type'};

	my $source = $lookupStrings{$brtype};

	if ($brtype eq 'presets') {

		# Presets.  Clear everything and reload just because we're lazy.
		$API->clearStationDirectory();
		$API->loadMemberPresets(
			$source, $client, \&completeBrowseStation, \&errorBrowseStation);
			
	} elsif ($lookupGenres{$brtype}) {

		# This is ugly but it's easy and it works.  We don't page like the Slim clients do.
		#   Slim clients page by retrieving the first N channels, then as you scroll, they
		#   append the next N channels, and so on... the Stations hash grows.
		#   We will only ever have N channels in the Stations hash.  We clear and reload
		#   the N channels page by page.  It allows us to skip around pages a bit easier
		#   at the expense of a possible performance hit.
		my @optionalFirstParam;

		if ($params->{'start'}) {
			@optionalFirstParam = ( "first", $params->{'start'} + 1);
		}
		
		$API->clearStationDirectory();
		$API->loadStationDirectory(
			$source,
			$client, 
			\&completeBrowseStation,
			\&errorBrowseStation,
			0,
			sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			searchfields	=> Slim::Utils::Prefs::get( 'plugin_live365_search_fields' ),
			rows			=> ROWS_TO_RETRIEVE,
			genre			=> $lookupGenres{$brtype},
			@optionalFirstParam
			);
	} else {

		# What are you asking us to do?!?
		return 1;
	}

	return 0;
}

sub completeBrowseStation {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','station');
	my $params = $fullparams->{'params'};
	my $brtype = $params->{'type'};

	my %pwd_form = %$params;
	$pwd_form{'pwditem'} = $params->{'listname'} = 
		string($lookupStrings{$brtype});
	$params->{'pwd_list'} .= 
		${filltemplatefile("live365_browse_pwdlist.html", 
						   \%pwd_form)};

	my $body = buildStationBrowseHTML($params);
		
	createAsyncWebPage($client,$body,$fullparams);
}

sub errorBrowseStation {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','station');
	my $params = $fullparams->{'params'};
	
        if ($API->isLoggedIn()) {
                $params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";
        } else {
                $params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
        }

	my $body = handleIndex($client,$params);
		
	createAsyncWebPage($client,$body,$fullparams);
}

sub buildStationBrowseHTML {
	my $params = shift;
	my $isSearch = shift;
	my $start;
	my $end;
	my $totalcount;

	# Get actual matched stations
	$totalcount = $API->getStationListLength();

	# Set up paging links for search vs. browse
	my $targetPage;
	my $targetParms;
	if ($isSearch) {
		$targetPage = "search.html";
		$targetParms = "type=" . $params->{'type'} . "&query=" .
					   URI::Escape::uri_escape($params->{'query'}) .
					   "&player=" . $params->{'player'};
	} else {
		$targetPage = "browse.html";
		$targetParms = "type=" . $params->{'type'} . "&player=" . $params->{'player'};
		if ($params->{'id'}) {
			$targetParms .= "&id=" . $params->{'id'};
		}
	}

	# If we have nothing to show, show an error.
	if ($totalcount == 0) {
		$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";
	} else {
	
		# Handle paging sections, if necessary
		if ($totalcount <= ROWS_TO_RETRIEVE) {
	
			# Force this since we're not paging anyway and simpleHeader likes to start
			# counting at zero otherwise.
			$params->{'start'} = 1;

			Slim::Web::Pages::simpleHeader(
				$totalcount,
				\$params->{'start'},
				\$params->{'browselist_header'},
				$params->{'skinOverride'},
				ROWS_TO_RETRIEVE,
				0
			);
	
		} else {
	
			Slim::Web::Pages::pageBar(
				$totalcount,
				$targetPage,
				0,
				$targetParms,
				\$params->{'start'},
				\$params->{'browselist_header'},
				\$params->{'browselist_pagebar'},
				$params->{'skinOverride'},
				ROWS_TO_RETRIEVE,
			);
		}
	
		my %listform = %$params;
		my $i = 0;
		my $slist = $API->{Stations};
		for my $station (@$slist) {
			$listform{'stationid'} = $station->{STATION_ID};
			$listform{'stationname'} = $station->{STATION_TITLE};
			$listform{'listeners'} = $station->{STATION_LISTENERS_ACTIVE};
			$listform{'maxlisteners'} = $station->{STATION_LISTENERS_MAX};
			$listform{'connection'} = $station->{STATION_CONNECTION};
			$listform{'rating'} = $station->{STATION_RATING};
			$listform{'quality'} = $station->{STATION_QUALITY_LEVEL};
			$listform{'access'} = $station->{LISTENER_ACCESS};
			$listform{'stationmode'} = 1;
			$listform{'odd'} = $i++ % 2;
			$listform{'current'} = $i;
			$listform{'mode'} = "";
			if ($params->{'extrainfo_function'}) {
				$listform{'extrainfo'} = eval($params->{'extrainfo_function'});
			}
			$params->{'browse_list'} .=	
				${filltemplatefile("live365_browse_list.html", 
							\%listform)};
		}
	
		$params->{'match_count'} = $totalcount;
	}

	return filltemplatefile(($isSearch ? "live365_search.html" : "live365_browse.html"), $params);
}

#
#  Handle Browse action (Genres or Stations)
#    Just refer them off to the right handler after checking the client and login status.
#
sub handleBrowse {
	my ($client, $params) = @_;

	if (!($API->isLoggedIn())) {
		$params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
		return handleIndex(@_);
	}

	if ($params->{'type'} eq "genres") {
		return handleBrowseGenre(@_);
	}
	else {
		return handleBrowseStation(@_);
	}

	return undef;
}
	
#
#  Handle searching stations by a variety of methods
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP search request.
#
sub handleSearch {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	if (!($API->isLoggedIn())) {
		$params->{'errmsg'} = "PLUGIN_LIVE365_NOT_LOGGED_IN";
		return handleIndex(@_);
	}

	# Short circuit error msg if query param not given
	unless ($params->{'query'}) {
		$params->{'numresults'} = -1;
		return filltemplatefile("live365_search.html", $params);
	}

	my $errcode = startSearch($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the search is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {
		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";
		}
		return filltemplatefile("live365_search.html", $params);
	}

	storeAsyncRequest("xxx","search",{client => $client, params => $params, callback => $callback, httpClient => $httpClient, response => $response});
	return undef;
}

my %lookupSearchFields = (
	"tac"			=> "T:A:C",
	"artist"		=> "A",
	"track"			=> "T",
	"cd"			=> "C",
	"station"		=> "E",
	"location"		=> "L",
	"broadcaster"	=> "H",
        );

my %lookupExtraInfo = (
	"tac"			=> "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"artist"		=> "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"track"			=> "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"cd"			=> "\&showPlaylistMatches(\$station->{STATION_PLAYLIST_INFO}->{PlaylistEntry})",
	"station"		=> "",
	"location"		=> "\$station->{STATION_LOCATION}",
	"broadcaster"	=> "\$station->{STATION_BROADCASTER}",
        );

sub startSearch {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	my $query = $params->{'query'};
	my $type = $params->{'type'};

	my $source = $lookupStrings{$type};

	# See startBrowseStations for how paging works
	my @optionalFirstParam;

	if ($params->{'start'}) {
		@optionalFirstParam = ( "first", $params->{'start'} + 1);
	}
	
	$API->clearStationDirectory();
	$API->loadStationDirectory(
			$source,
			$client, 
			\&completeSearch,
			\&errorSearch,
			0,
			sort			=> Slim::Utils::Prefs::get( 'plugin_live365_sort_order' ),
			searchfields	=> $lookupSearchFields{$type},
			rows			=> ROWS_TO_RETRIEVE,
			searchdesc		=> $query,
			@optionalFirstParam
		);

	return 0;
}

sub completeSearch {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','search');
	my $params = $fullparams->{'params'};
	my $brtype = $params->{'type'};

	my $showDetails = Slim::Utils::Prefs::get( 'plugin_live365_web_show_details' );
	my %pwd_form = %$params;
	$pwd_form{'pwditem'} = $params->{'listname'} = 
		string($lookupStrings{$brtype});
	$params->{'pwd_list'} .= 
		${filltemplatefile("live365_browse_pwdlist.html", 
						   \%pwd_form)};

	$pwd_form{'genreid'} = $params->{'id'};
	$pwd_form{'pwditem'} = $params->{'listname'} = 
		$params->{'name'};
	$params->{'pwd_list'} .= 
		${filltemplatefile("live365_browse_pwdlist.html", 
						   \%pwd_form)};

	if ($showDetails) {
		$params->{'extrainfo_function'} = $lookupExtraInfo{$brtype};
	}

	my $body = buildStationBrowseHTML($params,1);

	createAsyncWebPage($client,$body,$fullparams);
}

sub errorSearch {
	my $client = shift;

	my $fullparams = fetchAsyncRequest('xxx','search');
	my $params = $fullparams->{'params'};
	$params->{'errmsg'} = "PLUGIN_LIVE365_NOSTATIONS";

	my $body = filltemplatefile("live365_search.html", $params);
		
	createAsyncWebPage($client,$body,$fullparams);
}

#
#  Helper routine to format XML data returned from Live365 when
#    searching playlist artist, song, or album.
#
sub showPlaylistMatches {
	my $plist = shift;
	my @templist;
	my $retval = "";

	if (ref($plist) ne "ARRAY") {
		# One match in the playlist
		@templist = ($plist);
	} else {
		@templist = @$plist;
	}

	foreach my $item (@templist) {
		# Empty values in the XML show up as refs to hashes
		next if (ref($item->{Artist}) eq "HASH" ||
		         ref($item->{Title}) eq "HASH");
		$retval .= "<br>\n" if ($retval);
		$retval .= $item->{Artist} . " - " . $item->{Title};
		$retval .= " (" . $item->{Album} . ")" unless (ref($item->{Album}) eq "HASH");
	}

	return $retval;
}

#
#  Handle main Index page.
#    Nothing fancy, no async stuff here.
#
sub handleIndex {
	my ($client, $params) = @_;

	my $body = "";

	$params->{'loggedin'} = $API->isLoggedIn();

	if ($params->{'autologin'} && !($params->{'loggedin'})) {
		$params->{'action'} = "in";
		# Stop infinite loops in the event we don't log in successfully
		$params->{'autologin'} = 0;

		return handleLogin(@_);
	}

	$body = filltemplatefile("live365_index.html", $params);

	return $body;
}

#
#  Handle Login/Logout actions.
#    Play some async games here.  No response until we get a callback from the completion
#    of the Async_HTTP login request. 
#
sub handleLogin {
	my ($client, $params, $callback, $httpClient, $response) = @_;

	storeAsyncRequest("xxx","login",{client => $client, params => $params, callback => $callback, httpClient => $httpClient, response => $response});

	my $errcode = doLoginLogout($client, $params, $callback, $httpClient, $response);
	
	# Errcode > 0 is a real error.  Show it on the next screen.
	# Errcode = 0 means the login is in progress.
	# Errcode < 0 means normal completion with no async stuff needed.
	if ($errcode != 0) {
		if ($errcode > 0) {
			$params->{'errmsg'} = "PLUGIN_LIVE365_NO_CREDENTIALS";
		}
		return handleIndex($client,$params);
	}

	return undef;
}

sub doLoginLogout() {
	my ($client, $params, $callback, $httpClient, $response) = @_;
	
	my $action = $params->{'action'};

	my $userID   = Slim::Utils::Prefs::get( 'plugin_live365_username' );
	my $password = Slim::Utils::Prefs::get( 'plugin_live365_password' );

	if (defined $password) {
		$password = unpack('u', $password);
	}

	if ($action eq 'in') {
		if( $userID and $password ) {
			$::d_plugins && msg( "Logging in $userID\n" );
			my $loginStatus = $API->login( $userID, $password, $client, \&webLoginDone);
		} else {
			$::d_plugins && msg( "Live365.login: no credentials set\n" );
			return 1;
		}
	} else {
		$::d_plugins && msg( "Logging out $userID\n" );
		my $logoutStatus = $API->logout($client, \&webLogoutDone);
	}
	return 0;
}

sub webLoginDone {
	my $client = shift;
	my $loginStatus = shift;

	my @statusText = qw(
		PLUGIN_LIVE365_LOGIN_SUCCESS
		PLUGIN_LIVE365_LOGIN_ERROR_NAME
		PLUGIN_LIVE365_LOGIN_ERROR_LOGIN
		PLUGIN_LIVE365_LOGIN_ERROR_ACTION
		PLUGIN_LIVE365_LOGIN_ERROR_ORGANIZATION
		PLUGIN_LIVE365_LOGIN_ERROR_SESSION
		PLUGIN_LIVE365_LOGIN_ERROR_HTTP
	);
	
	my $params = fetchAsyncRequest('xxx','login');

	if( $loginStatus == 0 ) {
		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', $API->getSessionID() );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', $API->getMemberStatus() );
		$API->setLoggedIn( 1 );
		$::d_plugins && msg( "Live365 logged in: " . $API->getSessionID() . "\n" );
	} else {
		Slim::Utils::Prefs::set( 'plugin_live365_sessionid', undef );
		Slim::Utils::Prefs::set( 'plugin_live365_memberstatus', undef );
		$API->setLoggedIn( 0 );
		$::d_plugins && msg( "Live365 login failure: " . $statusText[ $loginStatus ] . "\n" );
		$params->{'params'}->{'errmsg'} = $statusText[ $loginStatus ];
	}

	my $body = handleIndex($client,$params->{'params'});
	
	createAsyncWebPage($client,$body,$params);
}

sub webLogoutDone {
	my $client = shift;

	$API->setLoggedIn( 0 );
	Slim::Utils::Prefs::set( 'plugin_live365_sessionid', '' );

	#my $params = fetchAsyncRequest($client->id(),'login');
	my $params = fetchAsyncRequest('xxx','login');

	my $body = handleIndex($client,$params->{'params'});
	
	createAsyncWebPage($client,$body,$params);
}

#
#  Pretty much stolen from the Shoutcast Plugin.
#    Send output back to the Asynchronous web page handler once we've built the page
#
sub createAsyncWebPage {
	my $APIclient = shift;
	my $output = shift;
	my $params = shift;
	
	# create webpage if we were called asynchronously
	my $current_player = "";
	if (defined($APIclient)) {
		$current_player = $APIclient->id();
	}
		
	$params->{callback}->($current_player, $params->{params}, $output, $params->{httpClient}, $params->{response});
}

#
# Routines and hash to manage the queue of parameters etc. for pending asynchronous requests.
#   Keyed by operation and client ID
#   Note: Fetching an object automatically deletes it
#
my %async_queue = ();

sub storeAsyncRequest {
	my $client = shift;
	my $operation = shift;
	my $params = shift;
	
	my $asynckey = $operation . "--" . $client;
	$async_queue{$asynckey} = $params;
}

sub fetchAsyncRequest {
	my $client = shift;
	my $operation = shift;

	my $asynckey = $operation . "--" . $client;
	my $retval = $async_queue{$asynckey};
	delete $async_queue{$asynckey};
	return $retval;
}

#
#  Local routine that just is a shortcut for the one in Slim::Web::HTTP.
#    The RealSlim plugin just did it this way.
#
sub filltemplatefile {
	return Slim::Web::HTTP::filltemplatefile(@_);
}

1;

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
