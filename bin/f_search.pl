#!/usr/bin/perl -w
#
# f_search.pl - Farly ADSF - Firewall Configuration Search
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
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Farly::Template::Cisco;
use Farly::ASA::PortFormatter;
use Farly::ASA::ProtocolFormatter;
use Farly::ASA::ICMPFormatter;
use Farly::Data;
use Farly::Topology::Search;
use Farly::Opts::Search;
use Farly::Remove::Rule;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;
my $search_parser;
my $search;
my $search_method = 'search';
my $include_any;

GetOptions(
    \%opts,          'action=s', 'p=s',     's=s',
    'sport=s',       'd=s',      'dport=s', 'all',
    'matches',       'contains', 'remove',  'exclude-src=s',
    'exclude-dst=s', 'help',     'man'
  )
  or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

if ( defined $opts{'all'} ) {
    $include_any = 1;
}

if ( defined $opts{'matches'} ) {
    $search_method = 'matches';
}

if ( defined $opts{'contains'} ) {
    $search_method = 'contains';
}

if ( defined $opts{'remove'} ) {
    $search_method = 'contained_by';
}

eval {
    $search_parser = Farly::Opts::Search->new( \%opts );
    $search        = $search_parser->search();
};
if ($@) {
    pod2usage("$0: $@");
    exit;
}

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

#retrieve the topology
my $topology = $repo->get('__TOPOLOGY__');

if ( !defined($topology) ) {

    print "The network topology was not found in the database.\n";
    print "Configure and run f_topology.pl\n\n";

    $ds->close();
    exit;
}

my $topology_search = Farly::Topology::Search->new($topology);

#search all firewalls? or not?
$topology_search->set_include_any($include_any);

# figure out which firewalls and rules to search
my $firewall_topology = $topology_search->matches($search);

my $device;

# $device->{'hostname'}->{'id'} = $rule_set_ref<Farly::Object::Ref>

# a search with both src and dst could result in more than one
# topology object being returned for the same firewall rule set
foreach my $topology_object ( $firewall_topology->iter() ) {

    my $hostname = $topology_object->get('HOSTNAME')->as_string();
    my $id       = $topology_object->get('RULE')->get('ID')->as_string();

    if ( !defined $device->{$hostname}->{$id} ) {
        $device->{$hostname}->{$id} = $topology_object->get('RULE');
    }

}

# do the search, only loading and expanding each firewall once
foreach my $hostname ( sort keys %$device ) {

    # load the firewall
    my $firewall = $repo->get($hostname);

    if ( !defined($firewall) ) {

        print "ERROR : $hostname is in the topology configuration but\n was not found in the database\n";

        $ds->close();
        exit;
    }

    # search each rule set in the firewall as required
    foreach my $id ( sort keys %{ $device->{$hostname} } ) {

        $search->set( 'ID', Farly::Value::String->new($id) );

        my $search_result = Farly::Object::List->new();

        $firewall->expanded_rules->$search_method( $search, $search_result );

        if ( $search_parser->filter->size > 0 ) {

            $search_result = filter( $search_result, $search_parser->filter() );

            display( $hostname, $search_result, \%opts );

            next;
        }

        if ( $search_result->size > 0 ) {

            if ( defined $opts{'remove'} ) {

                $search_result = remove( $firewall->config(), $search_result );
            }

            display( $hostname, $search_result, \%opts );
        }

        #else {
        #	print "\n! $hostname $id \n\n";
        #	print "no rules found\n";
        #}
    }
}

$ds->close();

exit;

# END MAIN

sub filter {
    my ( $search_result, $filter ) = @_;

    my $filtered_rule_set = Farly::Object::List->new();

    foreach my $rule_object ( $search_result->iter() ) {

        my $excluded;

        foreach my $exclude_object ( $filter->iter() ) {

            if ( $rule_object->contained_by($exclude_object) ) {

                $excluded = 1;
                last;
            }
        }

        if ( !$excluded ) {

            $filtered_rule_set->add($rule_object);
        }
    }

    return $filtered_rule_set;
}

