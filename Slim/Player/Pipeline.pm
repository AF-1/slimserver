package Slim::Player::Pipeline;

# $Id: Pipeline.pm,v 1.2 2004/10/16 00:16:03 vidur Exp $

# SlimServer Copyright (C) 2001-2004 Slim Devices Inc.
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License,
# version 2.

use strict;

use IPC::Open2;
use IO::Handle;
use Slim::Utils::Misc;
use Slim::Utils::Strings qw(string);
use Slim::Utils::OSDetect;

use bytes;

BEGIN {
	if ($^O =~ /Win32/) {
		*EWOULDBLOCK = sub () { 10035 };
		*EINPROGRESS = sub () { 10036 };
	} else {
		require Errno;
		import Errno qw(EWOULDBLOCK EINPROGRESS);
	}
}

use vars qw(@ISA);

@ISA = qw(IO::Handle);

sub new {
	my $class = shift;
	my $source = shift;
	my $command = shift;
	
	my $self = $class->SUPER::new();
	my ($reader, $writer);
	if ($^O =~ /Win32/) {
		my $listenReader = IO::Socket::INET->new(LocalAddr => 'localhost',
												 Listen => 5);
		unless (defined($listenReader)) {
			$::d_source && msg "Error creating listen socket for reader: !@\n";
			return undef;
		}
		my $listenWriter = IO::Socket::INET->new(LocalAddr => 'localhost',
												 Listen => 5);
		unless (defined($listenWriter)) {
			$::d_source && msg "Error creating listen socket for writer: !@\n";
			return undef;
		}
		
		my $readerPort = $listenReader->sockport;
		my $writerPort = $listenWriter->sockport;
		
		$command =~ s/"/\\"/g;
		$command = '"' . Slim::Utils::Misc::findbin('socketwrapper') . 
			'" -i ' . $writerPort . ' -o ' . $readerPort . ' -c "' .
				$command . '"';

		$::d_source && msg "Launching process with command: $command\n";

		eval "use Win32::Process";
		my $processObj;
		unless (Win32::Process::Create($processObj,
								   Slim::Utils::Misc::findbin("socketwrapper"),
								   $command,
								   0, 0x20,
								   ".")) {
			$::d_source && msg "Couldn't create socketwrapper process\n";
			$listenReader->close();
			$listenWriter->close();
			return undef;
		}

		${*$listenReader}{'pipeline'} = $self;
		${*$listenWriter}{'pipeline'} = $self;

		${*$self}{'pipeline_listen_reader'} = $listenReader;
		${*$self}{'pipeline_listen_writer'} = $listenWriter;
		
		Slim::Networking::Select::addRead($listenReader, \&acceptReader);
		Slim::Networking::Select::addError($listenReader, \&selectError);
		Slim::Networking::Select::addRead($listenWriter, \&acceptWriter);
		Slim::Networking::Select::addError($listenWriter, \&selectError);
	}
	else {
		$reader = IO::Handle->new();
		$writer = IO::Handle->new();

		my $child_pid = open2($reader, $writer, $command);
		unless (defined(Slim::Utils::Misc::blocking($reader, 0))) {
			$::d_source && msg "Cannot set pipe line reader to nonblocking\n";
			$reader->close();
			$writer->close();
			return undef;
		}
		
		unless (defined(Slim::Utils::Misc::blocking($writer, 0))) {
			$::d_source && msg "Cannot set pipe line writer to nonblocking\n";
			$reader->close();
			$writer->close();
			return undef;
		}
		
		binmode($reader);
		binmode($writer);
	}

	binmode($source);

	${*$self}{'pipeline_reader'} = $reader;
	${*$self}{'pipeline_writer'} = $writer;
	${*$self}{'pipeline_source'} = $source;
	${*$self}{'pipeline_pending_bytes'} = '';
	${*$self}{'pipeline_pending_size'} = 0;
	${*$self}{'pipeline_error'} = 0;

	return $self;
}

sub acceptReader {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	my $reader = $listener->accept();
	unless (defined($reader)) {
		$::d_source && msg "Error accepting on reader listener: !@\n";
		${*$pipeline}{'pipeline_error'} = 1;
		return;		
	}

	unless (defined(Slim::Utils::Misc::blocking($reader, 0))) {
		$::d_source && msg "Cannot set pipe line reader to nonblocking\n";
		${*$pipeline}{'pipeline_error'} = 1;
		return;		
	}

	$::d_source && msg "Pipeline reader connected\n";
			
	binmode($reader);
	${*$pipeline}{'pipeline_reader'} = $reader;
}

