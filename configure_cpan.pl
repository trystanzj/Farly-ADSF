#!/usr/bin/perl -w

# configure_cpan.pl - CPAN Configuration Script
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
use CPAN;

# initialize CPAN
CPAN::HandleConfig->load;
CPAN::Shell::setup_output;
CPAN::Index->reload;

# handle dependencies automatically
CPAN::Shell->o('conf', 'halt_on_failure', '1');
CPAN::Shell->o('conf', 'build_requires_install_policy', 'yes');
CPAN::Shell->o('conf', 'prerequisites_policy', 'follow');
CPAN::Shell->o('conf', 'commit');

# install/update YAML, CPAN, and Module::Build before proceeding
my @prereqs = ( 'YAML', 'CPAN', 'Test::More', 'Module::Build' );

foreach my $module (@prereqs) {
    eval {
        print "installing $module\n";
        install_module($module, 0);
    };
    if ($@) {
        print "re-trying $module\n";
        CPAN::Shell->reload('cpan');
        install_module($module, 0);
    }
    print "reloading cpan\n";
    CPAN::Shell->reload('cpan');
}

print "\nFinished OK\n";

sub install_module {
    my ( $module, $version ) = @_;

    # Save this because CPAN will chdir all over the place.
    my $cwd = Cwd::cwd();

    my $install_needed;

    if ( $version eq '0' ) {
        eval "require $module";
        if ($@) {
            $install_needed = 1;
        }
    }
    else {
        $install_needed = 1;
    }

    if ($install_needed) {

        CPAN::Shell->install($module);
        CPAN::Shell->expand( "Module", $module )->uptodate
          or die "module installation failed : $module\n";

    }

    chdir $cwd or die "chdir failed : $cwd: $! ... quiting install\n";
}
