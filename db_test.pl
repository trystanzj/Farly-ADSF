#!/usr/bin/perl -w

use strict;
use Test::Simple tests => 9;
use Farly;
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

ok( defined $ds->fw(), 'firewall db opened');
ok( defined $ds->host(), 'hosts db opened');
ok( defined $ds->srv(), 'services db opened');

# the firewalls repository
my $fw_repo = Farly::Object::Repository->new();
$fw_repo->connection( $ds->env, $ds->fw() );

test("fw db ", $fw_repo, $ds->fw() );

# the hosts repository
my $host_repo = Farly::Object::Repository->new();
$host_repo->connection( $ds->env, $ds->host() );

test("host db ", $host_repo, $ds->host() );

# the services repository
my $srv_repo = Farly::Object::Repository->new();
$srv_repo->connection( $ds->env, $ds->srv() );

test("services db ", $srv_repo, $ds->srv() );

$ds->close();

sub test {
    my ( $info, $repo, $db ) = @_;

    my $obj1 = Farly::Value::String->new('1');
    my $obj2 = Farly::Value::String->new('1');
    
    $repo->put( '1', $obj1 );
    
    my $ret = $repo->get('1');
    
    ok( $ret->equals($obj2), "$info write, read" );
    
    my $iterator = $repo->iterator();
   
    my $count = 0;
     
    while ( my( $key, $val) = NEXTREC($iterator) ) {
         $count++;
    }
    
    ok( $count != 0 , "$info iterator" );    

    my $status = $db->db_del( '1' );
    if ($status) {
    	  die $BerkeleyDB::Error;
    }

}
