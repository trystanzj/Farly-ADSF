package Farly::Net::Ping;

use 5.008008;
use strict;
use warnings;
use Carp;
use Net::Ping;
use IO::Select;
use IO::Socket::INET;
use NetPacket::IP;
use Log::Any qw($log);

our $VERSION = '0.26';

sub new {
    my ( $class, %args ) = @_;

    my $self = { %args, };

    bless( $self, $class );
    
    $log->info("$self NEW ");

    # validate the configuration in %args
    $self->_check_cfg();

    return $self;
}

sub timeout     { return $_[0]->{timeout} }
sub max_retries { return $_[0]->{max_retries} }

sub _check_cfg {
    my ($self) = @_;

    confess "config error : time out not specified"
      unless ( defined( $self->timeout ) );

    confess "config error : time out not a number ", $self->timeout
      unless ( $self->timeout =~ /^\d+$/ );

    confess "config error : max_retries not specified"
      unless ( defined( $self->max_retries ) );

    confess "config error : max_retries not a number ", $self->max_retries
      unless ( $self->max_retries =~ /^\d+$/ );
}

sub icmp_ping {
    my ( $self, $host ) = @_;

    my $p = Net::Ping->new( "icmp", $self->timeout );

    my $try = 0;
    my $status;

    while ( $try != $self->max_retries ) {
        if ( $p->ping($host) ) {
            $status = 1;
            last;
        }
        $try++;
    }

    $p->close();

    return $status;
}

sub tcp_ping {
    my ( $self, $host, $port ) = @_;

    my $try = 0;
    my $status;

    my $p = Net::Ping->new( "tcp", $self->timeout );
    $p->port_number($port);
    $p->service_check(1);

    while ( $try != $self->max_retries ) {
        if ( $p->ping($host) ) {
            $status = 1;
            last;
        }
        $try++;
    }

    $p->close();

    return $status;
}

sub udp_ping {
    my ( $self, $host, $port ) = @_;

    $log->debug("polling : host = $host - port = $port");

    # Time to wait for the "destination unreachable" packet.
    my $icmp_timeout = $self->timeout;

    # Create the icmp socket for the "destination unreachable" packets
    my $icmp_sock = IO::Socket::INET->new( Proto => 'icmp' );
    my $read_set = IO::Select->new();
    $read_set->add($icmp_sock);

    # Create UDP socket to the remote host and port
    my $sock = IO::Socket::INET->new(
        PeerAddr => $host,
        PeerPort => $port,
        Proto    => 'udp'
    );

    # Send the buffer and close the UDP socket.
    $sock->send('ThisIsFarly');
    close($sock);

    $log->debug("read_set: $read_set");

    # Wait for incoming packets. (doesn't work on Windows)
    my ($new_readable) = IO::Select->select( $read_set, undef, undef, $icmp_timeout );

    # Set the arrival flag.
    my $icmp_arrived;
    my $type = 255;    #initialize ICMP type
    my $code = 0;
    my $buffer;

    # only one socket - $icmp_socket
    foreach my $socket (@$new_readable) {

        $log->debug("socket = $socket : icmp_socket = $icmp_sock");

        # we have captured an icmp packet, check the ICMP type and code
        if ( $socket == $icmp_sock ) {

            # Set the flag and clean the socket buffers
            $icmp_arrived = 1;
            $icmp_sock->recv( $buffer, 50, 0 );

            my $icmp_data = NetPacket::IP::strip($buffer);
            ( $type, $code ) = unpack( "C2", substr( $icmp_data, 0, 2 ) );

            $log->debug("type = $type : code = $code");
        }
    }

    close($icmp_sock);

    if ( defined($icmp_arrived) && $type == 3 ) {
        $log->debug("UDP $port is closed");
        return undef;
    }
    else {
        $log->debug("UDP $port is open");
        return 1;
    }
}

1;
__END__

=head1 NAME

Farly::Net::Ping - ICMP, TCP and UDP pings

=head1 DESCRIPTION

Farly::Net::Ping implements ICMP, TCP and UDP pings 

=head1 METHODS

=head2 new()

The constructor. Ping timeouts and retries are configurable.

  $pinger = Farly::Net::Ping->new( timeout     => $seconds,
							       max_retries => $number );
								
=head2 icmp_ping( $ip<string>, $port<int> )

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

Farly::Net::Ping
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
