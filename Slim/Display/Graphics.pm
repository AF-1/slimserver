package Slim::Display::Graphics;

# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use File::Spec::Functions qw(catdir);
use FindBin qw($Bin);
use Tie::Cache::LRU;

use Slim::Utils::Misc;
use Slim::Utils::OSDetect;

use Storable;

our $fonts;
our $fonthash;
our $fontheight;
our $fontextents;

my $char0 = chr(0);
my $ord0a = ord("\x0a");

# TrueType support by using GD
my $canUseGD = eval {
	require GD;
	return 1;
};

my $gdError = $@;

my ($gd, $GDBlack, $GDWhite, $TTFFontFile, $useTTFCache, $useTTF);

# Keep a cache of up to 256 characters at a time.
tie my %TTFCache, 'Tie::Cache::LRU', 256;

my %font2TTF = (

	'standard.1' => {
		'GDFontSize' => 8,
		'GDBaseline' => 8,
	},

	'standard.2' => {
		'GDFontSize' => 14,
		'GDBaseline' => 27,
	},

	'light.1' => {
		'GDFontSize' => 9,
		'GDBaseline' => 10,
	},

	'light.2' => {
		'GDFontSize' => 11,
		'GDBaseline' => 28,
	},

	'full.2' => {
		'GDFontSize' => 18,
		'GDBaseline' => 24,
	},

	'high.2' => {
		'GDFontSize' => 7,
		'GDBaseline' => 7,
	},
);

sub init {
	loadFonts();

	$::d_graphics && msgf("Trying to load GD Library for TTF support: %s\n", $canUseGD ? 'ok' : 'not ok!');

	unless ($canUseGD) {
		$::d_graphics && msg("Error while trying to load GD Library: [$gdError]\n");
	}

	# Initialize an image for working (1 character=32x32) and some variables...
	# Try a few different fonts..
	for my $fontFile (qw(arialuni.ttf ARIALUNI.TTF CODE2000.TTF Cyberbit.ttf CYBERBIT.TTF)) {

		$TTFFontFile = catdir($Bin, 'Graphics', $fontFile);

		if ($canUseGD && -e $TTFFontFile) {

			$useTTF = 1;
			last;
		}
	}

	if ($useTTF) {

		$::d_graphics && msgf("Using TTF for Unicode on Player Display. Font: [$TTFFontFile]\n");

		$useTTFCache = 1;
		%TTFCache    = ();

		# This should be configurable.
		$gd = GD::Image->new(32, 32);

		$GDWhite = $gd->colorAllocate(255,255,255);
		$GDBlack = $gd->colorAllocate(0,0,0);
	}
}

sub gfonthash {
	return $fonthash;
}

sub fontnames {
	my $client = shift;
	my %fontnames;
	my $i=0;
	foreach my $gfont (keys %{$fonthash}) {
		my $fontname = ${$fonthash->{$gfont}->{line2}};
		$fontname =~ s/(\.2)?//g;
		$fontnames{$fontname} = $fontname;
	}
	return \%fontnames;
};

sub fontheight {
	my $fontname = shift;
	return $fontheight->{$fontname};
}

# extent returns the number of rows high a font is rendered (useful for vertical scrolling)
# based on char 0x1f, which is a bitmask of the valid rows.
# negative values are for top-row fonts
sub extent {
	my $fontname = shift;
	return $fontextents->{$fontname} || 0;
}

sub loadExtent {
	my $fontname = shift;

	my $extentbytes = string($fontname, chr(0x1f));	
	
	# count the number of set bits in the extent bytes (up to 32)
	my $extent = unpack( '%32b*', $extentbytes ); 
	
	if ($fontname =~ /\.1/) { $extent = -$extent; }
	
	$fonts->{fontextents}->{$fontname} = $extent;
	
	$::d_graphics && msg(" extent of: $fontname is $extent\n");
}

