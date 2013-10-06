package Farly::TDS::Manager;

use 5.008008;

use strict;
use warnings;
use Carp;
use File::stat;
use Storable qw(freeze thaw);
use BerkeleyDB;
use Log::Any qw($log);

our $VERSION = '0.26';

sub new {
    my ( $class, %args ) = @_;

    my $self = {
        %args,    # the datastore connection configuration is in %args
        ENV => undef,    # environment object
        FW  => undef,    # the firewall database object
        HOST => undef,   # the host database object
        SRV => undef,    # the service database object
    };
    bless $self, $class;

    $log->info("$self connecting $$ $0 to database");

    eval {
        # validate the datastore connection configuration in %args
        $self->_check_cfg();

        $self->_join_env();

        $self->_open_db();    # open the database connections
    };
    if ($@) {
        print $@, "\n";
        $log->fatal($@);
        die "datastore connection failed, see log for details\n";
    }

    return $self;
}

# accessors
sub dir { return $_[0]->{dir}; }    # datastore location
sub env { return $_[0]->{ENV}; }
sub fw  { return $_[0]->{FW}; }
sub host { return $_[0]->{HOST}; }
sub srv { return $_[0]->{SRV}; }

# validate the configuration
sub _check_cfg {
    my ($self) = @_;

    confess "config error : dir not specified"
      unless ( defined( $self->dir ) );

    confess "config error : invalid directory ", $self->dir
      unless ( -d $self->dir );

    $log->info("configuration loaded");
}

sub _check_db_register_file {
    my ($self) = @_;

    my $file = $self->dir . '/__db.register';

    die "__db.register file not found\n" if ( !-f $file );

    my $info = stat($file);

    my $mode = $info->mode();

    $log->debug("file = $file : mode = $mode");

    if ( ( $mode & 006 ) != 006 ) {
        chmod( 0666, $file ) == 1
          or die "chmod $file : $!\n";
    }
}

# scripts use this
sub _join_env {
    my ($self) = @_;

    $log->info( "joining env in " . $self->dir );

    # Berkeley DB default permissions are 0664
    # default root umask is usually 0022, it needs to be changed
    # 0666 - 0002 = 0664 (user and group read/write)

    my $old_umask = umask(0000);

    $self->{ENV} = BerkeleyDB::Env->new(
        -Home       => $self->dir,
        -LockDetect => DB_LOCK_DEFAULT,
        -Flags      => DB_REGISTER | DB_CREATE | DB_RECOVER | DB_INIT_LOG | DB_INIT_TXN | DB_INIT_MPOOL | DB_INIT_LOCK,
        -Mode       => 0666,
      )
      or die "can't open environment : $BerkeleyDB::Error\n";

    $self->_check_db_register_file();

    $log->info( "connected to environment " . $self->{ENV} );
}

#open the databases
sub _open_db {
    my ($self) = @_;

    $log->info("opening databases");

    my $txn = $self->env->txn_begin();

    #firewall database key is lc(hostname), no duplicates
    $self->{FW} = BerkeleyDB::Hash->new(
        -Filename => 'firewall.db',
        -Env      => $self->env,
        -Flags    => DB_CREATE,
        -Txn      => $txn
      )
      or die "cannot open database: $BerkeleyDB::Error\n";

    $self->{FW}->filter_store_value( sub { $_ = freeze($_) } );
    $self->{FW}->filter_fetch_value( sub { $_ = thaw($_) } );

    #host database key is integer IP address, no duplicates
    $self->{HOST} = BerkeleyDB::Hash->new(
        -Filename => 'host.db',
        -Env      => $self->env,
        -Flags    => DB_CREATE,
        -Txn      => $txn
      )
      or die "cannot open database: $BerkeleyDB::Error\n";

    $self->{HOST}->filter_store_value( sub { $_ = freeze($_) } );
    $self->{HOST}->filter_fetch_value( sub { $_ = thaw($_) } );

    #service database key is integer IP address, no duplicates
    $self->{SRV} = BerkeleyDB::Hash->new(
        -Filename => 'service.db',
        -Env      => $self->env,
        -Flags    => DB_CREATE,
        -Txn      => $txn
      )
      or die "cannot open database: $BerkeleyDB::Error\n";

    $self->{SRV}->filter_store_value( sub { $_ = freeze($_) } );
    $self->{SRV}->filter_fetch_value( sub { $_ = thaw($_) } );

    my $err = $txn->txn_commit();
    if ($err) {
        die "$BerkeleyDB::Error\n";
    }

    $log->info("databases opened successfully");
}

sub close {
    my ($self) = @_;

    eval {
        if ( defined $self->fw ) {

            #close the firewall datastore
            my $err = $self->fw->db_close();

            if ($err) {
                die "firewall database close failed : \n$BerkeleyDB::Error\n";
            }

            $log->info("firewall database closed");
        }

        if ( defined $self->host ) {

            #close the host datastore
            my $err = $self->host->db_close();

            if ($err) {
                die "host database close failed : \n$BerkeleyDB::Error\n";
            }

            $log->info("host database closed");
        }

        if ( defined $self->srv ) {

            #close the host datastore
            my $err = $self->srv->db_close();

            if ($err) {
                die "srv database close failed : \n$BerkeleyDB::Error\n";
            }

            $log->info("host database closed");
        }

        if ( defined $self->env ) {

            #exit the BDB environment
            my $err = $self->env->close();

            if ($err) {
                die "environment close failed : \n$BerkeleyDB::Error\n";
            }

            $log->info("environment close ok");
        }
    };
    if ($@) {
        $log->fatal("firewall database close failed : $@");
        die "datastore connection close error\n";
    }
}

1;
__END__

=head1 NAME

Farly::TDS::Manager - Berkeley DB Transactional Datastore Management

=head1 DESCRIPTION

Farly::TDS::Manager is an Oracle Berkeley DB Transactional Datastore
Manager for Farly object storage.

Farly::TDS::Manager uses Storable for object serialization.

All methods die on error.

=head1 METHODS

=head2 new( %{ config } )

The constructor. A hash with the datastore configuration parameters is required.

  my $db_conn = Farly::TDS::Manager->new( %{ ds connection configuration } );

=head2 fw()

Return the firewalls database object.

 my $fw_db = $db_conn->fw();

=head2 host()

Returns the host objects database object.

 my $host_db = $db_conn->host();

=head2 srv()

Returns the service objects database object.

 my $srv_db = $db_conn->srv();

=head1 COPYRIGHT AND LICENCE

Farly::TDS::Manager
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
