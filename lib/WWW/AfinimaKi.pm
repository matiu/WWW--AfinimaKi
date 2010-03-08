package WWW::AfinimaKi;
use strict;

require RPC::XML;
require RPC::XML::Client;
use Digest::MD5	qw(md5_hex);
use Encode;
use Carp;

our $VERSION = '0.4';

use constant KEY_LENGTH     => 32;
use constant TIME_SHIFT     => 10;

=head1 NAME

WWW::AfinimaKi - AfinimaKi Recommendation Engine Client


=head1 SYNOPSIS

    use WWW::AfinimaKi;         # Notice the uppercase "K"!

    my $api = WWW::AfinimaKi->new( $your_api_key, $your_api_secret);

    ...

    $api->set_rate($user_id, $item_id, $rate);

    ...

    my $estimated_rate = $api->estimate_rate($user_id, $rate);

    ...

    my $recommendations = $api->get_recommendations($user_id);
    foreach (@$recommendations) {
        print "item_id: $_->{item_id} estimated_rate: $_->{estimated_rate}\n";
    }

=head1 DESCRIPTION

WWW::AfinimaKi is a simple client for the AfinimaKi Recommendation API. Check http://www.afinimaki.com/api for more details.

=head1 Methods

=head3 new

    my $api = WWW::AfinimaKi->new( 
                    api_key     => $your_api_key, 
                    api_secret  => $your_api_secret, 
                    debug       => $debug_level,
    );

    if (!$api) {
        die "Error construction afinimaki, wrong keys length?";
    }

    new Construct the AfinimaKi object. No nework traffic is generated (the account credentialas are not checked at this point). 

    The given keys must be 32 character long. You can get them at afinimaki.com. Debug level can be 0 or 1.

=cut

sub new {
    my ($class, %args) = @_;  

    my $key     =  $args{api_key};
    my $secret  =  $args{api_secret};
    my $debug   =  $args{debug};
    my $url     =  $args{url} || 'http://api.afinimaki.com/RPC2';

    # url parameter is undocumented on purpose to simplify.

    if ( !$key  || ! $secret ) {
        carp "api_key and api_secret parameters are mandatory";
        return undef;
    }

    if ( length($key) != KEY_LENGTH ) {
        carp "Bad api_key '$key': it must be " .  KEY_LENGTH . " character long";
        return undef;
    }


    if ( length($secret) != KEY_LENGTH  ) {
        carp "Bad api_secret '$secret': it must be ". KEY_LENGTH . " character long";
        return undef;
    }

    if ( $url && $url !~ /^http:\/\// ) {
        carp "Bad URL given : $url";
        return undef;
    }

    my $self = {
        key     => $key,
        secret  => $secret,
        cli     => RPC::XML::Client->new($url),
        debug   => $debug,
    };

    # AfinimaKi, 5 seconds it's all you get!
    $self->{cli}->timeout(5);

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
        . int( time() >> TIME_SHIFT )
        ;

    #print STDERR "CODE: $code\n" if $self->{debug};

    return md5_hex( $code );
}

sub _is_error {
    my ($r) = @_;

    if ( !$r ) {
        return 1;
    }
    elsif ( $r->is_fault()) {
        carp __PACKAGE__ . " Error: ". $r->string;
        return 1;
    }
    return 0;
}

sub send_request {
    my ($self, $method, @args) = @_;

    my $val = $args[0] ? $args[0]->value : undef;


    print STDERR __PACKAGE__ 
        . "=> $method ("
        . join(
            ', ',  
            map { $_->value } 
            @args
        ) 
        . ")\n"
        if $self->{debug};


    my $r = $self->{cli}->send_request(
        $method,
        $self->{key},
        $self->_auth_code($method, $val),
        @args
    );

    if (ref($r)) {
        return $r;
    }

    carp $r;
    return undef;
}


=head2 user-item services

=head3 set_rate

    $api->set_rate($user_id, $item_id, $rate);

    Stores a rate in the server. Waits until the call has ended.

    On error, returns undef, and carp the RPC::XML error.

=cut

sub set_rate {
    my ($self, $user_id, $item_id, $rate) = @_;
    return undef if ! $user_id || ! $item_id || ! defined ($rate);

    my $r = $self->send_request(
        'set_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
        RPC::XML::double->new($rate),
    );
    return undef if _is_error($r);

    return $r;
}


=head3 estimate_rate

    my $estimated_rate = $api->estimate_rate($user_id, $item_id);

    Estimate a rate. Undef is returned if the rate could not be estimated (usually because the given user or the given item does not have many rates).

    On error, returns undef, and carp the RPC::XML error.
=cut

