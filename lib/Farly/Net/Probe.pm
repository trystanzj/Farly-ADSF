package Farly::Net::Probe;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Net::Ping;

our $VERSION = '0.26';

sub new {
    my ( $class, %args ) = @_;

    my $self = { %args };

    bless( $self, $class );

    $self->_check_cfg();
   
    $log->info("$self new");

    return $self;
}

sub _check_cfg {
    my ($self) = @_;

    confess "config error : time out not specified"
      unless ( defined( $self->_timeout ) );

    confess "config error : time out not a number ", $self->timeout
      unless ( $self->_timeout =~ /^\d+$/ );

    confess "config error : max_retries not specified"
      unless ( defined( $self->_max_retries ) );

    confess "config error : max_retries not a number ", $self->max_retries
      unless ( $self->_max_retries =~ /^\d+$/ );
}

sub _timeout     { return $_[0]->{timeout} }
sub _max_retries { return $_[0]->{max_retries} }

sub probe {
    my ( $self, $object ) = @_;

    my $p = Farly::Net::Ping->new(
        timeout     => $self->_timeout,
        max_retries => $self->_max_retries,
    );

    my $HOST = Farly::Object->new();
    $HOST->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );

    if ( $object->isa('Farly::Object::Set') ) {

        #only check services if the host is reachable via ICMP
        #if no ICMP response LAST_SEEN for the services won't be updated

        return if ( !$p->icmp_ping( $object->[0]->get('DST_IP')->as_string ) );

        foreach my $obj ( $object->iter ) {
            $self->_probe_service( $p, $obj );
        }

        return;
    }
    elsif ( $object->matches($HOST) ) {

        $self->_probe_host( $p, $object );
        return;
    }
    else {
        confess "wrong object";
    }               
}

sub _probe_host {
    my ( $self, $p, $object ) = @_;

    # the host must respond to ICMP or its considered down, 
    # i.e. don't update LAST_SEEN

    if ( $p->icmp_ping( $object->get('OBJECT')->as_string() ) ) {
        $object->set( 'LAST_SEEN', Farly::Value::Integer->new( time() ) );
    }

    $object->get('POLLED')->incr();
}

sub _probe_service {
    my ( $self, $p, $object ) = @_;

    my $TCP_SERVICE = Farly::Object->new();
    $TCP_SERVICE->set( 'PROTOCOL',    Farly::Transport::Protocol->new('6') );
    $TCP_SERVICE->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );

    my $UDP_SERVICE = Farly::Object->new();
    $UDP_SERVICE->set( 'PROTOCOL',    Farly::Transport::Protocol->new('17') );
    $UDP_SERVICE->set( 'OBJECT_TYPE', Farly::Value::String->new('SERVICE') );

    if ( $object->matches($TCP_SERVICE) ) {

        if ( $p->tcp_ping( $object->get('DST_IP')->as_string(),
                $object->get('DST_PORT')->as_string() ) )
        {
            $object->set( 'LAST_SEEN', Farly::Value::Integer->new( time() ) );
        }
    }
    elsif ( $object->matches($UDP_SERVICE) ) {

        if ( $p->udp_ping( $object->get('DST_IP')->as_string(),
                $object->get('DST_PORT')->as_string() ) )
        {
            $object->set( 'LAST_SEEN', Farly::Value::Integer->new( time() ) );
        }
    }
    else {
        die "unknown object\n", $object->dump(), "\n";
    }
    
    $object->get('POLLED')->incr();
}

1;
__END__

=head1 NAME

Farly::Net::Probe - Checks the status of network hosts and services

=head1 DESCRIPTION

Farly::Net::Probe Checks the status of network hosts and services 

=head1 METHODS

=head2 new()

The constructor. Ping timeouts and retries are configurable.

  $pinger = Farly::Net::Probe->new( timeout     => $seconds,
							        max_retries => $number );
								
=head2 host( $ip<string>, $port<int> )

Adjust the number of seconds before a host or service is declared down.

  $sync_object->set_timeout( $seconds );

=head2 tcp_ping( $ip<string>, $port<int> )

Send a TCP SYN to the given IP address and port

  $pinger->tcp_ping( $ip, $port );

A successful connection returns up, a timeout returns down.

=head2 udp_ping( $ip<string>, $port<int> )

Send a UDP packet to the given IP address and port

  $pinger->udp_ping( $ip, $port );

No response returns up, ICMP unreachable response returns down.

=head1 COPYRIGHT AND LICENCE

Farly::Net::Probe
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
