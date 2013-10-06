use strict;
use warnings;
use Test::Simple tests => 4;
use File::Spec; 
use Farly;
use Farly::Data;
use Farly::Template::Cisco;

my $abs_path = File::Spec->rel2abs( __FILE__ );
our ($volume,$dir,$file) = File::Spec->splitpath( $abs_path );
my $path = $volume.$dir;

my $importer = Farly->new();

my $container = $importer->process( "ASA", "$path/test.cfg" );

ok( $container->size() == 65, "import");

my $data = Farly::Data->new($container);

ok( $data->isa('Farly::Data'), "new Farly::Data" );

ok ( $data->config()->size() == 65, 'config' );

ok ( $data->expanded_rules()->size() == 21, 'expanded rules' );

=b
my $template = Farly::Template::Cisco->new('ASA');

foreach my $obj ( $data->config()->iter() ) {
	$template->as_string($obj);
	print "\n";
}

print "\n";

foreach my $obj ( $data->expanded_rules->iter() ) {
    $template->as_string($obj);
    print "\n";
}
