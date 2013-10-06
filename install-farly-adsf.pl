#!/usr/bin/perl -w

# install-farly-adsf.pl - Installation Script
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
use Module::Build;

# initialize CPAN
CPAN::HandleConfig->load;
CPAN::Shell::setup_output;
CPAN::Index->reload;

# create the service account
my ( $login, $pass, $uid, $gid ) = getpwnam('farly');

if ( !defined $uid ) {

    system('groupadd farly') == 0
      ? print "added group 'farly'\n"
      : die "\ngroupadd 'farly' failed... quiting install\n\n";

    system('useradd -s /sbin/nologin -g farly -p farly farly') == 0
      ? print "added user 'farly'\n"
      : die "\nuseradd 'farly' failed... quiting install\n\n";

}

my %build_requires = (
    'ExtUtils::MakeMaker' => '6.62',
    'Test::Simple'        => '0',
    'Test::More'          => '0',
);

install_dependencies(%build_requires);

my %requires = (
    'BerkeleyDB'                  => '0.51',
    'NetPacket::IP'               => '1.3.1',
    'Parse::RecDescent'           => '1.965001',
    'Log::Log4perl'               => '1.35',
    'Log::Any'                    => '0.15',
    'Log::Any::Adapter'           => '0.11',
    'Log::Any::Adapter::Log4perl' => '0.06',
    'Template'                    => '2.22',
    'Carp'                        => '0',
    'Config'                      => '0',
    'Config::Scoped'              => '0',
    'Cwd'                         => '0',
    'Exporter'                    => '0',
    'Exporter::Heavy'             => '0',
    'File::Path'                  => '0',
    'File::Spec'                  => '0',
    'File::Spec::Unix'            => '0',
    'File::Spec::Win32'           => '0',
    'Getopt::Long'                => '0',
    'IO'                          => '0',
    'IO::File'                    => '0',
    'IO::Handle'                  => '0',
    'IO::Seekable'                => '0',
    'IO::Select'                  => '0',
    'IO::Socket::INET'            => '0',
    'List::Util'                  => '0',
    'Net::Ping'                   => '0',
    'Pod::Usage'                  => '0',
    'Scalar::Util'                => '0',
    'SelectSaver'                 => '0',
    'SelfLoader'                  => '0',
    'Symbol'                      => '0',
    'Text::Balanced'              => '0',
    'Time::HiRes'                 => '0',
    'DynaLoader'                  => '0',
    'English'                     => '0',
    'Fcntl'                       => '0',
    'File::Basename'              => '0',
    'POSIX'                       => '0',
    'Sys::Hostname'               => '0',
);

install_dependencies(%requires);

my $class = Module::Build->subclass(
    class => "Module::Build::Farly",
    code  => <<'SUBCLASS' );

sub ACTION_f_configure {
	my ( $self ) = @_;

	my ( $login, $pass, $uid, $gid ) = getpwnam('farly')
	  or die "f_configure : user 'farly' not found ... quiting install\n";

	my %dirs = (
		'/etc/farly/'     => 0755,
		'/var/log/farly/' => 0770,
		'/var/db/farly/'  => 0770,
	);

	foreach my $dir ( keys %dirs ) {

		if ( ! -d $dir ) {

			mkdir $dir or die "failed to create $dir : $! ... quiting install \n";

			my $mode = $dirs{ $dir };

			chmod( $mode, $dir ) == 1 or
			  die "failed to chmod() $dir ... quiting install\n";

			# '/etc/farly/' is owned by root
			next if ( $dir eq '/etc/farly/' );

			chown( $uid, $gid, $dir ) == 1
			  or die "failed to chown() $dir ... quiting install\n";
		}
	}

	my $mode = 0666;
	my $log_file = '/var/log/farly/Farly.log';

	if ( ! -f $log_file ) {

		open my $fh, ">", $log_file or die "cannot open $log_file : $! ... quiting install\n";
		print $fh "initialize\n";		
		close $fh;

		chmod( $mode, $log_file ) == 1 
		  or die "failed to chmod() $log_file ... quiting install\n";

		chown( $uid, $gid, $log_file ) == 1
		  or die "failed to chown() $log_file ... quiting install\n";
	}
}

sub ACTION_install {
	my ( $self ) = @_;

	use Config;

	$self->SUPER::ACTION_install;

	print "Setting File Permissions and Ownership\n";

	my ( $login, $pass, $uid, $gid ) = getpwnam('farly')
	  or die "install : user 'farly' not found ... quiting install\n";

	my $dir = $Config{installsitebin}
	  or die "failed to read installsitebin ... quiting install\n";

	my $dh;
	opendir( $dh, $dir )
	  or die "failed to open $dir  ... quiting install\n";

	my $mode = 0750;

	while ( my $file = readdir($dh) ) {

		next if ( $file =~ /^\./ );

		my $abs_path = join( '/', $dir, $file );

		if ( $file =~ /^f_(.*)pl$/ ) {

			chown( $uid, $gid, $abs_path ) == 1
			  or die "failed to chown() $abs_path ... quiting install\n";

			chmod( $mode, $abs_path ) == 1
			  or die "failed to chmod() $abs_path ... quiting install\n";
		}
	}

	close($dh);

	$dir = '/etc/farly';
	$mode = 0644;

	opendir( $dh, $dir )
	  or die "failed to open $dir  ... quiting install\n";

	while ( my $file = readdir($dh) ) {

		next if ( $file =~ /^\./ );

		my $abs_path = join( '/', $dir, $file );

		chmod( $mode, $abs_path ) == 1
		  or die "failed to chmod() $abs_path ... quiting install\n";
	}

	close($dh);
}
SUBCLASS

my $build = $class->new(
    module_name    => 'Farly',
    license        => 'gpl',
    dist_author    => 'Trystan Johnson',
    build_requires => { %build_requires, },
    requires       => {%requires},
    module_name    => 'Farly',
    template_files =>
      { 'lib/Farly/Template/Files/ASA' => 'lib/Farly/Template/Files/ASA' },
    conf_files => {
        'conf/farly.conf'   => 'conf/farly.conf',
        'conf/logging.conf' => 'conf/logging.conf',
    },
    csv_files => {
        'conf/firewalls.csv' => 'conf/firewalls.csv',
        'conf/networks.csv'  => 'conf/networks.csv',
        'conf/topology.csv'  => 'conf/topology.csv',
    },
);

$build->add_build_element('template');
$build->install_path( template => 'lib/Farly/Template/Files/ASA' );

my $conf_dir = '/etc/farly/';

# -f because of bootstrapped logging.conf file
if ( !-f '/etc/farly/farly.conf' ) {
    $build->add_build_element('conf');
    $build->install_path( conf => $conf_dir );
    $build->add_build_element('csv');
    $build->install_path( csv => $conf_dir );
}

$build->dispatch('f_configure');
$build->dispatch('build');
$build->dispatch('test');
$build->dispatch('install');

print "\nInstallation Successful\n\n";

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

sub install_dependencies {
    my (%reqs) = @_;
    foreach my $module ( keys %reqs ) {
        my $version = $reqs{$module};
        install_module( $module, $version );
    }
}
