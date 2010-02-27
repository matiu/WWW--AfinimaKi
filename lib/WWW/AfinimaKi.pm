package WWW::AfinimaKi;
use strict;

require RPC::XML;
require RPC::XML::Client;
use Digest::MD5	qw(md5_hex);
use Carp;

our $VERSION = '0.1';

use constant KEY_LENGTH => 32;
use constant TIME_DIV   => 12;

=head3 new

    my $afinimaki = WWW::AfinimaKi->new( $your_api_key, $your_api_secret);

    if (!$afinimaki) {
        die "Error construction afinimaki, wrong keys length?";
    }

    new Construct the AfinimaKi object. No nework traffic is generation (the account credentialas are not comprobated at this step). 

    If the given keys are not 33 character long, 'undef' is returned.

=cut

sub new {
    my ($class, $key, $secret, $url) = @_;  

    # url parameter is undocumented on purpose to simplify.


    if ( length($key) != KEY_LENGTH ) {
        carp "Bad key '$key': it must be " .  KEY_LENGTH . " character long";
        return undef;
    }


    if ( length($secret) != KEY_LENGTH  ) {
        carp "Bad key '$secret': it must be ". KEY_LENGTH . " character long";
        return undef;
    }

    if ( $url && $url !~ /^http:\/\// ) {
        carp "Bad URL given : $url";
        return undef;
    }

    my $self = {
        key     => $key,
        secret  => $secret,
        cli     => RPC::XML::Client->new($url || 'http://api.afinimaki.com/RPC2'),
    };

    bless $self, $class;
    return $self;
}

sub _auth_code {
    my ($self, $method, $first_arg) = @_;
    return undef if ! $method;

    $first_arg ||= '';

    my $code = 
        $self->{secret} 
        . $method 
        . $first_arg 
        . int( time() / TIME_DIV )
        ;

    return md5_hex( $code );
}

sub send_request {
    my ($self, $method, @args) = @_;

    my $val = $args[0] ? $args[0]->value : undef;

    $self->{cli}->send_request(
        $method,
        $self->{key},
        $self->_auth_code($method, $val),
        @args
        );
}

=head3 set_rate

    $afinimaki->set_rate($user_id, $item_id, $rate);

    Stores a rate in the server. Waits until the call has ended.

=cut

sub set_rate {
    my ($self, $user_id, $item_id, $rate) = @_;
    return undef if ! $user_id || ! $item_id || ! defined ($rate);

    $self->send_request(
        'set_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
        RPC::XML::i4->new($rate),
        RPC::XML::boolean->new(0),
    );
}


=head3 estimate_rate

    my $estimated_rate = $afinimaki->estimate_rate($user_id, $rate);

    Estimate rate. Waits until the call has ended.

=cut

sub estimate_rate {
    my ($self, $user_id,  $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    $self->send_request(
        'estimate_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
}


=head3 get_recommendations 

    my $recommendations = $afinimaki->get_recommendations($user_id);

    foreach (@$recommendations) {
        print "item_id: $_->{item_id} estimated_rate: $_->{estimated_rate}\n";
    }

    Get a list of user's recommentations, based on users' and community previous rates.
    Recommendations does not include rated or marked items (in the whish or black list).

=cut

sub get_recommendations {
    my ($self, $user_id) = @_;
    return undef if ! $user_id;

    $self->get_recommendations('get_recommendations', 
        RPC::XML::i8->new($user_id),
        RPC::XML::boolean->new(0),
    );
}


