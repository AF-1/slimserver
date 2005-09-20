package Slim::Utils::Unicode;

# $Id$

use strict;

# This module is a wrapper around Encode:: functions, and comprises character
# set guessing, encoding, decoding and translation. 
#
# Most of these functions are non-ops on perl < 5.8.x
#
# The recompose & decompose parts have been modified from Simon's defunct
# Unicode::Decompose mdoule.
#
# Unicode characters that somehow become decomposed. Sometimes we'll see a URI
# encoding such as: o%CC%88 - which is an o with diaeresis. The correct
# (composed) version of this should be %C3%B6
#
# Proper documentation forthcoming.

use Fcntl qw(:seek);
use POSIX qw(strftime setlocale LC_TIME LC_CTYPE);

if ($] > 5.007) {
	require Encode;
	require File::BOM;
}

use Slim::Utils::Misc;

# Find out what code page we're in, so we can properly translate file/directory encodings.
our ($locale, $utf8_re_bits, $recomposeTable, $decomposeTable, $recomposeRE, $decomposeRE);

INIT {
        if ($^O =~ /Win32/) {

		my $langid = Win32::OLE::NLS::GetUserDefaultLangID();
		my $lcid   = Win32::OLE::NLS::MAKELCID($langid);
		my $linfo  = Win32::OLE::NLS::GetLocaleInfo($lcid, Win32::OLE::NLS::LOCALE_IDEFAULTANSICODEPAGE());

		$locale = "cp$linfo";

	} elsif ($^O =~ /darwin/) {

		# I believe this is correct from reading:
		# http://developer.apple.com/documentation/MacOSX/Conceptual/SystemOverview/FileSystem/chapter_8_section_6.html
		$locale = 'utf8';

	} else {

		my $lc = POSIX::setlocale(LC_CTYPE) || 'C';

		# If the locale is C or POSIX, that's ASCII - we'll set to iso-8859-1
		# Otherwise, normalize the codeset part of the locale.
		if ($lc eq 'C' || $lc eq 'POSIX') {
			$lc = 'iso-8859-1';
		} else {
			$lc = lc((split(/\./, $lc))[1]);
		}

		# Locale can end up with nothing, if it's invalid, such as "en_US"
		if (!defined $lc || $lc =~ /^\s*$/) {
			$lc = 'iso-8859-1';
		}

		# Sometimes underscores can be aliases - Solaris
		$lc =~ s/_/-/g;

		# ISO encodings with 4 or more digits use a hyphen after "ISO"
		$lc =~ s/^iso(\d{4})/iso-$1/;

		# Special case ISO 2022 and 8859 to be nice
		$lc =~ s/^iso-(2022|8859)([^-])/iso-$1-$2/;

		$lc =~ s/utf-8/utf8/gi;

		# CJK Locales
		$lc =~ s/eucjp/euc-jp/i;
		$lc =~ s/ujis/euc-jp/i;
		$lc =~ s/sjis/shiftjis/i;
		$lc =~ s/euckr/euc-kr/i;
		$lc =~ s/big5/big5-eten/i;
		$lc =~ s/gb2312/euc-cn/i;

		$locale = $lc;
	}

	# Setup suspects for Encode::Guess based on the locale - we might also
	# want to use our own Language pref?
	if ($locale ne 'utf8') {

		Encode::Guess->add_suspects($locale);
	}

	# Create a regex for looks_like_utf8()
	$utf8_re_bits = join "|", map { latin1toUTF8(chr($_)) } (127..255);

	$recomposeTable = {
		"o\x{30c}" => "\x{1d2}",
		"e\x{302}" => "\x{ea}",
		"i\x{306}" => "\x{12d}",
		"h\x{302}" => "\x{125}",
		"u\x{300}" => "\x{f9}",
		"O\x{302}" => "\x{d4}",
		"s\x{327}" => "\x{15f}",
		"i\x{308}" => "\x{ef}",
		"I\x{30f}" => "\x{208}",
		"A\x{303}" => "\x{c3}",
		"U\x{308}\x{30c}" => "\x{1d9}",
		"U\x{301}" => "\x{da}",
		"c\x{30c}" => "\x{10d}",
		"u\x{308}\x{304}" => "\x{1d6}",
		"r\x{301}" => "\x{155}",
		"o\x{301}" => "\x{f3}",
		"y\x{301}" => "\x{fd}",
		"I\x{301}" => "\x{cd}",
		"A\x{30f}" => "\x{200}",
		"i\x{303}" => "\x{129}",
		"Y\x{301}" => "\x{dd}",
		"A\x{302}" => "\x{c2}",
		"e\x{311}" => "\x{207}",
		"a\x{302}" => "\x{e2}",
		"a\x{328}" => "\x{105}",
		"U\x{304}" => "\x{16a}",
		"L\x{301}" => "\x{139}",
		"I\x{328}" => "\x{12e}",
		"u\x{30b}" => "\x{171}",
		"a\x{308}" => "\x{e4}",
		"u\x{306}" => "\x{16d}",
		"u\x{303}" => "\x{169}",
		"U\x{308}\x{301}" => "\x{1d7}",
		"I\x{303}" => "\x{128}",
		"G\x{306}" => "\x{11e}",
		"a\x{30a}" => "\x{e5}",
		"i\x{301}" => "\x{ed}",
		"t\x{30c}" => "\x{165}",
		"e\x{304}" => "\x{113}",
		"E\x{328}" => "\x{118}",
		"S\x{327}" => "\x{15e}",
		"u\x{308}\x{30c}" => "\x{1da}",
		"\x{226}\x{304}" => "\x{1e0}",
		"R\x{301}" => "\x{154}",
		"c\x{301}" => "\x{107}",
		"E\x{30f}" => "\x{204}",
		"N\x{300}" => "\x{1f8}",
		"U\x{302}" => "\x{db}",
		"o\x{302}" => "\x{f4}",
		"s\x{30c}" => "\x{161}",
		"U\x{30b}" => "\x{170}",
		"E\x{304}" => "\x{112}",
		"U\x{328}" => "\x{172}",
		"n\x{327}" => "\x{146}",
		"G\x{30c}" => "\x{1e6}",
		"a\x{311}" => "\x{203}",
		"\x{f8}\x{301}" => "\x{1ff}",
		"A\x{30a}" => "\x{c5}",
		"s\x{301}" => "\x{15b}",
		"Y\x{308}" => "\x{178}",
		"E\x{30c}" => "\x{11a}",
		"\x{292}\x{30c}" => "\x{1ef}",
		"A\x{308}" => "\x{c4}",
		"U\x{308}\x{304}" => "\x{1d5}",
		"T\x{30c}" => "\x{164}",
		"O\x{304}" => "\x{14c}",
		"A\x{328}" => "\x{104}",
		"a\x{30c}" => "\x{1ce}",
		"A\x{300}" => "\x{c0}",
		"o\x{311}" => "\x{20f}",
		"I\x{300}" => "\x{cc}",
		"U\x{31b}" => "\x{1af}",
		"\x{c6}\x{301}" => "\x{1fc}",
		"u\x{308}\x{300}" => "\x{1dc}",
		"k\x{327}" => "\x{137}",
		"Z\x{307}" => "\x{17b}",
		"E\x{302}" => "\x{ca}",
		"E\x{308}" => "\x{cb}",
		"n\x{303}" => "\x{f1}",
		"R\x{30c}" => "\x{158}",
		"D\x{30c}" => "\x{10e}",
		"c\x{302}" => "\x{109}",
		"L\x{30c}" => "\x{13d}",
		"N\x{301}" => "\x{143}",
		"N\x{30c}" => "\x{147}",
		"A\x{304}" => "\x{100}",
		"u\x{302}" => "\x{fb}",
		"I\x{308}" => "\x{cf}",
		"S\x{302}" => "\x{15c}",
		"O\x{30c}" => "\x{1d1}",
		"j\x{302}" => "\x{135}",
		"S\x{301}" => "\x{15a}",
		"\x{1b7}\x{30c}" => "\x{1ee}",
		"K\x{327}" => "\x{136}",
		"z\x{301}" => "\x{17a}",
		"O\x{300}" => "\x{d2}",
		"O\x{31b}" => "\x{1a0}",
		"O\x{328}" => "\x{1ea}",
		"o\x{31b}" => "\x{1a1}",
		"E\x{311}" => "\x{206}",
		"a\x{308}\x{304}" => "\x{1df}",
		"n\x{301}" => "\x{144}",
		"U\x{300}" => "\x{d9}",
		"g\x{301}" => "\x{1f5}",
		"i\x{304}" => "\x{12b}",
		"i\x{328}" => "\x{12f}",
		"k\x{30c}" => "\x{1e9}",
		"y\x{308}" => "\x{ff}",
		"E\x{306}" => "\x{114}",
		"g\x{307}" => "\x{121}",
		"z\x{30c}" => "\x{17e}",
		"a\x{300}" => "\x{e0}",
		"u\x{304}" => "\x{16b}",
		"e\x{308}" => "\x{eb}",
		"u\x{30c}" => "\x{1d4}",
		"e\x{301}" => "\x{e9}",
		"i\x{300}" => "\x{ec}",
		"u\x{31b}" => "\x{1b0}",
		"r\x{30c}" => "\x{159}",
		"g\x{302}" => "\x{11d}",
		"W\x{302}" => "\x{174}",
		"O\x{301}" => "\x{d3}",
		"e\x{328}" => "\x{119}",
		"A\x{306}" => "\x{102}",
		"a\x{306}" => "\x{103}",
		"S\x{30c}" => "\x{160}",
		"I\x{302}" => "\x{ce}",
		"R\x{327}" => "\x{156}",
		"w\x{302}" => "\x{175}",
		"U\x{308}" => "\x{dc}",
		"C\x{307}" => "\x{10a}",
		"I\x{306}" => "\x{12c}",
		"O\x{30f}" => "\x{20c}",
		"N\x{327}" => "\x{145}",
		"C\x{302}" => "\x{108}",
		"u\x{328}" => "\x{173}",
		"o\x{303}" => "\x{f5}",
		"r\x{327}" => "\x{157}",
		"U\x{30a}" => "\x{16e}",
		"i\x{302}" => "\x{ee}",
		"i\x{30c}" => "\x{1d0}",
		"E\x{307}" => "\x{116}",
		"O\x{328}\x{304}" => "\x{1ec}",
		"c\x{307}" => "\x{10b}",
		"Z\x{301}" => "\x{179}",
		"\x{e6}\x{304}" => "\x{1e3}",
		"E\x{301}" => "\x{c9}",
		"Y\x{302}" => "\x{176}",
		"o\x{308}" => "\x{f6}",
		"g\x{327}" => "\x{123}",
		"l\x{301}" => "\x{13a}",
		"u\x{308}" => "\x{fc}",
		"l\x{30c}" => "\x{13e}",
		"g\x{306}" => "\x{11f}",
		"A\x{301}" => "\x{c1}",
		"\x{e6}\x{301}" => "\x{1fd}",
		"C\x{327}" => "\x{c7}",
		"C\x{30c}" => "\x{10c}",
		"a\x{303}" => "\x{e3}",
		"a\x{30a}\x{301}" => "\x{1fb}",
		"o\x{30b}" => "\x{151}",
		"O\x{308}" => "\x{d6}",
		"z\x{307}" => "\x{17c}",
		"A\x{30a}\x{301}" => "\x{1fa}",
		"d\x{30c}" => "\x{10f}",
		"s\x{302}" => "\x{15d}",
		"R\x{30f}" => "\x{210}",
		"I\x{30c}" => "\x{1cf}",
		"U\x{303}" => "\x{168}",
		"i\x{311}" => "\x{20b}",
		"O\x{30b}" => "\x{150}",
		"u\x{308}\x{301}" => "\x{1d8}",
		"G\x{327}" => "\x{122}",
		"U\x{306}" => "\x{16c}",
		"e\x{306}" => "\x{115}",
		"u\x{301}" => "\x{fa}",
		"\x{227}\x{304}" => "\x{1e1}",
		"a\x{304}" => "\x{101}",
		"T\x{327}" => "\x{162}",
		"U\x{308}\x{300}" => "\x{1db}",
		"n\x{300}" => "\x{1f9}",
		"I\x{311}" => "\x{20a}",
		"A\x{308}\x{304}" => "\x{1de}",
		"I\x{307}" => "\x{130}",
		"\x{d8}\x{301}" => "\x{1fe}",
		"A\x{30c}" => "\x{1cd}",
		"I\x{304}" => "\x{12a}",
		"c\x{327}" => "\x{e7}",
		"o\x{328}\x{304}" => "\x{1ed}",
		"t\x{327}" => "\x{163}",
		"G\x{307}" => "\x{120}",
		"G\x{301}" => "\x{1f4}",
		"o\x{328}" => "\x{1eb}",
		"N\x{303}" => "\x{d1}",
		"O\x{311}" => "\x{20e}",
		"e\x{307}" => "\x{117}",
		"g\x{30c}" => "\x{1e7}",
		"Z\x{30c}" => "\x{17d}",
		"o\x{304}" => "\x{14d}",
		"L\x{327}" => "\x{13b}",
		"U\x{30c}" => "\x{1d3}",
		"o\x{306}" => "\x{14f}",
		"C\x{301}" => "\x{106}",
		"H\x{302}" => "\x{124}",
		"e\x{30f}" => "\x{205}",
		"J\x{302}" => "\x{134}",
		"\x{c6}\x{304}" => "\x{1e2}",
		"e\x{30c}" => "\x{11b}",
		"y\x{302}" => "\x{177}",
		"O\x{303}" => "\x{d5}",
		"o\x{30f}" => "\x{20d}",
		"K\x{30c}" => "\x{1e8}",
		"E\x{300}" => "\x{c8}",
		"a\x{301}" => "\x{e1}",
		"G\x{302}" => "\x{11c}",
		"o\x{300}" => "\x{f2}",
		"a\x{30f}" => "\x{201}",
		"l\x{327}" => "\x{13c}",
		"O\x{306}" => "\x{14e}",
		"A\x{311}" => "\x{202}",
		"j\x{30c}" => "\x{1f0}",
		"n\x{30c}" => "\x{148}",
		"e\x{300}" => "\x{e8}",
		"u\x{30a}" => "\x{16f}",
		"i\x{30f}" => "\x{209}"
	};

	$decomposeTable = {};

	while (my ($key, $value) = each %{$recomposeTable}) {
		$decomposeTable->{$value} = $key;
	}

	# Create a compiled regex.
	$recomposeRE = join "|", reverse sort keys %{$recomposeTable};
	$recomposeRE = qr/($recomposeRE)/o;

	$decomposeRE = join "|", reverse sort keys %{$decomposeTable};
	$decomposeRE = qr/($decomposeRE)/o;
}

