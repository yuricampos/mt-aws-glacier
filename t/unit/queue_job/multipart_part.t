#!/usr/bin/env perl

# mt-aws-glacier - Amazon Glacier sync client
# Copyright (C) 2012-2013  Victor Efimov
# http://mt-aws.com (also http://vs-dev.com) vs@vs-dev.com
# License: GPLv3
#
# This file is part of "mt-aws-glacier"
#
#    mt-aws-glacier is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    mt-aws-glacier is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Test::More tests => 147;
use Test::Deep;
use FindBin;
use lib map { "$FindBin::RealBin/../$_" } qw{../lib ../../lib};
use LCGRandom;
use App::MtAws::QueueJobResult;
use App::MtAws::QueueJob::MultipartPart;
use MyQueueEngine;
use QueueHelpers;
use TestUtils;

warning_fatal();


use Data::Dumper;

sub test_case
{
	my ($n, $relfilename, $mtime, $test_cb) = @_;
	my @orig_parts = map { [$_*10, "hash $_", \"file $_"] } (0..$n);
	my @parts = @orig_parts;
	my %args = (relfilename => $relfilename, partsize => 2*1024*1024, upload_id => "someuploadid", fh => "somefh", mtime => $mtime);

	no warnings 'redefine';
	local *App::MtAws::QueueJob::MultipartPart::read_part = sub {
		my $p = shift @parts;
		if ($p) {
			return (1, @$p)
		} else {
			return;
		}
	};

	my $j = App::MtAws::QueueJob::MultipartPart->new(%args);
	$test_cb->($j, \%args, \@orig_parts);
}


sub test_with_filename_and_mtime
{
	my ($relfilename, $mtime) = @_;
	
	# late finish (callbacks called in the end)
	
	test_case 15, $relfilename, $mtime, sub {
		my ($j, $args, $parts) = @_;
		my @callbacks;
		for (@$parts) {
			my $res = $j->next;
			cmp_deeply $res,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							start => $_->[0],
							upload_id => $args->{upload_id},
							part_final_hash => $_->[1],
							relfilename => $args->{relfilename},
							mtime => $args->{mtime},
						},
						attachment => $_->[2],
						action => 'upload_part',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
			push @callbacks, $res->{task}{cb_task_proxy};
		}
	
		lcg_srand 444242 => sub {
			@callbacks = lcg_shuffle @callbacks; # late finish, but in random order
	
			while (my $cb = shift @callbacks) {
				$cb->();
				cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => @callbacks ? JOB_WAIT : JOB_DONE);
			}
		}
	};
	
	# early finish (early calls of callbacks)
	
	test_case 11, $relfilename, $mtime, sub {
		my ($j, $args, $parts) = @_;
	
		for (@$parts) {
			my $res = $j->next;
			cmp_deeply $res,
				App::MtAws::QueueJobResult->full_new(
					task => {
						args => {
							start => $_->[0],
							upload_id => $args->{upload_id},
							part_final_hash => $_->[1],
							relfilename => $args->{relfilename},
							mtime => $args->{mtime},
						},
						attachment => $_->[2],
						action => 'upload_part',
						cb => test_coderef,
						cb_task_proxy => test_coderef,
					},
					code => JOB_OK,
				);
			$res->{task}{cb_task_proxy}->();
		}
		cmp_deeply $j->next, App::MtAws::QueueJobResult->full_new(code => JOB_DONE);
	
	};
}

test_with_filename_and_mtime "somefile", 12345;
test_with_filename_and_mtime "somefile", 0;
test_with_filename_and_mtime 0, 12345;

# test case with early/late/random finish

{
	{
		package QE;
		use MyQueueEngine;
		use base q{MyQueueEngine};

		sub on_upload_part
		{
			my ($self, %args) = @_;
			push @{$self->{res}}, $args{part_final_hash};
		}
	};

	lcg_srand 4672 => sub {
		for my $n (1, 2, 15) {
			for my $workers (1, 2, 10, 20) {
				test_case $n, "somefile", 12345, sub {
					my ($j, $args, $parts) = @_;
					my $q = QE->new(n => $workers);
					$q->process($j);
					cmp_deeply [sort @{ $q->{res} }], [sort map { $_->[1] } @$parts];
				};
			}
		}
	}
}

1;
