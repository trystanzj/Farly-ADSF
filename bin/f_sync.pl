#!/usr/bin/perl -w
#
# f_sync.pl - Farly ADSF - Retired Host and Services removal
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
use Farly::Object::Aggregate qw(NEXTVAL);
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Farly::Template::Cisco;
use Farly::Sync::Hosts;
use Farly::Sync::Services;
use Farly::Remove::Address;
use Farly::Remove::Rule;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

# need sync option hosts or services
GetOptions( \%opts, 'all', 'hostname=s', 'hosts', 'services', 'help', 'man' )
  or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

if ( defined $opts{'all'} && defined $opts{'hostname'} ) {
    pod2usage("$0: either --all or --hostname is required, not both");
    exit;
}

if ( !( defined $opts{'all'} || defined $opts{'hostname'} ) ) {
    pod2usage("$0: either --all or --hostname is required");
    exit;
}

if ( defined $opts{'hosts'} && defined $opts{'services'} ) {
    pod2usage("$0: either --hosts or --services are required, not both");
    exit;
}

if ( !( defined $opts{'hosts'} || defined $opts{'services'} ) ) {
    pod2usage("$0: either --hosts or --services is required");
    exit;
}

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

my $managed_networks = $cfg->{internal_networks}->{file}
  or die "Please specify the managed networks file in /etc/farly/farly.conf\n";

my $timeout = $cfg->{timeout}->{seconds}
  or die "Please specify the host and service timeout in /etc/farly/farly.conf\n";

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

if ( defined $opts{'all'} ) {

    my $it = $fw_repo->iterator();

    # sync will be run once for each firewall
    while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

        if ( defined $opts{'hosts'} ) {
            sync_hosts( $hostname, $firewall, $host_repo, $managed_networks, $timeout );
        }

        if ( defined $opts{'services'} ) {
            sync_services( $hostname, $firewall, $srv_repo, $managed_networks, $timeout );
        }
    }
}
elsif ( defined $opts{'hostname'} ) {

    my $hostname = lc( $opts{'hostname'} );

    my $firewall = $fw_repo->get($hostname)
      or die "$hostname not found in database\n";

    if ( defined $opts{'hosts'} ) {
        sync_hosts( $hostname, $firewall, $host_repo, $managed_networks, $timeout );
    }

    if ( defined $opts{'services'} ) {
        sync_services( $hostname, $firewall, $srv_repo, $managed_networks, $timeout );
    }
}

$ds->close();

exit;

# remove inactive host ip addresses from the configuration
sub sync_hosts {
    my ( $hostname, $firewall, $repo, $managed_networks, $timeout ) = @_;

    my $host_sync = Farly::Sync::Hosts->new();

    $host_sync->set_managed($managed_networks);
    $host_sync->set_timeout($timeout);
    $host_sync->set_repo($repo);

    $host_sync->check( $firewall->expanded_rules() );

    if ( $host_sync->result()->size() > 0 ) {

        my $remover = Farly::Remove::Address->new( $firewall->config() );

        foreach my $host ( $host_sync->result->iter() ) {

            my $last_seen_time = localtime( $host->get('LAST_SEEN')->number() );

            print "! ", $host->get('OBJECT')->as_string(),
              " was last seen $last_seen_time\n";

            $remover->remove( $host->get('OBJECT') );
        }

        print "\n! $hostname - remove inactive host references:\n\n";
        display( $remover->result() );

        print "\n";
    }
}

# remove rules referencing inactive services from the configuration
sub sync_services {
    my ( $hostname, $firewall, $repo, $managed_networks, $timeout ) = @_;

    # group the expanded rules
    my $agg = Farly::Object::Aggregate->new( $firewall->expanded_rules() );
    $agg->groupby( 'ENTRY', 'ID' );

    my $it = $agg->list_iterator();

    while ( my $list = NEXTVAL($it) ) {

        my $service_sync = Farly::Sync::Services->new();

        $service_sync->set_managed($managed_networks);
        $service_sync->set_timeout($timeout);
        $service_sync->set_repo($repo);

        $service_sync->check($list);

        my $error_list = errors($list);

        if ( $error_list->size() > 0 ) {

            print "\n!  $hostname  - rules referencing inactive services:\n\n";
            display($error_list);

            my $remover = Farly::Remove::Rule->new( $firewall->config() );
            $remover->remove($list);

            print "\n! $hostname - remove rules with inactive service references:\n\n";
            display( $remover->result() );

            print "\n";
        }
    }
}

sub errors {
    my ( $list ) = @_;

    my $remove = Farly::Object::List->new();

    foreach my $rule ( $list->iter() ) {
        if ( $rule->has_defined('REMOVE') ) {
            $remove->add($rule);
        }
    }

    return $remove;
}

sub display {
    my ($result) = @_;

    my $template = Farly::Template::Cisco->new('ASA');

    foreach my $object ( $result->iter() ) {
        $template->as_string($object);
        print "\n";
    }
}

__END__
 
=head1 NAME

f_sync.pl - Inactive host and services removal

=head1 SYNOPSIS

f_sync.pl --all | --hostname HOSTNAME --hosts | --services

=head1 DESCRIPTION

B<f_sync.pl> generates the commands needed to remove all references to inactive internal hosts 
or services from the firewall configurations.

Internal hosts and services are considered inactive if they have not been seen for a while. The 
timeout is specified in /etc/farly/farly.conf.

If the host is inactive all references to that host will be removed from the firewall configurations.

If the service was shut down or moved, all firewall rule entries referencing that service will be
removed from the firewall configurations. Services will be matched against rules which have defined
a protocol, destination IP address and destination port number. Subnets and port ranges will not be
matched.

Inactive hosts should be removed before attempting to remove inactive services.

=head1 OPTIONS

=over 8

=item B<--all>

Run for all firewalls in the database.

=item B<--hostname HOSTNAME>

Run for specified firewall.

=item B<--hosts>

Remove inactive hosts from the firewall configurations.

=item B<--services>

Remove inactive services from the firewall configurations.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Remove all rules on all firewalls that reference inactive hosts:

    f_sync.pl --all --hosts

Remove all rules on all firewalls that reference inactive services:

    f_sync.pl --all --services

Remove all rules on "test_firewall_1" that reference inactive hosts:

    f_sync.pl --hostname test_firewall_1 --hosts

Remove all rules on "test_firewall_1" that reference inactive services:

    f_sync.pl --hostname test_firewall_1 --services

=cut
