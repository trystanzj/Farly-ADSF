#!/usr/bin/perl -w
#
# f_create_topology.pl - Farly ADSF - Create the Topology Configuration File
# Copyright (C) 2012 Trystan Johnson
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Farly::Data;
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

my $it = $repo->iterator();

while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

    topology( $hostname, $firewall->config() );
}

$ds->close();

exit;

sub topology {
    my ( $hostname, $fw_config ) = @_;

    my $interface = Farly::Object->new();
    $interface->set( 'ENTRY', Farly::Value::String->new('INTERFACE') );

    my $route = Farly::Object->new();
    $route->set( 'ENTRY', Farly::Value::String->new('ROUTE') );

    my $search_result = Farly::Object::List->new();

    $fw_config->search( $interface, $search_result );
    $fw_config->search( $route,     $search_result );

    foreach my $object ( $search_result->iter() ) {

        if ( $object->matches($interface) ) {

            if (   $object->has_defined('OBJECT')
                && $object->has_defined('MASK') )
            {

                my $ip      = $object->get('OBJECT')->as_string();
                my $mask    = $object->get('MASK')->as_string();
                my $if_name = $object->get('ID')->as_string();

                print "$hostname,$ip $mask,$if_name\n";
            }
        }

        if ( $object->matches($route) ) {

            my $dst     = $object->get('DST_IP')->as_string();
            my $if_name = $object->get('INTERFACE')->get('ID')->as_string();

            print "$hostname,$dst,$if_name\n";
        }
    }
}

__END__
 
=head1 NAME

f_create_topology.pl - Create the Farly ADSF network topology configuration using
                       static route tables and interface configurations.

=head1 SYNOPSIS

f_create_topology.pl

=head1 DESCRIPTION

B<f_create_topology.pl> is a helper application which creates the Farly ADSF 'topology.csv' 
configuration file.

B<Important: This application only works for firewalls with static route tables.>

This application will not work for firewalls that use dynamic routing or operate in 
layer two transparent mode. Topology information for non-statically
routed firewalls will have to be added to the topology configuration
manually.

Put the full path to the topology.csv file in /etc/farly/farly.conf.

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Create the "topology.csv" file:

    f_create_topology.pl >topology.csv

=cut
