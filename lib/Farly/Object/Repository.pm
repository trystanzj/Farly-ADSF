package Farly::Object::Repository;

use 5.008008;
use strict;
use warnings;
use Carp;
require Exporter;
use Scalar::Util qw(blessed);
use Log::Any qw($log);
use BerkeleyDB;
use Farly::Data;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(NEXTREC);

our $VERSION = '0.26';

sub new {
    my ($class) = @_;

    my $self = {
        ENV => undef,
        DB  => undef,
    };

    bless $self, $class;

    return $self;
}

sub connection {
    my ( $self, $env, $db ) = @_;

    defined($env)
      or confess 'BerkeleyDB::Env object required';

    ref($env)
      or confess 'BerkeleyDB::Env object required';

    $env->isa('BerkeleyDB::Env')
      or confess 'BerkeleyDB::Env object required';

    $self->{ENV} = $env;

    defined($db)
      or confess 'BerkeleyDB::Hash object required';

    ref($db)
      or confess 'BerkeleyDB::Hash object required';

    $db->isa('BerkeleyDB::Hash')
      or confess 'BerkeleyDB::Hash object required';

    $self->{DB} = $db;
}

sub env { return $_[0]->{ENV} }
sub db  { return $_[0]->{DB} }

sub NEXTREC { $_[0]->() }

sub iterator {
    my ($self) = @_;

    #initialize the cursor / database iterator
    my ( $key, $val ) = ( "", "" );
    my $cursor;

    # the iterator code ref
    return sub {

        $cursor = $self->db->db_cursor();

        die "database error : cursor not set\n" if ( !defined $cursor );

        $log->debug("key = $key");

        if ( $key ne "" ) {

            $log->debug("c_get DB_SET at $key");

            my $err = $cursor->c_get( $key, $val, DB_SET );

            if ($err) {
                die "c_get error : \n$BerkeleyDB::Error\n\n";
            }
        }

        while ( $cursor->c_get( $key, $val, DB_NEXT ) == 0 ) {

            next if ( $key eq '__TOPOLOGY__' );

            if ( !blessed $val ) {
                die "database error : $key value not an object\n";
            }

            #close the cursor to unlock the database
            $cursor->c_close();

            $log->debug("returning : $key = $val");

            return ( $key, $val );
        }

        undef $cursor;

        return;
      }
}

sub get {
    my ( $self, $key ) = @_;

    $log->debug("get : key = $key");

    my $val = '';

    my $status = $self->db->db_get( $key, $val );

    if ( $status =~ /DB_NOTFOUND/ ) {
        return;
    }
    elsif ($status) {
        die "get error :\n $BerkeleyDB::Error \n $status\n";
    }

    return $val;
}

sub put {
    my ( $self, $key, $val ) = @_;

    my $txn = $self->env->txn_begin();

    $self->db->Txn($txn);

    my $err = $self->db->db_put( $key, $val );

    if ($err) {
        die "put $key error : \n $BerkeleyDB::Error \n $err\n";
    }

    $err = $txn->txn_commit();

    if ($err) {
        die "put $key error : transaction commit failed \n $BerkeleyDB::Error \n $err\n";
    }
}

1;
__END__

=head1 NAME

Farly::Object::Repository - Database interface

=head1 DESCRIPTION

Farly::Object::Repository is the Farly Berkeley DB database interface.

=head1 METHODS

=head2 new( $topology )

The constructor. No arguments.

    $repo = Farly::Object::Repository->new();

=head2 connection( $env, $db )

Connect to the specified environment and database.

    $repo->connection( $env, $db )

=head2 put( $key, $value )

Store the key, value pair.

    $repo->put( $key, $value );

=head2 get( $key )

Retrieve the value associated with $key.

    $object = $repo->get( $key );

=head2 iterator()

Return an iterator code reference which uses Berkeley DB cursors
to iterate over all objects in the database.

  use Farly::Object::Repository qw(NEXTREC);
  
  $it = $repo->iterator()

=head1 FUNCTIONS

=head2 NEXTREC( $it )

Advances the iterator to the next object.

=head1 COPYRIGHT AND LICENCE

Farly::Object::Repository
Copyright (C) 2013  Trystan Johnson

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