sub string {
	my $fontname = shift || return '';
	my $string   = shift || return '';

	my $bits = '';

	my $font = $fonts->{$fontname} || do {
		msg(" Invalid font $fontname\n");
		bt();
		return '';
	};
	
	my $interspace = $font->[0];
	my $cursorpos = undef;
	my $cursorend = 0;
	my $unpackTemplate = 'C*';

	# U - unpacks Unicode chars into ords, much faster than split(//, $string)
	# C - is needed for older 5.6 perl's
	if ($] > 5.007) {
		$unpackTemplate = 'U*';
	}

	# Font size & Offsets -- Optimized for the free Japanese TrueType font
	# 'sazanami-gothic' from 'waka'.
	#
	# They seem to work pretty well for CODE2000 & Cyberbit as well. - dsully
	my ($GDFontSize, $GDBaseline);
	my $useTTFNow = 0;

	if ($useTTF && defined $font2TTF{$fontname}) {

		$useTTFNow  = 1;
		$GDFontSize = $font2TTF{$fontname}->{'GDFontSize'};
		$GDBaseline = $font2TTF{$fontname}->{'GDBaseline'};
	}

	for my $ord (unpack($unpackTemplate, $string)) {

		# 29 == \x1d, 28 == \x1c, 10 == \x0a
		if ($ord == 29) { 

			$interspace = ''; 

		} elsif ($ord == 28) {

			$interspace = $font->[0]; 

		} elsif ($ord == 10) {

			$cursorpos = length($bits);

		} else {

			if ($ord > 255 && $useTTFNow) {

				my $bits_tmp = $useTTFCache ? $TTFCache{$fontname}{$ord} : '';

				unless ($bits_tmp) {

					$bits_tmp = '';

					# Create our canvas.
					$gd->filledRectangle(0, 0, 31, 31, $GDWhite);

					# Using a negative color index will
					# disable anti-aliasing, as described
					# in the libgd manual page at
					# http://www.boutell.com/gd/manual2.0.9.html#gdImageStringFT.
					#
					my @GDBounds = $gd->stringFT(-1*$GDBlack, $TTFFontFile, $GDFontSize, 0, 0, $GDBaseline, "&#${ord};");

					# Construct the bitmap
					for (my $x = 0; $x <= $GDBounds[2]; $x++) {

						for (my $y = 0; $y < 32; $y++) {

							$bits_tmp .= $gd->getPixel($x,$y) == $GDBlack ? 1 : 0
						}
					}

					$bits_tmp = pack("B*", $bits_tmp);

					$TTFCache{$fontname}{$ord} = $bits_tmp if $useTTFCache;
				}

				if (defined($cursorpos) && !$cursorend) { 
					$cursorend = length($bits_tmp) / length($font->[$ord0a]);
				}

				$bits .= $bits_tmp;

			} else {

				# We don't handle anything outside ISO-8859-1
				# right now in our non-TTF bitmaps.
				if ($ord > 255) {
					$ord = 63; # 63 == '?'
				}

				if (defined($cursorpos) && !$cursorend) { 
					$cursorend = length($font->[$ord])/ length($font->[$ord0a]); 
				}

				$bits .= $font->[$ord] . $interspace;
			}

		}
	}

	if (defined($cursorpos)) {
		$bits |= ($char0 x $cursorpos) . ($font->[$ord0a] x $cursorend);
	}
		
	return $bits;
}

sub measureText {
	my $fontname = shift;
	my $string = shift;
	my $bits = string($fontname, $string);
	return 0 if (!$fontname || !$fontheight->{$fontname});
	my $len = length($bits)/($fontheight->{$fontname}/8);
	
	return $len;
}
	
sub graphicsDirs {

	my @dirs = catdir($Bin,"Graphics");

	if (Slim::Utils::OSDetect::OS() eq 'mac') {
		push @dirs, $ENV{'HOME'} . "/Library/SlimDevices/Graphics/";
		push @dirs, "/Library/SlimDevices/Graphics/";
	}

	return @dirs;
}

