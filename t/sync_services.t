use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 8;
use Farly;
use Farly::Rule::Expander;
use Farly::Sync::Services;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

require "$path/Repo.pm";

my $sync;
$sync = Farly::Sync::Services->new();

eval { $sync->set_managed(); };
ok( $@ =~ /file not specified/, 'no managed networks' );

eval { $sync->set_managed("$path/internal.net.err"); };
ok( $@ =~ /Invalid input/, 'invalid input' );

$sync = Farly::Sync::Services->new();
$sync->set_managed("$path/internal.net");

my $four_days = 3600 * 24 * 4;

$sync->set_timeout($four_days);

ok( $sync->timeout() == $four_days, 'timeout' );
my $ip = Farly::IPv4::Address->new('172.16.1.56');

ok( $sync->_is_managed($ip), 'is_managed' );

my $object = Farly::Object->new();

$object->set( 'LAST_SEEN', Farly::Value::Integer->new( time() - $four_days - 3600 ) );
$object->set( 'POLLED', Farly::Value::Integer->new(40) );

ok( $sync->_is_down($object), '_is_down' );

$object->set( 'LAST_SEEN', Farly::Value::Integer->new( time() - $four_days + 3600 ) );

ok( !$sync->_is_down($object), '! _is_down' );

my $repo = Repo->new();

my $one_week_ago   = time() - 3600 * 24 * 7;
my $three_days_ago = time() - 3600 * 24 * 3;
my $one_hour_ago   = time() - 3600;

my $ce1 = Farly::Object->new();
$ce1->set( 'DST_IP',   Farly::IPv4::Address->new('172.16.1.10') );
$ce1->set( 'DST_PORT', Farly::Transport::Port->new('443') );
$ce1->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$ce1->set( 'PROTOCOL',    Farly::Transport::Protocol->new('6') );
$ce1->set( 'DISCOVERED', Farly::Value::Integer->new($one_week_ago) );
$ce1->set( 'LAST_SEEN',  Farly::Value::Integer->new($three_days_ago) );
$ce1->set( 'POLLED',     Farly::Value::Integer->new(10) );

my $set1 = Farly::Object::Set->new();
$set1->add($ce1);

my $address1 = $ce1->get('DST_IP')->address();

$repo->put( $address1, $set1 );

=b
my $set;
$db->db_get( $address1, $set);
foreach my $obj ( $set->iter ) {
	print $obj->dump(),"\n";
}
=cut

my $set2 = Farly::Object::Set->new();

my $ce4 = Farly::Object->new();
$ce4->set( 'DST_IP',      Farly::IPv4::Address->new('192.168.2.3') );
$ce4->set( 'DST_PORT',    Farly::Transport::Port->new('1494') );
$ce4->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$ce4->set( 'PROTOCOL',    Farly::Transport::Protocol->new('6') );
$ce4->set( 'DISCOVERED',  Farly::Value::Integer->new($one_week_ago) );
$ce4->set( 'LAST_SEEN',   Farly::Value::Integer->new($three_days_ago) );
$ce4->set( 'POLLED',      Farly::Value::Integer->new(10) );

$set2->add($ce4);

my $ce5 = Farly::Object->new();
$ce5->set( 'DST_IP',      Farly::IPv4::Address->new('192.168.2.3') );
$ce5->set( 'DST_PORT',    Farly::Transport::Port->new('2598') );
$ce5->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );
$ce5->set( 'PROTOCOL',    Farly::Transport::Protocol->new('17') );
$ce5->set( 'DISCOVERED',  Farly::Value::Integer->new($one_week_ago) );
$ce5->set( 'LAST_SEEN',   Farly::Value::Integer->new($one_hour_ago) );
$ce5->set( 'POLLED',      Farly::Value::Integer->new(10) );

$set2->add($ce5);

my $address2 = $ce5->get('DST_IP')->address();

$repo->put( $address2, $set2 );

my $importer = Farly->new();
my $container = $importer->process( 'ASA', "$path/discover.cfg" );
my $expander = Farly::Rule::Expander->new($container);
my $rules = $expander->expand_all();

my $srv_syncer = Farly::Sync::Services->new();
$srv_syncer->set_managed("$path/internal.net");
$srv_syncer->set_repo($repo);

$srv_syncer->check( $rules );

my $expected_rule_1 = Farly::Object->new();

$expected_rule_1->set( 'REMOVE'   => Farly::Value::String->new('RULE') );
$expected_rule_1->set( 'ACTION'   => Farly::Value::String->new('permit') );
$expected_rule_1->set( 'DST_IP'   => Farly::IPv4::Address->new('172.16.1.10') );
$expected_rule_1->set( 'DST_PORT' => Farly::Transport::Port->new('443') );
$expected_rule_1->set( 'ENTRY'    => Farly::Value::String->new('RULE') );
$expected_rule_1->set( 'ID'       => Farly::Value::String->new('outside-in') );
$expected_rule_1->set( 'LINE'     => Farly::Value::Integer->new('1') );
$expected_rule_1->set( 'PROTOCOL' => Farly::Transport::Protocol->new('6') );
$expected_rule_1->set( 'SRC_IP'   => Farly::IPv4::Address->new('10.2.3.25') );

my $expected_rule_2 = Farly::Object->new();

$expected_rule_2->set( 'REMOVE'   => Farly::Value::String->new('RULE') );
$expected_rule_2->set( 'ACTION'   => Farly::Value::String->new('permit') );
$expected_rule_2->set( 'DST_IP'   => Farly::IPv4::Address->new('192.168.2.3') );
$expected_rule_2->set( 'DST_PORT' => Farly::Transport::Port->new('1494') );
$expected_rule_2->set( 'ENTRY'    => Farly::Value::String->new('RULE') );
$expected_rule_2->set( 'ID'       => Farly::Value::String->new('outside-in') );
$expected_rule_2->set( 'LINE'     => Farly::Value::Integer->new('3') );
$expected_rule_2->set( 'PROTOCOL' => Farly::Transport::Protocol->new('6') );
$expected_rule_2->set( 'SRC_IP' => Farly::IPv4::Network->new('0.0.0.0 0.0.0.0') );

my $includes_1;
my $includes_2;

foreach my $obj ( $rules->iter() ) {

    #print $obj->dump(), "\n";
    if ( $obj->matches($expected_rule_1) ) {
        $includes_1 = 1;
    }
    if ( $obj->matches($expected_rule_2) ) {
        $includes_2 = 1;
    }
}

ok( $includes_1, 'remove first rule' );
ok( $includes_2, 'remove second rule' );
