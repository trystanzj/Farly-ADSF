package Farly::Net::Managed;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use IO::File;

our $VERSION = '0.26';

sub new {
    my ( $class, $file_name ) = @_;

    my $self = bless( [], $class );

    $self->_load_managed($file_name);

    $log->info("finished loading managed networks file : $file_name");

    return $self;
}

sub managed {
    my ( $self ) = @_;
    return @$self;
}

#create the list of managed networks
sub _load_managed {
    my ( $self, $file_name ) = @_;

    my $file = IO::File->new($file_name)
      or die "open failed";

    my @managed_networks;

    while ( my $line = $file->getline() ) {
        next if ( $line !~ /\S+/ );
        push @$self, Farly::IPv4::Network->new($line);
    }

    if ( scalar( @$self ) == 0 ) {
        die "no managed networks defined\n";
    }
}

sub is_managed {
    my ( $self, $ip ) = @_;

    foreach my $net ( @$self ) {
        if ( $net->contains($ip) ) {
            return 1;
        }
    }

    return undef;
}

1;
__END__

=head1 NAME

Farly::Net::Managed - Container of managed IP network objects

=head1 DESCRIPTION

Farly::Net::Managed is a list of managed network objects. It contains the
list of networks which are reachable from the Farly server.

=head1 METHODS

=head2 new( $file_name )

The constructor. A configuration file with the list of managed networks
must be passed to the constructor

  $managed_networks = Farly::Net::Managed->new( $file_name );

=head2 is_managed( $ip_address )

Returns true if the IP address is in a managed network. Returns false if the
IP address is not in a managed network.

  $bool = $managed_networks->is_managed( $ip_address );


=head1 COPYRIGHT AND LICENCE

Farly::Net::Managed
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