sub utf8decode {
	return utf8decode_guess(@_);
}

sub utf8decode_guess {
	my $string = shift;
	my $prefer_encoding;

	# Bail early if it's just ascii
	if (looks_like_ascii($string)) {
		return $string;
	}

	my $orig = $string;

	if ($string && $] > 5.007 && !Encode::is_utf8($string)) {

		eval {
			my $icode = Encode::Guess::guess_encoding($string);

			if (ref $icode) {

				$string = Encode::decode($icode, $string, Encode::FB_QUIET());

			} else {

				if ($icode =! /^no /i) {

					while ($prefer_encoding = shift) {

						$string = Encode::decode($prefer_encoding, $string, Encode::FB_QUIET());

						last if $icode =~ /$prefer_encoding/;
					}
				}
			}
		}
	}

	return $string;
}

sub utf8decode_locale {
	my $string = shift;

	if ($string && $] > 5.007 && !Encode::is_utf8($string)) {

		$string = Encode::decode($locale, $string, Encode::FB_QUIET());
	}

	return $string;
}

sub utf8encode {
	my $string   = shift;
	my $encoding = shift || 'utf8';

	# Bail early if it's just ascii
	if (looks_like_ascii($string)) {
		return $string;
	}

	my $orig = $string;

	# Don't try to encode a string which isn't utf8
	# 
	# If the incoming string already is utf8, turn off the utf8 flag.
	if ($string && $] > 5.007 && !Encode::is_utf8($string)) {

		$string = Encode::encode($encoding, $string, Encode::FB_QUIET());

	} elsif ($string && $] > 5.007) {

		Encode::_utf8_off($string);
	}

	# Check for doubly encoded strings - and revert back to our original
	# string if that's the case.
	if ($string && $] > 5.007 && !looks_like_utf8($string)) {

		$string = $orig;
	}

	return $string;
}

