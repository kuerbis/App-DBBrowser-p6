use v6;
unit class App::DBBrowser::GetContent::Filter;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Choose::Util :insert-sep;
use Term::Form;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.d;

has $!empty_to_null;


method input_filter ( $sql, $default_e2n ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $waiting = 'Working ... ';
    my $confirm          = '    OK';
    my $back             = '    <<';
    my $input_cols       = 'Choose_Cols';
    my $input_rows       = 'Choose_Rows';
    my $input_rows_range = 'Range_Rows';
    my $add_col          = 'Add_Col';
    my $empty_to_null    = 'Empty2NULL';
    my $merge_rows       = 'Merge_Rows ';
    my $split_table      = 'Split_Table';
    my $split_col        = 'Split_Col';
    my $replace          = 'Replace';
    my $reparse          = 'ReParse',
    my $cols_to_rows     = 'Cols2Rows';
    my $reset            = 'Reset';
    $!empty_to_null = $default_e2n;
    my Array @bu = |$sql<insert_into_args>.map: { [ |$_ ] };
    $!i<idx_added_cols> = [];
    my $old_idx = 0;

    FILTER: loop {
        $ax.print_sql( $sql );
        my @choices =
            Any,      $input_cols, $input_rows,  $input_rows_range, $add_col,   $empty_to_null, $reset,
            $confirm, $replace,    $split_table, $merge_rows,       $split_col, $cols_to_rows,  $reparse;
        # Choose
        my $idx = $tc.choose(
            @choices,
            :prompt( 'Filter:' ), :0layout, :0order, :90max-width, :1index, :default( $old_idx ), :undef( $back )
        );
        $ax.print_sql( $sql, $waiting );
        if ! $idx {
            $sql<insert_into_args> = [];
            return;
        }
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 0;
                next FILTER;
            }
            $old_idx = $idx;
        }
        given @choices[$idx] {
            when $reset {
                $sql<insert_into_args> = [ |@bu.map: { [ |$_ ] } ];
                $!empty_to_null = $default_e2n;
                next FILTER
            }
            when $confirm {
                if $!empty_to_null {
                    $ax.print_sql( $sql, $waiting );
                    $sql<insert_into_args> = [ |$sql<insert_into_args>.map: { [ |$_.map: { ($_//'').chars ?? $_ !! Any } ] } ];
                }
                return 1;
            }
            when $reparse {
                return -1;
            }
            when $input_cols {
                self!_choose_columns( $sql );
            }
            when $input_rows {
                self!_choose_rows( $sql, $waiting );
            }
            when $input_rows_range {
                self!_range_of_rows( $sql, $waiting );
            }
            when $empty_to_null {
                self!_empty_to_null();
            }
            when $add_col {
                self!_add_column( $sql );
            }
            when $cols_to_rows {
                self!_transpose_rows_to_cols( $sql );
            }
            when $merge_rows {
                self!_merge_rows( $sql, $waiting );
            }
            when $split_table {
                self!_split_table( $sql, $waiting );
            }
            when $split_col {
                self!_split_column( $sql, $waiting );
            }
            when $replace {
                self!_search_and_replace( $sql, $waiting );
            }
        }
    }
}


method !_empty_to_null {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my %tmp = :empty_to_null( $!empty_to_null );
    $tu.settings-menu(
        [
            [ 'empty_to_null', "- Empty fields to NULL", [ 'NO', 'YES' ] ],
        ],
        %tmp
    );
    $!empty_to_null = %tmp<empty_to_null>;
}



method !_prepare_header_and_mark ( $aoa ) { ##
    my $row_count = $aoa.elems;
    my $col_count = $aoa[0].elems;
    my @empty = 0 xx $col_count;
    COL: for ^$col_count -> $c { #
        for ^$row_count -> $r {
            if ($aoa[$r][$c]//'').chars {
                next COL;
            }
            ++@empty[$c];
        }
    }
    my $mark = [];
    my $header = [];
    for 0 .. @empty.end -> $i {
        if @empty[$i] < $row_count {
            $mark.push: $i;
            if ($aoa[0][$i]//'').chars {
                $header[$i] = $aoa[0][$i];
            }
            else {
                $header[$i] = 'no_header';
            }
        }
        else {
            $header[$i] = '[Empty]';
        }
    }
    if $mark.elems == $col_count {
        $mark = []; # no preselect if all cols have entries
    }
    return $header, $mark;
}



method !_choose_columns ( $sql ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $aoa = $sql<insert_into_args>;
    my ( $header, $mark ) = self!_prepare_header_and_mark( $aoa );
    # Choose
    my $col_idx = $tu.choose-a-subset(
        $header,
        :back( '<<' ), :confirm( $!i<ok> ), :1index, :$mark, :0layout, :1all-by-default, :name( 'Cols: ' ) # :$mark
        :0clear-screen, :0order
    );
    if ! $col_idx.defined {
        return;
    }
    $sql<insert_into_args> = [ |$aoa.map: { [ |$_[|$col_idx] ] } ];
    return 1;
}


method !_choose_rows ( $sql, $waiting ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $aoa = $sql<insert_into_args>;
    my %group; # group rows by the number of cols
    for 0 .. $aoa.end -> $row_idx {
        my $col_count = $aoa[$row_idx].elems;
        %group{$col_count}.push: $row_idx;
    }
    # sort keys by group size
    my @keys_sorted = %group.keys.sort: { %group{$^b}.elems <=> %group{$^a}.elems };
    $sql<insert_into_args> = []; # refers to a new empty array - this doesn't delete $aoa

    GROUP: loop {
        $ax.print_sql( $sql, $waiting );
        my $row_idxs = [];
        my @choices_rows;
        if @keys_sorted.elems == 1 {
            $row_idxs = [ 0 .. $aoa.end ];
            @choices_rows = |$aoa.map: { ( $_ // '' ).join: ',' };
        }
        else {
            my @choices_groups;
            my $len = insert-sep( %group{@keys_sorted[0]}.elems, $!o<G><thsd-sep> ).chars;
            for @keys_sorted -> $col_count {
                my $row_count = %group{$col_count}.elems;
                my $row_str = $row_count == 1 ?? 'row  has ' !! 'rows have';
                my $col_str = $col_count == 1 ?? 'column ' !! 'columns';
                @choices_groups.push: sprintf '  %*s %s %2d %s',
                    $len, insert-sep( $row_count, $!o<G><thsd-sep> ), $row_str,
                    $col_count, $col_str;
            }
            my @pre = Any;
            # Choose
            my $idx = $tc.choose(
                [ |@pre, |@choices_groups ],
                |$!i<lyt_v>, :prompt( 'Choose group:' ), :1index, :undef( '  <=' )
            );
            if ! $idx {
                $sql<insert_into_args> = $aoa;
                return;
            }
            $ax.print_sql( $sql, $waiting );
            $row_idxs = %group{ @keys_sorted[$idx-@pre.elems] };
            @choices_rows = |$aoa[|$row_idxs].map: { ($_//'').join: ',' };
        }

        loop {
            my @pre = Any, $!i<ok>;
            # Choose
            my @idx = $tc.choose-multi(
                [ |@pre, |@choices_rows ],
                |$!i<lyt_v>, :prompt( 'Choose rows:' ), :1index, :meta-items( |( 0 .. @pre.end ) ),
                :2include-highlighted, :undef( '<<' )
            );
            $ax.print_sql( $sql );
            if ! @idx[0] {
                if @keys_sorted.elems == 1 {
                    $sql<insert_into_args> = $aoa;
                    return;
                }
                $sql<insert_into_args> = [];
                next GROUP;
            }
            if @idx[0] == @pre.end {
                @idx.shift;
                for @idx -> $i {
                    my $idx = $row_idxs[$i-@pre.elems];
                    $sql<insert_into_args>.push: $aoa[$idx];
                }
                $ax.print_sql( $sql );
                if ! $sql<insert_into_args>.elems {
                    $sql<insert_into_args> = [ |$aoa[|$row_idxs] ];
                }
                return;
            }
            for @idx -> $i {
                my $idx = $row_idxs[$i-@pre.elems];
                $sql<insert_into_args>.push: $aoa[$idx];
            }
            $ax.print_sql( $sql );
        }
    }
}


method !_range_of_rows ( $sql, $waiting ) {
    my $aoa = $sql<insert_into_args>;
    my ( $first_row, $last_row ) = self!_choose_range( $sql, $waiting );
    if ! $first_row.defined || ! $last_row.defined {
        return;
    }
    $sql<insert_into_args> = [ |$aoa[$first_row .. $last_row] ];
    return;
}


method !_choose_range ( $sql, $waiting ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $aoa = $sql<insert_into_args>;
    my $tc = Term::Choose.new( |$!i<default> );
    my @pre = Any;
    my @choices = |@pre, |$aoa.map: { ($_//'').join: ',' }
    # Choose
    my $first_idx = $tc.choose(
        @choices,
        |$!i<lyt_v>, :prompt( "Choose FIRST ROW:" ), :1index, :undef( '<<' )
    );
    if ! $first_idx {
        return;
    }
    my $first_row = $first_idx - @pre.elems;
    @choices[$first_row + @pre.elems] = '* ' ~ @choices[$first_row + @pre.elems];
    $ax.print_sql( $sql );
    # Choose
    my $last_idx = $tc.choose(
        @choices,
        |$!i<lyt_v>, :prompt( "Choose LAST ROW:" ), :default( $first_row ), :1index, :undef( '<<' )
    );
    if ! $last_idx {
        return;
    }
    my $last_row = $last_idx - @pre.elems;
    if $last_row < $first_row {
        $ax.print_sql( $sql );
        # Choose
        $tc.pause(
            [ "Last row ($last_row) is less than First row ($first_row)!" ],
            :prompt( 'Press ENTER' ), :undef( '<<' )
        );
        return;
    }
    return $first_row, $last_row;
}


method !_add_column ( $sql ) {
    my $aoa = $sql<insert_into_args>;
    my $new_last_idx = $aoa[0].end + 1;
    for $aoa.list -> $row {
        while $row.end > $new_last_idx {
            $row.pop;
        }
    }
    $aoa[0][$new_last_idx] = 'col' ~ ( $new_last_idx + 1 );
    $!i<idx_added_cols>.push: $new_last_idx;
    $sql<insert_into_args> = $aoa;
    return;
}


method !_transpose_rows_to_cols ( $sql ) {
    my $aoa = $sql<insert_into_args>;
    my $tmp_aoa = [];
    for 0 .. $aoa.end -> $row {
        for 0 .. $aoa[$row].end -> $col {
            $tmp_aoa[$col][$row] = $aoa[$row][$col];
        }
    }
    $sql<insert_into_args> = $tmp_aoa;
    return;
}


method !_merge_rows ( $sql, $waiting ) {
    my ( $first_row, $last_row ) = self!_choose_range( $sql, $waiting );
    if ! $first_row.defined  || ! $last_row.defined {
        return;
    }
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $ax.print_sql( $sql, $waiting );
    my $aoa = $sql<insert_into_args>;
    my $first = 0;
    my $last = 1;
    my @rows_to_merge = |$aoa[ $first_row .. $last_row ];
    my $merged = [];
    for 0 .. @rows_to_merge[0].end -> $col {
        my @tmp;
        for 0 .. @rows_to_merge.end -> $row {
            next if ! @rows_to_merge[$row][$col].defined;
            next if @rows_to_merge[$row][$col] ~~ / ^ \s* $ /;
            @rows_to_merge[$row][$col].=trim;
            @tmp.push: @rows_to_merge[$row][$col];
        }
        $merged[$col] = @tmp.join: ' ';
    }
    my $col_number = 0;
    my $fields = [ |$merged.map: { [ ++$col_number, .defined ?? .Str !! '' ] } ];
    # Fill_form
    my $form = $tf.fill-form(
        $fields,
        :prompt( 'Edit result:' ), :2auto-up, :confirm( '  CONFIRM' ), :back( '  BACK   ' )
    );
    if ! $form {
        return;
    }
    $merged = [ |$form.map: { .[1] } ];
    $aoa.splice: $first_row, ( $last_row - $first_row + 1 ), $merged; # modifies $aoa
    $sql<insert_into_args> = $aoa;
    return;
}


method !_split_table ( $sql, $waiting ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $aoa = $sql<insert_into_args>;
    # Choose
    my $col_count = $tu.choose-a-number(
        $aoa[0].elems.chars,
        :name( 'Number columns new table: ' ), :1small-first
    );
    if ! $col_count.defined {
        return;
    }
    if $aoa[0].elems < $col_count {
        $tc.pause(
            [ 'Chosen number bigger than the available columns!' ],
            :prompt( 'Close with ENTER' )
        );
        return;
    }
    if $aoa[0].elems % $col_count {
        $tc.pause(
            [ 'The number of available columns cannot be divided by the chosen number without rest!' ],
            :prompt( 'Close with ENTER' )
        );
        return;
    }
    $ax.print_sql( $sql, $waiting );
    my $begin = 0;
    my $end   = $col_count - 1;
    my $tmp = [];

    loop {
        for $aoa.list -> $row {
            $tmp.push: [ |$row[ $begin .. $end ] ];
        }
        $begin = $end + 1;
        if $begin > $aoa[0].end {
            last;
        }
        $end = $end + $col_count;
    }
    $sql<insert_into_args> = $tmp;
}


method !_split_column ( $sql, $waiting ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    my $aoa = $sql<insert_into_args>;
    my ( $header, $mark ) = self!_prepare_header_and_mark( $aoa );
    my @pre = Any;
    # Choose
    my $idx = $tc.choose(
        [ |@pre, |$header ],
        :prompt( 'Choose Column:' ), :1index
    );
    if ! $idx {
        return;
    }
    $idx -= @pre.elems;
    # Readline
    my $sep = $tf.readline( 'Separator: ' );
    if ! $sep.defined {
        return;
    }
    # Readline
    my $left_trim = $tf.readline( 'Left trim: ', '\s+' );
    if ! $left_trim.defined {
        return;
    }
    # Readline
    my $right_trim = $tf.readline( 'Right trim: ', '\s+' );
    if ! $right_trim.defined {
        return;
    }
    $ax.print_sql( $sql, $waiting );
    for $aoa.list -> $row { # modifies $aoa ?
        my $col = $row.splice: $idx, 1;
        my @split_col = $col.split: /$sep/;
        for @split_col -> $c {
            $c.=trim-leading  if $left_trim.chars;
            $c.=trim-trailing if $right_trim.chars;
        }
        $row.splice: $idx, 0, @split_col;
    }
    $sql<insert_into_args> = $aoa;
}


method !_search_and_replace ( $sql, $waiting ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my $tu = Term::Choose::Util.new( |$!i<default> );

    SEARCH_AND_REPLACE: loop {
        my $mods = [ 'g', 'i', 'e', 'e' ];
        my $chosen_mods = [];
        my $info_fmt = "s/%s/%s/%s;\n";
        my Array @bu;

        MODIFIERS: loop {
            $ax.print_sql( $sql, $waiting );
            my $mods_str = $chosen_mods.sort({ $^b cmp $^a }).join: '';
            my $info = sprintf $info_fmt, '', '', $mods_str;
            my @pre = Any, $!i<ok>;
            # Choose
            my @idx = $tc.choose-multi(
                [ |@pre, |$mods.map: { "[$_]" } ],
                |$!i<lyt_h>, :prompt( 'Modifieres: ' ), :$info, :meta-items( |( 0 .. @pre.end ) ),
                :2include-highlighted, :1index
            );
            my $last;
            if ! @idx[0] {
                if @bu {
                    ( $mods, $chosen_mods ) = |@bu.pop;
                    next MODIFIERS;
                }
                return;
            }
            elsif @idx[0] eq @pre.end {
                $last = @idx.shift;
            }
            @bu.push: [ [ |$mods ], [ |$chosen_mods ] ];
            for @idx.reverse -> $i {
                $chosen_mods.push: $mods.splice: $i - @pre.elems, 1;
            }
            if $last.defined {
                last MODIFIERS;
            }
        }
        my $insensitive = $chosen_mods.first: 'i';
        my $globally = $chosen_mods.first: 'g';
        my @eval = $chosen_mods.grep: { $_ eq 'e' };
        my $mods_str = ( $insensitive, $globally, |@eval ).join: '';
        my $info = sprintf $info_fmt, '', '', $mods_str;
        $ax.print_sql( $sql, $waiting );
        # Readline
        my $pattern = $tf.readline( 'Pattern: ', :$info );
        if ! $pattern.defined {
            next SEARCH_AND_REPLACE;
        }
        $info = sprintf $info_fmt, $pattern, '', $mods_str;
        $ax.print_sql( $sql, $waiting );
        my $c; # counter available in the replacement
        # Readline
        my $replacement = $tf.readline( 'Replacement: ', :$info );
        if ! $replacement.defined {
            next SEARCH_AND_REPLACE;
        }
        $info = sprintf $info_fmt, $pattern, $replacement, $mods_str;
        $ax.print_sql( $sql, $waiting );
        my $aoa = $sql<insert_into_args>;
        my ( $header, $mark ) = self!_prepare_header_and_mark( $aoa );
        # Choose
        my $col_idx = $tu.choose-a-subset(
            $header,
            :back( '<<' ), :confirm( $!i<ok> ), :1index, :0layout, :$info, :name( 'Columns: ' )
            :0clear-screen, :1all-by-default
        );
        if ! $col_idx.defined {
            next SEARCH_AND_REPLACE;
        }
        $ax.print_sql( $sql, $waiting );
        my $regex;
        if $insensitive {
            $regex = rx{ :i <$pattern> };
        }
        else {
            $regex = rx{ <$pattern> };
        }
        my $g;
        if $globally {
            $g = True;
        }
        for $aoa.list -> $row { # modifies $aoa
            for $col_idx.list -> $i {
                $c = 0; ###
                if ! $row[$i].defined {
                    next;
                }
                if ! @eval.elems {
                    $row[$i].=subst( $regex, $replacement, :$g );
                }
                elsif @eval.elems == 1 {
                    $row[$i].=subst( $regex, { $replacement.EVAL }, :$g );
                }
                elsif @eval.elems == 2 {
                    $row[$i].=subst( $regex, { ( $replacement.EVAL ).EVAL }, :$g );
                }
            }
        }
        $sql<insert_into_args> = $aoa;
        return;
    }
}




