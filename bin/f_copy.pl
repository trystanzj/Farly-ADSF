#!/usr/bin/perl -w
#
# f_copy.pl - Farly ADSF - Copy Firewall Rules
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
use Farly::Template::Cisco;
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'old=s', 'new=s', 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

my $old;
my $new;

if ( defined $opts{'old'} ) {
    eval { $old = Farly::IPv4::Address->new( $opts{'old'} ); };
    if ($@) {
        pod2usage( "$0: Invalid IP address --old " . $opts{'old'} );
        exit;
    }
}
else {
    pod2usage("$0: --old <IP address> is required");
    exit;
}

if ( defined $opts{'new'} ) {
    eval { $new = Farly::IPv4::Address->new( $opts{'new'} ); };
    if ($@) {
        pod2usage( "$0: Invalid IP address --new " . $opts{'new'} );
        exit;
    }
}
else {
    pod2usage("$0: --new <IP address> is required");
    exit;
}

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

my $it = $repo->iterator();

while ( my ( $hostname, $firewall ) = NEXTREC($it) ) {

    my $new_rules = do_copy( $firewall->expanded_rules(), $old, $new );

    if ( $new_rules->size() > 0 ) {
        display( $hostname, $new_rules );
    }
}

$ds->close();

exit;

sub do_substitution {
    my ( $list, $key, $old, $new ) = @_;

    foreach my $object ( $list->iter() ) {
        if ( $object->get($key)->equals($old) ) {
            $object->set( $key, $new );
        }
    }
}

sub do_copy {
    my ( $expanded_rules, $old, $new ) = @_;

    # container for the search result
    my $search_result = Farly::Object::List->new();

    # the first search for matching SRC_IP addresses
    my $search = Farly::Object->new();

    $search->set( 'SRC_IP', $old );

    $expanded_rules->matches( $search, $search_result );

    do_substitution( $search_result, 'SRC_IP', $old, $new );

    # the second search for matching DST_IP addresses
    $search = Farly::Object->new();

    $search->set( 'DST_IP', $old );

    $expanded_rules->matches( $search, $search_result );

    do_substitution( $search_result, 'DST_IP', $old, $new );

    return $search_result;
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

f_copy.pl - Copy firewall rules

=head1 SYNOPSIS

f_copy.pl --old ADDRESS --new ADDRESS

=head1 DESCRIPTION

B<f_copy.pl> copies all firewall rules that exactly match the old IP address 
to new firewall rules using the new IP address. This script is a quick answer to the 
request "I need the rules for the new server to be the same as the old server."

=head1 OPTIONS

=over 8

=item B<--old ADDRESS>

The old IPv4 address, in dotted decimal format.

=item B<--new ADDRESS>

The new IPv4 address, in dotted decimal format.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Copy rules for existing server 192.168.2.1 to new server 192.168.2.8:

    f_copy.pl --old 192.168.2.1 --new 192.168.2.8


=cut