sub utf8encode_locale {

	return utf8encode($_[0], $locale);
}

sub utf8off {
	my $string = shift;

	if ($string && $] > 5.007) {
		Encode::_utf8_off($string);
	}

	return $string;
}

sub utf8on {
	my $string = shift;

	if ($string && $] > 5.007 && looks_like_utf8($string)) {
		Encode::_utf8_on($string);
	}

	return $string;
}

sub looks_like_ascii {
	use bytes;

	return 1 if $_[0] !~ /([^\x00-\x7F])/;
	return 0;
}

sub looks_like_latin1 {
	use bytes;

	return 1 if $_[0] !~ /([^\x00-\xFF])/;
	return 0;
}

sub looks_like_utf8 {
	use bytes;

	return 1 if $_[0] =~ /($utf8_re_bits)/o;
	return 0;
}

sub latin1toUTF8 {
	my $data = shift;

	if ($] > 5.007) {

		$data = eval { Encode::encode('utf8', $data, Encode::FB_QUIET()) } || $data;

	} else {

		$data =~ s/([\x80-\xFF])/chr(0xC0|ord($1)>>6).chr(0x80|ord($1)&0x3F)/eg;
	}

	return $data;
}

sub utf8toLatin1 {
	my $data = shift;

	if ($] > 5.007) {

		$data = eval { Encode::encode('iso-8859-1', $data, Encode::FB_QUIET()) } || $data;

	} else {

		$data =~ s/([\xC0-\xDF])([\x80-\xBF])/chr(ord($1)<<6&0xC0|ord($2)&0x3F)/eg; 
		$data =~ s/[\xE2][\x80][\x99]/'/g;
	}

	return $data;
}

