use strict;
use warnings;
use Test::Simple tests => 3;
use File::Spec;
use Farly;
use Farly::Topology::Routes;
use Farly::Topology::Calculator;
use Farly::Topology::Search;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $routes = Farly::Topology::Routes->new("$path/topology.csv");

ok ( $routes->list->size() == 29, "routes" );

my $importer = Farly->new();

my $fw1 = $importer->process( 'ASA', "$path/fw1.cfg" );
my $fw2 = $importer->process( 'ASA', "$path/fw2.cfg" );

my $new_if = Farly::Object->new();

$new_if->set('ENTRY' => Farly::Value::String->new('INTERFACE'));
$new_if->set('ID' => Farly::Value::String->new('dmz'));
$new_if->set('MASK' => Farly::IPv4::Address->new('255.255.255.248'));
$new_if->set('NAME' => Farly::Value::String->new('Vlan1'));
$new_if->set('OBJECT' => Farly::IPv4::Address->new('10.2.5.8'));
$new_if->set('SECURITY_LEVEL' => Farly::Value::Integer->new('0'));

$fw1->add($new_if);

my $topology_calculator = Farly::Topology::Calculator->new("$path/topology.csv");
$topology_calculator->calculate( $fw1 );
$topology_calculator->calculate( $fw2 );

my $topology = Farly::Topology::Search->new( $topology_calculator->topology );

my $search1 = Farly::Object->new();
$search1->set( 'SRC_IP', Farly::IPv4::Address->new('10.30.51.4') );

my $rule_sets = $topology->matches($search1);

ok ( $rule_sets->size == 1, 'search');

$topology->set_include_any(1);

$rule_sets = $topology->matches($search1);

ok ( $rule_sets->size == 4, 'search including any');

=b
print "\n";
foreach my $object ($rule_sets->iter ) {
	print $object->get('HOSTNAME')->as_string()," ";	
	print $object->get('RULE')->get('ID')->as_string(),"\n";
#    print $object->dump(),"\n";
}