sub estimate_rate {
    my ($self, $user_id,  $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    my $r = $self->send_request(
        'estimate_rate', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
    return undef if _is_error($r);

    return 1.0 * $r->value;
}



=head3 estimate_multiple_rates

    my $rates_hashref = $api->estimate_rate($user_id, @item_ids);
        foreach my $item_id (keys %$rates_hashref) {
        print "Estimated rate for $item_id is $rates_hashref->{$item_id}\n";
    }

    Estimate multimple rates. The returned hash has the structure: 
            item_id => estimated_rate

    On error, returns undef, and carp the RPC::XML error.

=cut

sub estimate_multiple_rates {
    my ($self, $user_id,  @item_ids) = @_;
    return undef if ! $user_id || ! @item_ids;

    my $r = $self->send_request(
            'estimate_multiple_rates', 
            RPC::XML::i8->new($user_id),
            RPC::XML::array->new( 
                    map {
                        RPC::XML::i8->new($_)
                    } @item_ids
                )
        );
    return undef if _is_error($r);
    
    my $ret = {}; 
    my $i = 0;
    foreach (@$r) {
        $ret->{$item_ids[$i++]} = 1.0 * $_->value;
    }

    return $ret;
}

=head3 get_recommendations 

    my $recommendations = $api->get_recommendations($user_id);

    foreach (@$recommendations) {
        print "item_id: $_->{item_id} estimated_rate: $_->{estimated_rate}\n";
    }

    Get a list of user's recommentations, based on users' and community previous rates.
    Recommendations does not include rated or marked items (in the whish or black list).

=cut

sub get_recommendations {
    my ($self, $user_id) = @_;
    return undef if ! $user_id;

    my $r = $self->send_request(
        'get_recommendations', 
        RPC::XML::i8->new($user_id),
        RPC::XML::boolean->new(0),
    );
    return undef if _is_error($r);

    return [
        map { {
            item_id         => 1   * $_->[0]->value,
            estimated_rate  => 1.0 * $_->[1]->value,
        } } @$r
    ];
}

=head3 add_to_wishlist

    $api->add_to_wishlist($user_id, $item_id);

    The given $item_id will be added do user's wishlist. This means that id will not
    be in the user's recommentation list anymore, and the action will be use to tune users's recommendations (The user seems to like this item).

=cut

sub add_to_wishlist {
    my ($self, $user_id, $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    my $r =  $self->send_request(
        'add_to_wishlist', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
    return undef if _is_error($r);

    return $r;
}


=head3 add_to_blacklist

    $api->add_to_blacklist($user_id, $item_id);

    The given $item_id will be added do user's blacklist. This means that id will not
    be in the user's recommentation list anymore, and the action will be use to tune users's recommendations (The user seems to dislike this item). 

=cut

sub add_to_blacklist {
    my ($self, $user_id, $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    my $r =  $self->send_request(
        'add_to_blacklist', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
    return undef if _is_error($r);

    return $r;
}


=head3 remove_from_lists 

    $api->remove_from_lists($user_id, $item_id);

    Remove the given item from user's wish and black lists, and also removes user item's rating (if any).

=cut

sub remove_from_lists {
    my ($self, $user_id, $item_id) = @_;
    return undef if ! $user_id || ! $item_id;

    my $r = $self->send_request(
        'remove_from_lists', 
        RPC::XML::i8->new($user_id),
        RPC::XML::i8->new($item_id),
    );
    return undef if _is_error($r);

    return $r;
}


=head2 user-user services

=head3 get_user_user_afinimaki 

    my $afinimaki = $api->get_user_user_afinimaki($user_id_1, $user_id_2);

    Gets user vs user afinimaki. AfinimaKi range is [0.0-1.0].

=cut

sub get_user_user_afinimaki {
    my ($self, $user_id_1,  $user_id_2) = @_;
    return undef if ! $user_id_1 || ! $user_id_2;
    
    my $r = $self->send_request(
        'get_user_user_afinimaki', 
        RPC::XML::i8->new($user_id_1),
        RPC::XML::i8->new($user_id_2),
    );
    return undef if _is_error($r);

    return 1.0 * $r->value;
}



=head3 get_soul_mates 

    my $soul_mates = $api->get_soul_mates($user_id);

    foreach (@$soul_mates) {
        print "user_id: $_->{user_id} afinimaki: $_->{afinimaki}\n";
    }

    Get a list of user's soul mates (users with similar tastes). AfinimaKi range is [0.0-1.0].

=cut

sub get_soul_mates {
    my ($self, $user_id) = @_;
    return undef if ! $user_id;

    my $r = $self->send_request(
        'get_soul_mates', 
        RPC::XML::i8->new($user_id),
    );
    return undef if _is_error($r);

    return [
        map { {
            user_id         => 1   * $_->[0]->value,
            afinimaki       => 1.0 * $_->[1]->value,
        } } @$r
    ];
}



__END__

=head1 AUTHORS

WWW::AfinimaKi by Matias Alejo Garcia (matiu at cpan.org)

=head1 COPYRIGHT

Copyright (c) 2010 Matias Alejo Garcia. All rights reserved.  This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

=head1 SUPPORT / WARRANTY

The WWW::AfinimaKi is free Open Source software. IT COMES WITHOUT WARRANTY OF ANY KIND. 

Github repository is at http://github.com/matiu/WWW--AfinimaKi


=head1 BUGS

None discovered yet... please let me know if you run into one.
	

