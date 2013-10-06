#!/usr/bin/perl -w
#
# f_remove - Farly ADSF - Retired hosts removal
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
use Farly::Remove::Address;
use Farly::Template::Cisco;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'address=s', 'all', 'hostname=s', 'help', 'man' )
  or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

my $ip;

if ( defined $opts{'address'} ) {

    my $address = $opts{'address'};

    eval {
        if ( $address =~ /((\d{1,3})((\.)(\d{1,3})){3})\s+((\d{1,3})((\.)(\d{1,3})){3})/ )
        {
            $ip = Farly::IPv4::Network->new($address);
        }
        elsif ( $address =~ /(\d{1,3}(\.\d{1,3}){3})(\/)(\d+)/ ) {
            $ip = Farly::IPv4::Network->new($address);
        }
        elsif ( $address =~ /((\d{1,3})((\.)(\d{1,3})){3})/ ) {
            $ip = Farly::IPv4::Address->new($address);
        }
    };
    if ($@) {
        pod2usage( "$0: invalid --address " . $opts{'address'} );
        exit;
    }

}
else {
    pod2usage("$0: --address IP or --address NETWORK is required");
    exit;
}

if ( defined $opts{'all'} && defined $opts{'hostname'} ) {
    pod2usage("$0: --all or --hostname are required, not both");
    exit;
}

if ( !( defined $opts{'all'} || defined $opts{'hostname'} ) ) {
    pod2usage("$0: option --all or --hostname is required");
    exit;
}

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

if ( defined $opts{'all'} ) {

    my $it = $repo->iterator();

    while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

        remove( $hostname, $firewall->config(), $ip );
    }
}
elsif ( defined $opts{'hostname'} ) {

    my $hostname = lc( $opts{'hostname'} );

    my $firewall = $repo->get($hostname)
      or die "$hostname not found in database\n";

    remove( $hostname, $firewall->config(), $ip );
}

$ds->close();

exit;

sub remove {
    my ( $hostname, $firewall, $ip ) = @_;

    my $remover = Farly::Remove::Address->new( $firewall );
    $remover->remove($ip);

    if ( $remover->result()->size() > 0 ) {
        display( $hostname, $remover->result() );
    }
}

sub display {
    my ( $hostname, $list ) = @_;

    print "! $hostname\n\n";

    my $template = Farly::Template::Cisco->new('ASA');

    foreach my $ce ( $list->iter() ) {
        $template->as_string($ce);
        print "\n";
    }

    print "\n";
}

__END__
 
=head1 NAME

f_remove.pl - Generates firewall configurations needed to remove all references to the specified host or subnet.

=head1 SYNOPSIS

f_remove.pl --all|--hostname HOSTNAME --address ADDRESS|NETWORK

=head1 DESCRIPTION

B<f_remove.pl> generates the commands needed to remove an IP address or 
subnet from a firewall configuration. All references to the specified host or 
subnet are removed, taking into account both rules and groups.

=head1 OPTIONS

=over 8

=item B<--all>

Run for all firewalls in the database.

=item B<--hostname HOSTNAME>

Run for the specified firewall.

=item B<--address ADDRESS|NETWORK>

Host IPv4 address, or Network in CIDR or Subnet Mask format

B<Important: Usage of subnet mask format requires quotes>, for example -d "192.168.1.0 255.255.255.0"

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Remove all rules with IP addresses in the 192.168.2.0/24 network:

    f_remove.pl --all --address 192.168.2.0/24

Remove all rules on "test_firewall_1" with IP addresses 192.168.2.2:

    f_remove.pl --hostname test_firewall_1 --address 192.168.2.2

=cut

