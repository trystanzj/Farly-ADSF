use strict;
use warnings;
use Test::More tests => 4;
use Farly::Config::Reader;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $cfg_reader;

eval { $cfg_reader = Farly::Config::Reader->new(); };

ok( $@ =~ /configuration file not specified/, 'no file' );

eval { $cfg_reader = Farly::Config::Reader->new('not_a_file.txt'); };

ok( $@ =~ /configuration file not_a_file.txt not found/, 'wrong file' );

eval { $cfg_reader = Farly::Config::Reader->new("$path/farly.conf.err") };

ok( $@ =~ /Invalid decl item/, 'error in config' );

$cfg_reader = Farly::Config::Reader->new("$path/farly.conf");

my $expected = {
    'object_storage' => {
        'db_password' => '1234',
        'pid_dir'     => '/var/run/farly',
        'dir'         => '/var/db/farly'
    },
    'firewall_list'     => { 'file' => '/etc/farly/firewalls.csv' },
    'internal_networks' => { 'file' => '/etc/farly/networks.csv' },
    'network_topology'  => { 'file' => 'topology.csv' }
};

is_deeply( $cfg_reader->config, $expected, 'read ok' );
