package Farly::Rule::Direction;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);

our $VERSION = '0.26';

sub new {
    my ( $class, $list ) = @_;

    defined($list)
      or confess "topology container object required";

    confess "invalid object ", ref($list)
      unless ( $list->isa('Farly::Object::List') );

    my $self = { TOPOLOGY => $list, };

    bless( $self, $class );
    
    $log->info("$self NEW ");

    return $self;
}

# accessors
sub topology { return $_[0]->{'TOPOLOGY'}; }

# remove non layer 3 properties
sub _l3_only {
    my ( $self, $list ) = @_;

    my $result = Farly::Object::List->new();

    foreach my $object ( $list->iter ) {

        my $clone = $object->clone();

        foreach my $property ( $clone->get_keys() ) {
            if ( $property !~ /SRC_IP|DST_IP/ ) {
                $clone->delete_key($property);
            }
        }

        $result->add($clone);
    }

    return $result;
}

#Topology Object format :
# ENTRY         => Farly::Value::String 'TOPOLOGY'
# HOSTNAME      => Farly::Value::String 'hostname' of firewall confirmed to be in datastore
# INTERFACE     => Farly::Object::Ref to interface confirmed to be on the firewall
# RULE          => Farly::Object::Ref to the rules filtering the SRC_IP|DST_IP
# SRC_IP|DST_IP => Farly::IPv4::Network <$ip, $mask>

# find the topology objects for the given firewall and rule set
# return a list of SRC_IP|DST_IP objects
sub _network_list {
    my ( $self, $hostname, $rule_ref ) = @_;

    # firewall hostname datastore key always lowercase
    my $search = Farly::Object->new();
    $search->set( 'HOSTNAME', Farly::Value::String->new($hostname) );
    $search->set( 'RULE',     $rule_ref );

    my $result = Farly::Object::List->new();

    $self->topology->matches( $search, $result );

    return $self->_l3_only($result);
}

# use $network_list container to find the default route
# i.e. a default route is mandatory
sub _default_direction {
    my ( $self, $network_list ) = @_;

    my $ANY = Farly::IPv4::Network->new('0.0.0.0 0.0.0.0');

    foreach my $network_object ( $network_list->iter() ) {

        foreach my $property ( $network_object->get_keys ) {

            if ( $network_object->get($property)->equals($ANY) ) {
                return $property;
            }
        }
    }

    die "no default route found\n";
}

sub _is_unique {
    my ( $self, $list, $ref ) = @_;

    foreach my $object ( $list->iter() ) {
        if ( !$object->matches($ref) ) {
            confess "rule list not unique ", $object->get('ID')->as_string();
        }
    }
}

sub _rule_ref {
    my ( $self, $list ) = @_;

    my $rule_ref = Farly::Object::Ref->new();
    $rule_ref->set( 'ENTRY', $list->[0]->get('ENTRY') );
    $rule_ref->set( 'ID',    $list->[0]->get('ID') );

    $self->{'RULE_REF'} = $rule_ref;
}

# set the expanded ruleset to search
sub _validate {
    my ( $self, $list ) = @_;

    defined($list)
      or confess "rule list container object required";

    confess "invalid list type ", ref($list)
      unless ( $list->isa('Farly::Object::List') );

    confess "empty list not valid",
      unless ( $list->size() > 0 );
}

# All rules must pass the following error checks:
# intersects test:
#   - RULE DST_IP must 'intersect' NETWORK DST_IP
#   - RULE SRC_IP must 'intersect' a NETWORK SRC_IP
# not contained test:
#   - RULE SRC_IP must not be contained by NETWORK DST_IP
#   - RULE DST_IP must not be contained by NETWORK SRC_IP
sub check {
    my ( $self, $rule_list, $hostname ) = @_;

    # defined, isa ::List, not empty, also need to check is expanded
    $self->_validate($rule_list);

    # create a reference object to this $rule_list
    my $rule_ref = $self->_rule_ref($rule_list);

    # confirm that $rule_list is unique
    $self->_is_unique( $rule_list, $rule_ref );

    $log->info( "checking $hostname " . $rule_ref->get('ID')->as_string() );

    # $network_list isa Farly::Object::List< Farly::Object{ 'SRC_IP'|'DST_IP' => Farly::IPv4::Network } >
    # i.e. all properties which are not SRC_IP|DST_IP are removed

    my $network_list = $self->_network_list( $hostname, $rule_ref );    # set 'NETWORKS'

    # all direction checks are referenced to the direction which is
    # opposite of the default route

    my $default_direction = $self->_default_direction($network_list);

    $log->info("the default route is a $default_direction");

    my $l3_properties = {
        'DST_IP' => 'SRC_IP',
        'SRC_IP' => 'DST_IP'
    };

    my $l3_property = $l3_properties->{$default_direction}
      or die "invalid $default_direction";

    $log->info("direction tests refered to $l3_property");

    # iterate over the expanded rules
    foreach my $rule ( $rule_list->iter() ) {

        next if ( $rule->has_defined('COMMENT') );

        my $intersects;

        # run the intersects test
        # iterate over the list of networks associated with this rule list
        foreach my $network ( $network_list->iter ) {

            next if ( !$network->has_defined($l3_property) );

            $log->debug( "checking if rule $l3_property intersect " .
                $network->get($l3_property)->as_string() );

            # intersects test:
            # - the rule source must intersect a network source
            # - the rule destination must intersect a network dest
            if ( $rule->get($l3_property)->intersects( $network->get($l3_property) ) )
            {
                $log->debug("$l3_property - rule intersects - OK");

                # the rule passes this check
                $intersects = 1;
                last;
            }
        }

        if ( !$intersects ) {

            $rule->set( 'REMOVE', Farly::Value::String->new('RULE') );

            $log->debug("$l3_property FAIL rule intersects test");

            # check the next rule
            next;
        }

        # run the contained_by test
        # iterate over the list of networks associated with this rule list
        foreach my $network ( $network_list->iter ) {

            next if ( !$network->has_defined($l3_property) );

            $log->debug( "checking if rule $default_direction is contained by " .
                $network->get($l3_property)->as_string() );

            # contains test:
            # - the rule has a destination which is actually a source
            # - the rule has a source which is actually a destination
            if ( $network->get($l3_property)->contains( $rule->get($default_direction) ) )
            {
                $rule->set( 'REMOVE', Farly::Value::String->new('RULE') );

                $log->debug( "contained_by FAIL - network $default_direction - contained_by $l3_property" );

                # this rule is an error, no need to check any more networks
                last;
            }
        }
    }
}

1;
__END__

=head1 NAME

Farly::Rule::Direction - Uses the network topology to validate that the rules
                         are configured in the correct location.

=head1 DESCRIPTION

Farly::Rule::Direction uses the network topology to validate that the rules
are configured in the correct location.

Rules with source/destination errors or rules which are configured in the wrong
place are marked with the 'REMOVE' property.

=head1 METHODS

=head2 new( $topology )

The constructor. The network topology list must be passed to the constructor.

  $direction = Farly::Rule::Direction->new( $topology );

=head2 check( <Farly::Object::List>, <string>)

Validate the direction and location of each firewall rule in the given
expanded $rule_list container. 

  $direction->check( $rule_list, $hostname )

The $hostname string needs to be the same as the hostname in the topology.

Expanded rules in the wrong rule list are marked with the 'REMOVE' property.

=head1 COPYRIGHT AND LICENCE

Farly::Rule::Direction
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