sub encodingFromString {

	my $encoding = 'raw';

	# Don't copy a potentially large string - just read it from the stack.
	if (looks_like_ascii($_[0])) {

		$encoding = 'ascii';

	} elsif (looks_like_utf8($_[0])) {
	
		$encoding = 'utf8';

	} elsif (looks_like_latin1($_[0])) {
	
		$encoding = 'iso-8859-1';
	}

	return $encoding;
}

sub encodingFromFileHandle {
	my $fh = shift;

	# If we didn't get a filehandle, not much we can do.
	if (!ref($fh) || !$fh->can('seek')) {

		msg("Warning: Not a filehandle in encodingFromFileHandle()\n");
		bt();

		return;
	}

	local $/ = undef;

	# Save the old position (if any)
	# And find the file size.
	#
	# These must be seek() and not sysseek(), as File::BOM uses seek(),
	# and they'll get confused otherwise.
	my $pos  = tell($fh);
	my $size = seek($fh, 0, SEEK_END);

	# Don't do any translation.
	binmode($fh, ":raw");

	# Try to find a BOM on the file - otherwise check the string
	#
	# Although get_encoding_from_filehandle tries to determine if
	# the handle is seekable or not - the Protocol handlers don't
	# implement a seek() method, and even if they did, File::BOM
	# internally would try to read(), which doesn't mix with
	# sysread(). So skip those m3u files entirely.
	my $enc = '';

	# Explitly check for IO::String - as it does have a seek() method!
	if ($] > 5.007 && ref($fh) && ref($fh) ne 'IO::String' && $fh->can('seek')) {
		$enc = File::BOM::get_encoding_from_filehandle($fh);
	}

	# File::BOM got something - let's get out of here.
	return $enc if $enc;

	# Seek to the beginning of the file.
	seek($fh, 0, SEEK_SET);

	#
	read($fh, my $string, $size);

	# Seek back to where we started.
	seek($fh, $pos, SEEK_SET);

	return encodingFromString($string);
}

