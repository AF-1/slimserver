package Slim::Control::Request;

# SlimServer Copyright (c) 2001-2006 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

# This class implements a generic request mechanism for SlimServer.
# More documentation is provided below the table of commands & queries

######################################################################################################################################################################
# COMMANDS & QUERIES LIST
######################################################################################################################################################################
#
# This table lists all supported commands and queries with their parameters. 
#
# C     P0             P1                          P2                          P3               P4       P5
######################################################################################################################################################################

#### GENERAL ####
# N    debug           <debugflag>                 <0|1|?|>
# N    pref            <prefname>                  <prefvalue|?>
# N    version         ?
# N    stopserver


#### DATABASE ####
# N    rescan          <|playlists|?>
# N    wipecache

# Y    albums          <startindex>                <numitems>                  <tagged parameters>
# Y    artists         <startindex>                <numitems>                  <tagged parameters>
# Y    genres          <startindex>                <numitems>                  <tagged parameters>
# N    playlists       <startindex>                <numitems>                  <tagged parameters>
# Y    playlisttracks  <startindex>                <numitems>                  <tagged parameters>
# Y    songinfo        <startindex>                <numitems>                  <tagged parameters>
# Y    titles          <startindex>                <numitems>                  <tagged parameters>


#### PLAYERS ####
# Y    alarm           <tagged parameters>
# Y    button          <buttoncode>
# Y    client          forget
# Y    display         <line1>                     <line2>                       <duration>
# Y    ir              <ircode>                    <time>
# Y    mixer           volume                      <0..100|-100..+100|?>
# Y    mixer           bass                        <0..100|-100..+100|?>
# Y    mixer           treble                      <0..100|-100..+100|?>
# Y    mixer           pitch                       <80..120|-100..+100|?>
# Y    mixer           muting                      <|?>
# Y    playerpref      <prefname>                  <prefvalue|?>
# Y    power           <0|1|?|>
# Y    sleep           <0..n|?>
# Y    sync            <playerindex|playerid|-|?>

# Y    alarms          <startindex>                <numitems>                  <tagged parameters>
# Y    signalstrength  ?
# Y    connected       ?
# Y    display         ?                           ?
# Y    displaynow      ?                           ?
# N    player          count                       ?
# N    player          ip                          <index or ID>               ?
# N    player          id|address                  <index or ID>               ?
# N    player          name                        <index or ID>               ?
# N    player          model                       <index or ID>               ?
# N    player          displaytype                 <index or ID>               ?
# N    players         <startindex>                <numitems>                  <tagged parameters>


#### PLAYLISTS ####
# Y    pause           <0|1|>
# Y    play
# Y    playlist        add|append                  <item> (item can be a song, playlist or directory)
# Y    playlist        addalbum                    <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        addtracks                   <searchterms>    
# Y    playlist        clear
# Y    playlist        delete                      <index>
# Y    playlist        deletealbum                 <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        deleteitem                  <item> (item can be a song, playlist or directory)
# Y    playlist        deletetracks                <searchterms>   
# Y    playlist        index|jump                  <index|?>
# Y    playlist        insert|insertlist           <item> (item can be a song, playlist or directory)
# Y    playlist        insertalbum                 <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        inserttracks                <searchterms>    
# Y    playlist        loadalbum|playalbum         <genre>                     <artist>         <album>  <songtitle>
# Y    playlist        loadtracks                  <searchterms>    
# Y    playlist        move                        <fromindex>                 <toindex>
# Y    playlist        play|load                   <item> (item can be a song, playlist or directory)
# Y    playlist        playtracks                  <searchterms>    
# Y    playlist        repeat                      <0|1|2|?|>
# Y    playlist        shuffle                     <0|1|2|?|>
# Y    playlist        resume                      <playlist>    
# Y    playlist        save                        <playlist>    
# Y    playlist        zap                         <index>
# Y    playlistcontrol <tagged parameters>
# Y    rate            <rate|?>
# Y    stop
# Y    time|gototime   <0..n|-n|+n|?>

# Y    artist          ?
# Y    album           ?
# Y    duration        ?
# Y    genre           ?
# Y    title           ?
# Y    mode            ?
# Y    path            ?
# Y    playlist        name                        ?
# Y    playlist        url                         ?
# Y    playlist        modified                    ?
# Y    status          <startindex>                <numitems>                  <tagged parameters>


#### NOTIFICATION ####
# The following 'terms' are used for notifications 

# Y    client          disconnect
# Y    client          new
# Y    client          reconnect
# Y    playlist        load_done
# Y    playlist        newsong
# Y    playlist        open                        <url>
# Y    playlist        sync
# Y    playlist        cant_open                   <url>
# N    rescan          done
# Y    unknownir       <ircode>                    <timestamp>

# DEPRECATED (BUT STILL SUPPORTED)
# Y    mode            <play|pause|stop>


######################################################################################################################################################################


