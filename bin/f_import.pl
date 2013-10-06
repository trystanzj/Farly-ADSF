#!/usr/bin/perl -w

# f_import.pl - Farly ADSF - File system based firewall configuration importer
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
use IO::Dir;
use IO::File;
use Farly;
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

GetOptions( \%opts, 'verbose', 'help', 'man' ) or pod2usage(2);

pod2usage(1) if ( defined $opts{'help'} );

pod2usage( -verbose => 2 ) if ( defined $opts{'man'} );

our $cfg = Farly::Config::Reader->new('/etc/farly/farly.conf')->config()
  or die "failed to read /etc/farly/farly.conf\n";

my $firewall_list = IO::File->new( $cfg->{firewall_list}->{file} )
  or die "failed to load firewall list\n";

our $ds = Farly::TDS::Manager->new( %{ $cfg->{object_storage} } );

$SIG{INT} = sub { $ds->close(); exit; };

my $repo = Farly::Object::Repository->new();

$repo->connection( $ds->env, $ds->fw() );

my $importer = Farly->new();

while ( my $dir = $firewall_list->getline() ) {

    chomp($dir);

    my $file;

    if ( -f $dir ) {
        $file = $dir;
    }
    else {
        $file = most_recent_file($dir);
    }

    if ( !defined $file ) {
        warn "ERROR : Most recent file not found in $dir\n";
        next;
    }

    print "Importing $file... " if ( defined $opts{'verbose'} );

    my $container;
    my $hostname;
    my $data;    # config and expanded rules

    eval {
        $container  = $importer->process( 'ASA', $file );
        $hostname   = hostname($container);
        $data = Farly::Data->new($container);
    };
    if ($@) {
        print "ERROR - import of $file failed\n";
        print $@, "\n";
        next;
    }

    eval { $repo->put( $hostname, $data ); };
    if ($@) {
        print "ERROR - failed to store $hostname in the db\n";
        next;
    }

    print "OK - $hostname stored in db\n" if ( defined $opts{'verbose'} );

}

$ds->close();

exit;

sub hostname {
    my ($container) = @_;

    my $HOSTNAME = Farly::Object->new();
    $HOSTNAME->set( 'ENTRY', Farly::Value::String->new('HOSTNAME') );

    foreach my $ce ( $container->iter() ) {
        if ( $ce->matches($HOSTNAME) ) {
            return lc( $ce->get('ID')->as_string() );
        }
    }

    die "failed to find hostname\n";
}

sub most_recent_file {
    my ($dir) = @_;
    chomp $dir;

    my $temp = 0;
    my $new;

    my $d = IO::Dir->new($dir)
      or die "failed to read dir : $dir\n";

    if ( defined $d ) {

        while ( defined( $_ = $d->read ) ) {

            next if ( $_ =~ /^\./ );

            my $file = $dir . "/" . $_;

            my $mtime = ( stat($file) )[9];

            my $diff = time() - $mtime;

            if ( ( $_ ne "." ) && ( $_ ne ".." ) ) {

                if ( $temp == 0 ) {
                    $temp = $diff;
                    $new  = $file;
                }

                if ( $diff < $temp ) {
                    $temp = $diff;
                    $new  = $file;
                }
            }
        }
        undef $d;
    }

    if ( $temp == 0 ) {
        return undef;
    }

    return $new;
}

__END__
 
=head1 NAME

f_import.pl - Default file system based firewall configuration importer

=head1 SYNOPSIS

f_import.pl

=head1 DESCRIPTION

B<f_import.pl> will read the firewall configuration list file name from /etc/farly/farly.conf

If a specific file is given in the firewall list, f_import.pl will attempt to 
load that file. If a directory is given in the firewall list, f_import.pl will
attempt to load the most recent file in the directory.

Details of any failed imports will be written to /var/log/farly/Farly.log

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
