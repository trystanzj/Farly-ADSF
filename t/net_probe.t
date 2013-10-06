use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 6;
use Farly::Object;
use Farly::Net::Probe;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $one_week_ago   = time() - 3600 * 24 * 7;
my $three_days_ago = time() - 3600 * 24 * 3;
my $one_hour_ago   = time() - 3600;

my $host = Farly::Object->new();
$host->set( 'OBJECT',      Farly::IPv4::Address->new('127.0.0.1') );
$host->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );
$host->set( 'DISCOVERED',  Farly::Value::Integer->new($one_week_ago) );
$host->set( 'LAST_SEEN',   Farly::Value::Integer->new($three_days_ago) );
$host->set( 'POLLED',      Farly::Value::Integer->new(10) );

my $prober = Farly::Net::Probe->new(
    timeout     => 3,
    max_retries => 2,
);

$prober->probe($host);

ok( $host->get('POLLED')->number() == 11, 'host polled' );

ok( $host->get('LAST_SEEN')->number() > $three_days_ago, 'host last seen' );

my $tcp_srv = Farly::Object->new();
$tcp_srv->set( 'DST_IP',   Farly::IPv4::Address->new('127.0.0.1') );
$tcp_srv->set( 'DST_PORT', Farly::Transport::Port->new('22') );
$tcp_srv->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$tcp_srv->set( 'PROTOCOL',    Farly::Transport::Protocol->new('6') );
$tcp_srv->set( 'DISCOVERED', Farly::Value::Integer->new($one_week_ago) );
$tcp_srv->set( 'LAST_SEEN',  Farly::Value::Integer->new($three_days_ago) );
$tcp_srv->set( 'POLLED',     Farly::Value::Integer->new(10) );

my $udp_srv = Farly::Object->new();
$udp_srv->set( 'DST_IP',   Farly::IPv4::Address->new('127.0.0.1') );
$udp_srv->set( 'DST_PORT', Farly::Transport::Port->new('63022') );
$udp_srv->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$udp_srv->set( 'PROTOCOL',    Farly::Transport::Protocol->new('17') );
$udp_srv->set( 'DISCOVERED', Farly::Value::Integer->new($one_week_ago) );
$udp_srv->set( 'LAST_SEEN',  Farly::Value::Integer->new($three_days_ago) );
$udp_srv->set( 'POLLED',     Farly::Value::Integer->new(10) );

my $set = Farly::Object::Set->new();

$set->add($tcp_srv);
$set->add($udp_srv);

$prober->probe($set);

ok( $tcp_srv->get('POLLED')->number() == 11, 'tcp service polled' );

ok( $tcp_srv->get('LAST_SEEN')->number() > $three_days_ago, 'service last seen' );

ok( $udp_srv->get('POLLED')->number() == 11, 'udp service polled' );

$set->add($host);

eval{ $prober->probe($set); };

ok( $@ =~ /unknown object/, 'host in service set' );

