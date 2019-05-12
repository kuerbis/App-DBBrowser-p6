use v6;
unit class App::DBBrowser::Subqueries;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;

use Term::Choose;
use Term::Choose::Screen :get-term-size;
use Term::Choose::LineFold :line-fold;
use Term::Form;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.d;


method !_tmp_history ( @saved_history ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $db = $!d<db>;
    my $keep = [];
    my @tmp_main_stmt;
    if $!i<history>{$db}<main> ~~ List { ##
        for $!i<history>{$db}<main>.list -> ( $stmt, $args ) {
            my $filled_stmt = $ax.stmt_placeholder_to_value( $stmt, $args, 1 );
            if $filled_stmt ~~ / ^ <-[\(]>+ FROM \s* \( \s* ( <-[)(]>+ ) \s* \) <-[\)]>* $ / { # Union, Join
                $filled_stmt = $0;
            }
            if $filled_stmt eq @tmp_main_stmt.any {
                next;
            }
            if $keep.elems == 7 {
                $!i<history>{$db}<main> = $keep;
                last;
            }
            $keep.push: [ $stmt, $args ];
            @tmp_main_stmt.push: $filled_stmt;
        }
    }
    my @tmp_substmts;
    if $!i<history>{$db}<substmt> ~~ List { ##
        @tmp_substmts = |$!i<history>{$db}<substmt>.unique;
        while @tmp_substmts.elems > 9 {
            @tmp_substmts.pop;
        }
    }
    my @tmp_history;
    for ( @tmp_substmts, @tmp_main_stmt ).flat.unique -> $stmt {
        if $stmt eq @saved_history.map({ .[1] }).any {
            next;
        }
        @tmp_history.push: [ $stmt, $stmt ];
    }
    return @tmp_history;
}


method !_get_history {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $h_ref = $ax.read_json( $!i<f_subqueries> );
    my @saved_history := $h_ref{ $!i<driver> }{ $!d<db> } // [];
    my @tmp_history := self!_tmp_history( @saved_history );
    my @lyt_history = |@saved_history, |@tmp_history; ##
    return @lyt_history;
}


method choose_subquery ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my @lyt_history := self!_get_history();
    my $edit_sq_file = 'Choose SQ:';
    my $readline     = '  Read-Line';
    my $old_idx = 1;

    SUBQUERY: loop {
        my @pre = $edit_sq_file, Any, $readline;
        my @choices = |@pre, |@lyt_history.map: { '- ' ~ $_[1] };
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v>, :prompt( '' ), :1index, :default( $old_idx ), :undef( '  <=' )
        );
        if ! $idx.defined || ! @choices[$idx].defined {
            return;
        }
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 1;
                next SUBQUERY;
            }
            $old_idx = $idx;
        }
        if @choices[$idx] eq $edit_sq_file {
            if self!_edit_sq_file() {
                @lyt_history := self!_get_history();
                @choices = |@pre, |@lyt_history.map: { '- ' ~ .[1] };
            }
            $ax.print_sql( $sql );
            next SUBQUERY;
        }
        my ( $prompt, $default );
        if @choices[$idx] eq $readline {
            $prompt = 'Enter SQ: ';
            $default = '';
        }
        else {
            $prompt = 'Edit SQ: ';
            $idx -= @pre.elems;
            $default = @lyt_history[$idx][0];
        }
        # Readline
        my $stmt = $tf.readline( $prompt, :$default, :1show-context );
        if ! $stmt.defined || ! $stmt.chars {
            $ax.print_sql( $sql );
            next SUBQUERY;
        }
        my $db = $!d<db>;
        $!i<history>{$db}<substmt>.unshift: $stmt;
        if $stmt !~~ / ^ \s* \( <-[)(]>+ \) \s* $ / {
            $stmt = "(" ~ $stmt ~ ")";
        }
        return $stmt;
    }
}


method !_edit_sq_file {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $driver = $!i<driver>;
    my $db = $!d<db>;
    my @pre = Any;
    my ( $add, $edit, $remove ) = ( '- Add', '- Edit', '- Remove' );
    my $any_change = 0;

    loop {
        my $top_lines = [ sprintf( 'Stored Subqueries:' ) ];
        my $h_ref = $ax.read_json( $!i<f_subqueries> );
        my @saved_history := $h_ref{$driver}{$db} // [];
        my @tmp_info = (
            |$top_lines,
            |@saved_history.map({ line-fold( $_[*-1], get-term-size().[0], '  ', '    ' ) }),
            ' '
        );
        my $info = @tmp_info.join: "\n";
        # Choose
        my $choice = $tc.choose(
            [ |@pre, $add, $edit, $remove ],
            |$!i<lyt_v_clear>, :prompt( 'Choose:' ), :$info, :undef( '  <=' )
        );
        my $changed = 0;
        if ! $choice.defined {
            return $any_change;
        }
        elsif $choice eq $add {
            $changed = self!_add_subqueries( @saved_history, $top_lines );
        }
        elsif $choice eq $edit {
            $changed = self!_edit_subqueries( @saved_history, $top_lines );
        }
        elsif $choice eq $remove {
            $changed = self!_remove_subqueries( @saved_history, $top_lines );
        }
        if $changed {
            if @saved_history.elems {
                $h_ref{$driver}{$db}<substmt> = @saved_history;
            }
            else {
                $h_ref{$driver}{$db}<substmt>:delete;
            }
            $ax.write_json( $!i<f_subqueries>, $h_ref );
            $any_change++;
        }
    }
}