sub acceptWriter {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	my $writer = $listener->accept();
	unless (defined($writer)) {
		$::d_source && msg "Error accepting on writer listener: !@\n";
		${*$pipeline}{'pipeline_error'} = 1;
		return;
	}

	unless (defined(Slim::Utils::Misc::blocking($writer, 0))) {
		$::d_source && msg "Cannot set pipe line writer to nonblocking\n";
		${*$pipeline}{'pipeline_error'} = 1;
		return;
	}
			
	$::d_source && msg "Pipeline writer connected\n";

	binmode($writer);
	${*$pipeline}{'pipeline_writer'} = $writer;
}

sub selectError {
	my $listener = shift;
	my $pipeline = ${*$listener}{'pipeline'};

	$::d_source && msg "Error from select on pipeline listeners\n";
	${*$pipeline}{'pipeline_error'} = 1;
	return;	
}

sub sysread {
	my $self = $_[0];
	my $chunksize = $_[2];
	my $readlen;

	my $error = ${*$self}{'pipeline_error'};
	if ($error) {
		$! = -1;
		return undef;
	}

	my $reader = ${*$self}{'pipeline_reader'};
	my $writer = ${*$self}{'pipeline_writer'};
	unless (defined($reader) && defined($writer)) {
		$! = EWOULDBLOCK;
		return undef;
	}

	my $loop;
	do {
		$loop = 0;
		$readlen = $reader->sysread($_[1], $chunksize);

		# We'd block on the reader, so see if we can write more
		if (!defined($readlen) && ($! == EWOULDBLOCK)) {
			my $pendingBytes = ${*$self}{'pipeline_pending_bytes'};
			my $pendingSize = ${*$self}{'pipeline_pending_size'};

			if ($pendingSize) {
				$::d_source && msg("Pipeline has some pending bytes\n");
			}
			else {
				$::d_source && msg("Pipeline doesn't have  pending bytes - trying to get some from source\n");
				my $source = ${*$self}{'pipeline_source'};
				my $socketReadlen = $source->sysread($pendingBytes, 
													 $chunksize);
				if (!$socketReadlen) {
					return $socketReadlen;
				}
				$pendingSize = $socketReadlen;
			}

			$::d_source && msg("Attempting to write to pipeline writer\n");
			my $writelen = $writer->syswrite($pendingBytes, $pendingSize);
			if ($writelen) {
				$::d_source && msg("Wrote $writelen bytes to pipeline writer\n");
				if ($writelen != $pendingSize) {
					${*$self}{'pipeline_pending_bytes'} = 
							substr($pendingBytes, $writelen);
					${*$self}{'pipeline_pending_size'} = 
							$pendingSize - $writelen;
				}
				else {
					${*$self}{'pipeline_pending_bytes'} = '';
					${*$self}{'pipeline_pending_size'} = 0;
				}			
			}
			else {
				return $writelen;
			}
			$loop = 1;
		}
	} while ($loop);
	
	return $readlen;
}

sub sysseek {
	my $self = shift;

	return 0;
}

sub close {
	my $self = shift;

	my $reader = ${*$self}{'pipeline_reader'};
	if (defined($reader)) {
		$reader->close();
	}

	my $writer = ${*$self}{'pipeline_writer'};
	if (defined($writer)) {
		$writer->close();
	}

	my $listenReader = ${*$self}{'pipeline_listen_reader'};
	if (defined($listenReader)) {
		Slim::Networking::Select::addRead($listenReader, undef);
		Slim::Networking::Select::addError($listenReader, undef);
		${*$listenReader}{'pipeline'} = undef;
		$listenReader->close();
	}

	my $listenWriter = ${*$self}{'pipeline_listen_writer'};
	if (defined($listenWriter)) {
		Slim::Networking::Select::addRead($listenWriter, undef);
		Slim::Networking::Select::addError($listenWriter, undef);
		${*$listenWriter}{'pipeline'} = undef;
		$listenWriter->close();
	}

	my $source = ${*$self}{'pipeline_source'};
	if (defined($source)) {
		$source->close();
	}
}

1;
__END__

# Local Variables:
# tab-width:4
# indent-tabs-mode:t
# End:
