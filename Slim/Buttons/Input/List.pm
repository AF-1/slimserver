package Slim::Buttons::Input::List;

# $Id$
# SlimServer Copyright (c) 2001-2004 Sean Adams, Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;
use Slim::Buttons::Common;
use Slim::Utils::Misc;
use Slim::Display::Display;

Slim::Buttons::Common::addMode('INPUT.List',getFunctions(),\&setMode);

###########################
#Button mode specific junk#
###########################
our %functions = (
	#change character at cursorPos (both up and down)
	'up' => sub {
			my ($client,$funct,$functarg) = @_;
			changePos($client,-1);
		}
	,'down' => sub {
			my ($client,$funct,$functarg) = @_;
			changePos($client,1);
		}
	,'numberScroll' => sub {
			my ($client,$funct,$functarg) = @_;
			my $isSorted = $client->param('isSorted');
			my $listRef = $client->param('listRef');
			my $numScrollRef;
			if ($isSorted && uc($isSorted) eq 'E') {
				# sorted by the external value
				$numScrollRef = $client->param('externRef');
			} else {
				# not sorted or sorted by the internal value
				$numScrollRef = $listRef;
			}
			my $newIndex = Slim::Buttons::Common::numberScroll($client, $functarg, $numScrollRef, $isSorted ? 1 : 0);
			if (defined $newIndex) {
				$client->param('listIndex',$newIndex);
				my $valueRef = $client->param('valueRef');
				$$valueRef = $listRef->[$newIndex];
				my $onChange = $client->param('onChange');
				if (ref($onChange) eq 'CODE') {
					my $onChangeArgs = $client->param('onChangeArgs');
					my @args;
					push @args, $client if $onChangeArgs =~ /c/i;
					push @args, $$valueRef if $onChangeArgs =~ /v/i;
					$onChange->(@args);
				}
			}
			$client->update;
		}
	#call callback procedure
	,'exit' => sub {
			my ($client,$funct,$functarg) = @_;
			if (!defined($functarg) || $functarg eq '') {
				$functarg = 'exit'
			}
			exitInput($client,$functarg);
		}
	,'passback' => sub {
			my ($client,$funct,$functarg) = @_;
			my $parentMode = $client->param('parentMode');
			if (defined($parentMode)) {
				Slim::Hardware::IR::executeButton($client,$client->lastirbutton,$client->lastirtime,$parentMode);
			}
		}
);

sub changePos {
	my ($client, $dir) = @_;
	my $listRef = $client->param('listRef');
	my $listIndex = $client->param('listIndex');
	if ($client->param('noWrap') 
		&& (($listIndex == 0 && $dir < 0) || ($listIndex == (scalar(@$listRef) - 1) && $dir > 0))) {
			#not wrapping and at end of list
			return;
	}
	my $newposition = Slim::Buttons::Common::scroll($client, $dir, scalar(@$listRef), $listIndex);
	my $valueRef = $client->param('valueRef');
	$$valueRef = $listRef->[$newposition];
	$client->param('listIndex',$newposition);
	my $onChange = $client->param('onChange');
	if (ref($onChange) eq 'CODE') {
		my $onChangeArgs = $client->param('onChangeArgs');
		my @args;
		push @args, $client if $onChangeArgs =~ /c/i;
		push @args, $$valueRef if $onChangeArgs =~ /v/i;
		push @args, $client->param('listIndex') if $onChangeArgs =~ /i/i;
		$onChange->(@args);
	}
	$client->update();
}

sub lines {
	my $client = shift;
	my ($line1, $line2);
	my $listIndex = $client->param('listIndex');
	my $listRef = $client->param('listRef');
	if (!defined($listRef)) { return ('','');}
	if ($listIndex && ($listIndex == scalar(@$listRef))) {
		$client->param('listIndex',$listIndex-1);
		$listIndex--;
	}
	
	$line1 = getExtVal($client,$listRef->[$listIndex],$listIndex,'header');
	if ($client->param('stringHeader') && Slim::Utils::Strings::stringExists($line1)) {
		$line1 = $client->string($line1);
	}
	if (scalar(@$listRef) == 0) {
		$line2 = $client->string('EMPTY');
	} else {

		if ($client->param('headerAddCount')) {
			$line1 .= ' (' . ($listIndex + 1)
				. ' ' . $client->string('OF') .' ' . scalar(@$listRef) . ')';
		}

		$line2 = getExtVal($client,$listRef->[$listIndex],$listIndex,'externRef');

		if ($client->param('stringExternRef') && Slim::Utils::Strings::stringExists($line2)) {
			$line2 = $client->linesPerScreen() == 1 ? $client->doubleString($line2) : $client->string($line2);
		}
	}
	my @overlay = getExtVal($client,$listRef->[$listIndex],$listIndex,'overlayRef');
	return ($line1,$line2,@overlay);
}

