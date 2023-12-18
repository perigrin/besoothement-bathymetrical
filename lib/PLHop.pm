use 5.38.0;
use warnings;

use experimental 'class';

use Scalar::Util qw(blessed);

class PLHop::State {
    use Storable qw(dclone);

    field $name : param;
    field $data : param = {};

    method name() { $name }
    method keys() { keys %$data }
    method get ($key)           { $data->{$key} }
    method set ( $key, $value ) { $data->{$key} = $value }

    method copy ($new_name) {
        blessed($self)->new( name => $new_name, data => dclone($data) );
    }
}

class PLHop::Multigoal {
    field $name : param;
    field $data : param;

    method name() { $name }
    method keys() { keys %$data }
    method get ($key)           { $data->{$key} }
    method set ( $key, $value ) { $data->{$key} = $value }

    method copy ($new_name) {
        blessed($self)->new( name => $new_name, data => dclone($data) );
    }
}

class PLHop::Domain {
    use List::Util qw(uniq);
    use Carp       qw(confess);

    field $name : param;

    field %actions;
    method get_action      ( $name //= confess ) { $actions{$name} }
    method declare_actions (%new) { %actions = ( %actions, %new ) }

    field %commands;
    method get_command      ($name) { $commands{$name} }
    method declare_commands (%new)  { %commands = ( %commands, %new ) }

    field %task_methods = (
        '_verify_g'  => [ \&m_verify_g ],
        '_verify_mg' => [ \&m_verify_mg ],
    );
    method get_task_methods ($name) { $task_methods{$name}->@* }

    method declare_task_methods ( $name, @methods ) {
        my $old_methods = $task_methods{$name} // [];
        $task_methods{$name} = [ uniq( @methods, @$old_methods ) ];
        return %task_methods;
    }

    field %unigoal_methods;
    method get_unigoal_methods ($name) { $unigoal_methods{$name} }

    method declare_unigoal_methods ( $state_var_name, @methods ) {
        my $old_methods = $unigoal_methods{$name} // [];
        $unigoal_methods{$name} = [ uniq( @methods, @$old_methods ) ];
        return %unigoal_methods;
    }

    field @multigoal_methods;
    method get_multi_goal_methods() { @multigoal_methods }

    method declare_multigoal_methods (@methods) {
        @multigoal_methods = uniq( @methods, @multigoal_methods );
    }

}

class PLHop::Planner {
    use Storable qw(dclone);

    field $domain : param;
    field $state : param     = {};
    field $todo_list : param = [];

    method _seek_plan ( $s, $list, $plan, $depth ) {
        return $plan unless @$list;

        my sub lookup_handler ($item) {
            return unless $item && @$item;
            my ($task) = @$item;

            return '_apply_action' if $domain->get_action($task);
            return '_refine_task'  if $domain->get_task_methods($task);

      #        return '_refine_unigoal'   if $domain->get_unigoal_method($task);
      #        return '_refine_multigoal' if $item isa 'PLHop::MultiGoal';
            return;
        }
        my ( $item, @rest ) = @$list;
        my $handler = lookup_handler($item) // return $plan;

        return $self->$handler( $s, $item, \@rest, $plan, $depth );
    }

    method _apply_action ( $s, $item, $list, $plan, $depth ) {
        my ( $name, @args ) = @$item;
        my $action    = $domain->get_action($name) // return;
        my $new_state = $action->( dclone($s), @args );

        return unless $new_state;
        return $self->_seek_plan( $new_state, $list, [ @$plan, $item ],
            $depth + 1 );
    }

    method _refine_task ( $s, $item, $list, $plan, $depth ) {
        my ( $name, @args ) = @$item;
        my @methods = $domain->get_task_methods($name);

        for my $method (@methods) {
            my @subtasks = $method->( $s, @args );
            if ( @subtasks > 0 ) {
                return $self->_seek_plan( $s, [ @subtasks, @$list ],
                    $plan, $depth + 1 );
            }
        }
        return;
    }

    method plan ( $s = $state, $list = $todo_list ) {
        $self->_seek_plan( $s, $list, [], 0 )->@*;
    }

    method run_lazy_lookahead (
        $s         = dclone($state),    # we modify the state, so take a copy
        $list      = $todo_list,
        $max_tries = 10
      )
    {
        for ( 0 .. $max_tries ) {
            my @plan = $self->plan( $s, $list );
            return $s unless @plan;

            for my $action (@plan) {
                my ( $name, @rest ) = @$action;

                my $command = $domain->get_command($name)
                  // $domain->get_action($name);

                my $new_state = $command->( dclone($s), @rest ) // last;
                $s = $new_state;
            }
        }
        return $s;
    }
}

my sub m_verify_g ( $state, $method, $state_var, $arg, $desired_val, $depth ) {
    if ( $state->get($state_var)->{$arg} != $desired_val ) {
        die
"depth $depth: method $method didn't achieve goal $state_var [$arg] = $desired_val";
    }
    return [];
}

my sub m_verify_mg ( $state, $method, $multigoal, $depth ) {
    my %goals = goals_not_achieved( $state, $multigoal );
    if (%goals) {
        die "depth $depth: method $method didn't achieve $multigoal";
    }
    return [];
}

my sub goals_not_achieved ( $state, $multigoal ) {
    my %unachieved = ();
    for my $name ( $multigoal->keys() ) {
        for my $arg ( keys $multigoal->get($name)->%* ) {
            my $val = $multigoal->get($name)->{$arg};
            if ( $val != $state->get($name)->{$arg} ) {
                $unachieved{$name} //= {};
                $unachieved{$name}->{$arg} = $val;
            }
        }
    }
    return %unachieved;
}

