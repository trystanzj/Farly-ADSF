use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 4;
use Farly::Object;
use Farly::Net::Managed;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $managed_nets;

eval { $managed_nets = Farly::Net::Managed->new('internal1.txt'); };

ok( $@ =~ /open failed/, 'wrong file' );

$managed_nets = Farly::Net::Managed->new("$path/internal.net");

ok( scalar( $managed_nets->managed ) == 4, 'managed netorks list' );

my $ip = Farly::IPv4::Address->new('172.16.1.56');

ok( $managed_nets->is_managed($ip), 'is_managed' );

my $ip2 = Farly::IPv4::Address->new('10.1.2.3');

ok( !$managed_nets->is_managed($ip2), '! is_managed' );
