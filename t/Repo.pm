package Repo;

use 5.008008;
use strict;
use warnings;
use Carp;
require Exporter;

our @ISA       = qw(Exporter);
our @EXPORT_OK = qw(NEXTREC);

our $VERSION = '0.23';

sub new {
    my ($class) = @_;
    my $self = {};
    bless $self, $class;
    return $self;
}

sub connection {
    my ( $self ) = @_;
}

sub NEXTREC { $_[0]->() }

sub iterator {
    my ($self) = @_;

    my @keys = keys %$self;
        
    my $i = 0;

    # the iterator code ref
    return sub {
        return undef if $i == scalar( @keys );
        my $key = $keys[$i];
        $i++;
        return $self->{$key}
    }
}

sub get {
    my ( $self, $key ) = @_;
    return $self->{$key};
}

sub put {
    my ( $self, $key, $val ) = @_;
    $self->{$key} = $val;
}

1;
__END__

=head1 NAME

Repo - Sync test Repo module

=head1 DESCRIPTION

Repo is for testing Farly::Sync modules 

=head1 COPYRIGHT AND LICENCE

Repo
Copyright (C) 2012  Trystan Johnson

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