# ABOUT THIS CLASS
#
# This class implements a generic request mechanism for SlimServer.
# This new mechanism supplants (and hopefully) improves over the "legacy"
# mechanisms that used to be provided by Slim::Control::Command. Where 
# appropriate, the Request class provides hooks supporting this legacy.
# This is why, for example, the debug flag for this code is $::d_command.
#
#
# The general mechansim is to create a Request object and execute it. There
# is an option of specifying a callback function, to be called once the 
# request is executed. In addition, it is possible to be notified of command
# execution (see NOTIFICATIONS below).
#
#
# Function "Slim::Control::Request::executeRequest" accepts the usual parameters
# of client, command array and callback params, and returns the request object.
# This command can be used in place of "Slim::Control::Command::execute", but
# it does not return the array as execute did. If you need the array returned,
# use "executeLegacy".
#
# Slim::Control::Request::executeRequest($client, ['stop']);
# my @result = Slim::Control::Request::executeLegacy($client, ['playlist', 'save']);
#
#
# REQUESTS
#
# Requests are object that embodies all data related to performing an action or
# a query.
#
# ** client ID **          
#   Requests store the client ID, if any, to with it applies
#     my $clientid = $request->clientid();   # read
#     $request->clientid($client->id());     # set
#
#   Methods are provided for convenience using a client, in particular all 
#   executeXXXX calls
#     my $client = $request->client();       # read
#     $request->client($client);             # set
#
#   Some requests require a client to operate. This is encoded in the
#   request for error detection. These calls are unlikely to be useful to 
#   users of the class but mentioned here for completeness.
#     if ($request->needClient()) { ...      # read
#     $request->needClient(1);               # set
#
# ** type **
#   Requests are commands that do something or query that change nothing but
#   mainly return data. They are differentiated mainly for performance reasons,
#   for example queries are NOT notified. These calls are unlikely to be useful
#   to users of the class but mentioned here for completeness.
#     if ($request->query()) {...            # read
#     $request->query(1);                    # set
#
# ** request name **
#   For historical reasons, command names are composed of multiple terms, f.e.
#   "playlist save" or "info total genres", represented as an array. This
#   convention was kept, mainly because of the amount of code relying on it.
#   The request name is therefore represented as an array, that you can access
#   using the getRequest method
#     $request->getRequest(0);               # read the first term f.e. "playlist"
#     $request->getRequest(1);               # read 2nd term, f.e. "save"
#     my $cnt = $request->getRequestCount(); # number of terms
#     my $str = $request->getRequestString();# string of all terms, f.e. "playlist save"
#
#   Normally, creating the request is performed through the execute calls or by
#   calling new with an array that is parsed by the code here to match the
#   available commands and automatically assign parameters. The following
#   method is unlikely to be useful to users of this class, but is mentioned
#   for completeness.
#     $request->addRequest($term);           # add a term to the request
#
# ** parameters **
#   The parsing performed on the array names all parameters, positional or
#   tagged. Positional parameters are assigned a name from the addDispatch table,
#   and any extra parameters are added as "_pX", where X is the position in the
#   array.
#   As a consequence, users of the class only access parameter by name
#     $request->getParam('_index');          # get the '_index' param
#     $request->getParam('_p4');             # get the '_p4' param (auto named)
#     $request->getParam('cmd');             # get a tagged param
#
#   Here again, the routine used to add a positional params is normally not used
#   by users of this class, but for completeness
#     $request->addParamPos($value);         # adds positional parameter
#     $request->addParam($key, $value);      # adds named parameter
#   
# ** results **
#   Queries, but some commands as well, do add results to a request. Results
#   are either single data points (f.e. how many elements where inserted) or 
#   loops (i.e. data for song 1, data being a list of single data point, data for
#   song 2, etc).
#   Results are named like parameters. Obviously results are only available 
#   once the request has been executed (without errors)
#     my $data = $request->getResult('_value');
#                                            # get a result
#
#   There can be multiple loops in the results. Each loop is named and starts
#   with a '@'.
#     my $looped = $request->getResultLoop('@songs', 0, '_value');
#                                            # get first '_value' result in
#                                            # loop '@songs'
#
#
# NOTIFICATIONS
#
# The Request mechanism can notify "subscriber" functions of successful
# command request execution (not of queries). Callback functions have a single
# parameter corresponding to the request object.
# Optionally, the subscribe routine accepts a filter, which limits calls to the
# subscriber callback to those requests matching the filter. The filter is
# in the form of an array ref containing arrays refs (one per dispatch level) 
# containing lists of desirable commands (easier to code than explain, see
# examples below)
#
# Example
#
# Slim::Control::Request::subscribe( \&myCallbackFunction, 
#                                     [['playlist']]);
# -> myCallbackFunction will be called for any command starting with 'playlist'
# in the table below ('playlist save', playlist loadtracks', etc).
#
# Slim::Control::Request::subscribe( \&myCallbackFunction, 
#				                      [['mode'], ['play', 'pause']]);
# -> myCallbackFunction will be called for commands "mode play" and
# "mode pause", but not for "mode stop".
#
# In both cases, myCallbackFunction must be defined as:
# sub myCallbackFunction {
#      my $request = shift;
#
#      # do something useful here
#      # use the methods of $request to find all information on the
#      # request.
#
#      my $client = $request->client();
#
#      my $cmd = $request->getRequest(0);
#
#      msg("myCallbackFunction called for cmd $cmd\n");
# }
#
# 


use strict;

use Scalar::Util qw(blessed);
use Tie::LLHash;

use Slim::Control::Commands;
use Slim::Control::Queries;
use Slim::Utils::Alarms;
use Slim::Utils::Misc;

our %dispatchDB;                # contains a multi-level hash pointing to
                                # each command or query subroutine

our %subscribers = ();          # contains the clients to the notification
                                # mechanism

our @notificationQueue;         # contains the Requests waiting to be notified

my $callExecuteCallback = 0;    # flag to know if we must call the legacy
                                # Slim::Control::Command::executeCallback

my $d_notify = 1;               # local debug flag for notifications. Note that
                                # $::d_command must be enabled as well.

################################################################################
# Package methods
################################################################################
# These function are really package functions, i.e. to be called like
#  Slim::Control::Request::subscribe() ...