sub fontCacheFile {
	return catdir( Slim::Utils::Prefs::get('cachedir'), 
		Slim::Utils::OSDetect::OS() eq 'unix' ? 'fontcache' : 'fonts.bin');
}

#returns a reference to a hash of filenames/external names and newest modification time
sub fontfiles {
	my %fontfilelist = ();
	my $newest = 0;
	foreach my $fontfiledir (graphicsDirs()) {
		if (opendir(DIR, $fontfiledir)) {
			foreach my $fontfile ( sort(readdir(DIR)) ) {
				if ($fontfile =~ /(.+)\.font.bmp$/) {
					$::d_graphics && msg(" fontfile entry: $fontfile\n");
					$fontfilelist{$1} = catdir($fontfiledir, $fontfile);
					my $moddate = (stat($fontfilelist{$1}))[9]; 
					$newest = $moddate if $moddate > $newest;
				}
			}
			closedir(DIR);
		}
	}
	return ($newest, %fontfilelist);
}

sub loadFonts {
	my $forceParse = shift;

	my ($newest, %fontfiles) = fontfiles();
	my $fontCache = fontCacheFile();
	
	# use stored fontCache if newer than all font files
	if (!$forceParse && -r $fontCache && ($newest < (stat($fontCache))[9])) { 
		# check cache for consitency
		my $cacheOK = 1;

		$::d_graphics && msg( "Retrieving font data from font cache: $fontCache\n");
		eval { $fonts = retrieve($fontCache); };
		
		$::d_graphics && $@ && msg(" Tried loading fonts: $@\n");

		if (!$@ && defined $fonts && defined($fonts->{fonthash}) && defined($fonts->{fontheight}) && defined($fonts->{fontextents})) {
			$fonthash = $fonts->{fonthash};
			$fontheight = $fonts->{fontheight};
			$fontextents = $fonts->{fontextents};
		} else {
			$cacheOK = 0;
		}

		# check for font files being removed
		foreach my $font (keys %{$fontheight}) {
			$cacheOK = 0 if !exists($fontfiles{$font});
		}

		# check for new fonts being added (with old modification date)
		foreach my $font (keys %fontfiles) {
			$cacheOK = 0 if !exists($fontheight->{$font});
		}

		return if $cacheOK;

		$::d_graphics && msg( " font cache contains old data - reparsing fonts\n");
	}

	# otherwise clear data and parse all font files
	$fonts = {};

	foreach my $font (keys %fontfiles) {

		$::d_graphics && msg( "Now parsing: $font\n");
		if ($font =~ m/(.*?).(\d)/i) {
			$fonts->{fonthash}->{$1}->{"line$2"} = \$font;
			$fonts->{fonthash}->{$1}->{"overlay$2"} = \$font;
			$fonts->{fonthash}->{$1}->{"center$2"} = \$font;
		}
		my ($fontgrid, $height) = parseBMP($fontfiles{$font});

		$::d_graphics && msg( " height of: $font is ".($height - 1)."\n");		
		$fonts->{fontheight}->{$font} = $height - 1;
		$fonts->{$font} = parseFont($fontgrid);
		$fonts->{fontextent}->{$font} = loadExtent($font);
	}

	# set to \undef if undefined (e.g. font is double height and only one line defined)
	foreach my $name (keys %{$fonts->{fonthash}}) {
		$fonts->{fonthash}->{$name}->{line1} = \undef if !exists($fonts->{fonthash}->{$name}->{line1});
		$fonts->{fonthash}->{$name}->{line2} = \undef if !exists($fonts->{fonthash}->{$name}->{line2});
		$fonts->{fonthash}->{$name}->{overlay1} = \undef if !exists($fonts->{fonthash}->{$name}->{overlay1});
		$fonts->{fonthash}->{$name}->{overlay2} = \undef if !exists($fonts->{fonthash}->{$name}->{overlay2});
		$fonts->{fonthash}->{$name}->{center1} = \undef if !exists($fonts->{fonthash}->{$name}->{center1});
		$fonts->{fonthash}->{$name}->{center2} = \undef if !exists($fonts->{fonthash}->{$name}->{center2});
	}

	$fonthash = $fonts->{fonthash};
	$fontheight = $fonts->{fontheight};
	$fontextents = $fonts->{fontextents};

	$::d_graphics && msg( "Writing font cache: $fontCache\n");
	store($fonts, $fontCache);
}

