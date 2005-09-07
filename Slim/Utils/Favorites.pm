package Slim::Utils::Favorites;

# $Id:$

# SlimServer Copyright (C) 2001-2005 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

# This class persists a user's choice of favorite tracks.  In this
# implementation, the favorites are stored as server-wide prefs.
# However, its important to abstract the underlying implementation.
# Callers need not know how the favorites are stored.  In the future,
# they could be stored as a playlist file or in a database table.

use strict;

use FindBin qw($Bin);

use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);

use Slim::Utils::Prefs;


# Class-only method, not an instance method
# Adds a favorite for the given client to the database.  
# Should station titles be localized??  Should they be pulled from tags in the stream?
sub clientAdd {
	my $class = shift;
	# this is a class only method.
	assert (!ref($class), "call clientAdd as a class method, not an instance\n");
	my $client = shift;
	my $url = shift;
	my $title = shift;

	# don't crash if no url
	if (!$url) {
		$::d_favorites && msg("No url passed to $class\::clientAdd, skipping.\n");
		return undef;
	}

	$::d_favorites && msg("Favorites::add(". $client->id().", $url, $title)\n");

	# if its already a favorite, don't add it again
	my $fav = findByClientAndURL($class, $client, $url);
	if (defined($fav)) {
		return $fav->{'num'};
	}
	
	# find any vacated spots
	my $fav = findByClientAndURL($class, $client, '');
	if (defined($fav)) {
		Slim::Utils::Prefs::set('favorite_urls', $url, $fav->{'num'}-1);
		Slim::Utils::Prefs::set('favorite_titles', $title, $fav->{'num'}-1);
		return $fav->{'num'};
	}

	# append to list
	Slim::Utils::Prefs::push('favorite_urls', $url);
	Slim::Utils::Prefs::push('favorite_titles', $title);

	# return the favorite number
	return Slim::Utils::Prefs::getArrayMax('favorite_urls') + 1;
}

# for internal use only.  Get pref index for given url
sub _indexByUrl {
	my $url = shift;

	my @urls = Slim::Utils::Prefs::getArray('favorite_urls');
	my $i = 0;
	my $found = 0;
	while (!$found && $i < scalar(@urls)) {
		if ($urls[$i] eq $url) {
			$found = 1;
		} else {
			$i++;
		}
	}
	if ($found) {
		return $i;
	} else {
		return undef;
	}
}

sub findByClientAndURL {
	my $class = shift;
	my $client = shift;
	my $url = shift;

	my $i = _indexByUrl($url);
	if (defined($i)) {
		$::d_favorites && msg("Favorites: found favorite number " . ($i+1) . ": $url\n");
		my $title = Slim::Utils::Prefs::getInd('favorite_titles', $i);
		return {'url' => $url, 'title' => $title, 'num' => $i+1};
	} else {
		$::d_favorites && msg("Favorites: not found: $url\n");
		return undef;
	}
}

sub moveItem {
	my $client = shift;
	my $from = shift;
	my $to = shift;

	if (defined $to && $to =~ /^[\+-]/) {
		$to = $from + $to;
	}

	my @titles = Slim::Utils::Prefs::getArray('favorite_titles');
	my @urls = Slim::Utils::Prefs::getArray('favorite_urls');

	if (defined $from && defined $to && 
		$from < scalar @titles && 
		$to < scalar @titles && $from >= 0 && $to >= 0) {

		Slim::Utils::Prefs::set('favorite_titles',$titles[$from],$to);
		Slim::Utils::Prefs::set('favorite_urls',$urls[$from],$to);
		Slim::Utils::Prefs::set('favorite_titles',$titles[$to],$from);
		Slim::Utils::Prefs::set('favorite_urls',$urls[$to],$from);
	}
}

sub deleteByClientAndURL {
	my $class = shift;
	my $client = shift;
	my $url = shift;

	my $i = _indexByUrl($url);
	if (defined($i)) {
		Slim::Utils::Prefs::set('favorite_titles','', $i);
		Slim::Utils::Prefs::set('favorite_urls','', $i);
	}

}

sub deleteByClientAndId {
	my $class = shift;
	my $client = shift;
	my $i = shift;

	if (defined($i)) {
		Slim::Utils::Prefs::set('favorite_titles','', $i);
		Slim::Utils::Prefs::set('favorite_urls','', $i);
	}

}

# creates a read-only list of favorites.
# if you need to modify the list, use add then call new again.
sub new {
	my $class = shift;
	# this is a class only method.
	assert (!ref($class), "new is a class method, not an instance\n");
	# nothing really to do for this implementation
	return bless({}, $class);
}

# returns an array of titles
sub titles {
	ref(my $self = shift) or assert(0, __PACKAGE__."::titles is an instance-only method\n");
	my @titles = Slim::Utils::Prefs::getArray('favorite_titles');
	return @titles;
}
# returns an array of urls
sub urls {
	ref(my $self = shift) or assert(0, __PACKAGE__."::urls is an instance-only method\n");
	my @urls = Slim::Utils::Prefs::getArray('favorite_urls');
	return @urls;
}


1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
