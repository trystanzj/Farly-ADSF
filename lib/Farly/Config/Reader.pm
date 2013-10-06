package Farly::Config::Reader;

use 5.008008;
use strict;
use warnings;
use Config::Scoped;
use Log::Any qw($log);

our $VERSION = '0.26';

sub new {
    my ( $class, $config_file ) = @_;

    die "configuration file not specified\n"
      unless ( defined $config_file );

    die "configuration file $config_file not found\n"
      unless ( -f $config_file );

    my $self = { CFG => undef, };

    bless $self, $class;

    $self->_read_conf($config_file);

    $log->info("read configuration file = $config_file");

    return $self;
}

sub config { return $_[0]->{CFG}; }

sub _read_conf {
    my ( $self, $config_file ) = @_;

    my $cs = Config::Scoped->new(
        file     => $config_file,
        lc       => 1,
        warnings => 'off'
    );

    $self->{CFG} = $cs->parse();
}

1;
__END__

=head1 NAME

Farly::Config::Reader - Read the configuration file.

=head1 DESCRIPTION

Farly::Config::Reader reads farly.conf Config::Scoped configuration file.

=head1 METHODS

=head2 new( $config_file )

The constructor. The Config::Scoped config file must be passed to the constructor.

  $reader = Farly::Config::Reader->new( $config_file );

=head2 config()

Returns the configuration hash table.

  \%config = $reader->config()

=head1 COPYRIGHT AND LICENCE

Farly::Config::Reader
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
