package Slim::Formats::Ogg;

# $Id$

# SqueezeCenter Copyright 2001-2007 Logitech.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

=head1 NAME

Slim::Formats::Ogg

=head1 SYNOPSIS

my $tags = Slim::Formats::Ogg->getTag( $filename );

=head1 DESCRIPTION

Read tags & metadata embedded in Ogg Vorbis files.

=head1 METHODS

=cut

use strict;
use base qw(Slim::Formats);

use Slim::Utils::Log;
use Slim::Utils::Unicode;

use MIME::Base64 qw(decode_base64);
use Ogg::Vorbis::Header::PurePerl;

my %tagMapping = (
	'TRACKNUMBER'               => 'TRACKNUM',
	'DISCNUMBER'                => 'DISC',
	'URL'                       => 'URLTAG',
	'MUSICBRAINZ_SORTNAME'      => 'ARTISTSORT',
	'MUSICBRAINZ_ALBUMARTIST'   => 'ALBUMARTIST',
	'MUSICBRAINZ_ALBUMARTISTID' => 'MUSICBRAINZ_ALBUMARTIST_ID',
	'MUSICBRAINZ_ALBUMID'       => 'MUSICBRAINZ_ALBUM_ID',
	'MUSICBRAINZ_ALBUMSTATUS'   => 'MUSICBRAINZ_ALBUM_STATUS',
	'MUSICBRAINZ_ALBUMTYPE'     => 'MUSICBRAINZ_ALBUM_TYPE',
	'MUSICBRAINZ_ARTISTID'      => 'MUSICBRAINZ_ARTIST_ID',
	'MUSICBRAINZ_TRACKID'       => 'MUSICBRAINZ_ID',
	'MUSICBRAINZ_TRMID'         => 'MUSICBRAINZ_TRM_ID',
);

=head2 getTag( $filename )

Extract and return audio information & any embedded metadata found.

=cut

sub getTag {
	my $class = shift;
	my $file  = shift || return {};

	# This hash will map the keys in the tag to their values.
	my $tags = {};
	my $ogg  = undef;

	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new($file);
	};

	if (!$ogg or $@) {

		logWarning("Warning Can't open Ogg file $file: [$@]");

		return $tags;
	}

	if (!$ogg->info('length')) {

		logWarning("Length for Ogg file: $file is 0 - skipping.");

		return $tags;
	}

	# Tags can be stacked, in an array.
	foreach my $key ($ogg->comment_tags) {

		my $ucKey  = uc($key);
		my @values = $ogg->comment($key);
		my $count  = scalar @values;

		for my $value (@values) {

			if ($] > 5.007) {
				$value = Slim::Utils::Unicode::utf8decode($value, 'utf8');
			} else {
				$value = Slim::Utils::Unicode::utf8toLatin1($value);
			}

			if ($count == 1) {

				$tags->{$ucKey} = $value;

			} else {

				push @{$tags->{$ucKey}}, $value;
			}
		}
	}

	# Correct ogginfo tags
	while (my ($old,$new) = each %tagMapping) {

		if (exists $tags->{$old}) {

			$tags->{$new} = delete $tags->{$old};
		}
	}

	# Special handling for DATE tags
	# Parse the date down to just the year, for compatibility with other formats
	if (defined $tags->{'DATE'} && !defined $tags->{'YEAR'}) {
		($tags->{'YEAR'} = $tags->{'DATE'}) =~ s/.*(\d\d\d\d).*/$1/;
	}

	# Add additional info
	$tags->{'SIZE'}	    = -s $file;

	$tags->{'SECS'}	    = $ogg->info('length');
	$tags->{'BITRATE'}  = $ogg->info('bitrate_average') || $ogg->info('bitrate_nominal');
	$tags->{'STEREO'}   = $ogg->info('channels') == 2 ? 1 : 0;
	$tags->{'CHANNELS'} = $ogg->info('channels');
	$tags->{'RATE'}	    = $ogg->info('rate');

	if (defined $ogg->info('bitrate_upper') && defined $ogg->info('bitrate_lower')) {

		if ($ogg->info('bitrate_upper') != $ogg->info('bitrate_lower')) {

			$tags->{'VBR_SCALE'} = 1;
		} else {
			$tags->{'VBR_SCALE'} = 0;
		}

	} else {

		$tags->{'VBR_SCALE'} = 0;
	}

	$tags->{'OFFSET'}   =  0; # the header is an important part of the file. don't skip it
	
	# Read cover art if available
	if ( $tags->{'COVERART'} ) {
		$tags->{'ARTWORK'} = decode_base64( delete $tags->{'COVERART'} );
	}

	return $tags;
}

=head2 scanBitrate( $fh )

Scans a file and returns just the bitrate and VBR setting.  This is used
to determine the bitrate for remote streams.  This method is not very accurate
for Ogg files because we only know the nominal bitrate value, not the actual average
bitrate.

=cut

sub scanBitrate {
	my $class = shift;
	my $fh    = shift;
	
	my $ogg;
	my $log   = logger('scan.scanner');
	
	# some ogg files can blow up - especially if they are invalid.
	eval {
		local $^W = 0;
		$ogg = Ogg::Vorbis::Header::PurePerl->new( $fh->filename );
	};

	if ( !$ogg || $@ ) {

		logWarning("Unable to parse Ogg stream");

		return (-1, undef);
	}
	
	my $vbr = 0;

	if (defined $ogg->info('bitrate_upper') && defined $ogg->info('bitrate_lower')) {

		if ($ogg->info('bitrate_upper') != $ogg->info('bitrate_lower')) {

			$vbr = 1;
		}
	}
	
	if ( my $bitrate = $ogg->info('bitrate_nominal') ) {

		if ( $log->is_debug ) {
			$log->debug("Found bitrate header: $bitrate kbps " . ( $vbr ? 'VBR' : 'CBR' ));
		}

		return ( $bitrate, $vbr );
	}
	
	logWarning("Unable to read bitrate from stream!");

	return (-1, undef);
}

1;
