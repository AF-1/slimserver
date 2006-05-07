package Slim::Utils::PerfMon;

# Package to add simple 'bucket' based logging to SlimServer
# Used to store the distibution of values logged plus min/avg/max
# May also set high and low warning levels which trigger a msg() 

# $Id$

# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License, 
# version 2.

use strict;
use Slim::Utils::Misc;

sub new {
	my $class = shift;

	my $ref = {};
	bless $ref, $class;

	return adjust($ref,@_);
}

sub adjust {
	my ($ref, $name, $array, $warnLo, $warnHi) = @_;

	my $buckets = $#{$array};

	$ref->{name} = $name;                  # name of log - used in warning msgs
	$ref->{buckets} = $buckets;            # number of buckets
	$ref->{over} = 0;                      # count of values exceeding highest threshold
	$ref->{max} = 0;                       # max logged value
	$ref->{min} = @$array[$buckets] || 0;  # min logged value (assumed < highest thres)
	$ref->{sum} = 0;                       # sum of logged values
	$ref->{val} = [];                      # array holding counts per bucket
	$ref->{thres} = [];                    # array holding thresholds per bucket
	$ref->{warnlo} = $warnLo;              # low warning threshold - msg if crossed
	$ref->{warnhi} = $warnHi;              # high warning threshold - msg if crossed

	# optimise speed of logging to lowest & highest buckets by storing extra data in hash direct
	$ref->{valL}   = 0;                    # val for bucket 0
	$ref->{thresL} = @$array[0] || 0;      # thres for bucket 0
	$ref->{thresH} = @$array[$buckets]||0; # thres for overflow

    for my $entry (0..$buckets) {
		$ref->{val}[$entry] = 0;
		$ref->{thres}[$entry] = @$array[$entry];
    }

	return $ref;
}

sub setWarnLow {
	my $ref = shift || return;
	my $val = shift;

	$ref->{warnlo} = $val;
}

sub setWarnHigh {
	my $ref = shift || return;
	my $val = shift;

	$ref->{warnhi} = $val;
}

sub clear {
	my $ref = shift;

	$ref->{over} = 0; 
	$ref->{max} = 0;
	$ref->{min} = $ref->{thres}[$ref->{buckets}] || 0;
	$ref->{sum} = 0;

	for my $entry (0..$ref->{buckets}) {
		$ref->{val}[$entry]  = 0;
	}
	$ref->{valL} = 0;
}	

sub log {
	# normal logging method including checking of warning thresholds
	# returns 1 if threshold crossing msg produced to allow caller to add more details
	# [optimised for speed by use of && rather than if statements]
	my $ref = shift;
	my $val = shift;

	my $warn;

	$ref->{sum} += $val;
	($val > $ref->{max}) && ($ref->{max} = $val);
	($val < $ref->{min}) && ($ref->{min} = $val);

	# test for crossing warning threshold and log msg if appropriate
	$ref->{warnlo} && ($val < $ref->{warnlo}) && msg($ref->{name}." < ".$ref->{warnlo}." : ".$val."\n") && ($warn = 1);
	$ref->{warnhi} && ($val > $ref->{warnhi}) && msg($ref->{name}." > ".$ref->{warnhi}." : ".$val."\n") && ($warn = 1);

	# shortcut for hits on first bucket
	($val < $ref->{thresL}) && ++$ref->{valL} && return $warn;

	# shortcut for overflows past all buckets
	($val >= $ref->{thresH}) && ++$ref->{over} && return $warn;

	# update appropriate other bucket
	for my $entry (1..$ref->{buckets}) {
		($val < $ref->{thres}[$entry]) && ++$ref->{val}[$entry] && return $warn;
	}
}

sub sprint {
	my $ref = shift;
	my $displayTitle = shift;

	my $str = '';

	my $total = $ref->count() || return $str;

	$str .= $ref->{name}.":\n" if $displayTitle;

	for my $entry (0..$ref->{buckets}) {
		my $val = $entry ? $ref->{val}[$entry] : $ref->{valL};
		my $percent = $val/$total*100;
		$str .= sprintf "%8s : %8d :%3.0f%% %s\n","< ".$ref->{thres}[$entry], $val, $percent, "#" x ($percent/2);
	}
	$str .= sprintf "%8s : %8d :%3.0f%% %s\n", ">=".$ref->{thres}[$ref->{buckets}], $ref->{over}, $ref->{over}/$total*100, "#" x ($ref->{over}/$total*100/2);
	$str .= sprintf "    max  : %8f\n", $ref->{max};
	$str .= sprintf "    min  : %8f\n", $ref->{min};
	$str .= sprintf "    avg  : %8f\n", $ref->{sum}/$total;

	return $str
}

sub print {
	print sprint(@_);
}

sub count {
	my $ref = shift;

	my $count = $ref->{over};

	for my $entry (0..$ref->{buckets}) {
		$count += $entry ? $ref->{val}[$entry] : $ref->{valL};
	}

	return $count;
}	

sub above {
	my $ref = shift;
	my $val = shift;

	my $count = $ref->{over};

	for my $entry (0..$ref->{buckets}) {
		if ($ref->{thres}[$entry] > $val) {
			$count += $entry ? $ref->{val}[$entry] : $ref->{valL};
		}
	}
	return $count;
}

sub below {
	my $ref = shift;
	my $val = shift;

	my $count = 0;

	for my $entry (0..$ref->{buckets}) {
		if ($ref->{thres}[$entry] <= $val) {
			$count += $entry ? $ref->{val}[$entry] : $ref->{valL};
		}
	}
	return $count;
}

sub percentAbove {
	my $ref = shift;
	my $val = shift;

	my $total = $ref->count() || return 0;
	return $ref->above($val)/$total*100;
}

sub percentBelow {
	my $ref = shift;
	my $val = shift;

	my $total = $ref->count() || return 0;
	return $ref->below($val)/$total*100;
}

1;

__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:

