package Farly::Discover::Hosts;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Net::Managed;

our $VERSION = '0.26';

sub new {
    my ( $class, $file_name ) = @_;

    confess "managed networks file not specified"
      unless ( defined $file_name );

    confess "managed networks file $file_name not found"
      unless ( -f $file_name );

    my $self = {
        MANAGED => Farly::Net::Managed->new($file_name),  # list of managed networks
        RESULT  => {},
    };

    bless( $self, $class );

    $log->info("$self new");

    return $self;
}

sub result { return $_[0]->{'RESULT'} }

sub _is_managed {
    my ( $self, $ip ) = @_;
    return $self->{'MANAGED'}->is_managed($ip);
}

sub _store {
    my ( $self, $address, $object ) = @_;

    # mirrors object storage
    if ( !defined $self->{'RESULT'}->{$address} ) {
        $self->{'RESULT'}->{$address} = $object;
    }
}

# check rule entry list against managed networks 
# if the rule references a host in a managed network 
# put the result in $hosts
sub check {
    my ( $self, $list ) = @_;

    #specify the access-list properties to search
    my @addr_properties = ( 'SRC_IP', 'DST_IP' );

    foreach my $rule ( $list->iter() ) {

        foreach my $property (@addr_properties) {

            next if ( !$rule->has_defined($property) );

            next if ( !$rule->get($property)->isa('Farly::IPv4::Address') );

            if ( $self->_is_managed( $rule->get($property) ) ) {

                my $object = Farly::Object->new();

                # source or destination host object, can match to
                # rule object, less 'OBJECT_TYPE' property
                $object->set( 'OBJECT', $rule->get($property) );
                $object->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );

                $self->_store( $object->get('OBJECT')->address(), $object );
            }
        }
    }
}

1;
__END__

=head1 NAME

Farly::Discover::Hosts - Discover managed hosts referenced in the firewall rule sets.

=head1 DESCRIPTION

Farly::Discover::Hosts finds all managed hosts referenced in the firewall rule sets.

=head1 METHODS

=head2 new( $file_name )

The constructor. A configuration file with the list of managed networks
must be passed to the constructor.

  $discover = Farly::Net::Discover->new( $file_name );

=head2 result()

Returns a hash map of Farly::Object::Set network objects.

  \%hash = $discover->result();

$hash->{'32 bit int IP'} = $set<Farly::Object::Set>;

=head2 check( $list )

Check if the given rule set for references to hosts in a managed network.

  $discover->hosts( $list );

=head1 COPYRIGHT AND LICENCE

Farly::Discover::Hosts
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
