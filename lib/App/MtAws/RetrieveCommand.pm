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

package App::MtAws::RetrieveCommand;

use strict;
use warnings;
use utf8;
use Carp;
use App::MtAws::ForkEngine qw/with_forks fork_engine/;
use App::MtAws::Utils;

sub run
{
	my ($options, $j) = @_;
		
	with_forks !$options->{'dry-run'}, $options, sub {
		$j->read_journal(should_exist => 1);
		
		my $files = $j->{journal_h};
		# TODO: refactor
		my @filelist =	grep { ! -f binaryfilename $_->{filename} } map { {archive_id => $files->{$_}->{archive_id}, relfilename =>$_, filename=> $j->absfilename($_) } } keys %{$files};
		@filelist  = splice(@filelist, 0, $options->{'max-number-of-files'});
		
		if (@filelist) {
			if ($options->{'dry-run'}) {
				for (@filelist) {
					print "Will RETRIEVE archive $_->{archive_id} (filename $_->{relfilename})\n"
				}
			} else {
				$j->open_for_write();
				my $ft = App::MtAws::JobProxy->new(job => App::MtAws::FileListRetrievalJob->new(archives => \@filelist ));
				my ($R) = fork_engine->{parent_worker}->process_task($ft, $j);
				die unless $R;
				$j->close_for_write();
			}
		} else {
			print "Nothing to restore\n";
		}
	}
}

1;

__END__
