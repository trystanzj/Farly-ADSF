package Farly::Topology::Search;

use 5.008008;
use strict;
use warnings;
use Carp;

our $VERSION = '0.26';

sub new {
    my ( $class, $topology ) = @_;

    confess "network topology configuration container object required"
      unless ( defined($topology) );

    confess "Farly::Object::List object required"
      unless ( $topology->isa('Farly::Object::List') );

    my $self = {
        TOPOLOGY    => $topology,
        INCLUDE_ANY => undef,
        ANY => Farly::IPv4::Network->new('0.0.0.0 0.0.0.0'),
    };
    bless $self, $class;

    return $self;
}

#accessors
sub topology    { return $_[0]->{'TOPOLOGY'} }
sub include_any { return $_[0]->{'INCLUDE_ANY'} }
sub any         { return $_[0]->{'ANY'} }

sub set_include_any {
    my ( $self, $include_any ) = @_;
    $self->{'INCLUDE_ANY'} = $include_any;
}

# return a new object with the IP address properties only
sub _network_object {
    my ( $self, $topology_object ) = @_;

    # the IP address properties in a 'RULE'
    my @network_properties = ( 'DST_IP', 'SRC_IP' );

    # create a new object which will have network properties only
    my $network_object = Farly::Object->new();

    # check the topology object for one of the two network properties
    foreach my $property (@network_properties) {

        if ( $topology_object->has_defined($property) ) {

            $network_object->set( $property, $topology_object->get($property) );

            # each topology object should have only one network property, so done
            return $network_object;
        }
    }

    die "topology object had no network properties";
}

# return a new object with the topology properties only
sub _topology_object {
    my ( $self, $topology_object ) = @_;

    # the IP address properties in a 'RULE'
    my @network_properties = ( 'DST_IP', 'SRC_IP' );

    # create a new object which will have device properties only
    my $clone = $topology_object->clone();

    # check the topology object for one of the two network properties
    foreach my $property (@network_properties) {
        if ( $clone->has_defined($property) ) {
            $clone->delete_key($property);
        }
    }

    return $clone;
}

# is the IP address property equal to '0.0.0.0 0.0.0.0'?
sub _network_is_any {
    my ( $self, $network_object ) = @_;

    my @network_properties = ( 'DST_IP', 'SRC_IP' );

    foreach my $property (@network_properties) {
        if ( $network_object->has_defined($property) ) {
            if ( $network_object->get($property)->equals( $self->any ) ) {
                return 1;
            }
        }
    }
}

# returns a set of the matching topology objects
# i.e. the firewall and rule sets to search
sub matches {
    my ( $self, $search ) = @_;

    my $result = Farly::Object::Set->new();

    #my $exclude = Farly::Object::Set->new();

    # has search defined network properties?
    if ( !( $search->has_defined('SRC_IP') || $search->has_defined('DST_IP') ) )
    {

        # if search has not defined network properties then
        # check to see if 'include_any' flag is set
        if ( $self->include_any ) {
            return $self->topology;
        }
        else {
            # return the empty set
            return Farly::Object::Set->new();
        }
    }

    foreach my $topology_object ( $self->topology->iter ) {

        # remove non-network properties
        my $network_object = $self->_network_object($topology_object);

        # not including 'ANY'?
        if ( !$self->include_any ) {

            # therefore skip this object if it is 'ANY'
            if ( $self->_network_is_any($network_object) ) {
                next;
            }
        }

        # remove the network property
        my $new_topology_object = $self->_topology_object($topology_object);

        # does this topology object reference a firewall and rule
        # that need to be searched?
        if ( $search->intersects($network_object) ) {
            if ( !$result->includes($new_topology_object) ) {
                $result->add($new_topology_object);
            }
        }
    }

    return $result;
}

1;
__END__

=head1 NAME

Farly::Topology::Search - Searches the network topology

=head1 DESCRIPTION

Given a Farly search object Farly::Topology::Search searches the
network topology and returns a list of matching topology objects which
refer to the relevant firewall and rule set.

=head1 METHODS

=head2 new( $topology )

The constructor. The network topology container must be passed to the constructor.

  $topology_search = Farly::Topology::Search->new( $topology );

=head2 include_any()

Include default routes in the search result.

  $topology_search->include_any(1);

By default Farly::Topology::Search skips default routes.

=head2 matches( $search<Farly::Object> )

Returns a container of topology objects matching the given search.

  $topology_object_list = $topology_search->matches( $search );

=head1 COPYRIGHT AND LICENCE

Farly::Topology::Search
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
