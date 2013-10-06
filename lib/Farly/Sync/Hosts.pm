package Farly::Sync::Hosts;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Net::Managed;

our $VERSION = '0.26';

sub new {
    my ($class) = @_;

    my $self = {
        MANAGED => undef,
        TIMEOUT => 172800,                       # default = 2 days
        REPO    => undef,
        RESULT  => Farly::Object::List->new(),
        HOST    => undef,
        SEEN    => {},
    };
    bless( $self, $class );

    # define a HOST object type
    $self->{'HOST'} = Farly::Object->new();
    $self->{'HOST'}->set( 'OBJECT_TYPE', Farly::Value::String->new('HOST') );
    
    $log->info("$self NEW");

    return $self;
}

# accessors
sub managed { return $_[0]->{'MANAGED'} }
sub timeout { return $_[0]->{'TIMEOUT'} }
sub repo    { return $_[0]->{'REPO'} }
sub result  { return $_[0]->{'RESULT'} }

sub set_managed {
    my ( $self, $file_name ) = @_;

    confess "file not specified"
      unless ( defined $file_name );

    confess "$file_name is not a file"
      unless ( -f $file_name );

    $self->{'MANAGED'} = Farly::Net::Managed->new($file_name);
}

sub set_timeout {
    my ( $self, $seconds ) = @_;

    confess "set_timeout seconds not defined"
      unless ( defined $seconds );

    confess "set_timeout seconds not a number"
      unless ( $seconds =~ /^\d+$/ );

    $self->{'TIMEOUT'} = $seconds;
}

sub set_repo {
    my ( $self, $repo ) = @_;

    confess "repository not defined"
      unless ( defined $repo );

    $self->{'REPO'} = $repo;
}

sub _is_managed {
    my ( $self, $ip ) = @_;
    return $self->managed->is_managed($ip);
}

# if object last seen > 2 days and it has been polled then
# host or service is down so remove rule
sub _is_down {
    my ( $self, $object ) = @_;

    if ( ( ( time() - $object->get('LAST_SEEN')->number ) > $self->timeout )
        && ( $object->get('POLLED')->number > 0 ) )
    {
        return 1;
    }
    else {
        return 0;
    }
}

# list against repo
sub check {
    my ( $self, $list ) = @_;

    # expanded list
    foreach my $object ( $list->iter ) {
        $self->_check_rule($object);
    }
}

# the rule can be removed if the rule references a host in
# a managed network and the host referenced is not active
sub _check_rule {
    my ( $self, $rule ) = @_;

    #specify the access-list properties to search
    my @address_properties = ( 'SRC_IP', 'DST_IP' );

    $log->debug( "rule: \n{" . $rule->dump() . "}" )
      if $log->is_debug();

    foreach my $property (@address_properties) {

        $log->debug( "checking $property " . $rule->get($property)->as_string() );

        if ( !$rule->has_defined($property) ) {
            $log->debug("skipped rule property $property not defined");
            return;
        }

        # check the rules which have an IP address in them
        if ( !$rule->get($property)->isa('Farly::IPv4::Address') ) {
            $log->debug( "skipped $property " . ref( $rule->get($property) ) );
            next;
        }

        # $address is the 32 bit int IP address
        my $address = $rule->get($property)->address();

        # each address will be checked one time only
        # because all references to the address will be removed
        # this the address is considered down
        next if $self->{'SEEN'}->{$address}++;

        # is this a managed IP address?
        if ( !$self->_is_managed( $rule->get($property) ) ) {
            $log->debug( "skipped $property : " . $rule->get($property)->as_string() . " is not managed" );
            next;
        }

        $log->debug("retrieving address $address");

        my $object = $self->repo->get($address);

        # if there is no info about this host then do nothing
        if ( !defined $object ) {
            $log->debug("address $address not found in database");
            next;
        }

        confess "not a host object"
          if ( !$object->matches( $self->{'HOST'} ) );

        if ( $self->_is_down($object) ) {

            # all rules referencing this host will be removed
            # because the host is not active

            $log->warn( "host : " . $object->get('OBJECT')->as_string() .
                " was last seen at " . localtime( $object->get('LAST_SEEN')->number() ) );

            $self->result->add($object);

            return;
        }
    }
}

1;
__END__

=head1 NAME

Farly::Sync::Hosts - Host based rule to network synchronization

=head1 DESCRIPTION

Farly::Sync::Hosts finds inactive hosts referenced in the firewall rules.

Inherits from Farly::Sync.

All expanded rules are checked against the host repo.

There must a single Farly::Sync::Host object per firewall.

=head1 METHODS

=head2 new( $file_name )

The constructor. A configuration file with the list of managed networks
must be passed to the constructor.

  $sync_hosts = Farly::Sync::Hosts->new( $file_name );

=head2 result()

Return a Farly::Object::List of inactive 'HOST' objects

  @inactive_hosts = $sync_hosts->result();

=head2 check( $rule_list )

Check the given rules for references to inactive hosts.

  $sync_hosts->check( $rule_list );
  
If the rule does not reference a host which is in the host db then that
rule is skipped and left in the rules.

=head1 COPYRIGHT AND LICENCE

Farly::Sync::Host
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
Check if the given rule references a host which is inactive.
