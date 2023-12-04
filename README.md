# PLHop

## DESCRIPTION

A Hierarchical Task Network Planner based on Pyhop and it's derivatives.

## SYNOPSIS

```perl
#!/usr/bin/env perl
use 5.38.0;
use lib 'lib';

use PLHop;

# Ported From:
# https://github.com/dananau/GTPyhop/blob/main/Examples/pyhop_simple_travel_example.py

my $domain = PLHop::Domain->new( name => 'pyhop_simple_travel_example' );

sub taxi_rate ($dist) { 1.5 + 0.5 * $dist }

$domain->declare_actions(
    walk => sub ( $state, $p, $x, $y ) {
        return unless $state->{loc}->{$p} eq $x;
        $state->{loc}->{$p} = $y;
        return $state;
    },
    call_taxi => sub ( $state, $p, $x ) {
        $state->{loc}->{'taxi'} = $x;
        return $state;
    },
    ride_taxi => sub ( $state, $p, $x, $y ) {
        return if $state->{loc}->{taxi} ne $x || $state->{loc}->{$p} ne $x;
        $state->{loc}->{taxi} = $y;
        $state->{loc}->{$p} = taxi_rate( $state->{dist}{$x}{$y} );
        return $state;
    },
    pay_driver => sub ( $state, $p, $y ) {
        return if $state->{cash}->{$p} < $state->{owe}->{$p};
        $state->{cash}->{$p} = $state->{cash}->{$p} - $state->{owe}->{$p};
        $state->{owe}->{$p}  = 0;
        $state->{loc}->{$p}  = $y;
        return $state;
    },
);

sub travel_by_foot ( $state, $p, $x, $y ) {
    return unless $state->{dist}->{$x}{$y} <= 2;
    return [ 'walk', $p, $x, $y ];
}

sub travel_by_taxi ( $state, $p, $x, $y ) {
    return unless $state->{cash}->{$p} >= taxi_rate( $state->{dist}{$x}{$y} );
    return (
        [ 'call_taxi',  $p, $x ],
        [ 'ride_taxi',  $p, $x, $y ],
        [ 'pay_driver', $p, $y ]
    );
}

$domain->declare_task_methods( 'travel', \&travel_by_foot, \&travel_by_taxi );

my $state = {
    loc  => { me   => 'home' },
    cash => { me   => 20 },
    owe  => { me   => 0 },
    dist => { home => { park => 8 }, park => { home => 8 } },
};

my $planner = PLHop::Planner->new(
    domain    => $domain,
    state     => $state,
    todo_list => [ [ 'travel', 'me', 'home', 'park' ] ]
);

say "@$_" for $planner->plan();
```