sub getExtVal {
	my ($client, $value, $listIndex, $source) = @_;
	my $extref = $client->param($source);
	my $extval;
	if (ref($extref) eq 'ARRAY') {
		$extref = $extref->[$listIndex];
	}

	if (!ref($extref)) {
		return $extref;
	} elsif (ref($extref) eq 'CODE') {
		my @args;
		my $argtype = $client->param($source . 'Args');
		push @args, $client if $argtype =~ /c/i;
		push @args, $value if $argtype =~ /v/i;
		return $extref->(@args);
	} elsif (ref($extref) eq 'HASH') {
		return $extref->{$value};
	} elsif (ref($extref) eq 'ARRAY') {
		return @$extref;
	} else {
		return undef;
	}
}

sub getFunctions {
	return \%functions;
}

sub setMode {
	my $client = shift;
	my $setMethod = shift;
	#possibly skip the init if we are popping back to this mode
	#if ($setMethod ne 'pop') {
		if (!init($client)) {
			Slim::Buttons::Common::popModeRight($client);
		}
	#}
	$client->lines(\&lines);
}
# set unsupplied parameters to the defaults
# listRef = none # reference to list of internal values, exit mode if not supplied
# header = 'Select item:' # message displayed on top line, can be a scalar, a code ref
	# , or an array ref to a list of scalars or code refs
# headerArgs = CV # accepts C and V
# stringHeader = undef # if true, put the value of header through the string function
	# before displaying it.
# headerAddCount = undef # if true add (I of T) to end of header
	# where I is the 1 based index and T is the total # of items
# valueRef =  # reference to value to be selected
# callback = undef # function to call to exit mode
# listIndex = 0 or position of valueRef in listRef
# noWrap = undef # whether or not the list wraps at the ends
# externRef = undef
# externRefArgs = CV # accepts C and V
# stringExternRef = undef # same as with stringHeader, but for the value of externRef
# overlayRef = undef
# overlayRefArgs = CV # accepts C and V
# onChange = undef
# onChangeArgs = CV # accepts C, V and I
# for the *Args parameters, the letters indicate what values to send to the code ref
#  (C for client object, V for current value, I for list index)

# other parameters used
# isSorted = undef # whether the interal or external list is sorted 
	#(I for internal, E for external, undef or anything else for unsorted)

sub init {
	my $client = shift;
	if (!defined($client->param('parentMode'))) {
		my $i = -2;
		while ($client->modeStack->[$i] =~ /^INPUT./) { $i--; }
		$client->param('parentMode',$client->modeStack->[$i]);
	}
	if (!defined($client->param('header'))) {
		$client->param('header','Select item:');
	}
	my $listRef = $client->param('listRef');
	my $externRef = $client->param('externRef');
	if (!defined $listRef && ref($externRef) eq 'ARRAY') {
		$listRef = $externRef;
		$client->param('listRef',$listRef);
	}
	if (!defined $externRef && ref($listRef) eq 'ARRAY') {
		$externRef = $listRef;
		$client->param('externRef',$externRef);
	}
	return undef if !defined($listRef);
	my $isSorted = $client->param('isSorted');
	if ($isSorted && ($isSorted !~ /[iIeE]/ || (uc($isSorted) eq 'E' && ref($externRef) ne 'ARRAY'))) {
		$client->param('isSorted',0);
	}
	my $listIndex = $client->param('listIndex');
	my $valueRef = $client->param('valueRef');
	if (!defined($listIndex) || (scalar(@$listRef) == 0)) {
		$listIndex = 0;
	} elsif ($listIndex > $#$listRef) {
		$listIndex = $#$listRef;
	}
	while ($listIndex < 0) {
		$listIndex += scalar(@$listRef);
	}
	if (!defined($valueRef) || (ref($valueRef) && !defined($$valueRef))) {
		$$valueRef = $listRef->[$listIndex];
		$client->param('valueRef',$valueRef);
	} elsif (!ref($valueRef)) {
		$$valueRef = $valueRef;
		$client->param('valueRef',$valueRef);
	}
	if ((scalar(@$listRef) != 0) && $$valueRef ne $listRef->[$listIndex]) {
		my $newIndex;
		for ($newIndex = 0; $newIndex < scalar(@$listRef); $newIndex++) {
			last if $$valueRef eq $listRef->[$newIndex];
		}
		if ($newIndex < scalar(@$listRef)) {
			$listIndex = $newIndex;
		} else {
			$$valueRef = $listRef->[$listIndex];
		}
	}
	$client->param('listIndex',$listIndex);
	if (!defined($client->param('externRefArgs'))) {
		$client->param('externRefArgs','CV');
	}
	if (!defined($client->param('overlayRefArgs'))) {
		$client->param('overlayRefArgs','CV');
	}
	if (!defined($client->param('onChangeArgs'))) {
		$client->param('onChangeArgs','CV');
	}
	if (!defined($client->param('headerArgs'))) {
		$client->param('headerArgs','CV');
	}
	return 1;
}

sub exitInput {
	my ($client,$exitType) = @_;
	my $callbackFunct = $client->param('callback');
	if (!defined($callbackFunct) || !(ref($callbackFunct) eq 'CODE')) {
		if ($exitType eq 'right') {
			$client->bumpRight();
		} elsif ($exitType eq 'left') {
			Slim::Buttons::Common::popModeRight($client);
		} else {
			Slim::Buttons::Common::popMode($client);
		}
		return;
	}
	$callbackFunct->(@_);
}

1;
