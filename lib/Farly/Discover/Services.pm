package Farly::Discover::Services;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Net::Managed;

our $VERSION = '0.26';

sub new {
    my ( $class, $file_name ) = @_;

    confess "managed network file list not specified"
      unless ( defined $file_name );

    confess "managed networks file $file_name not found"
      unless ( -f $file_name );

    my $self = {
        MANAGED => Farly::Net::Managed->new($file_name),  # list of managed networks
        RESULT => {},
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

    if ( !defined $self->{'RESULT'}->{$address} ) {
        $self->{'RESULT'}->{$address} = Farly::Object::Set->new();
    }

    if ( !$self->{'RESULT'}->{$address}->includes($object) ) {
        $self->{'RESULT'}->{$address}->add($object);
    }
}

sub _has_service {
    my ( $self, $rule ) = @_;

    my $TCP = Farly::Transport::Protocol->new('6');
    my $UDP = Farly::Transport::Protocol->new('17');

    if (   $rule->has_defined('DST_IP')
        && $rule->has_defined('DST_PORT')
        && $rule->has_defined('PROTOCOL') )
    {
        if (   $rule->get('DST_IP')->isa('Farly::IPv4::Address')
            && $rule->get('DST_PORT')->isa('Farly::Transport::Port')
            && ( $rule->get('PROTOCOL')->equals($TCP) || $rule->get('PROTOCOL')->equals($UDP) ) )
        {
            return 1;
        }
    }

    return undef;
}

# if the rule references a service in a managed network 
# store that service in the host's set of services 
sub check {
    my ( $self, $list ) = @_;

    foreach my $rule ( $list->iter() ) {

        if ( $self->_has_service($rule) ) {

            #found a service, is it a network we manage?
            if ( $self->_is_managed( $rule->get('DST_IP') ) ) {

                #its one we want to check, create a new service object
                my $object = Farly::Object->new();
                $object->set( 'PROTOCOL', $rule->get('PROTOCOL') );
                $object->set( 'DST_IP',   $rule->get('DST_IP') );
                $object->set( 'DST_PORT', $rule->get('DST_PORT') );
                $object->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );

                $self->_store( $object->get('DST_IP')->address(), $object );
            }
        }
    }
}

1;
__END__

=head1 NAME

Farly::Discover::Services - Discover managed services referenced in the firewall rule set.

=head1 DESCRIPTION

Farly::Net::Discover finds all managed services referenced in the firewall rule sets.

=head1 METHODS

=head2 new( $file_name )

The constructor. A configuration file with the list of managed networks
must be passed to the constructor.

  $discover = Farly::Net::Discover->new( $file_name );

=head2 result()

Returns a hash map of Farly::Object::Set network objects.

  \%hash = $discover->result();

$hash->{'32 bit int IP'} = $set<Farly::Object::Set>;

=head2 check()

Check if the given rule has a service in a managed network.

  $discover->check( $rule_object );

=head1 COPYRIGHT AND LICENCE

Farly::Net::Discover
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
