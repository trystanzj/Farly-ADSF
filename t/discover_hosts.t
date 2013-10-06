use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 4;
use Farly::Object;
use Farly::Discover::Hosts;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $discoverer;

eval { $discoverer = Farly::Discover::Hosts->new('internal1.txt'); };

ok( $@ =~ /managed networks file internal1.txt not found/, 'wrong file' );

my $ip = Farly::IPv4::Address->new('172.16.1.56');
$discoverer = Farly::Discover::Hosts->new("$path/internal.net");

ok( $discoverer->_is_managed($ip), 'is_managed' );

my $ce = Farly::Object->new();

$ce->set( 'ACTION',   Farly::Value::String->new('permit') );
$ce->set( 'DST_IP',   Farly::IPv4::Address->new('172.16.1.10') );
$ce->set( 'DST_PORT', Farly::Transport::Port->new('443') );
$ce->set( 'ENTRY',    Farly::Value::String->new('RULE') );
$ce->set( 'ID',       Farly::Value::String->new('outside-in') );
$ce->set( 'LINE',     Farly::Value::Integer->new('1') );
$ce->set( 'PROTOCOL', Farly::Transport::Protocol->new('6') );
$ce->set( 'SRC_IP',   Farly::IPv4::Address->new('10.2.3.25') );

my $list = Farly::Object::List->new();

$list->add( $ce );

$discoverer->check( $list);

ok( defined( $discoverer->result()->{ $ce->get('DST_IP')->address() } ), '_store and result' );

my $actual_object = $discoverer->result()->{ $ce->get('DST_IP')->address() };

my $expected_obj = Farly::Object->new();
$expected_obj->set( 'OBJECT', Farly::IPv4::Address->new('172.16.1.10') );
$expected_obj->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );

ok( $actual_object->matches( $expected_obj ), 'result ok' );