# adds standard commands and queries to the dispatch DB...
sub init {

	# Allow deparsing of code ref function names.
	if ($::d_command && $d_notify) {
		require Slim::Utils::PerlRunTime;
	}

######################################################################################################################################################################
#                                                                                                     |requires Client
#                                                                                                     |  |is a Query
#                                                                                                     |  |  |has Tags
#                                                                                                     |  |  |  |Function to call
#                 P0               P1              P2            P3             P4         P5         C  Q  T  F
######################################################################################################################################################################

    addDispatch(['alarm'],                                                                           [1, 0, 1, \&Slim::Control::Commands::alarmCommand]);
    addDispatch(['alarms',         '_index',      '_quantity'],                                      [1, 1, 1, \&Slim::Control::Queries::alarmsQuery]);
    addDispatch(['album',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['albums',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['artist',         '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['artists',        '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['button',         '_buttoncode',  '_time',      '_orFunction'],                     [1, 0, 0, \&Slim::Control::Commands::buttonCommand]);
    addDispatch(['client',         'forget'],                                                        [1, 0, 0, \&Slim::Control::Commands::clientForgetCommand]);
    addDispatch(['connected',      '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::connectedQuery]);
    addDispatch(['debug',          '_debugflag',   '?'],                                             [0, 1, 0, \&Slim::Control::Queries::debugQuery]);
    addDispatch(['debug',          '_debugflag',   '_newvalue'],                                     [0, 0, 0, \&Slim::Control::Commands::debugCommand]);
    addDispatch(['display',        '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displayQuery]);
    addDispatch(['display',        '_line1',       '_line2',     '_duration'],                       [1, 0, 0, \&Slim::Control::Commands::displayCommand]);
    addDispatch(['displaynow',     '?',            '?'],                                             [1, 1, 0, \&Slim::Control::Queries::displaynowQuery]);
    addDispatch(['duration',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genre',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['genres',         '_index',      '_quantity'],                                      [0, 1, 1, \&Slim::Control::Queries::browseXQuery]);
    addDispatch(['info',           'total',        'albums',     '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'artists',    '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'genres',     '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['info',           'total',        'songs',      '?'],                               [0, 1, 0, \&Slim::Control::Queries::infoTotalQuery]);
    addDispatch(['ir',             '_ircode',      '_time'],                                         [1, 0, 0, \&Slim::Control::Commands::irCommand]);
    addDispatch(['linesperscreen', '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::linesperscreenQuery]);
    addDispatch(['mixer',          'bass',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'bass',         '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'muting',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'muting',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'pitch',        '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'pitch',        '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'treble',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'treble',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mixer',          'volume',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::mixerQuery]);
    addDispatch(['mixer',          'volume',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::mixerCommand]);
    addDispatch(['mode',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::modeQuery]);
    addDispatch(['path',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['pause',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['play'],                                                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['player',         'address',      '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'count',        '?'],                                             [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'displaytype',  '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'id',           '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'ip',           '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'model',        '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['player',         'name',         '_IDorIndex', '?'],                               [0, 1, 0, \&Slim::Control::Queries::playerXQuery]);
    addDispatch(['playerpref',     '_prefname',    '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playerprefQuery]);
    addDispatch(['playerpref',     '_prefname',    '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playerprefCommand]);
    addDispatch(['players',        '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playersQuery]);
    addDispatch(['playlist',       'add',          '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'addalbum',     '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'addtracks',    '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'album',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'append',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'artist',       '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'clear'],                                                         [1, 0, 0, \&Slim::Control::Commands::playlistClearCommand]);
    addDispatch(['playlist',       'delete',       '_index'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistDeleteCommand]);
    addDispatch(['playlist',       'deletealbum',  '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'deleteitem',   '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistDeleteitemCommand]);
    addDispatch(['playlist',       'deletetracks', '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'duration',     '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'genre',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'index',        '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'index',        '_index',     '_noplay'],                         [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',       'insert',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'insertlist',   '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'insertalbum',  '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'inserttracks', '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'jump',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'jump',         '_index',     '_noplay'],                         [1, 0, 0, \&Slim::Control::Commands::playlistJumpCommand]);
    addDispatch(['playlist',       'load',         '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'loadalbum',    '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'loadtracks',   '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'modified',     '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'move',         '_fromindex', '_toindex'],                        [1, 0, 0, \&Slim::Control::Commands::playlistMoveCommand]);
    addDispatch(['playlist',       'name',         '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'path',         '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'play',         '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'playalbum',    '_genre',     '_artist',     '_album', '_title'], [1, 0, 0, \&Slim::Control::Commands::playlistXalbumCommand]);
    addDispatch(['playlist',       'playtracks',   '_what',      '_listref'],                        [1, 0, 0, \&Slim::Control::Commands::playlistXtracksCommand]);
    addDispatch(['playlist',       'repeat',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'repeat',       '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playlistRepeatCommand]);
    addDispatch(['playlist',       'resume',       '_item'],                                         [1, 0, 0, \&Slim::Control::Commands::playlistXitemCommand]);
    addDispatch(['playlist',       'save',         '_title'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistSaveCommand]);
    addDispatch(['playlist',       'shuffle',      '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'shuffle',      '_newvalue'],                                     [1, 0, 0, \&Slim::Control::Commands::playlistShuffleCommand]);
    addDispatch(['playlist',       'title',        '_index',     '?'],                               [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'tracks',       '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'url',          '?'],                                             [1, 1, 0, \&Slim::Control::Queries::playlistXQuery]);
    addDispatch(['playlist',       'zap',          '_index'],                                        [1, 0, 0, \&Slim::Control::Commands::playlistZapCommand]);
    addDispatch(['playlisttracks', '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playlisttracksQuery]);
    addDispatch(['playlists',      '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::playlistsQuery]);
    addDispatch(['playlistcontrol'],                                                                 [1, 0, 1, \&Slim::Control::Commands::playlistcontrolCommand]);
    addDispatch(['power',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::powerQuery]);
    addDispatch(['power',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::powerCommand]);
    addDispatch(['pref',           '_prefname',    '?'],                                             [0, 1, 0, \&Slim::Control::Queries::prefQuery]);
    addDispatch(['pref',           '_prefname',    '_newvalue'],                                     [0, 0, 0, \&Slim::Control::Commands::prefCommand]);
    addDispatch(['rate',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::rateQuery]);
    addDispatch(['rate',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::rateCommand]);
    addDispatch(['rescan',         '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::rescanQuery]);
    addDispatch(['rescan',         '_playlists'],                                                    [0, 0, 0, \&Slim::Control::Commands::rescanCommand]);
    addDispatch(['show'],                                                                            [1, 0, 1, \&Slim::Control::Commands::showCommand]);
    addDispatch(['signalstrength', '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::signalstrengthQuery]);
    addDispatch(['sleep',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::sleepQuery]);
    addDispatch(['sleep',          '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::sleepCommand]);
    addDispatch(['songinfo',       '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::songinfoQuery]);
    addDispatch(['songs',          '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['status',         '_index',       '_quantity'],                                     [1, 1, 1, \&Slim::Control::Queries::statusQuery]);
    addDispatch(['stop'],                                                                            [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['stopserver'],                                                                      [0, 0, 0, \&main::stopServer]);
    addDispatch(['sync',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::syncQuery]);
    addDispatch(['sync',           '_indexid-'],                                                     [1, 0, 0, \&Slim::Control::Commands::syncCommand]);
    addDispatch(['time',           '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['time',           '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
    addDispatch(['title',          '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::cursonginfoQuery]);
    addDispatch(['titles',         '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['tracks',         '_index',       '_quantity'],                                     [0, 1, 1, \&Slim::Control::Queries::titlesQuery]);
    addDispatch(['version',        '?'],                                                             [0, 1, 0, \&Slim::Control::Queries::versionQuery]);
    addDispatch(['wipecache'],                                                                       [0, 0, 0, \&Slim::Control::Commands::wipecacheCommand]);

# NOTIFICATIONS
    addDispatch(['client',         'disconnect'],                                                    [1, 0, 0, undef]);
    addDispatch(['client',         'new'],                                                           [1, 0, 0, undef]);
    addDispatch(['client',         'reconnect'],                                                     [1, 0, 0, undef]);
    addDispatch(['playlist',       'load_done'],                                                     [1, 0, 0, undef]);
    addDispatch(['playlist',       'newsong'],                                                       [1, 0, 0, undef]);
    addDispatch(['playlist',       'open',         '_path'],                                         [1, 0, 0, undef]);
    addDispatch(['playlist',       'sync'],                                                          [1, 0, 0, undef]);
    addDispatch(['playlist',       'cant_open',    '_url'],                                          [1, 0, 0, undef]);
    addDispatch(['rescan',         'done'],                                                          [0, 0, 0, undef]);
    addDispatch(['unknownir',      '_ircode',      '_time'],                                         [1, 0, 0, undef]);

# DEPRECATED
	addDispatch(['mode',           'pause'],                                                         [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'play'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
    addDispatch(['mode',           'stop'],                                                          [1, 0, 0, \&Slim::Control::Commands::playcontrolCommand]);
	# use commands "pause", "play" and "stop"
    
    addDispatch(['gototime',       '?'],                                                             [1, 1, 0, \&Slim::Control::Queries::timeQuery]);
    addDispatch(['gototime',       '_newvalue'],                                                     [1, 0, 0, \&Slim::Control::Commands::timeCommand]);
	# use command "time"

######################################################################################################################################################################

}

# add an entry to the dispatch DB
sub addDispatch {
	my $arrayCmdRef  = shift; # the array containing the command or query
	my $arrayDataRef = shift; # the array containing the function to call

# parse the first array in parameter to create a multi level hash providing
# fast access to 2nd array data, i.e. (the example is incomplete!)
# { 
#  'rescan' => {
#               '?'          => 2nd array associated with ['rescan', '?']
#               '_playlists' => 2nd array associated with ['rescan', '_playlists']
#              },
#  'info'   => {
#               'total'      => {
#                                'albums'  => 2nd array associated with ['info', 'total', albums']
# ...
#
# this is used by init() above to add the standard commands and queries to the 
# table and by the plugin glue code to add plugin-specific and plugin-defined
# commands and queries to the system.
# Note that for the moment, there is no identified need to ever REMOVE commands
# from the dispatch table (and consequently no defined function for that).

	my $DBp     = \%dispatchDB;	    # pointer to the current table level
	my $CRindex = 0;                # current index into $arrayCmdRef
	my $done    = 0;                # are we done
	my $oldDR;						# if we replace, what did we?
	
	while (!$done) {
	
		# check if we have a subsequent verb in the command
		my $haveNextLevel = defined $arrayCmdRef->[$CRindex + 1];
		
		# get the verb at the current level of the command
		my $curVerb       = $arrayCmdRef->[$CRindex];
	
		# if the verb is undefined at the current level
		if (!defined $DBp->{$curVerb}) {
		
			# if we have a next verb, prepare a hash for it
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {};
			
			# else store the 2nd array and we're done
			} else {
			
				$DBp->{$curVerb} = $arrayDataRef;
				$done = 1;
			}
		}
		
		# if the verb defined at the current level points to an array
		elsif (ref $DBp->{$curVerb} eq 'ARRAY') {
		
			# if we have more terms, move the array to the next level using
			# an empty verb
			# (note: at the time of writing these lines, this never occurs with
			# the commands as defined now)
			if ($haveNextLevel) {
			
				$DBp->{$curVerb} = {'', $DBp->{$curVerb}};
			
			# if we're out of terms, something is maybe wrong as we're adding 
			# twice the same command. In Perl hash fashion, replace silently with
			# the new value and we're done
			} else {
			
				$oldDR = $DBp->{$curVerb};
				$DBp->{$curVerb} = $arrayDataRef;
				$done = 1;
			}
		}
		
		# go to next level if not done...
		if (!$done) {
		
			$DBp = \%{$DBp->{$curVerb}};
			$CRindex++;
		}
	}
	
	# return what we replaced, if any
	return $oldDR;
}

# add a subscriber to be notified of requests
sub subscribe {
	my $subscriberFuncRef = shift || return;
	my $requestsRef = shift;
	
	$subscribers{$subscriberFuncRef} = [$subscriberFuncRef, $requestsRef];
	
	$::d_command && $d_notify && msgf(
		"Request: subscribe(%s) - (%d subscribers)\n",
		Slim::Utils::PerlRunTime::realNameForCodeRef($subscriberFuncRef),
		scalar(keys %subscribers)
	);
}

# remove a subscriber
sub unsubscribe {
	my $subscriberFuncRef = shift;
	
	delete $subscribers{$subscriberFuncRef};

	$::d_command && $d_notify && msgf(
		"Request: unsubscribe(%s) - (%d subscribers)\n",
		Slim::Utils::PerlRunTime::realNameForCodeRef($subscriberFuncRef),
		scalar(keys %subscribers)
	);
}

# notify subscribers from an array, useful for notifying w/o execution
# (requests must, however, be defined in the dispatch table)
sub notifyFromArray {
	my $client         = shift;     # client, if any, to which the query applies
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs

	$::d_command && $d_notify && msg("Request: notifyFromArray(" .
						(join " ", @{$requestLineRef}) . ")\n");

	my $request = Slim::Control::Request->new(
									(blessed($client) ? $client->id() : undef), 
									$requestLineRef
								);
	
	push @notificationQueue, $request;
}

# sends notifications for first entry in queue - called once per idle loop
sub checkNotifications {
	
	return 0 if (!scalar @notificationQueue);

	# notify first entry on queue
	my $request = shift @notificationQueue;
	$request->notify() if blessed($request);

	return 1;
}

# convenient function to execute a request from an array, with optional
# callback parameters. Returns the Request object.
sub executeRequest {
	my($client, $parrayref, $callbackf, $callbackargs) = @_;

	# create a request from the array
	my $request = Slim::Control::Request->new( 
									(blessed($client) ? $client->id() : undef), 
									$parrayref
								);
	
	if (defined $request && $request->isStatusDispatchable()) {
		
		# add callback params
		$request->callbackParameters($callbackf, $callbackargs);
		
		$request->execute();
	}

	return $request;
}

################################################################################
# Constructors
################################################################################

sub new {
	my $class          = shift;    # class to construct
	my $clientid       = shift;    # clientid, if any, to which the request applies
	my $requestLineRef = shift;    # reference to an array containing the 
                                   # request verbs
	
	tie (my %paramHash, "Tie::LLHash", {lazy => 1});
	tie (my %resultHash, "Tie::LLHash", {lazy => 1});
	
	my $self = {
		'_request'    => [],
		'_isQuery'    => undef,
		'_clientid'   => $clientid,
		'_needClient' => 0,
		'_params'     => \%paramHash,
		'_curparam'   => 0,
		'_status'     => 0,
		'_results'    => \%resultHash,
		'_func'       => undef,
		'_cb_enable'  => 1,
		'_cb_func'    => undef,
		'_cb_args'    => undef,
		'_source'     => undef,
		'_private'    => undef,
	};

	bless $self, $class;
	
	# parse $requestLineRef to finish create the Request
	$self->__parse($requestLineRef) if defined $requestLineRef;
	
	$self->validate();
	
	return $self;
}

# makes a request out of another one, discarding results and callback data.
# except for '_private' which we don't know about, all data is 
# duplicated
sub virginCopy {
	my $self = shift;
	
	my $copy = Slim::Control::Request->new($self->clientid());
	
	# fill in the scalars
	$copy->{'_isQuery'} = $self->{'_isQuery'};
	$copy->{'_needClient'} = $self->{'_needClient'};
	$copy->{'_func'} = \&{$self->{'_func'}};
	$copy->{'_source'} = $self->{'_source'};
	$copy->{'_private'} = $self->{'_private'};
	$copy->{'_curparam'} = $self->{'_curparam'};
	
	# duplicate the arrays and hashes
	my @request = @{$self->{'_request'}};
	$copy->{'_request'} = \@request;

	tie (my %paramHash, "Tie::LLHash", {lazy => 1});	
	while (my ($key, $val) = each %{$self->{'_params'}}) {
		$paramHash{$key} = $val;
 	}
	$copy->{'_params'} = \%paramHash;
	
	$self->validate();
	
	return $copy;
}
	

################################################################################
# Read/Write basic query attributes
################################################################################

# sets/returns the client (we store the id only)
sub client {
	my $self = shift;
	my $client = shift;
	
	if (defined $client) {
		$self->{'_clientid'} = (blessed($client) ? $client->id() : undef);
		$self->validate();
	}
	
	return Slim::Player::Client::getClient($self->{'_clientid'});
}

# sets/returns the client ID
sub clientid {
	my $self = shift;
	my $clientid = shift;
	
	if (defined $clientid) {
		$self->{'_clientid'} = $clientid;
		$self->validate();
	}
	
	return $self->{'_clientid'};
}

# sets/returns the need client state
sub needClient {
	my $self = shift;
	my $needClient = shift;
	
	if (defined $needClient) {
		$self->{'_needClient'} = $needClient;
		$self->validate();
	}

	return $self->{'_needClient'};
}

# sets/returns the query state
sub query {
	my $self = shift;
	my $isQuery = shift;
	
	$self->{'_isQuery'} = $isQuery if defined $isQuery;
	
	return $self->{'_isQuery'};
}

# sets/returns the function that executes the request
sub function {
	my $self = shift;
	my $newvalue = shift;
	
	if (defined $newvalue) {
		$self->{'_func'} = $newvalue;
		$self->validate();
	}
	
	return $self->{'_func'};
}

# sets/returns the callback enabled state
sub callbackEnabled {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_enable'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_enable'};
}

# sets/returns the callback function
sub callbackFunction {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_func'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_func'};
}

# sets/returns the callback arguments
sub callbackArguments {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_cb_args'} = $newvalue if defined $newvalue;
	
	return $self->{'_cb_args'};
}

# sets/returns the request source
sub source {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_source'} = $newvalue if defined $newvalue;
	
	return $self->{'_source'};
}

# sets/returns the source private data
sub privateData {
	my $self = shift;
	my $newvalue = shift;
	
	$self->{'_private'} = $newvalue if defined $newvalue;
	
	return $self->{'_private'};
}


################################################################################
# Read/Write status
################################################################################
# useful hash for debugging and as a reminder when writing new status methods
my %statusMap = (
	  0 => 'New',
	  1 => 'Dispatchable',
	  2 => 'Dispatched',
	  3 => 'Processing',
	 10 => 'Done',
#	 11 => 'Callback done',
	101 => 'Bad dispatch!',
	102 => 'Bad params!',
	103 => 'Missing client!',
	104 => 'Unkown in dispatch table',
);

# validate the Request, make sure we are dispatchable
sub validate {
	my $self = shift;

	if (ref($self->{'_func'}) ne 'CODE') {

		$self->setStatusNotDispatchable();

	} elsif ($self->{'_needClient'} && 
				(!defined $self->{'_clientid'} || 
				!defined Slim::Player::Client::getClient($self->{'_clientid'}))){

		$self->setStatusNeedsClient();
		$self->{'_clientid'} = undef;

	} else {

		$self->setStatusDispatchable();
	}
}

sub isStatusNew {
	my $self = shift;
	return ($self->__status() == 0);
}

sub setStatusDispatchable {
	my $self = shift;
	$self->__status(1);
}

sub isStatusDispatchable {
	my $self = shift;
	return ($self->__status() == 1);
}

sub setStatusDispatched {
	my $self = shift;
	$self->__status(2);
}

sub isStatusDispatched {
	my $self = shift;
	return ($self->__status() == 2);
}

sub wasStatusDispatched {
	my $self = shift;
	return ($self->__status() > 1);
}

sub setStatusProcessing {
	my $self = shift;
	$self->__status(3);
}

sub isStatusProcessing {
	my $self = shift;
	return ($self->__status() == 3);
}

sub setStatusDone {
	my $self = shift;
	
	# if we are in processing state, we need to call executeDone AFTER setting
	# the status to Done...
	my $callDone = $self->isStatusProcessing();
	$self->__status(10);
	$self->executeDone() if $callDone;
}

sub isStatusDone {
	my $self = shift;
	return ($self->__status() == 10);
}

sub isStatusError {
	my $self = shift;
	return ($self->__status() > 100);
}

sub setStatusBadDispatch {
	my $self = shift;	
	$self->__status(101);
}

sub isStatusBadDispatch {
	my $self = shift;
	return ($self->__status() == 101);
}

sub setStatusBadParams {
	my $self = shift;	
	$self->__status(102);
}

sub isStatusBadParams {
	my $self = shift;
	return ($self->__status() == 102);
}

sub setStatusNeedsClient {
	my $self = shift;	
	$self->__status(103);
}

sub isStatusNeedsClient {
	my $self = shift;
	return ($self->__status() == 103);
}

sub setStatusNotDispatchable {
	my $self = shift;	
	$self->__status(104);
}

sub isStatusNotDispatchable {
	my $self = shift;
	return ($self->__status() == 104);
}

sub getStatusText {
	my $self = shift;
	return ($statusMap{$self->__status()});
}
################################################################################
# Request mgmt
################################################################################

# returns the request name. Read-only
sub getRequestString {
	my $self = shift;
	
	return join " ", @{$self->{_request}};
}

# add a request value to the request array
sub addRequest {
	my $self = shift;
	my $text = shift;

	push @{$self->{'_request'}}, $text;
	++$self->{'_curparam'};
}

sub getRequest {
	my $self = shift;
	my $idx = shift;
	
	return $self->{'_request'}->[$idx];
}

sub getRequestCount {
	my $self = shift;
	my $idx = shift;
	
	return scalar @{$self->{'_request'}};
}

################################################################################
# Param mgmt
################################################################################

# add a parameter
sub addParam {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_params'}}{$key} = $val;
	++$self->{'_curparam'};
}

# add a nameless parameter
sub addParamPos {
	my $self = shift;
	my $val = shift;
	
	${$self->{'_params'}}{ "_p" . $self->{'_curparam'}++ } = $val;
}

# get a parameter by name
sub getParam {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_params'}}{$key};
}

# delete a parameter by name
sub deleteParam {
	my $self = shift;
	my $key = shift || return;
	
	delete ${$self->{'_params'}}{$key};
}

################################################################################
# Result mgmt
################################################################################

sub addResult {
	my $self = shift;
	my $key = shift;
	my $val = shift;

	${$self->{'_results'}}{$key} = $val;
}

sub addResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift;
	my $val = shift;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	if (!defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		tie (my %paramHash, "Tie::LLHash", {lazy => 1});
		${$self->{'_results'}}{$loop}->[$loopidx] = \%paramHash;
	}
	
	${${$self->{'_results'}}{$loop}->[$loopidx]}{$key} = $val;
}

sub setResultLoopHash {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $hashRef = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (!defined ${$self->{'_results'}}{$loop}) {
		${$self->{'_results'}}{$loop} = [];
	}
	
	${$self->{'_results'}}{$loop}->[$loopidx] = $hashRef;
}

sub getResult {
	my $self = shift;
	my $key = shift || return;
	
	return ${$self->{'_results'}}{$key};
}

sub getResultLoopCount {
	my $self = shift;
	my $loop = shift;
	
	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop}) {
		return scalar(@{${$self->{'_results'}}{$loop}});
	}
}

sub getResultLoop {
	my $self = shift;
	my $loop = shift;
	my $loopidx = shift;
	my $key = shift || return undef;

	if ($loop !~ /^@.*/) {
		$loop = '@' . $loop;
	}
	
	if (defined ${$self->{'_results'}}{$loop} && 
		defined ${$self->{'_results'}}{$loop}->[$loopidx]) {
		
			return ${${$self->{'_results'}}{$loop}->[$loopidx]}{$key};
	}
	return undef;
}

sub cleanResults {
	my $self = shift;

	tie (my %resultHash, "Tie::LLHash", {lazy => 1});
	
	# not sure this helps release memory, but can't hurt
	delete $self->{'_results'};

	$self->{'_results'} = \%resultHash;
	
	# this will reset it to dispatchable so we can execute it once more
	$self->validate();
}


################################################################################
# Compound calls
################################################################################

# accepts a reference to an array containing references to arrays containing
# synonyms for the query names, 
# and returns 1 if no name match the request. Used by functions implementing
# queries to check the dispatcher did not send them a wrong request.
# See Queries.pm for usage examples, for example infoTotalQuery.
sub isNotQuery {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(1, $possibleNames);
}

# same for commands
sub isNotCommand {
	my $self = shift;
	my $possibleNames = shift;
	
	return !$self->__isCmdQuery(0, $possibleNames);
}

sub isCommand{
	my $self = shift;
	my $possibleNames = shift;
	
	return $self->__isCmdQuery(0, $possibleNames);
}

sub isQuery{
	my $self = shift;
	my $possibleNames = shift;
	
	return $self->__isCmdQuery(1, $possibleNames);
}


# sets callback parameters (function and arguments) in a single call...
sub callbackParameters {
	my $self = shift;
	my $callbackf = shift;
	my $callbackargs = shift;

	$self->{'_cb_func'} = $callbackf;
	$self->{'_cb_args'} = $callbackargs;	
}

# returns true if $param is undefined or not one of the possible values
# not really a method on request data members but defined as such since it is
# useful for command and queries implementation.
sub paramUndefinedOrNotOneOf {
	my $self = shift;
	my $param = shift;
	my $possibleValues = shift;

	return 1 if !defined $param;
	return 1 if !defined $possibleValues;
	return !grep(/$param/, @{$possibleValues});
}

# returns true if $param being defined, it is not one of the possible values
# not really a method on request data members but defined as such since it is
# useful for command and queries implementation.
sub paramNotOneOfIfDefined {
	my $self = shift;
	my $param = shift;
	my $possibleValues = shift;

	return 0 if !defined $param;
	return 1 if !defined $possibleValues;
	return !grep(/$param/, @{$possibleValues});
}

# not really a method on request data members but defined as such since it is
# useful for command and queries implementation.
sub normalize {
	my $self = shift;
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


################################################################################
# Other
################################################################################

# execute the request
sub execute {
	my $self = shift;
	
	$::d_command && msg("\n");
#	$::d_command && $self->dump("Request");

	# some time may have elapsed between the request creation
	# and its execution, and the client, f.e., could have disappeared
	# check all is OK once more...
	$self->validate();

	# do nothing if something's wrong
	if ($self->isStatusError()) {
		$::d_command && msg('Request: Request in error, exiting');
		return;
	}
	
	# call the execute function
	if (my $funcPtr = $self->{'_func'}) {

		# notify for commands
		# done here so that order of calls is maintained in all cases.
		if (!$self->query()) {
		
			push @notificationQueue, $self;
		}

		eval { &{$funcPtr}($self) };

		if ($@) {
			errorMsg("Request: Error when trying to run function coderef: [$@]\n");
			$self->setStatusBadDispatch();
			$self->dump('Request');
		}
	}
	
	# contine execution unless the Request is still work in progress (async)...
	$self->executeDone() unless $self->isStatusProcessing();
}

# perform end of execution, calling the callback etc...
sub executeDone {
	my $self = shift;
	
	# perform the callback
	# do it unconditionally as it is used to generate the response web page
	# smart callback routines test the request status!
	$self->callback();
		
	if (!$self->isStatusDone()) {
	
		# remove the notification if we pushed it...
		my $notif = pop @notificationQueue;
		
		if ($notif != $self) {
		
			# oops wrong one, repush it...
			push @notificationQueue, $notif;
		}
	}

	$::d_command && $self->dump('Request');
}

sub callback {
	my $self = shift;

	# do nothing unless callback is enabled
	if ($self->callbackEnabled()) {
		
		if (defined(my $funcPtr = $self->callbackFunction())) {

			$::d_command && msg("Request: Calling callback function\n");

			my $args = $self->callbackArguments();
		
			# if we have no arg, use the request
			if (!defined $args) {

				eval { &$funcPtr($self) };

				if ($@) { 
					errorMsg("Request: Error when trying to run callback coderef: [$@]\n");
					$self->dump('Request');
				}
			
			# else use the provided arguments
			} else {

				eval { &$funcPtr(@$args) };

				if ($@) { 
					errorMsg("Request: Error when trying to run callback coderef: [$@]\n");
					$self->dump('Request');
				}
			}
		}
	} else {
	
		$::d_command && msg("Request: Callback disabled\n");
	}
}

# notify subscribers...
sub notify {
	my $self = shift || return;
	my $dontcallExecuteCallback = shift;

	for my $subscriber (keys %subscribers) {

		if ( $subscribers{$subscriber} ) {

			# filter based on desired requests
			# undef means no filter
			my $notifyFuncRef = $subscribers{$subscriber}->[0];
			my $requestsRef   = $subscribers{$subscriber}->[1];

			my $funcName = $subscriber;

			if ($::d_command && $d_notify && ref($notifyFuncRef) eq 'CODE') {
				$funcName = Slim::Utils::PerlRunTime::realNameForCodeRef($notifyFuncRef);
			}
		
			if (defined($requestsRef)) {

				if ($self->isNotCommand($requestsRef)) {

					$::d_command && $d_notify && msg("Request: Don't notify "
						. $funcName . " of " . $self->getRequestString() . " !~ "
						. __filterString($requestsRef) . "\n");

					next;
				}
			}

			$::d_command && $d_notify && msg("Request: Notifying $funcName of " 
				. $self->getRequestString() . " =~ "
				. __filterString($requestsRef) . "\n");
		
			&$notifyFuncRef($self);
		}
	}
	
	# if we must call executeCallback (there are entries in its queue) and
	# this is not where we're been call from, render as Array and call
	# executeCallback with the array.
	# The reason for the first parameter is that renderAsArray is somewhat
	# expensive and we try to avoid it if we can.
	# The reason for the second parameter is simply to avoid a infinite loop...
	if ($callExecuteCallback && !defined $dontcallExecuteCallback) {
		my @params = $self->renderAsArray();
		Slim::Control::Command::executeCallback(
			$self->client(),
			\@params,
			"not again"
			);
	}
}

# handle encoding for external commands
sub fixEncoding {
	my $self = shift || return;
	
	my $encoding = ${$self->{'_params'}}{'charset'} || 'utf8';

	while (my ($key, $val) = each %{$self->{'_params'}}) {

		if (!ref($val)) {

			${$self->{'_params'}}{$key} = Slim::Utils::Unicode::decode($encoding, $val);
		}
	}
}


################################################################################
# Legacy
################################################################################
# support for legacy applications

# perform the same feat that the old execute: array in, array out
sub executeLegacy {

	my $request = executeRequest(@_);
	
	return $request->renderAsArray() if defined $request;
}

# returns the request as an array
sub renderAsArray {
	my $self = shift;
	my $encoding = shift;
	
	my @returnArray;
	
	# conventions: 
	# -- parameter or result with key starting with "_": value outputted
	# -- parameter or result with key starting with "__": no output
	# -- result starting with "@": is a loop
	# -- anything else: output "key:value"
	
	# push the request terms
	push @returnArray, @{$self->{'_request'}};
	
	# push the parameters
	while (my ($key, $val) = each %{$self->{'_params'}}) {

		$val = Slim::Utils::Unicode::encode($encoding, $val) if $encoding;

		if ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ":" . $val);
		}
 	}
 	
 	# push the results
	while (my ($key, $val) = each %{$self->{'_results'}}) {

		$val = Slim::Utils::Unicode::encode($encoding, $val) if $encoding;

		if ($key =~ /^@/) {

			# loop over each elements
			foreach my $hash (@{${$self->{'_results'}}{$key}}) {

				while (my ($key2, $val2) = each %{$hash}) {

					$val2 = Slim::Utils::Unicode::encode($encoding, $val2) 
						if $encoding;

					if ($key2 =~ /^__/) {
						# no output
					} elsif ($key2 =~ /^_/) {
						push @returnArray, $val2;
					} else {
						push @returnArray, ($key2 . ':' . $val2);
					}
				}	
			}

		} elsif ($key =~ /^__/) {
			# no output
		} elsif ($key =~ /^_/) {
			push @returnArray, $val;
		} else {
			push @returnArray, ($key . ':' . $val);
		}
 	}
	
	return @returnArray;
}

# called from Slim::Control::Command::set/clearExecuteCallback, this 
# lets us know if there are entries in the queue and consequently, if 
# we should call the legacy routine.
sub needToCallExecuteCallback {
	$callExecuteCallback = shift;
}

################################################################################
# Utility function to dump state of the request object to stdout
################################################################################
sub dump {
	my $self = shift;
	my $introText = shift || '?';
	
	my $str = $introText . ": ";
	
	if ($self->query()) {
		$str .= 'Query ';
	} else {
		$str .= 'Command ';
	}
	
	if (my $client = $self->client()) {
		my $clientid = $client->id();
		$str .= "[$clientid->" . $self->getRequestString() . "]";
	} else {
		$str .= "[" . $self->getRequestString() . "]";
	}

	if ($self->callbackFunction()) {

		if ($self->callbackEnabled()) {
			$str .= " cb+ ";
		} else {
			$str .= " cb- ";
		}
	}

	if ($self->source()) {
		$str .= " from " . $self->source() ." ";
	}

	$str .= ' (' . $self->getStatusText() . ")\n";
		
	msg($str);

	while (my ($key, $val) = each %{$self->{'_params'}}) {

    		msg("   Param: [$key] = [$val]\n");
 	}
 	
	while (my ($key, $val) = each %{$self->{'_results'}}) {
    	
		if ($key =~ /^@/) {

			my $count = scalar @{${$self->{'_results'}}{$key}};

			msg("   Result: [$key] is loop with $count elements:\n");
			
			# loop over each elements
			for (my $i = 0; $i < $count; $i++) {

				my $hash = ${$self->{'_results'}}{$key}->[$i];

				while (my ($key2, $val2) = each %{$hash}) {
					msg("   Result:   $i. [$key2] = [$val2]\n");
				}	
			}

		} else {
			msg("   Result: [$key] = [$val]\n");
		}
 	}
}

################################################################################
# Private methods
################################################################################
sub __isCmdQuery {
	my $self = shift;
	my $isQuery = shift;
	my $possibleNames = shift;
	
	# the query state must match
	if ($isQuery == $self->{'_isQuery'}) {

		my $possibleNamesCount = scalar (@{$possibleNames});

		# we must have the same number (or more) of request terms
		# than of passed names
		if ((scalar(@{$self->{'_request'}})) >= $possibleNamesCount) {

			# check each request term matches one of the passed params
			for (my $i = 0; $i < $possibleNamesCount; $i++) {
				
				my $name = $self->{'_request'}->[$i];;

				# return as soon we fail
				return 0 if !grep(/^$name$/, @{$possibleNames->[$i]});
			}

			# everything matched
			return 1;
		}
	}
	return 0;
}

# sets/returns the status state of the request
sub __status {
	my $self = shift;
	my $status = shift;
	
	$self->{'_status'} = $status if defined $status;
	
	return $self->{'_status'};
}

# returns a string corresponding to the notification filter, used for 
# debugging
sub __filterString {
	my $requestsRef = shift;
	
	return "(no filter)" if !defined $requestsRef;
	
	my $str = "[";

	foreach my $req (@$requestsRef) {
		$str .= "[";
		my @list = map { "\'$_\'" } @$req;
		$str .= join(",", @list);
		$str .= "]";
	}
		
	$str .= "]";
}

# given a command or query in an array, walk down the dispatch DB to find
# the function to call for it. Used by the Request constructor
sub __parse {
	my $self           = shift;
	my $requestLineRef = shift;     # reference to an array containing the 
									# query verbs
		
#	$::d_command && msg("Request: parse(" 
#						. (join " ", @{$requestLineRef}) . ")\n");

	my $debug = 0;					# debug flag internal to the function


	my $found;						# have we found the right command
	my $outofverbs;					# signals we're out of verbs to try and match
	my $LRindex    = 0;				# index into $requestLineRef
	my $done       = 0;				# are we done yet?
	my $DBp        = \%dispatchDB;	# pointer in the dispatch table
	my $match      = $requestLineRef->[$LRindex];
									# verb of the command we're trying to match

	while (!$done) {
	
		# we're out of verbs to check for a match -> try with ''
		if (!defined $match) {

			$match = '';
			$outofverbs = 1;
		}

		$debug && msg("..Trying to match [$match]\n");
		$debug && print Data::Dumper::Dumper($DBp);

		# our verb does not match in the hash 
		if (!defined $DBp->{$match}) {
		
			$debug && msg("..no match for [$match]\n");
			
			# if $match is '?', abandon ship
			if ($match eq '?') {
			
				$debug && msg("...[$match] is ?, done\n");
				$done = 1;
				
			} else {
			
				my $foundparam = 0;
				my $key;

				# Can we find a key that starts with '_' ?
				$debug && msg("...looking for a key starting with _\n");
				foreach $key (keys %{$DBp}) {
				
					$debug && msg("....considering [$key]\n");
					
					if ($key =~ /^_.*/) {
					
						$debug && msg("....[$key] starts with _\n");
						
						# found it, add $key=$match to the params
						if (!$outofverbs) {
							$debug && msg("....not out of verbs, adding param [$key, $match]\n");
							$self->addParam($key, $match);
						}
						
						# and continue with $key...
						$foundparam = 1;
						$match = $key;
						last;
					}
				}
				
				if (!$foundparam) {
					$done = 1;
				}
			}
		}
		
		# Our verb matches, and it is an array -> done
		if (!$done && ref $DBp->{$match} eq 'ARRAY') {
		
			$debug && msg("..[$match] is ARRAY -> done\n");
			
			if ($match ne '' && !($match =~ /^_.*/) && $match ne '?') {
			
				# add $match to the request list if it is something sensible
				$self->addRequest($match);
			}

			# we're pointing to an array -> done
			$done = 1;
			$found = $DBp->{$match};
		}
		
		# Our verb matches, and it is a hash -> go to next level
		# (no backtracking...)
		if (!$done && ref $DBp->{$match} eq 'HASH') {
		
			$debug && msg("..[$match] is HASH\n");

			if ($match ne '' && !($match =~ /^_.*/) && $match ne '?') {
			
				# add $match to the request list if it is something sensible
				$self->addRequest($match);
			}

			$DBp = \%{$DBp->{$match}};
			$match = $requestLineRef->[++$LRindex];
		}
	}

	if (defined $found) {
		# 0: needs client
		# 1: is a query
		# 2: has Tags
		# 3: Function
		
		# handle the remaining params
		for (my $i=++$LRindex; $i < scalar @{$requestLineRef}; $i++) {
			
			# try tags if we know we have some
			if ($found->[2] && ($requestLineRef->[$i] =~ /([^:]+):(.*)/)) {

				$self->addParam($1, $2);

			} else {
			
				# default to positional param...
				$self->addParamPos($requestLineRef->[$i]);
			}
		}
		
		$self->{'_needClient'} = $found->[0];
		$self->{'_isQuery'} = $found->[1];
		$self->{'_func'} = $found->[3];
				
	} else {

		$::d_command && msg("Request [" . (join " ", @{$requestLineRef}) . "]: no match in dispatchDB!\n");

		# handle the remaining params, if any...
		# only for the benefit of CLI echoing...
		for (my $i=$LRindex; $i < scalar @{$requestLineRef}; $i++) {
			$self->addParamPos($requestLineRef->[$i]);
		}
	}
}


1;

__END__