sub remove {
    my ( $fw, $search_result ) = @_;

    foreach my $object ( $search_result->iter() ) {
        $object->set( 'REMOVE', Farly::Value::String->new('RULE') );
    }

    my $remover = Farly::Remove::Rule->new($fw);
    $remover->remove($search_result);

    return $remover->result();
}

sub display {
    my ( $hostname, $list, $opts ) = @_;

    my $template = Farly::Template::Cisco->new('ASA');

    print "! $hostname\n\n";

    foreach my $rule_object ( $list->iter() ) {

        if ( !defined $opts{'remove'} ) {

            my $f = {
                'port_formatter'     => Farly::ASA::PortFormatter->new(),
                'protocol_formatter' => Farly::ASA::ProtocolFormatter->new(),
                'icmp_formatter'     => Farly::ASA::ICMPFormatter->new(),
            };

            $template->use_text(1);
            $template->set_formatters($f);

            $rule_object->delete_key('LINE');
        }

        $template->as_string($rule_object);
        print "\n";
    }

    print "\n";
}

__END__

=head1 NAME

f_search.pl - Searches firewall configurations for all references to the specified host, subnet, ports or protocols.

=head1 SYNOPSIS

f_search.pl [--all] [--matches|contains] [--action|p|s|sport|d|dport VALUE] [--exclude-src|exclude-dst FILE] [--remove]

=head1 DESCRIPTION

B<f_search.pl> searches firewall configurations by source IP, source port, 
destination IP, destination port or any combination of the above. 

The configurable search options are "matches" and "contains." The default option 
is "search," which returns every rule that could possibly match the given Layer 3 or
Layer 4 options. This means a search range larger than ranges on the firewall will
still return results.

f_search.pl uses the network topology to determine which firewall to search based
on the source or destination IP addresses specified. The specific firewall configuration
does not need to be specified.  The --all option can be specified in order to force
a search of all firewall configurations in the database.

=head1 OPTIONS

=over 8

=item B<-p PROTOCOL> 

Search for rules using the specified protocol. Can be a text ID such as tcp or udp, or a protocol number.

=item B<-s ADDRESS>

Source IP Address, Network or FQDN

B<Important: Usage of subnet mask format requires quotes>, for example -s "192.168.1.0 255.255.255.0"

=item B<-d ADDRESS>

Destination IP Address, Network or FQDN

B<Important: Usage of subnet mask format requires quotes>, for example -d "192.168.1.0 255.255.255.0"

=item B<--sport PORT>

Source Port Name or Number

=item B<--dport PORT>

Destination Port Name or Number

=item B<--action permit|deny>

Specify the firewall rule action to match.

=item B<--all>

The default route is not used to search firewalls.  Use --all if no IP address is specified
in the search or if the IP address is not a managed IP address.
 
=item B<--matches>

Will match the given search options exactly.

=item B<--contains>

Will find rules the firewall would match.

=item B<--remove>

The remove option can be used to generate the commands needed to remove the search result from the firewalls.

=item B<--exclude-src FILE>

Specify a FILE with a list of source IPv4 networks to exclude from the search results.

=item B<--exclude-dst FILE>

Specify a FILE with a list of destination IPv4 networks to exclude from the search results.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Display all rules which permit connectivity to 192.168.2.1:

    f_search.pl -d 192.168.2.1

Display all rules which permit connectivity to 192.168.2.1 tcp/80:

    f_search.pl -d 192.168.2.1 --dport www

Display all permit rules, on any firewall, with a source IP address of "any":

    f_search.pl --all --matches --action permit -s "0.0.0.0 0.0.0.0"

Display all rules, on any firewall, permitting telnet:

    f_search.pl --all --matches --dport telnet

Report all connectivity to subnet 192.168.3.0/24, database port 1433 from external locations:

    f_search.pl -d 192.168.3.0/24 --dport 1433 --exclude-src internal_networks.txt

=cut
