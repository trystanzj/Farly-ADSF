use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 7;
use Farly;
use Farly::Rule::Expander;
use Farly::Sync::Hosts;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

require "$path/Repo.pm";

my $sync;
$sync = Farly::Sync::Hosts->new();

eval { $sync->set_managed(); };
ok( $@ =~ /file not specified/, 'no managed networks' );

eval { $sync->set_managed("$path/internal.net.err"); };
ok( $@ =~ /Invalid input/, 'invalid input' );

$sync = Farly::Sync::Hosts->new();
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
$ce1->set( 'OBJECT',      Farly::IPv4::Address->new('172.16.1.10') );
$ce1->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );
$ce1->set( 'DISCOVERED',  Farly::Value::Integer->new($one_week_ago) );
$ce1->set( 'LAST_SEEN',   Farly::Value::Integer->new($three_days_ago) );
$ce1->set( 'POLLED',      Farly::Value::Integer->new(10) );

my $address1 = $ce1->get('OBJECT')->address();

$repo->put( $address1, $ce1 );

=b
my $set;
$db->db_get( $address1, $set);
foreach my $obj ( $set->iter ) {
	print $obj->dump(),"\n";
}
=cut

my $ce2 = Farly::Object->new();
$ce2->set( 'OBJECT',      Farly::IPv4::Address->new('192.168.2.3') );
$ce2->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );
$ce2->set( 'DISCOVERED',  Farly::Value::Integer->new($one_week_ago) );
$ce2->set( 'LAST_SEEN',   Farly::Value::Integer->new($one_hour_ago) );
$ce2->set( 'POLLED',      Farly::Value::Integer->new(10) );

my $address2 = $ce2->get('OBJECT')->address();

$repo->put( $address2, $ce2 );

my $importer = Farly->new();
my $container = $importer->process( 'ASA', "$path/discover.cfg" );
my $expander = Farly::Rule::Expander->new($container);
my $rules = $expander->expand_all();

my $host_syncer = Farly::Sync::Hosts->new();
$host_syncer->set_managed("$path/internal.net");
$host_syncer->set_repo($repo);

$host_syncer->check( $rules );

#print "\n\n";
my $expected_host = Farly::Object->new();

$expected_host->set( 'OBJECT' => Farly::IPv4::Address->new('172.16.1.10') );
$expected_host->set( 'OBJECT_TYPE' => Farly::Value::String->new('HOST') );

my $includes_host;

foreach my $host ( @{ $host_syncer->result() } ) {

    #print $host->dump(), "\n";
    if ( $host->matches($expected_host) ) {
        $includes_host = 1;
    }
}

ok( $includes_host, 'host found' );
