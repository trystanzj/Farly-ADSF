package Farly::Topology::Routes;

use 5.008008;
use strict;
use warnings;
use Carp;
use IO::File;
use Log::Any qw($log);

our $VERSION = '0.26';

sub new {
    my ( $class, $file_name ) = @_;

    confess "network topology configuration file not specified\n"
      unless ( defined $file_name );

    my $self = { LIST => Farly::Object::List->new(), };
    bless $self, $class;

    #the config file associates a network with a firewall interface
    $self->_process_routes($file_name);

    return $self;
}

sub list { return $_[0]->{'LIST'} }

# convert CSV file format to $route<Farly::Object>
#   ENTRY     'ROUTE'
#   HOSTNAME  'hostname'
#   NETWORK   'Farly::IPv4::Network'
#   INTERFACE 'name'

sub _process_routes {
    my ( $self, $file_name ) = @_;

    my $file = IO::File->new($file_name)
      or die "invalid file $file_name";

    while ( my $line = $file->getline() ) {

        #skip blank lines
        next if ( $line !~ /\S+/ );

        chomp($line);

        my ( $hostname, $subnet, $interface ) = split( ',', $line );

        eval {

            # but the next hop isn't actually needed
            my $route = Farly::Object->new();
            $route->set( 'ENTRY', Farly::Value::String->new('ROUTE') );
            $route->set( 'HOSTNAME', Farly::Value::String->new( lc($hostname) ) );
            $route->set( 'INTERFACE', Farly::Value::String->new($interface) );
            $route->set( 'NETWORK',   Farly::IPv4::Network->new($subnet) );

            $self->list->add($route);
        };
        if ($@) {
            confess "problem with config file - line : $line : $@";
        }
    }
}

1;
__END__

=head1 NAME

Farly::Topology::Routes - Import the network route configuration file

=head1 DESCRIPTION

Farly::Topology::Routes maps network routes to firewall rule
sources or destinations. It calculates which firewall rule sets
apply to a given source or destination.

=head1 METHODS

=head2 new( $topology_file )

The constructor. The network topology file must be passed to the constructor.

  $route_importer = Farly::Topology::Routes->new( $route_csv_file );

The network topology file is a modified network route table.

=head2 route_list()

Return the container of route objects.

  $route_list = $route_importer->route_list()

=head1 COPYRIGHT AND LICENCE

Farly::Topology::Routes
Copyright (C) 2013  Trystan Johnson

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
