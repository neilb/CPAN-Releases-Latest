#!perl

#
# 05-live-test.t
#
# Iterate across all releases and look for the three dists that
# were last released by AMOSS in 1995. Check that we get the expected
# timestamp for each dist.
#

use strict;
use warnings;
use Test::More tests => 2;

use CPAN::Releases::Latest;

my %expected = (
    'SGI-FM'        => 'A/AM/AMOSS/SGI-FM-0.1.tar.gz 1995-08-20 07:29:54',
    'SGI-GL'        => 'A/AM/AMOSS/SGI-GL-0.2.tar.gz 1995-08-20 07:30:34',
    'SGI-SysCalls'  => 'A/AM/AMOSS/SGI-SysCalls-0.1.tar.gz 1995-08-20 07:31:05',
);
my %got;

my $latest;

eval { $latest = CPAN::Releases::Latest->new(max_age => '1 hour') };

SKIP: {
    skip("Looks like either you or MetaCPAN is offline", 2) if $@;

    my $iterator = $latest->release_iterator;

    while (my $release = $iterator->next_release) {
        next unless exists($expected{ $release->distname });
        $got{ $release->distname } = $release->path
                                     .' '
                                     .format_timestamp($release->timestamp);
    }

    ok(keys(%got) == keys(%expected),
       "Did we see the expected number of dists?");

    is(render_dists(\%got), render_dists(\%expected),
       "Did we get the expected information for the dists?");
}

sub format_timestamp
{
    my $timestamp = shift;
    my @tm        = gmtime($timestamp);

    return sprintf('%d-%.2d-%.2d %.2d:%.2d:%.2d',
                   $tm[5]+1900, $tm[4]+1, $tm[3], $tm[2], $tm[1], $tm[0]
                  );
}

sub render_dists
{
    my $hashref = shift;
    my $string  = '';

    foreach my $dist (sort { lc($a) cmp lc($b) } keys %$hashref) {
        $string .= "$dist $hashref->{$dist}\n";
    }
    return $string;
}

