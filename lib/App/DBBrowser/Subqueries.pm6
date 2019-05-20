use v6;
unit class App::DBBrowser::Subqueries; # p5

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Choose::Screen :get-term-size;
use Term::Choose::LineFold :line-fold;
use Term::Form;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.d;


method !_tmp_history ( Array $history_HD ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $db = $!d<db>;
    my Array @keep;
    my Str @main_queries;
    if $!i<history>{$db}<main> ~~ List { ##
        for $!i<history>{$db}<main>.list -> ( $stmt, $args ) {
            my $filled_stmt = $ax.stmt_placeholder_to_value( $stmt, $args, 1 );
            if $filled_stmt ~~ / ^ <-[\(]>+ FROM \s* \( \s* ( <-[)(]>+ ) \s* \) <-[\)]>* $ / { # Union, Join
                $filled_stmt = $0.Str;
            }
            if $filled_stmt eq @main_queries.any {
                next;
            }
            if @keep.elems == 7 {
                $!i<history>{$db}<main> = @keep;
                last;
            }
            @keep.push: [ $stmt, $args ];
            @main_queries.push: $filled_stmt;
        }
    }
    my Str @sub_queries;
    if $!i<history>{$db}<substmt> ~~ List { ##
        @sub_queries = |$!i<history>{$db}<substmt>.unique;
        while @sub_queries.elems > 9 {
            @sub_queries.pop;
        }
    }
    my Array $history_RAM = [];
    for ( @sub_queries, @main_queries ).flat.unique -> $stmt {
        if $stmt eq $history_HD.map({ .[1] }).any {
            next;
        }
        $history_RAM.push: [ $stmt, $stmt ];
    }
    return $history_RAM;
}


method !_get_history {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $h_ref = $ax.read_json: $!i<f_subqueries>;
    my Array $history_HD = $h_ref{ $!i<driver> }{ $!d<db> } // [];
    my Array $history_RAM = self!_tmp_history( $history_HD );
    return [ |$history_HD, |$history_RAM ];
}


method choose_subquery ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my Array $history_comb = self!_get_history();
    my $edit_sq_file = 'Choose SQ:';
    my $readline     = '  Read-Line';
    my $old_idx = 1;

    SUBQUERY: loop {
        my @pre = $edit_sq_file, Any, $readline;
        my @choices = |@pre, |$history_comb.map: { '- ' ~ $_[1] };
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
            if self!_subqueries_file() {
                $history_comb = self!_get_history();
                @choices = |@pre, |$history_comb.map: { '- ' ~ .[1] };
            }
            $ax.print_sql( $sql );
            next SUBQUERY;
        }
        my ( $prompt, $default );
        #my ( $info, $default );
        if @choices[$idx] eq $readline {
            $prompt = 'Enter SQ: ';
            #$info = 'Enter SQ: ';
            $default = '';
        }
        else {
            $prompt = 'Edit SQ: ';
            #$info = 'Edit SQ: ';
            $idx -= @pre.elems;
            $default = $history_comb[$idx][0];
        }
        # Readline
        my $stmt = $tf.readline( $prompt, :$default, :1show-context );
        #my $stmt = $tf.readline( '', :$info, :$default, :1show-context ); # rl
        if ! $stmt.defined || ! $stmt.chars {
            $ax.print_sql( $sql );
            next SUBQUERY;
        }
        $!i<history>{$!d<db>}<substmt>.unshift: $stmt;
        if $stmt !~~ / ^ \s* \( <-[)(]>+ \) \s* $ / {
            $stmt = "(" ~ $stmt ~ ")";
        }
        return $stmt;
    }
}


method !_subqueries_file {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $driver = $!i<driver>;
    my $db = $!d<db>;
    my @pre = Any;
    my ( $add, $edit, $remove ) = ( '- Add', '- Edit', '- Remove' );
    my $any_change = 0;

    loop {
        my Str @top_lines = 'Stored Subqueries:';
        my $h_ref = $ax.read_json: $!i<f_subqueries>;
        my Array $history_HD = $h_ref{$driver}{$db} // [];
        my Str @tmp_info = (
            |@top_lines,
            |$history_HD.map({ |line-fold( $_[1], get-term-size().[0], '  ', '    ' ) }),
            ' '
        );
        my Str $info = @tmp_info.join: "\n";
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
            $changed = self!_add_subqueries( $history_HD, @top_lines );
        }
        elsif $choice eq $edit {
            $changed = self!_edit_subqueries( $history_HD, @top_lines );
        }
        elsif $choice eq $remove {
            $changed = self!_remove_subqueries( $history_HD, @top_lines );
        }
        if $changed {
            if $history_HD.elems {
                $h_ref{$driver}{$db} = $history_HD;
            }
            else {
                $h_ref{$driver}{$db}:delete;
            }
            $ax.write_json: $!i<f_subqueries>, $h_ref;
            $any_change++;
        }
    }
}


