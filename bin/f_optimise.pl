#!/usr/bin/perl -w
#
# f_optimise.pl - Farly ADSF - Duplicate and Shadowed Firewall Rule Analysis
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
use Farly::Rule::Optimizer;
use Farly::Remove::Rule;
use Farly::Template::Cisco;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'all', 'hostname=s', 'verbose', 'help', 'man' )
  or pod2usage(2);

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

if ( defined $opts{'all'} && defined $opts{'verbose'} ) {
    pod2usage("$0: --verbose not supported with option --all");
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

        optimise( $hostname, $firewall, %opts );
    }
}
elsif ( defined $opts{'hostname'} ) {

    my $hostname = lc( $opts{'hostname'} );

    my $firewall = $repo->get($hostname)
      or die "$hostname not found in database\n";

    optimise( $hostname, $firewall, %opts );
}

$ds->close();

exit;

sub optimise {
    my ( $hostname, $firewall, %opts ) = @_;

    # $firewall isa Farly::Data

    if ( $opts{'verbose'} ) {
        print "! $hostname\n\n";
    }

    # group the expanded rules
    my $agg = Farly::Object::Aggregate->new( $firewall->expanded_rules() );
    $agg->groupby( 'ENTRY', 'ID' );

    # create the rule remover object for this firewall
    my $remover = Farly::Remove::Rule->new( $firewall->config() );

    my $it = $agg->list_iterator();

    while ( my $list = NEXTVAL($it) ) {

        # ::Optimizer marks rules in $list with 'REMOVE'
        # ::Optimizer does not create object copies

        my $l4_optimizer = Farly::Rule::Optimizer->new($list);
        $l4_optimizer->verbose( $opts{'verbose'} );
        $l4_optimizer->run();

        my $icmp_optimizer = Farly::Rule::Optimizer->new( $l4_optimizer->optimized() );
        $icmp_optimizer->verbose( $opts{'verbose'} );
        $icmp_optimizer->set_icmp();
        $icmp_optimizer->run();

        my $l3_optimizer = Farly::Rule::Optimizer->new( $icmp_optimizer->optimized() );
        $l3_optimizer->verbose( $opts{'verbose'} );
        $l3_optimizer->set_l3();
        $l3_optimizer->run();

        # expanded entries in $list which are marked with 'REMOVE' will be 
        # removed from the firewall configuration

        $remover->remove( $list ); 

        # does the configuration need to be modified?
        if ( $remover->result()->size() > 0 ) {

            display( "$hostname - optimise :", $remover->result() );
        }
    }
}

sub display {
    my ( $hostname, $list ) = @_;

    my $template = Farly::Template::Cisco->new('ASA');

    print "\n! $hostname\n\n";

    foreach my $object ( $list->iter() ) {
        $template->as_string($object);
        print "\n";
    }

    print "\n";
}

__END__
 
=head1 NAME

f_optimise.pl - Find duplicate and shadowed firewall rules

=head1 SYNOPSIS

f_optimise.pl --all | --hostname HOSTNAME [--verbose]

=head1 DESCRIPTION

B<f_optimise.pl> finds technical errors, including shadowed and duplicate rules, in the
firewall rules and automatically generates the configuration commands needed to remove
the unnecessary rules.

If the error is in a configuration firewall rule that uses a group, the configuration
rule will be replaced by the expanded optimised rules and then the configuration rule will
be removed.

=head1 OPTIONS

=over 8

=item B<--all>

Run optimisation for all firewalls in the database.

=item B<--hostname HOSTNAME>

Run optimisation for the specified firewall.

=item B<--verbose>

Prints a detailed duplicate and shadowed rule analysis. Works with --hostname option only.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Print a detailed analysis and optimisation for "test_firewall_1":

    f_optimise.pl --hostname test_firewall_1 --verbose

Optimize all firewall rules: 

    f_optimise.pl --all

=cut
