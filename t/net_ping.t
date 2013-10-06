use strict;
use warnings;
use File::Spec;
use Test::Simple tests => 5;
use Farly::Net::Ping;

# flush after every write
$| = 1;

my $p = Farly::Net::Ping->new(
    timeout     => 1,
    max_retries => 2,
);

my $icmp_up_ok;
my $icmp_down_ok;
my $tcp_up_ok;
my $tcp_down_ok;
my $udp_up_ok;
my $udp_down_ok;

if ( $p->icmp_ping('127.0.0.1') ) {
    $icmp_up_ok = 1;
}

if ( $p->icmp_ping('127.0.0.25') ) {
    $icmp_down_ok = 1;
}

if ( $p->tcp_ping( '127.0.0.1', 22 ) ) {
    $tcp_up_ok = 1;
}

if ( !$p->tcp_ping( '127.0.0.1', 30 ) ) {
    $tcp_down_ok = 1;
}

if ( !$p->udp_ping( '127.0.0.1', 59835 ) ) {
    $udp_down_ok = 1;
}

ok( $icmp_up_ok,   'icmp up' );
ok( $icmp_down_ok, 'icmp down' );
ok( $tcp_up_ok,    'tcp up' );
ok( $tcp_down_ok,  'tcp down' );
ok( $udp_down_ok,  'udp down' );