method !_add_subqueries ( @saved_history, $top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my @tmp_history := self!_tmp_history( @saved_history );
    my @used;
    my $readline = '  Read-Line';
    my @pre = Any, $!i<_confirm>, $readline;
    my @bu;
    my @tmp_new;

    loop {
        my @tmp_info = (
            |$top_lines,
            |@saved_history.map({ line-fold( $_[1], get-term-size().[0], '  ', '    ' ) }),
        );
        if @tmp_new.elems {
            @tmp_info.push: |@tmp_new.map({ line-fold( $_[1], get-term-size().[0], '| ', '    ' ) });
        }
        @tmp_info.push: ' ';
        my $info = @tmp_info.join: "\n";
        my @choices = |@pre, |@tmp_history.map: {  '- ' ~ $_[1] };
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :prompt( 'Add:' ), :$info, :1index
        );
        if ! $idx {
            if @bu.elems {
                ( @tmp_new, @tmp_history, @used ) = |@bu.pop;
                next;
            }
            return;
        }
        elsif @choices[$idx] eq $!i<_confirm> {
            @saved_history.push: |@tmp_new;
            return 1;
        }
        elsif @choices[$idx] eq $readline {
            # Readline
            my $stmt = $tf.readline( 'Stmt: ', :$info, :1show-context, :1clear-screen );
            if ! $stmt.defined || ! $stmt.chars {
                next;
            }
            if $stmt ~~ / ^ \s* \( ( <-[)(]>+ ) \) \s* $ / {
                $stmt = $0;
            }
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars );
            # Readline
            my $name = $tf.readline( 'Name: ', :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                next;
            }
            @bu.push: [ [ |@tmp_new ], [ |@tmp_history ], [ |@used ] ];
            @tmp_new.push: [ $stmt, $name ];
        }
        else {
            @bu.push: [ [ |@tmp_new ], [ |@tmp_history ], [ |@used ] ];
            @used.push: |@tmp_history.splice: $idx - @pre.elems, 1;
            my $stmt = @used[*-1][0];
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars );
            # Readline
            my $name = $tf.readline( 'Name: ', :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                ( @tmp_new, @tmp_history, @used ) = |@bu.pop;
                next;
            }
            @tmp_new.push: [ $stmt, $name ];
        }
    }
}


method !_edit_subqueries ( @saved_history, $top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    if ! @saved_history.elems {
        return;
    }
    my @indexes;
    my @pre = Any, $!i<_confirm>;
    my @bu;
    my $old_idx = 0;
    my @unchanged_saved_history = @saved_history;

    STMT: loop {
        my $info = $top_lines.join: "\n";
        my @available;
        for 0 .. @saved_history.end -> $i { ##
            my $pre = $i == @indexes.any ?? '| ' !! '- ';
            @available.push: $pre ~ @saved_history[$i][1];
        }
        my @choices = |@pre, |@available;
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :prompt( 'Edit:' ), :$info, :1index, :default( $old_idx )
        );
        if ! $idx {
            if @bu.elems {
                ( @saved_history, @indexes ) = |@bu.pop;
                next STMT;
            }
            return;
        }
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 0;
                next STMT;
            }
            $old_idx = $idx;
        }
        if @choices[$idx] eq $!i<_confirm> {
            return 1;
        }
        else {
            $idx -= @pre.elems;
            my @tmp_info = |$top_lines, 'Edit:', '  BACK', '  CONFIRM';
            for 0 .. @saved_history.end -> $i {  ##
                my $stmt = @saved_history.[$i][1];
                my $pre = '  ';
                if $i == $idx {
                    $pre = '> ';
                }
                elsif $i == @indexes.any {
                    $pre = '| ';
                }
                my $folded_stmt = line-fold( $stmt, get-term-size().[0], $pre,  $pre ~ ( ' ' x 2 ) );
                @tmp_info.push: $folded_stmt;
            }
            @tmp_info.push: ' ';
            my $info = @tmp_info.join: "\n";
            # Readline
            my $stmt = $tf.readline( 'Stmt: ', :default( @saved_history[$idx][0] ), :$info, :1show-context, :1clear-screen );
            if ! $stmt.defined || ! $stmt.chars {
                next STMT;
            }
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars );
            my $default;
            if @saved_history[$idx][0] ne @saved_history[$idx][1] {
                $default = @saved_history[$idx][1];
            }
            # Readline
            my $name = $tf.readline( 'Name: ', :$default, :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                next STMT;
            }
            if $stmt ne @saved_history[$idx][0] || $name ne @saved_history[$idx][1] {
                @bu.push: [ [ |@saved_history ], [ |@indexes ] ];
                @saved_history[$idx] = [ $stmt, $name.chars ?? $name !! $stmt ];
                @indexes.push: $idx;
            }
        }
    }
}


method !_remove_subqueries ( @saved_history, $top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    if ! @saved_history.elems {
        return;
    }
    my @backup;
    my @remove;

    loop {
        my @tmp_info = (
            |@$top_lines,
            'Remove:',
            |@remove.map({ line-fold( $_, get-term-size().[0], '  ', '    ' ) }),
            ' '
        );
        my $info = @tmp_info.join: "\n";
        my @pre = Any, $!i<_confirm>;
        my @choices = |@pre, |@saved_history.map: { '- ' ~ $_[1] };
        my $idx = $tc.choose(
            @choices,
            :prompt( 'Choose:' ), :$info, :3layout, :1index, :undef( '  BACK' )
        );
        if ! $idx {
            if @backup.elems {
                @saved_history = @backup.pop;
                @remove.pop;
                next;
            }
            return;
        }
        elsif @choices[$idx] eq $!i<_confirm> {
            if ! @remove.elems {
                return;
            }
            return 1;
        }
        @backup.push: [ |@saved_history ];
        my $ref = @saved_history.splice; $idx - @pre.elems, 1;
        @remove.push: $ref[1];
    }
}


