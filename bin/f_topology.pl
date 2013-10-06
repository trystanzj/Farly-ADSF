#!/usr/bin/perl -w

# f_topology.pl - Farly ADSF - Firewall Network Topology Calculations
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
use Farly::Data;
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Farly::Topology::Calculator;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'verbose', 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $topology_calc = Farly::Topology::Calculator->new( $cfg->{network_topology}->{file} );

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

my $it = $repo->iterator();

while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {
    $topology_calc->calculate( $firewall->config() );
}

$repo->put( '__TOPOLOGY__', $topology_calc->topology() );

print "Topology Import - OK\n" if ( defined $opts{'verbose'} );

$ds->close();

exit;

__END__
 
=head1 NAME

f_topology.pl - Determines which firewall rule sets filter traffic to or from a specific subnet.

=head1 SYNOPSIS

f_topology.pl

=head1 DESCRIPTION

B<f_topology.pl> makes the Farly ADSF network topology aware.

B<f_topology.pl> imports the network topology into the Farly database. The topology configuration CSV
file is specified in /etc/farly/farly.conf

The topology configuration is a CSV spreadsheet with three columns: hostname, network and interface.  This
information is obtained from network route tables. "hostname" must match the hostname of a firewall
in the Farly database. "interface" is an interface name which must exist on the specified firewall.
"network" is an IP network behind the specified firewall interface.

Using the topology configuration, all paths through the firewalls are calculated and stored in the Farly
database within a "topology container."

Given an IP address or network, the network topology is referenced and the firewall and 
rule sets to search are returned to the Farly application; or, the full network topology can be used
for the analysis being performed.

=head1 OPTIONS

=over 8

=item B<--verbose>

Prints success status messages.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=cut
