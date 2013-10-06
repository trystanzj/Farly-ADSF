#!/usr/bin/perl -w
#
# f_direction.pl - Farly ADSF - Find Firewall Rule Source/Destination Errors
# Copyright (C) 2012 Trystan Johnson
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
use Farly::Rule::Direction;
use Farly::Remove::Rule;
use Farly::Template::Cisco;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'all', 'hostname=s', 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

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

my $topology = $repo->get('__TOPOLOGY__');

if ( !defined($topology) ) {

    print "The network topology was not found in the database.\n";
    print "Configure and run f_topology.pl\n\n";

    $ds->close();
    exit;
}

if ( defined $opts{'all'} ) {

    my $it = $repo->iterator();

    while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

        check_directions( $hostname, $firewall, $topology );
    }
}
elsif ( defined $opts{'hostname'} ) {

    my $hostname = lc( $opts{'hostname'} );

    my $firewall = $repo->get($hostname)
      or die "$hostname not found in database\n";

    check_directions( $hostname, $firewall, $topology );
}

$ds->close();

exit;

sub check_directions {
    my ( $hostname, $firewall, $topology ) = @_;

    # group the expanded rules
    my $agg = Farly::Object::Aggregate->new( $firewall->expanded_rules() );
    $agg->groupby( 'ENTRY', 'ID' );

    # create the direction checker object
    my $direction = Farly::Rule::Direction->new( $topology );

    # create the rule remover object for this firewall
    my $remover = Farly::Remove::Rule->new( $firewall->config() );

    my $it = $agg->list_iterator();

    while ( my $list = NEXTVAL($it) ) {

        # mark expanded entries with 'REMOVE' if they are incorrect
        $direction->check( $list, $hostname );

        my $error_list = errors($list);
        
        # are there any errors to cleanup?
        if ( $error_list->size() > 0 ) {

            # remove expanded entries from the firewall configuration as needed
            $remover->remove( $list );

            display( "$hostname - direction errors :", $error_list );
        }
    }
    
    # does the configuration need to be modified?
    if ( $remover->result()->size() > 0 ) {

        display( "$hostname - cleanup :", $remover->result() );
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
    my ( $hostname, $result ) = @_;

    my $template = Farly::Template::Cisco->new('ASA');

    print "! $hostname\n\n";

    foreach my $object ( $result->iter() ) {
        $template->as_string($object);
        print "\n";
    }

    print "\n";
}

__END__

=head1 NAME

f_direction.pl - Find Firewall Rule Source/Destination Errors

=head1 SYNOPSIS

f_direction.pl --all | --hostname HOSTNAME

=head1 DESCRIPTION

B<f_direction.pl> generates configurations to remove firewall rule source destination reversal
errors. These errors may be caused by rules being configured backwards, in the wrong rule set,
or as the result of a firewall rule set split or merge.

B<Important: f_direction.pl requires a default route for each firewall in the network topology
configuration in order to work properly.>

=head1 OPTIONS

=over 8

=item B<--all>

Run for all firewalls in the database.

=item B<--hostname HOSTNAME>

Run for specified firewall.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Validate the direction of all firewall rules in the firewall database:

    f_direction.pl --all

Validate the direction of all "test_firewall_1" rules:

    f_direction.pl --hostname test_firewall_1

=cut
