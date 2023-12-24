#!/usr/bin/env perl
use 5.38.0;
use lib 'lib';

use Test::More;
use Storable qw(dclone);
use PLHop;

my $domain = PLHop::Domain->new( name => 'backtracking_htn' );

my $state = { flag => -1, };

sub m_err ($s) { return ( [ 'putv', 0 ], [ 'getv', 1 ] ) }
sub m0    ($s) { return ( [ 'putv', 0 ], [ 'getv', 0 ] ) }
sub m1    ($s) { return ( [ 'putv', 1 ], [ 'getv', 1 ] ) }

$domain->declare_task_methods( 'put_it', \&m_err, \&m0, \&m1 );

sub m_need0 ($s) { return ( [ 'getv', 0 ] ) }
sub m_need1 ($s) { return ( [ 'getv', 1 ] ) }

$domain->declare_task_methods( 'need0',  \&m_need0 );
$domain->declare_task_methods( 'need1',  \&m_need1 );
$domain->declare_task_methods( 'need01', \&m_need0, \&m_need1 );
$domain->declare_task_methods( 'need10', \&m_need1, \&m_need0 );

$domain->declare_actions(
    putv => sub ( $s, $flag ) { $s->{flag} = $flag;               return $s; },
    getv => sub ( $s, $flag ) { return $s if $s->{flag} == $flag; return },
);

my $expect0 = [ [ 'putv', 0 ], [ 'getv', 0 ], [ 'getv', 0 ] ];
my $expect1 = [ [ 'putv', 1 ], [ 'getv', 1 ], [ 'getv', 1 ] ];

{
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => dclone($state),
        todo_list => [ ['put_it'], ['need0'] ],
    );

    is_deeply [ $planner->plan() ], $expect0, 'got exiected results (expect0)';
}
{
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => dclone($state),
        todo_list => [ ['put_it'], ['need01'] ],
    );

    is_deeply [ $planner->plan() ], $expect0, 'got exiected results (expect0)';
}
{
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => dclone($state),
        todo_list => [ ['put_it'], ['need10'] ],
    );

    is_deeply [ $planner->plan() ], $expect0, 'got exiected results (expect0)';
}
{
    my $planner = PLHop::Planner->new(
        domain    => $domain,
        state     => dclone($state),
        todo_list => [ ['put_it'], ['need1'] ],
    );

    is_deeply [ $planner->plan() ], $expect1, 'got exiected results (expect0)';
}

done_testing();