# parse the array of pixels ino a font table
sub parseFont {
	use bytes;
	my $g = shift;
	my $fonttable;
	
	my $bottomIndex = scalar(@{$g}) - 1;
	
	my $bottomRow = $g->[$bottomIndex];
	
	my $width = @{scalar($bottomRow)};
	
	my $charIndex = -1;
	
	for (my $i = 0; $i < $width; $i++) {
		#print "\n";
		next if ($bottomRow->[$i]);
		last if (!defined($bottomRow->[$i]));
		$charIndex++;

		my @column = ();
		while (!$bottomRow->[$i]) {
			for (my $j = 0; $j < $bottomIndex; $j++) {
				push @column, $g->[$j][$i]; 
				#print  $g->[$j][$i] ? '*' : ' ';
			}
			#print "\n";
			$i++;
		}
		$fonttable->[$charIndex] = pack("B*", join('',@column));
		#print $charIndex . " " . chr($charIndex) . " " . scalar(@column) . " ". length($fonttable->[$charIndex]) . " i: $i width: $width\n";
	}
	#print "done fonttable\n";
	return $fonttable;
	
}

# parses a monochrome, uncompressed BMP file into an array for font data
sub parseBMP {
	use bytes;
	my $fontfile = shift;
	my $fontstring;
	my @font;
	
	# slurp in bitmap file
	{
		local $/;

		open(my $fh, $fontfile) or do {
			msg(" couldn't open fontfile $fontfile\n"); 
			return undef;
		};

		binmode $fh;
		$fontstring = <$fh>;
	}
	
	my ($type, $fsize, $offset, 
	    $biSize, $biWidth, $biHeight, $biPlanes, $biBitCount, $biCompression, $biSizeImage  ) 
		= unpack("a2 V xx xx V  V V V v v V V xxxx xxxx xxxx xxxx", $fontstring);
	
	if ($type ne "BM") { msg(" No BM header on $fontfile\n"); return undef; }
	if ($fsize ne -s $fontfile) { msg(" Bad size in $fontfile\n"); return undef; }
	if ($biPlanes ne 1) { msg(" Planes must be one, not $biPlanes in $fontfile\n"); return undef; }
	if ($biBitCount ne 1) { msg(" Font files must be one bpp, not $biBitCount in $fontfile\n"); return undef; }
	if ($biCompression ne 0) { msg(" Font files must be uncompressed in $fontfile\n"); return undef; }
	
	# skip over the BMP header and the color table
	$fontstring = substr($fontstring, $offset);
	
	my $bitsPerLine = $biWidth - ($biWidth % 32);
	$bitsPerLine += 32 if ($biWidth % 32); # round up to 32 pixels wide

	for (my $i = 0 ; $i < $biHeight; $i++) {

		my @line = ();

		my $bitstring = substr(unpack( "B$bitsPerLine", substr($fontstring, $i * $bitsPerLine / 8) ), 0,$biWidth);
		my $bsLength  = length($bitstring);

		# Surprisingly, this loop is about 20% faster than doing split(//, $bitString)
		for (my $j = 0; $j < $bsLength; $j++) {

			$line[$j] = substr($bitstring, $j, 1);
		}

		$font[$biHeight-$i-1] = \@line;
	}	

	return (\@font, $biHeight);
}

1;


__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
