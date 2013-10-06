use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 3;
use BerkeleyDB;
use Storable qw(freeze thaw);
use Farly::Data;
use Farly::Topology::Calculator;
use Farly::Topology::Search;
use Farly::Topology::Routes;

my $abs_path = File::Spec->rel2abs(__FILE__);
our ( $volume, $dir, $file ) = File::Spec->splitpath($abs_path);
my $path = $volume . $dir;

my $routes;

eval { $routes = Farly::Topology::Routes->new(); };
ok ( $@ =~ /network topology configuration file not specified/, "no file");

eval { $routes = Farly::Topology::Routes->new('not.likely.a.file'); };
ok ( $@ =~ /invalid file/, "wrong file");

$routes = Farly::Topology::Routes->new("$path/topology.csv");

ok ( $routes->list->size() == 29, "_process_routes and route_list" );
