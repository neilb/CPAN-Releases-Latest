package CPAN::Releases::Latest::ReleaseIterator;

use 5.006;
use Moo;
use CPAN::Releases::Latest;
use CPAN::Releases::Latest::Release;
use autodie;

has 'latest' =>
    (
        is      => 'ro',
        default => sub { CPAN::Releases::Latest->new() },
    );

has _fh => (is => 'rw');

sub next_release
{
    my $self = shift;
    my $fh;

    if (not defined($fh = $self->_fh)) {
        open($fh, '<', $self->latest->path || $self->latest->cache_path);
        my $header = <$fh>;
        $self->_fh($fh);
    }

    my $line = <$fh>;
    if (defined($line)) {
        chomp($line);
        my ($distname, $path, $time, $size) = split(/\s+/, $line);
        return CPAN::Releases::Latest::Release->new(
                   distname  => $distname,
                   path      => $path,
                   timestamp => $time,
                   size      => $size,
               );
    }
    else {
        return undef;
    }

}

1;
