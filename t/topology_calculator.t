use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 3;
use Farly;
use Farly::Topology::Routes;
use Farly::Topology::Calculator;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $routes = Farly::Topology::Routes->new("$path/topology.csv");

ok ( $routes->list->size() == 29, "routes" );

my $importer = Farly->new();

my $fw1 = $importer->process( 'ASA', "$path/fw1.cfg" );
my $fw2 = $importer->process( 'ASA', "$path/fw2.cfg" );

my $topology_calculator = Farly::Topology::Calculator->new("$path/topology.csv");

eval{ $topology_calculator->calculate( $fw1 );};
ok ( $@ =~ /interface dmz not found/, 'no dmz interface');

my $new_if = Farly::Object->new();

$new_if->set('ENTRY' => Farly::Value::String->new('INTERFACE'));
$new_if->set('ID' => Farly::Value::String->new('dmz'));
$new_if->set('MASK' => Farly::IPv4::Address->new('255.255.255.248'));
$new_if->set('NAME' => Farly::Value::String->new('Vlan1'));
$new_if->set('OBJECT' => Farly::IPv4::Address->new('10.2.5.8'));
$new_if->set('SECURITY_LEVEL' => Farly::Value::Integer->new('0'));

$fw1->add($new_if);

$topology_calculator = Farly::Topology::Calculator->new("$path/topology.csv");

$topology_calculator->calculate( $fw2 );

ok( $topology_calculator->topology->size() == 12, "topology size");

=b
foreach my $object ($topology_calculator->topology->iter ) {
	my $property;
	$property = 'SRC_IP' if ( $object->has_defined('SRC_IP') );
	$property = 'DST_IP' if ( $object->has_defined('DST_IP') );

	print $object->get('HOSTNAME')->as_string()," ";	
	print $object->get('RULE')->get('ID')->as_string()," ";
	print $property," ",$object->get($property)->as_string(),"\n";
	
}