# Handle either a filename or filehandle
sub encodingFromFile {
	my $file = shift;

	my $encoding = $locale;

	if (ref($file) && $file->can('seek')) {

		$encoding = encodingFromFileHandle($file);

	} elsif (-r $file) {

		my $fh = new FileHandle;
		$fh->open($file) or do {
			msg("Couldn't open file: [$file] : $!\n");
			return $encoding;
		};

		$encoding = encodingFromFileHandle($fh);

		$fh->close();

	} else {

		msg("Warning: Not a filename or filehandle encodingFromFile( $file )\n");
		bt();
	}

	return $encoding;
}

sub recomposeUnicode {
	my $string = shift;

	if ($] <= 5.007) {
		return $string;
	}

	# Make sure we're on.
	$string = Encode::decode('utf8', $string);

	$string =~ s/$recomposeRE/$recomposeTable->{$1}/go;

	$string = Encode::encode('utf8', $string);

	return $string;
}

sub decomposeUnicode {
	my $string = shift;

	if ($] <= 5.007) {
		return $string;
	}

	# Make sure we're on.
	$string = Encode::decode('utf8', $string);

	$string =~ s/$decomposeRE/$decomposeTable->{$1}/go;

	$string = Encode::encode('utf8', $string);

	return $string;
}

sub stripBOM {
	my $string = shift;

	if ($] > 5.007) {

		use bytes;

		$string =~ s/^(?:
			\xef\xbb\xbf     |
			\xfe\xff         |
			\xff\xfe         |
			\x00\x00\xfe\xff |
			\xff\xfe\x00\x00
		)//x;
	}

	return $string;
}

1;

__END__


# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
