use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 1;
use Farly;
use Farly::Rule::Expander;
use Farly::Topology::Calculator;
use Farly::Rule::Direction;
use Farly::Template::Cisco;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $importer = Farly->new();
my $fw = $importer->process( 'ASA', "$path/fw1.cfg" );
my $expander = Farly::Rule::Expander->new($fw);
my $rules = $expander->expand_all();

my $search = Farly::Object->new();
$search->set( 'ENTRY', Farly::Value::String->new('RULE') );
$search->set( 'ID',    Farly::Value::String->new('outside-in') );

my $outside_rules = Farly::Object::List->new();
$rules->matches( $search, $outside_rules );

my $new_if = Farly::Object->new();
$new_if->set('ENTRY' => Farly::Value::String->new('INTERFACE'));
$new_if->set('ID' => Farly::Value::String->new('dmz'));
$new_if->set('MASK' => Farly::IPv4::Address->new('255.255.255.248'));
$new_if->set('NAME' => Farly::Value::String->new('Vlan1'));
$new_if->set('OBJECT' => Farly::IPv4::Address->new('10.2.5.8'));
$new_if->set('SECURITY_LEVEL' => Farly::Value::Integer->new('0'));
$fw->add($new_if);

my $topology_calculator = Farly::Topology::Calculator->new("$path/topology.csv");

$topology_calculator->calculate( $fw );

my $direction_checker = Farly::Rule::Direction->new( $topology_calculator->topology() );

$direction_checker->check( $outside_rules, 'fw1' );

my $count;

foreach my $obj ( $outside_rules->iter() ) {
      if ( $obj->has_defined('REMOVE') ) {
          $count++;
      }
}

ok( $count == 5, 'found errors' );
