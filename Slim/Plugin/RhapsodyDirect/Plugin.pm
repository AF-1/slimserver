package Slim::Plugin::RhapsodyDirect::Plugin;

# $Id$

# Browse Rhapsody Direct via SqueezeNetwork

use strict;
use base 'Slim::Plugin::OPMLBased';

use Slim::Networking::SqueezeNetwork;
use Slim::Plugin::RhapsodyDirect::ProtocolHandler;
use Slim::Plugin::RhapsodyDirect::RPDS ();

my $log = Slim::Utils::Log->addLogCategory({
	'category'     => 'plugin.rhapsodydirect',
	'defaultLevel' => $ENV{RHAPSODY_DEV} ? 'DEBUG' : 'ERROR',
	'description'  => 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME',
});

sub initPlugin {
	my $class = shift;
	
	Slim::Player::ProtocolHandlers->registerHandler(
		rhapd => 'Slim::Plugin::RhapsodyDirect::ProtocolHandler'
	);
	
	Slim::Networking::Slimproto::addHandler( 
		RPDS => \&Slim::Plugin::RhapsodyDirect::RPDS::rpds_handler
	);

	$class->SUPER::initPlugin(
		feed   => Slim::Networking::SqueezeNetwork->url('/api/rhapsody/v1/opml'),
		tag    => 'rhapsodydirect',
		menu   => 'music_services',
		weight => 20,
	);
	
	if ( !$ENV{SLIM_SERVICE} ) {
		# Add a function to view trackinfo in the web
		Slim::Web::HTTP::addPageFunction( 
			'plugins/rhapsodydirect/trackinfo.html',
			sub {
				my $client = $_[0];
				my $params = $_[1];
				
				my $url;
				
				if ( $params->{item} ) {
					# The user clicked on a different URL than is currently playing
					if ( my $track = Slim::Schema->find( Track => $params->{item} ) ) {
						$url = $track->url;
					}
				}
				else {
					$url = Slim::Player::Playlist::url($client);
				}
				
				Slim::Web::XMLBrowser->handleWebIndex( {
					client  => $client,
					feed    => Slim::Plugin::RhapsodyDirect::ProtocolHandler->trackInfoURL( $client, $url ),
					path    => 'trackinfo.html',
					title   => 'Rhapsody Direct Track Info',
					timeout => 35,
					args    => \@_
				} );
			},
		);
	}
}

sub playerMenu () {
	return 'MUSIC_SERVICES';
}

sub getDisplayName () {
	return 'PLUGIN_RHAPSODY_DIRECT_MODULE_NAME';
}

sub handleError {
	my ( $error, $client ) = @_;
	
	$log->debug("Error during request: $error");
	
	# Strip long number string from front of error
	$error =~ s/\d+( : )?//;
	
	# Allow status updates again
	$client->suppressStatus(0);
	
	# XXX: Need to give error feedback for web requests

	if ( $client ) {
		$client->unblock;
		
		Slim::Buttons::Common::pushModeLeft( $client, 'INPUT.Choice', {
			header  => '{PLUGIN_RHAPSODY_DIRECT_ERROR}',
			listRef => [ $error ],
		} );
		
		if ( $ENV{SLIM_SERVICE} ) {
		    logError( $client, $error );
		}
	}
}

1;
