#!/usr/bin/perl -w

use lib qw(lib ../lib);

use WWW::AfinimaKi;
use Data::Dumper;

my $api_key     = 'ecca0a898b2740ba825444aaedc5ef3b';
my $secret_key  = '1576cbb0b0891c42265a75357dcbfaa9';
my $host        = 'http://localhost:8080/RPC2';

my $afinimaki = WWW::AfinimaKi->new($api_key, $secret_key, $host);


#foreach my $user_id (10..100) {
foreach my $user_id (10..2000) {

    print "Estimated rate for item_id: 2211 => ";

    print Dumper(
            $afinimaki->estimate_rate($user_id, 2211)
            );
}

