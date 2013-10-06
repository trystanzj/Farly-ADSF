package Farly::Data;

use 5.008008;
use strict;
use warnings;
use Carp;
use Log::Any qw($log);
use Farly::Object;
use Farly::Rule::Expander;

our $VERSION = '0.26';

sub new {
    my ( $class, $list ) = @_;

    defined($list)
      or confess "firewall configuration object required";

    confess "invalid container ", ref($list)
      unless ( $list->isa('Farly::Object::List') );

    my $self = {
        CONFIG => $list,    # the original model
        RULES  => undef,    # an aggregate of the expanded rules
    };

    bless( $self, $class );
    
    $log->info("$self new");

    $self->_expand($list);

    return $self;
}

sub config         { return $_[0]->{CONFIG} }
sub expanded_rules { return $_[0]->{RULES} }

sub _rule_ref_list {
    my ( $self, $list ) = @_;

    my $search = Farly::Object->new();
    $search->set( 'ENTRY', Farly::Value::String->new('ACCESS_GROUP') );

    my $result = Farly::Object::List->new();

    foreach my $object ( $list->iter() ) {
        if ( $object->matches($search) ) {
            $result->add( $object->get('ID') );
        }
    }

    confess "no access-groups found" if ( $result->size == 0 );

    return $result;
}

sub _expand {
    my ( $self, $config ) = @_;

    # expand the rules
    my $rule_expander  = Farly::Rule::Expander->new($config);
    my $expanded_rules = $rule_expander->expand_all();

    # get a list of expanded rule reference objects
    my $ref_list = $self->_rule_ref_list($config);

    my $rules = Farly::Object::List->new();

    # foreach ag create a separate ::List of rules
    foreach my $ref_object ( $ref_list->iter() ) {

        $expanded_rules->matches( $ref_object, $rules );
    }

    $self->{'RULES'} = $rules;
}

1;

__END__

=head1 NAME

Farly::Data - Contains the configuration and expanded rules

=head1 DESCRIPTION

Farly::Data stores references to the orginal firewall model container
and expanded rule lists.

Farly::Data objects are stored in and retrieved from the Farly database.

=head1 METHODS

=head2 new( $config )

The constructor. An imported configuration list must be passed to the constructor.

  $farly_data = Farly::Data->new( $config );

=head2 config()

Returns the configuration container.

  $config = $farly_data->config();

=head2 expanded_rules()

Returns a Farly::Object::List with all expanded rules.

  $rules = $data->expanded_rules();

=head1 COPYRIGHT AND LICENCE

Farly::Data
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
