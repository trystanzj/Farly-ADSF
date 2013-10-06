package Farly::Sync::Services;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Net::Managed;

our $VERSION = '0.26';

sub new {
    my ( $class ) = @_;

    my $self = {
        MANAGED => undef,
        TIMEOUT => 172800,  # default = 2 days
        REPO    => undef,        
        CACHE   => {},
    };
    bless( $self, $class );
    
    $log->info("$self NEW");

    return $self;
}

# accessors
sub managed { return $_[0]->{'MANAGED'} }
sub timeout { return $_[0]->{'TIMEOUT'} }
sub repo    { return $_[0]->{'REPO'} }

sub set_managed {
    my ( $self, $file_name ) = @_;

    confess "file not specified"
      unless ( defined $file_name );

    confess "$file_name is not a file"
      unless ( -f $file_name );

    $self->{'MANAGED'} = Farly::Net::Managed->new($file_name);
}

sub set_timeout {
    my ( $self, $seconds ) = @_;

    confess "set_timeout seconds not defined"
      unless ( defined $seconds );

    confess "set_timeout seconds not a number"
      unless ( $seconds =~ /^\d+$/ );

    $self->{'TIMEOUT'} = $seconds;
}

sub set_repo {
    my ( $self, $repo ) = @_;

    confess "repository not defined"
      unless ( defined $repo );

    $self->{'REPO'} = $repo;
}

sub _is_managed {
    my ( $self, $ip ) = @_;
    return $self->managed->is_managed($ip);
}

# if object last seen > 2 days and it has been polled then
# host or service is down so remove rule
sub _is_down {
    my ( $self, $object ) = @_;

    if (   ( ( time() - $object->get('LAST_SEEN')->number ) > $self->timeout )
        && ( $object->get('POLLED')->number > 0 ) )
    {
        return 1;
    }
    else {
        return 0;
    }
}

sub _do_get {
    my ( $self, $address ) = @_;

    if ( defined $self->{'CACHE'}->{$address} ) {
        $log->debug("returning $address from cache");
        return $self->{'CACHE'}->{$address};
    }

    $log->debug("retrieving $address from repo");

    my $object = $self->repo->get($address);

    if ( !defined $object ) {
        $log->debug("$address not found");
        return;
    }

    $log->debug("found $object");

    $self->{'CACHE'}->{$address} = $object;

    return $object;
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
}

sub _network_object {
    my ( $self, $object ) = @_;

    my $service_properties = {
        'PROTOCOL' => 1,
        'DST_IP'   => 1,
        'DST_PORT' => 1,
    };

    # create a new object which will have network properties only
    my $clone = $object->clone();

    # check the topology object for one of the two network properties
    foreach my $property ( $clone->get_keys() ) {
        if ( !defined $service_properties->{$property} ) {
            $clone->delete_key($property);
        }
    }

    return $clone;
}

# list against repo
sub check {
    my ( $self, $list ) = @_;

    # unique and expanded list
    foreach my $object ( $list->iter ) {
        $self->_check_rule( $object );
    }
}

sub _check_rule {
    my ( $self, $rule ) = @_;

    # check the rules which reference services
    return if ( !$self->_has_service($rule) );

    # $address is the 32 bit int IP address
    my $address = $rule->get('DST_IP')->address();

    # only check this IP if it's managed
    return if ( !$self->_is_managed( $rule->get('DST_IP') ) );

    # the size of the services set may be > 1
    # every rule needs to be checked against all services
    # _do_get checks the CACHE first instead of going
    # straight to the datbase

    my $set = $self->_do_get($address);

    return if ( !defined $set );

    # add if host down, don't check services

    foreach my $object ( $set->iter ) {

        my $net_object = $self->_network_object($object);

        $log->debug( "net_object : \n" . $net_object->dump() . "\n" )
          if $log->is_debug();

        if ( $rule->matches($net_object) && $self->_is_down($object) ) {

            $log->warn( $object->get('DST_IP')->as_string() .
                ":" . $object->get('PROTOCOL')->as_string() .
                "/" . $object->get('DST_PORT')->as_string() .
                " was last seen at ", localtime( $object->get('LAST_SEEN')->number() )
            );
            
            $rule->set( 'REMOVE', Farly::Value::String->new('RULE') );
        }
    }
}

1;

__END__

=head1 NAME

Farly::Sync::Services - Service based rule to network synchronization

=head1 DESCRIPTION

Farly::Sync::Services finds inactive services referenced in the firewall rules.

Inherits from Farly::Sync.

Expanded rule entries from a single expanded rule set are checked against the
service repo.

=head1 METHODS

=head2 new( $file_name )

The constructor. A configuration file with the list of managed networks
must be passed to the constructor.

  $sync_services = Farly::Sync::Services->new( $file_name );

=head2 check( $list )

Check if the any rules in the list given reference an inactive service.

  $sync_services->check( $list );

Any rules referencing an inactive service are marked with 'REMOVE'.

If the rule does not reference a host which is in the net db then that
rule is skipped and left in the rules.

=head1 COPYRIGHT AND LICENCE

Farly::Sync::Services
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
Check if the given rule references a host which is inactive.


