#!/usr/bin/env perl
use 5.38.0;
use lib 'lib';

use Test::More;
use PLHop;

# Ported From:
# https://github.com/dananau/GTPyhop/blob/main/Examples/pyhop_simple_travel_example.py

# Rather than hard-coding the domain name, use the name of the current file.
# This makes the code more portable.
my $domain = PLHop::Domain->new( name => 'pyhop_simple_travel_example' );

my $state = {
    dist => {
        home_a => {
            home_b => 7,
            park   => 8,
        },
        home_b  => { park => 2, },
        station => {
            home_a => 1,
            home_b => 7,
            park   => 9,
        },
    },
    loc => {
        alice => 'home_a',
        bob   => 'home_b',
        taxi1 => 'park',
        taxi2 => 'station',
    },
    cash => {
        alice => 20,
        bob   => 15,
    },
    owe => {
        alice => 0,
        bob   => 0,
    },
};

sub taxi_rate ($dist) { 1.5 + 0.5 * $dist }

sub distance ( $x, $y ) {
    return 0 if $x eq $y;
    $state->{dist}->{$x}->{$y} //= $state->{dist}->{$y}->{$x};
}

$domain->declare_actions(
    walk => sub ( $state, $p, $x, $y ) {
        return unless $state->{loc}->{$p} eq $x;
        $state->{loc}->{$p} = $y;
        return $state;
    },
    call_taxi => sub ( $state, $p, $x ) {
        $state->{loc}->{'taxi1'} = $x;
        $state->{loc}->{$p} = 'taxi1';
        return $state;
    },
    ride_taxi => sub ( $state, $p, $y ) {
        my $taxi = $state->{loc}->{$p};
        my $x    = $state->{loc}->{$taxi};

        return if $x eq $y;    # already there

        $state->{loc}->{$taxi} = $y;
        $state->{owe}->{$p}    = taxi_rate( distance( $x, $y ) );
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

$domain->declare_commands(
    walk => sub ( $state, $p, $x, $y ) {
        return unless $state->{loc}->{$p} eq $x;
        $state->{loc}->{$p} = $y;
        return $state;
    },
    call_taxi => sub ( $state, $p, $x ) {
        return if int( rand(1) ) == 1;    # 50% of the time it fails
        $state->{loc}->{'taxi1'} = $x;
        $state->{loc}->{$p} = 'taxi1';
        return $state;
    },
    ride_taxi => sub ( $state, $p, $y ) {
        my $taxi = $state->{loc}->{$p};
        my $x    = $state->{loc}->{$taxi};

        return if $x eq $y;               # already there

        $state->{loc}->{$taxi} = $y;
        $state->{owe}->{$p}    = taxi_rate( distance( $x, $y ) );
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

sub do_nothing ( $state, $p, $y ) {
    my $x = $state->{loc}->{$p};
    return [] if $x eq $y;
    return;
}

sub travel_by_foot ( $state, $p, $y ) {
    my $x = $state->{loc}->{$p};
    return if $x eq $y;
    return if distance( $x, $y ) > 2;    # more than 2 is too far to walk
    return [ 'walk', $p, $x, $y ];
}

sub travel_by_taxi ( $state, $p, $y ) {
    my $x = $state->{loc}->{$p};
    return unless $state->{cash}->{$p} >= taxi_rate( distance( $x, $y ) );
    return (
        [ 'call_taxi',  $p, $x ],
        [ 'ride_taxi',  $p, $y ],
        [ 'pay_driver', $p, $y ]
    );
}

$domain->declare_task_methods( 'travel', \&do_nothing, \&travel_by_foot,
    \&travel_by_taxi );
{
    note "Can we get Alice to the park?";
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => $state,
        todo_list => [ [ 'travel', 'alice', 'park' ] ]
    );

    is_deeply [ $planner->plan() ],
      [
        [qw(call_taxi alice home_a)], [qw(ride_taxi alice park)],
        [qw(pay_driver alice park)],
      ],
      'got the plan we expected';
}
{
    note "Now make a plan to get Alice and then Bob to the park";
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => $state,
        todo_list =>
          [ [ 'travel', 'alice', 'park' ], [ 'travel', 'bob', 'park' ] ],
    );

    is_deeply [ $planner->plan() ],
      [
        [qw(call_taxi alice home_a)], [qw(ride_taxi alice park)],
        [qw(pay_driver alice park)],  [qw(walk bob home_b park)]
      ],
      'got the plan we expected';

}

{

    note <<~EOF;
        Next, we'll use run_lazy_lookahead to try to get Alice to the park. With Pr = 1/2,
        the taxi won't arrive. In this case, run_lazy_lookahead will call find_plan again,
        and find_plan will return the same plan as before. This will happen repeatedly
        until either the taxi arrives or run_lazy_lookahead decides it has tried too many times.
        EOF

    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => $state,
        todo_list => [ [ 'travel', 'alice', 'park' ] ],
    );

    my $new_state = $planner->run_lazy_lookahead();
    is $new_state->{loc}->{alice}, 'park', 'alice is at the park';

    note "If it succeeded then Alice is at the park, and the planer is empty";

    $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => $new_state,
        todo_list => [ [ 'travel', 'alice', 'park' ] ],

    );

    is_deeply [ $planner->plan() ], [], 'got an empty plan';

}

done_testing;

