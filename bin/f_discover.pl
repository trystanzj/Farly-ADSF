#!/usr/bin/perl -w

# f_discover.pl - Farly ADSF - Host and Service Discovery
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

# iterate over all firewalls
# store DST_IP ::Address to hosts db
# store tcp/ip/port to service db - IP is key
# add discovery date, add last seen = discovery
# add 'polled' flag

use strict;
use warnings;
use Getopt::Long;
use Pod::Usage;
use Farly::Data;
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Farly::Discover::Hosts;
use Farly::Discover::Services;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

my $managed_networks = $cfg->{internal_networks}->{file}
  or die "Please specify the managed networks file in /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

# the firewalls repository
my $fw_repo = Farly::Object::Repository->new();
$fw_repo->connection( $ds->env, $ds->fw() );

# the hosts repository
my $host_repo = Farly::Object::Repository->new();
$host_repo->connection( $ds->env, $ds->host() );

# the services repository
my $srv_repo = Farly::Object::Repository->new();
$srv_repo->connection( $ds->env, $ds->srv() );

# create the Discover objects
my $hosts = Farly::Discover::Hosts->new( $managed_networks );
my $services = Farly::Discover::Services->new( $managed_networks );

my $it = $fw_repo->iterator();

while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

    $hosts->check( $firewall->expanded_rules() );
    store_hosts( $host_repo, $hosts->result() );

    $services->check( $firewall->expanded_rules() );
    store_services( $srv_repo, $services->result() );
}

$ds->close();

exit;

# set polled count to 0 (don't remove objects which haven't been polled)
sub update_new {
    my ($object) = @_;
    my $time = time();
    $object->set( 'DISCOVERED', Farly::Value::Integer->new($time) );
    $object->set( 'LAST_SEEN',  Farly::Value::Integer->new($time) );
    $object->set( 'POLLED',     Farly::Value::Integer->new(0) );
}

# only store new hosts
sub store_hosts {
    my ( $repo, $data ) = @_;

    # $data isa { $address => $host<Farly::Object> }

    foreach my $address ( keys %$data ) {

        my $host = $repo->get($address);

        if ( !defined($host) ) {

            # this address was not in the database
            $host = $data->{$address};

            # set polled count to 0 (don't remove objects which haven't been polled)
            update_new($host);

            $repo->put( $address, $host );
        }
        # else, the host is already in the ds, no action required
    }
}

# only store new services
sub store_services {
    my ( $repo, $data ) = @_;

    # $data isa { $address => $service_list<Farly::Object::List> }

    foreach my $address ( keys %$data ) {

        my $list = $repo->get($address);

        if ( !defined($list) ) {

            # this address was not in the database

            $list = $data->{$address};

            foreach my $object ( $list->iter() ) {

                update_new($object);
            }

            $repo->put( $address, $list );
        }
        else {

            # $new_list is a list of objects are not already in the data store $list
            my $new_list = difference( $data->{$address}, $list );

            # $new_list objects won't have time stamp properties - update time here
            foreach my $object ( $new_list->iter() ) {

                update_new($object);

                # add the new object to the existing list
                $list->add($object);
            }

            # put the existing set back in the database
            $repo->put( $address, $list );
        }
    }
}

sub difference {
    my ( $new_list, $existing_list ) = @_;

    my $diff = Farly::Object::Set->new();

    # $list->includes calls the matches method

    foreach my $object ( $new_list->iter() ) {
        if ( ! $existing_list->includes($object) ) {
            $diff->add($object);
        }
    }

    return $diff;
}

__END__
 
=head1 NAME

f_discover.pl - Host and Service Discovery

=head1 SYNOPSIS

f_discover.pl

=head1 DESCRIPTION

B<f_discover.pl> runs for all firewalls in the firewall database. Any hosts (IP address) or 
services (IP/protocol/port) within managed networks are saved to a database. Host and 
Service discovery time, last seen time, and polled count are noted. If the host or service
already exists in the database, no action will be taken.

B<f_discover.pl> will read the managed networks file name from /etc/farly/farly.conf. The
list of managed networks are networks that are reachable from the Farly server
with ICMP echo requests and on all TCP and UDP ports.

=head1 OPTIONS

=over 8

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=cut