method !_add_subqueries ( Array $history_HD, Str @top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my Array $history_RAM = self!_tmp_history( $history_HD );
    my Array $saved_new = [];
    my Array $used = [];
    my Array @bu;
    my $readline = '  Read-Line';
    my @pre = Any, $!i<_confirm>, $readline;

    loop {
        my Str @tmp_info = (
            |@top_lines,
            |$history_HD.map({ |line-fold( $_[1], get-term-size().[0], '  ', '    ' ) }),
        );
        if $saved_new.elems {
            @tmp_info.push: |$saved_new.map: { |line-fold( $_[1], get-term-size().[0], '| ', '    ' ) };
        }
        @tmp_info.push: ' ';
        my Str $info = @tmp_info.join: "\n";
        my @choices = |@pre, |$history_RAM.map: {  '- ' ~ $_[1] };
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :prompt( 'Add:' ), :$info, :1index
        );
        if ! $idx {
            if @bu.elems {
                ( $saved_new, $history_RAM, $used ) = |@bu.pop;
                next;
            }
            return;
        }
        elsif @choices[$idx] eq $!i<_confirm> {
            $history_HD.push: |$saved_new;
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
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars ).join: "\n";
            # Readline
            my $name = $tf.readline( 'Name: ', :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                next;
            }
            @bu.push: [ [ |$saved_new ], [ |$history_RAM ], [ |$used ] ];
            $saved_new.push: [ $stmt, $name ];
        }
        else {
            @bu.push: [ [ |$saved_new ], [ |$history_RAM ], [ |$used ] ];
            $used.push: |$history_RAM.splice: $idx - @pre.elems, 1;
            my $stmt = $used[*-1][0];
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars ).join: "\n";
            # Readline
            my $name = $tf.readline( 'Name: ', :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                ( $saved_new, $history_RAM, $used ) = |@bu.pop;
                next;
            }
            $saved_new.push: [ $stmt, $name ];
        }
    }
}


method !_edit_subqueries ( Array $history_HD, Str @top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    if ! $history_HD.elems {
        return;
    }
    my Array @unchanged_history_HD = $history_HD;
    my Int @indexes;
    my Array @bu;
    my @pre = Any, $!i<_confirm>;
    my $old_idx = 0;

    STMT: loop {
        my $info = @top_lines.join: "\n";
        my Str @available;
        for 0 .. $history_HD.end -> $i { ##
            my $pre = $i == @indexes.any ?? '| ' !! '- ';
            @available.push: $pre ~ $history_HD[$i][1];
        }
        my @choices = |@pre, |@available;
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :prompt( 'Edit:' ), :$info, :1index, :default( $old_idx )
        );
        if ! $idx {
            if @bu.elems {
                ( $history_HD, @indexes ) = |@bu.pop;
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
            my Str @tmp_info = |@top_lines, 'Edit:', '  BACK', '  CONFIRM';
            for 0 .. $history_HD.end -> $i {  ##
                my $stmt = $history_HD.[$i][1];
                my $pre = '  ';
                if $i == $idx {
                    $pre = '> ';
                }
                elsif $i == @indexes.any {
                    $pre = '| ';
                }
                my $folded_stmt = line-fold( $stmt, get-term-size().[0], $pre,  $pre ~ ( ' ' x 2 ) ).join: "\n";
                @tmp_info.push: $folded_stmt;
            }
            @tmp_info.push: ' ';
            my $info = @tmp_info.join: "\n";
            # Readline
            my $stmt = $tf.readline( 'Stmt: ', :default( $history_HD[$idx][0] ), :$info, :1show-context, :1clear-screen );
            if ! $stmt.defined || ! $stmt.chars {
                next STMT;
            }
            my $folded_stmt = "\n" ~ line-fold( 'Stmt: ' ~ $stmt, get-term-size().[0], '', ' ' x 'Stmt: '.chars ).join: "\n";
            my $default;
            if $history_HD[$idx][0] ne $history_HD[$idx][1] {
                $default = $history_HD[$idx][1];
            }
            # Readline
            my $name = $tf.readline( 'Name: ', :$default, :info( $info ~ $folded_stmt ), :1show-context );
            if ! $name.defined  {
                next STMT;
            }
            if $stmt ne $history_HD[$idx][0] || $name ne $history_HD[$idx][1] {
                @bu.push: [ [ |$history_HD ], [ |@indexes ] ];
                $history_HD[$idx] = [ $stmt, $name.chars ?? $name !! $stmt ];
                @indexes.push: $idx;
            }
        }
    }
}


method !_remove_subqueries ( Array $history_HD, Str @top_lines ) {
    my $tc = Term::Choose.new( |$!i<default> );
    if ! $history_HD.elems {
        return;
    }
    my Array @bu;
    my Str @remove;

    loop {
        my Str @tmp_info = (
            |@top_lines,
            'Remove:',
            |@remove.map({ |line-fold( $_, get-term-size().[0], '  ', '    ' ) }),
            ' '
        );
        my $info = @tmp_info.join: "\n";
        my @pre = Any, $!i<_confirm>;
        my @choices = |@pre, |$history_HD.map: { '- ' ~ $_[1] };
        my $idx = $tc.choose(
            @choices,
            :prompt( 'Choose:' ), :$info, :2layout, :1index, :undef( '  BACK' )
        );
        if ! $idx {
            if @bu.elems {
                $history_HD = |@bu.pop;
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
        @bu.push: [ |$history_HD ];
        my ( $stmt, $name ) = $history_HD.splice( $idx - @pre.elems, 1 )[0]; # [0]
        @remove.push: $name;
    }
}


