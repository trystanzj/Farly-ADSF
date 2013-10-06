#!/usr/bin/perl -w
#
# f_db_dump.pl - Farly ADSF - Display database contents
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
use Farly::Config::Reader;
use Farly::TDS::Manager;
use Farly::Object::Repository qw(NEXTREC);
use Log::Log4perl;
use Log::Any::Adapter;

my $umask = umask(0000)
  or die "error : failed to change umask\n";

Log::Log4perl::init('/etc/farly/logging.conf');
Log::Any::Adapter->set('Log4perl');

my %opts;

GetOptions( \%opts, 'all', 'key=s', 'db=s', 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

if ( defined $opts{'all'} && defined $opts{'key'} ) {
    pod2usage("$0: --all or --key are required, not both");
    exit;
}

if ( !( defined $opts{'all'} || defined $opts{'key'} ) ) {
    pod2usage("$0: --all or --key is required");
    exit;
}

if ( !defined $opts{'db'} ) {
    pod2usage("$0: --db required");
    exit;
}

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

my $db = $opts{'db'};

if ( $db !~ /fw|host|srv/ ) {
    pod2usage("$0: --db values must be 'fw' or 'host' or 'srv'\n");    
}

$repo->connection( $ds->env, $ds->$db );

if ( defined $opts{'all'} ) {

    my $it = $repo->iterator();

    while ( my ( $key, $val ) = NEXTREC($it) ) {
        display( $key, $val );
    }
}
elsif ( defined $opts{'key'} ) {

    my $key = get_key(%opts);

    my $val = $repo->get($key)
      or die $opts{'key'}, " not found in the ", $opts{'db'}, " db\n";

    display( $key, $val );
}

$ds->close();

exit;

sub get_key {
    my (%opts) = @_;

    if ( $opts{'db'} eq 'fw' ) {

        return lc( $opts{'key'} );
    }
    else {

        return Farly::IPv4::Address->new( $opts{'key'} )->address();
    }
}

sub display {
    my ( $key, $val ) = @_;

    if ( $val->isa('Farly::Data') ) {

        display_container( $key, $val->config() );
    }
    elsif ( $val->isa('Farly::Object::Set') ) {

        display_container( $key, $val );
    }
    elsif ( $val->isa('Farly::Object') ) {

        print "$key : \n", $val->dump(), "\n";
    }
    else {
        
        die "error : $key : unknown object $val\n";
    }
}

sub display_container {
    my ( $key, $container ) = @_;

    print "\n$key\n";

    foreach my $object ( $container->iter() ) {

        print $object->dump(), "\n";
    }
}

__END__
 
=head1 NAME

f_db_dump.pl - Display database contents

=head1 SYNOPSIS

f_db_dump.pl --db fw|host|srv --all | --key HOSTNAME|ADDRESS

=head1 DESCRIPTION

B<f_db_dump.pl> is for troubleshooting. It will display the contents of the 
firewalls, hosts or services databases.

=head1 OPTIONS

=over 8

=item B<--db 'fw|host|srv'>

'fw' for the firewall database
'host' for the host database
'srv' for the service database

=item B<--all>

Dump all objects in the specified database.

=item B<--key HOSTNAME|ADDRESS>
  
Dump an individual object in the specified database. HOSTNAME = the firewall hostname. 
ADDRESS = A host IP address in dotted decimal format.

=item B<--help>

Prints a brief help message and exits.

=item B<--man>

Prints the manual page and exits.

=back

=head1 EXAMPLES

Display all objects in the firewall database:

    f_db_dump.pl --db fw --all

Display all "test_fw_1" objects the firewall database:

    f_db_dump.pl --db fw --key test_fw_1

Display all host objects in the host database:

    f_db_dump.pl --db host --all

Display all service objects associated with 192.168.2.1:

    f_db_dump.pl --db srv --key 192.168.2.1

=cut
