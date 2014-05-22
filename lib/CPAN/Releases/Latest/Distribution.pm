package CPAN::Releases::Latest::Distribution;

use 5.006;
use Moo;

has 'distname'          => (is => 'ro');
has 'release'           => (is => 'ro');
has 'developer_release' => (is => 'ro');

1;
