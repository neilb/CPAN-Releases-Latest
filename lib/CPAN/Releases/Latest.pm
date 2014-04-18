package CPAN::Releases::Latest;

use 5.006;
use Moo;
use File::HomeDir;
use File::Spec::Functions 'catfile';
use MetaCPAN::Client 1.001001;
use CPAN::DistnameInfo;
use Carp;
use autodie;

my $FORMAT_REVISION = 1;

has 'max_age'    => (is => 'ro', default => sub { '1 day' });
has 'cache_path' => (is => 'rw');
has 'basename'   => (is => 'ro', default => sub { 'latest-releases.txt' });
has 'path'       => (is => 'ro');

sub BUILD
{
    my $self = shift;

    if ($self->path) {
        if (-f $self->path) {
            return;
        }
        else {
            croak "the file you specified with 'path' doesn't exist";
        }
    }

    if (not $self->cache_path) {
        my $classid = __PACKAGE__;
           $classid =~ s/::/-/g;

        $self->cache_path(
            catfile(File::HomeDir->my_dist_data($classid, { create => 1 }),
                    $self->basename)
        );
    }

    if (-f $self->cache_path) {
        require Time::Duration::Parse;
        my $max_age_in_seconds = Time::Duration::Parse::parse_duration(
                                     $self->max_age
                                 );
        return unless time() - $max_age_in_seconds
                      > (stat($self->cache_path))[9];
    }

    $self->_build_cached_index();
}

sub _build_cached_index
{
    my $self     = shift;
    my $distdata = $self->_get_release_info_from_metacpan();

    $self->_write_cache_file($distdata);
}

sub _get_release_info_from_metacpan
{
    my $self       = shift;
    my $client     = MetaCPAN::Client->new();
    my $query      = {
                        either => [
                                      { all => [
                                          { status   => 'latest'    },
                                          { maturity => 'released'  },
                                      ]},

                                      { all => [
                                          { status   => 'cpan'      },
                                          { maturity => 'developer' },
                                      ]},
                                   ]
                     };
    my $params     = {
                         fields => [qw(name version date status maturity stat download_url)]
                     };
    my $result_set = $client->release($query, $params);
    my $distdata   = {
                         released  => {},
                         developer => {},
                     };

    while (my $release = $result_set->next) {
        my $maturity = $release->maturity;
        my $slice    = $distdata->{$maturity};
        my $path     = $release->download_url;
           $path     =~ s!^.*/authors/id/!!;
        my $distinfo = CPAN::DistnameInfo->new($path);
        my $distname = defined($distinfo) && defined($distinfo->dist)
                       ? $distinfo->dist
                       : $release->name;

        next unless !exists($slice->{ $distname })
                 || $release->stat->{mtime} > $slice->{$distname}->{time};
        $slice->{ $distname } = {
                                    path => $path,
                                    time => $release->stat->{mtime},
                                    size => $release->stat->{size},
                                };
    }

    return $distdata;
}

sub _write_cache_file
{
    my $self     = shift;
    my $distdata = shift;
    my %seen;

    $seen{$_} = 1 for keys(%{ $distdata->{released} });
    $seen{$_} = 1 for keys(%{ $distdata->{developer} });

    open(my $fh, '>', $self->cache_path);
    print $fh "#FORMAT: $FORMAT_REVISION\n";
    foreach my $distname (sort { lc($a) cmp lc($b) } keys %seen) {
        my ($stable_release, $developer_release);

        if (defined($stable_release = $distdata->{released}->{$distname})) {
            printf $fh "%s %s %d %d\n",
                       $distname,
                       $stable_release->{path},
                       $stable_release->{time},
                       $stable_release->{size};
        }

        if (   defined($developer_release = $distdata->{developer}->{$distname})
            && (   !defined($stable_release)
                || $developer_release->{time} > $stable_release->{time}
               )
           )
        {
            printf $fh "%s %s %d %d\n",
                       $distname,
                       $developer_release->{path},
                       $developer_release->{time},
                       $developer_release->{size};
        }

    }
    close($fh);
}

sub release_iterator
{
    my $self = shift;

    require CPAN::Releases::Latest::ReleaseIterator;
    return CPAN::Releases::Latest::ReleaseIterator->new( latest => $self, @_ );
}

sub _open_file
{
    my $self       = shift;
    my $options    = @_ > 0 ? shift : {};
    my $filename   = $self->cache_path;
    my $whatfile   = 'cached';
    my $from_cache = 1;
    my $fh;

    if (defined($self->path)) {
        $filename   = $self->path;
        $from_cache = 0;
        $whatfile   = 'passed';
    }

    open($fh, '<', $filename);
    my $line = <$fh>;
    if ($line !~ m!^#FORMAT: (\d+)$!) {
        croak "unexpected format of first line - should give format";
    }
    my $file_revision = $1;

    if ($file_revision > $FORMAT_REVISION) {
        croak "the $whatfile file has a later format revision ($file_revision) ",
              "than this version of ", __PACKAGE__,
              " supports ($FORMAT_REVISION). Maybe it's time to upgrade?\n";
    }

    if ($file_revision < $FORMAT_REVISION) {
        if ($whatfile eq 'passed') {
            croak "the passed file $filename is from an older version of ",
                  __PACKAGE__, "\n";
        }

        # The locally cached version was written by an older version of
        # this module, but is still within the max_age constraint, which
        # is how we ended up here. We rebuild the cached index and call
        # this method again. But if we're here because we were trying to
        # rebuild the index, then bomb out, because This Should Never Happen[TM].
        if ($options->{rebuilding}) {
            croak "failed to rebuild the cached index with the expected version\n";
        }
        $self->_build_cached_index();
        return $self->_open_file({ rebuilding => 1});
    }

    return $fh;
}

1;

=head1 NAME

CPAN::Releases::Latest - find latest release(s) of all dists on CPAN, including dev releases

=head1 SYNOPSIS

 use CPAN::Releases::Latest;
 
 my $latest   = CPAN::Releases::Latest->new(max_age => '1 day');
 my $iterator = $latest->release_iterator();
 
 while (my $release = $iterator->next_release) {
     printf "%s path=%s  time=%d  size=%d\n",
            $release->distname,
            $release->path,
            $release->timestamp,
            $release->size;
 }

=head1 DESCRIPTION

VERY MUCH AN ALPHA. ALL THINGS MAY CHANGE.

This module uses the MetaCPAN API to construct a list of all dists on CPAN.
The generated index is cached locally.
It will let you iterate across these, returning the latest release of the dist.
If the latest release is a developer release, then you'll first get back the
non-developer release (if there is one), and then you'll get back the developer release.

When you instantiate this class, you can specify the C<max_age> of
the generated index. You can specify the age
using any of the expressions supported by L<Time::Duration::Parse>:

 5 minutes
 1 hour and 30 minutes
 2d
 3600

If no units are given, it will be interpreted as a number of seconds.
The default for max age is 1 day.

If you already have a cached copy of the index, and it is less than
the specified age, then we'll use your cached copy and not even
check with MetaCPAN.

=head1 SEE ALSO

L<CPAN::ReleaseHistory> provides a similar iterator, but for all releases
ever made to CPAN, even those that are no longer on CPAN.

L<BackPAN::Index> is another way to get information about all releases
ever made to CPAN.

=head1 REPOSITORY

L<https://github.com/neilbowers/CPAN-Releases-Latest>

=head1 AUTHOR

Neil Bowers E<lt>neilb@cpan.orgE<gt>

=head1 COPYRIGHT AND LICENSE

This software is copyright (c) 2014 by Neil Bowers <neilb@cpan.org>.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=cut

