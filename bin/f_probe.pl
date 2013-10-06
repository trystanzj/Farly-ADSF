#!/usr/bin/perl -w
#
# f_probe.pl - Farly ADSF - Host and Service Probing
# Copyright (C) 2012  Trystan Johnson
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use BerkeleyDB;
use Farly::Data;
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Farly::Net::Probe;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

our %opts;

GetOptions( \%opts, 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

my $p = Farly::Net::Probe->new(
    timeout     => 3,
    max_retries => 2,
);

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

# probe hosts with ICMP

my $host_repo = Farly::Object::Repository->new();
$host_repo->connection( $ds->env, $ds->host() );

my $host_it = $host_repo->iterator();

while ( my ( $address, $host ) = NEXTREC($host_it) ) {

    # probe will update 'LAST_SEEN' to the current time if the host is active
    $p->probe( $host );

    #update the record
    $host_repo->put( $address, $host );
}

# probe services with TCP SYN, or UDP "icmp unreachables"

my $srv_repo = Farly::Object::Repository->new();
$srv_repo->connection( $ds->env, $ds->srv() );

my $srv_it = $srv_repo->iterator();

while ( my ( $address, $srv ) = NEXTREC($srv_it) ) {

    # probe will update 'LAST_SEEN' to the current time for each
    # service object if the service is active

    $p->probe( $srv );

    #update the record
    $srv_repo->put( $address, $srv );
}

$ds->close();

exit;


__END__
 
=head1 NAME

f_probe.pl - Probe all hosts and services in the database

=head1 SYNOPSIS

f_probe.pl

B<This script must be run as 'root'>

=head1 DESCRIPTION

B<f_probe.pl> uses active probing to check the status of internal hosts and services. (i.e. if a host
or service is down, it can safely be removed from the firewall rules.)

B<f_probe.pl> iterates through the hosts and services database.

Every host is pinged via ICMP to see if it is up or down. The host is considered to be down if there is
no response to the ICMP echo.

Services referenced in the firewall rules are pinged via TCP or UDP pings to check if the service is up or
down. TCP pings are done with a TCP SYN and TCP services are considered down if there is no response to the
SYN packet. UDP pings are done with a custom UDP ping module. UDP services are only considered to be down 
if an ICMP unreachable packet is received from the host.

If the host or service is up then the last seen time is updated in the database.

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=cut
