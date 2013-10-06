use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 11;
use Farly;
use Farly::Rule::Expander;
use Farly::Discover::Services;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $discoverer;

eval { $discoverer = Farly::Discover::Services->new('internal1.txt'); };

ok( $@ =~ /managed networks file internal1.txt not found/, 'wrong file' );

my $ip = Farly::IPv4::Address->new('172.16.1.56');
$discoverer = Farly::Discover::Services->new("$path/internal.net");

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

ok( $discoverer->_has_service($ce), '_has_service' );

my $clone = $ce->clone();

$clone->set( 'PROTOCOL', Farly::Transport::Protocol->new('0') );
$clone->delete_key('DST_PORT');

ok( !$discoverer->_has_service($clone), '! _has_service' );

my $list = Farly::Object::List->new();

$list->add( $ce );

$discoverer->check( $list);

ok( defined( $discoverer->result()->{ $ce->get('DST_IP')->address() } ), '_store and result' );

my $set = $discoverer->result()->{ $ce->get('DST_IP')->address() };

ok( $set->isa('Farly::Object::Set'), 'result type' );

ok( $set->size() == 1, 'result size' );

my $srv = Farly::Object->new();
$srv->set( 'DST_IP',      Farly::IPv4::Address->new('172.16.1.10') );
$srv->set( 'DST_PORT',    Farly::Transport::Port->new('443') );
$srv->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$srv->set( 'PROTOCOL',    Farly::Transport::Protocol->new('6') );

ok( $set->contains($srv), 'result included' );

my $importer = Farly->new();
my $container = $importer->process( 'ASA', "$path/discover.cfg" );
my $expander = Farly::Rule::Expander->new($container);
my $rules = $expander->expand_all();

$discoverer->check($rules);

ok( scalar( keys %{ $discoverer->result() } ) == 3, 'result size, rules' );

$ip = Farly::IPv4::Address->new('10.2.3.25');

ok( !$discoverer->result()->{ $ip->address }, 'excluded unmanaged' );

$ip = Farly::IPv4::Address->new('192.168.2.3');

$set = $discoverer->result()->{ $ip->address };

ok( $set->size() == 2, 'found services' );

=b
foreach my $obj ( $set->iter ) {
	print $obj->dump(),"\n";
}
