package Farly::Topology::Calculator;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Object::Aggregate qw(NEXTVAL);
use Farly::Topology::Routes;

our $VERSION = '0.26';

sub new {
    my ( $class, $file_name ) = @_;

    confess "route topology file not specified"
      unless ( defined $file_name );

    confess "invalid route topology file"
      unless ( -f $file_name );

    my $self = {
        ROUTES   => Farly::Topology::Routes->new($file_name),
        TOPOLOGY => Farly::Object::List->new(),
    };

    bless $self, $class;

    return $self;
}

sub routes   { return $_[0]->{'ROUTES'}->list() }
sub topology { return $_[0]->{'TOPOLOGY'} }

sub _hostname {
    my ( $self, $fw ) = @_;

    my $HOSTNAME = Farly::Object->new();
    $HOSTNAME->set( 'ENTRY', Farly::Value::String->new('HOSTNAME') );

    foreach my $object ( $fw->iter() ) {
        if ( $object->matches($HOSTNAME) ) {
            return lc( $object->get('ID')->as_string() );
        }
    }

    confess "hostname not found\n";
}

# create an interface reference object

sub _if_ref {
    my ( $self, $interface ) = @_;

    # $interface isa Farly::Value::String

    my $interface_ref = Farly::Object::Ref->new();
    $interface_ref->set( 'ENTRY', Farly::Value::String->new('INTERFACE') );
    $interface_ref->set( 'ID',    $interface );

    return $interface_ref;
}

# verify that the interface specified in the topology
# configuration is actually present in the firewall

sub _verify_interface {
    my ( $self, $hostname, $fw, $if_ref ) = @_;

    foreach my $object ( $fw->iter() ) {
        if ( $object->matches($if_ref) ) {
            return 1;
        }
    }

    confess "$hostname interface ", $if_ref->get('ID')->as_string(), " not found\n";
}

# "route object"
#   ENTRY     'ROUTE'
#   HOSTNAME  'hostname'
#   NETWORK   'Farly::IPv4::Network'
#   INTERFACE 'name'

# A "topology object" maps flows through the firewall
# "topology object" after processing configuration:
#	ENTRY         'TOPOLOGY'
#	HOSTNAME      'hostname'   of firewall confirmed to be in datastore
#	INTERFACE     <Farly::Object::Ref> to interface confirmed to be on the firewall
#	SRC_IP|DST_IP 'Farly::IPv4::Network'
#	RULE          <Farly::Object::Ref> from

sub calculate {
    my ( $self, $fw ) = @_;

    # get the firewall hostname string
    my $hostname = $self->_hostname($fw);
    $log->info("found hostname = $hostname");

    # get the route list for this firewall
    my $search = Farly::Object->new();
    $search->set( 'HOSTNAME', Farly::Value::String->new( lc($hostname) ) );

    my $routes = Farly::Object::List->new();
    $self->routes->matches( $search, $routes );

    $log->info( "found ". $routes->size() . " routes" );

    # aggregate the route objects for each interface into a ::Set
    my $agg = Farly::Object::Aggregate->new($routes);
    $agg->groupby('INTERFACE');

    $log->info("new aggregate is $agg");

    foreach my $agg_object ( $agg->iter() ) {

        # $agg_object isa Farly::Object
        #   INTERFACE => ::String('nameif')
        #   __AGG__   => ::List[ route objects ]

        # create an interface reference object from the aggregate object
        # the aggregate's identity is the "INTERFACE" property
        my $interface_ref = $self->_if_ref( $agg_object->get('INTERFACE') );

        $log->info( "if_ref = " . $agg_object->get('INTERFACE')->as_string() );

        # confirm that this interface exists on the firewall
        $self->_verify_interface( $hostname, $fw, $interface_ref );

        # $route_set is the ::Set of all network route objects
        # behind this interface
        my $route_list = $agg_object->get('__AGG__');

        foreach my $route_object ( $route_list->iter ) {

            # the template for the topology objects associated with this route
            my $topology_object = Farly::Object->new();
            $topology_object->set( 'ENTRY', Farly::Value::String->new('TOPOLOGY') );
            $topology_object->set( 'HOSTNAME', Farly::Value::String->new( lc($hostname) ) );
            $topology_object->set( 'INTERFACE', $interface_ref );
            $topology_object->set( 'NETWORK',   $route_object->get('NETWORK') );

# foreach interface access-group, determine if 'NETWORK' is a src or dst
# i.e. _direction converts 'NETWORK' to 'SRC_IP' or 'DST_IP' and notes the RULE ID
            $self->_direction( $fw, $topology_object );
        }
    }
}

# is_interface  direction   direction property
#    yes           in            SRC_IP
#    yes           out           DST_IP
#    no            in            DST_IP
#    no            out           SRC_IP

sub _direction {
    my ( $self, $fw, $topology_object ) = @_;

    # create a search object to match any access-group
    my $ACCESS_GROUP_ENTRY = Farly::Object->new();
    $ACCESS_GROUP_ENTRY->set( 'ENTRY', Farly::Value::String->new('ACCESS_GROUP') );

    # create a search object to match the access-group specific to the interface
    my $ACCESS_GROUP = Farly::Object->new();
    $ACCESS_GROUP->set( 'ENTRY', Farly::Value::String->new('ACCESS_GROUP') );
    $ACCESS_GROUP->set( 'INTERFACE', $topology_object->get('INTERFACE') );

    # create a search object to match the access-group direction
    my $IN  = Farly::Value::String->new('in');
    my $OUT = Farly::Value::String->new('out');

    # the direction for the given interface_ref is calculated
    # relative to every access-group in the firewall
    foreach my $object ( $fw->iter() ) {

        #the object is an access-group
        if ( $object->matches($ACCESS_GROUP_ENTRY) ) {

            my $direction_property;

            # the access-group is for the specified interface
            if ( $object->matches($ACCESS_GROUP) ) {
                if ( $object->get('DIRECTION')->equals($IN) ) {
                    $direction_property = 'SRC_IP';
                }
                elsif ( $object->get('DIRECTION')->equals($OUT) ) {
                    $direction_property = 'DST_IP';
                }
                else {
                    confess "unknown DIRECTION";
                }
            }
            else {

                # the access-group is not for this interface
                if ( $object->get('DIRECTION')->equals($IN) ) {
                    $direction_property = 'DST_IP';
                }
                elsif ( $object->get('DIRECTION')->equals($OUT) ) {
                    $direction_property = 'SRC_IP';
                }
                else {
                    confess "unknown DIRECTION";
                }
            }

            my $clone = $topology_object->clone();

            $clone->set( $direction_property, $topology_object->get('NETWORK') );
            $clone->delete_key('NETWORK');

            $clone->set( 'RULE', $object->get('ID') );

            $self->topology->add($clone);
        }
    }
}

1;
__END__

=head1 NAME

Farly::Topology::Calculation - Map network routes to firewall rule
                               sources or destinations

=head1 DESCRIPTION

Farly::Topology::Calculation maps network routes to firewall rule
sources or destinations. It calculates which firewall rule sets
apply to a given source or destination.

=head1 METHODS

=head2 new()

The constructor.

  $topology_calculator = Farly::Topology::Calculation->new();

=head2 topology()

Return the container of topology objects.

  $topology_container = $topology_calculator->topology()

=head2 calculate( $firewall, $route_list )

Runs the topology calculation for the $firewall and network $route_list.
  
  $topology_calculator->calculate( $firewall, $route_list );

=head1 COPYRIGHT AND LICENCE

Farly::Topology::Calculation
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
