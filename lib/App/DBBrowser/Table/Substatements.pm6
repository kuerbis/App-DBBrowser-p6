use v6;
unit class App::DBBrowser::Table::Substatements;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Choose::Util;

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;
use App::DBBrowser::Table::Substatements::Operators;

has $.i;
has $.o;
has $.d;

has $!distinct  = "DISTINCT";
has $!all       = "ALL";
has $!asc       = "ASC";
has $!desc      = "DESC";
has $!and       = "AND";
has $!or        = "OR";


method select ( $sql ) {
    my $clause = 'select';
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my $expand_sign = $!i<expand_signs>[$sign_idx];
    my @pre = Any, $!i<ok>, $expand_sign ?? $expand_sign !! |();
    my @choices;
    if $sql<group_by_cols>.elems || $sql<aggr_cols>.elems {
        @choices = |@pre, |$sql<group_by_cols>, |$sql<aggr_cols>;
    }
    else {
        @choices = |@pre, |$sql<cols>;
    }
    $sql<select_cols> = [];
    #$sql<alias> = { |$sql<alias> };
    my @bu;

    COLUMNS: loop {
        $ax.print_sql( $sql, '' );
        # Choose
        my @idx = $tc.choose-multi( # meta-items: range
            @choices,
            |$!i<lyt_h>, :meta-items( |( 0 .. @pre.end - 1 ) ), :no-spacebar( @pre.end, ), :1index,
            :2include-highlighted
        );
        if ! @idx[0] {
            if @bu {
                ( $sql<select_cols>, $sql<alias> ) = |@bu.pop;
                next COLUMNS;
            }
            return;
        }
        @bu.push: [ [ |$sql<select_cols> ], { |$sql<alias> } ];
        if @choices[@idx[0]] eq $!i<ok> {
            @idx.shift;
            $sql<select_cols>.append: @choices[@idx];
            return 1;
        }
        elsif @choices[@idx[0]] eq $expand_sign {
            my $ext = App::DBBrowser::Table::Extensions.new( :$!i, :$!o, :$!d );
            my $ext_col = $ext.extended_col( $sql, $clause );
            if ! $ext_col.defined {
                ( $sql<select_cols>, $sql<alias> ) = |@bu.pop;
            }
            else {
                $sql<select_cols>.push: $ext_col;
            }
            next COLUMNS;
        }
        $sql<select_cols>.append: @choices[@idx];
    }
}


method distinct ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my @pre = Any, $!i<ok>;
    $sql<distinct_stmt> = '';

    DISTINCT: loop {
        my @choices = |@pre, $!distinct, $!all;
        $ax.print_sql( $sql, '' );
        # Choose
        my $select_distinct = $tc.choose(
            @choices,
            |$!i<lyt_h>
        );
        if ! $select_distinct.defined {
            if $sql<distinct_stmt> {
                $sql<distinct_stmt> = '';
                next DISTINCT;
            }
            return;
        }
        elsif $select_distinct eq $!i<ok> {
            return 1;
        }
        $sql<distinct_stmt> = ' ' ~ $select_distinct;
    }
}


method aggregate ( $sql ) {
    $sql<aggr_cols> = [];
    $sql<select_cols> = [];

    AGGREGATE: loop {
        my $ret = self!add_aggregate_substmt( $sql );
        if ! $ret {
            if $sql<aggr_cols>.elems {
                my $aggr = $sql<aggr_cols>.pop;
                $sql<alias>{$aggr}:delete if $sql<alias>{$aggr}:exists; ###
                next AGGREGATE;
            }
            return;
        }
        elsif $ret eq $!i<ok> {
            return 1;
        }
    }
}

method !add_aggregate_substmt ( $sql ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my @pre = Any, $!i<ok>;
    my $i = $sql<aggr_cols>.elems;
    $ax.print_sql( $sql, '' );
    # Choose
    my $aggr = $tc.choose(
        [ |@pre, |$!i<aggregate> ],
        |$!i<lyt_h>
    );
    if ! $aggr.defined {
        return;
    }
    elsif $aggr eq $!i<ok> {
        return $aggr;
    }
    if $aggr eq 'COUNT(*)' {
        $sql<aggr_cols>[$i] = $aggr;
    }
    else {
        $aggr ~~ s/ \( \S \) $ //; #
        $sql<aggr_cols>[$i] = $aggr ~ "(";
        if $aggr ~~ / ^ [ COUNT || GROUP_CONCAT || STRING_AGG ] $ / {
            $ax.print_sql( $sql, '' );
            # Choose
            my $all_or_distinct = $tc.choose(
                [ Any, $!all, $!distinct ],
                |$!i<lyt_h>
            );
            if ! $all_or_distinct.defined {
                return;
            }
            if $all_or_distinct eq $!distinct {
                $sql<aggr_cols>[$i] ~= $!distinct;
            }
        }
        $ax.print_sql( $sql, '' );
        # Choose
        my $f_col = $tc.choose(
            [ Any, |$sql<cols> ],
            |$!i<lyt_h>
        );
        if ! $f_col.defined {
            return;
        }
        if $aggr eq 'STRING_AGG' {
            # pg: the separator is mandatory in STRING_AGG(DISTINCT, "Col", ',')
            $sql<aggr_cols>[$i] ~= ' ' ~ $f_col ~ ", ',')";
        }
        else {
            $sql<aggr_cols>[$i] ~= ' ' ~ $f_col ~ ")";
        }
    }
    my $alias = $ax.alias( 'aggregate', $sql<aggr_cols>[$i] );
    if $alias.defined && $alias.chars  {
        $sql<alias>{$sql<aggr_cols>[$i]} = $ax.quote_col_qualified( [ $alias ] );
    }
    return 1;
}


method set ( $sql ) {
    my $clause = 'set';
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $op = App::DBBrowser::Table::Substatements::Operators.new( :$!i, :$!o, :$!d );
    my $col_sep = ' ';
    $sql<set_args> = [];
    $sql<set_stmt> = " SET";
    my @bu;
    my @pre = Any, $!i<ok>;

    SET: loop {
        $ax.print_sql( $sql, '' );
        # Choose
        my $col = $tc.choose(
            [ |@pre, |$sql<cols> ],
            |$!i<lyt_h>
        );
        if ! $col.defined {
            if @bu {
                ( $sql<set_args>, $sql<set_stmt>, $col_sep ) = |@bu.pop;
                next SET;
            }
            return;
        }
        if $col eq $!i<ok> {
            if $col_sep eq ' ' {
                $sql<set_stmt> = '';
            }
            return 1;
        }
        @bu.push: [ [ |$sql<set_args> ], $sql<set_stmt>, $col_sep ];
        $sql<set_stmt> ~= $col_sep ~ $col;
        my $ok = $op.add_operator_with_value( $sql, $clause, $col );
        if ! $ok {
            ( $sql<set_args>, $sql<set_stmt>, $col_sep ) = |@bu.pop;
            next SET;
        }
        $col_sep = ', ';
    }
}


method where ( $sql ) {
    my $clause = 'where';
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $op = App::DBBrowser::Table::Substatements::Operators.new( :$!i, :$!o, :$!d );
    my @cols = |$sql<cols>;
    my $AND_OR = '';
    $sql<where_args> = [];
    $sql<where_stmt> = " WHERE";
    my $unclosed = 0;
    my $count = 0;
    my @bu;
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my $expand_sign = $!i<expand_signs>[$sign_idx];
    my @pre = Any, $!i<ok>, $sign_idx ?? $expand_sign !! |();

    WHERE: loop {
        my @choices = @cols;
        if $!o<enable><parentheses> {
            @choices.unshift: $unclosed ?? ')' !! '(';
        }
        $ax.print_sql( $sql, '' );
        # Choose
        my $quote_col = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_h>
        );
        if ! $quote_col.defined {
            if @bu {
                ( $sql<where_args>, $sql<where_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
                next WHERE;
            }
            return;
        }
        if $quote_col eq $!i<ok> {
            if $count == 0 {
                $sql<where_stmt> = '';
            }
            if $unclosed == 1 { # close an open parentheses automatically on OK
                $sql<where_stmt> ~= ")";
                $unclosed = 0;
            }
            return 1;
        }
        if $quote_col eq $expand_sign {
            my $ext = App::DBBrowser::Table::Extensions.new( :$!i, :$!o, :$!d );
            my $ext_col = $ext.extended_col( $sql, $clause );
            if ! $ext_col.defined {
                if @bu {
                    ( $sql<where_args>, $sql<where_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
                }
                next WHERE;
            }
            $quote_col = $ext_col;
        }
        if $quote_col eq ')' {
            @bu.push: [ [ |$sql<where_args> ], $sql<where_stmt>, $AND_OR, $unclosed, $count ];
            $sql<where_stmt> ~= ")";
            $unclosed--;
            next WHERE;
        }
        if $count > 0 && $sql<where_stmt> !~~ / \( $ / { #
            $ax.print_sql( $sql, '' );
            # Choose
            $AND_OR = $tc.choose(
                [ Any, $!and, $!or ],
                |$!i<lyt_h>
            );
            if ! $AND_OR.defined {
                next WHERE;
            }
            $AND_OR = ' ' ~ $AND_OR;
        }
        if $quote_col eq '(' {
            @bu.push: [ [ |$sql<where_args> ], $sql<where_stmt>, $AND_OR, $unclosed, $count ];
            $sql<where_stmt> ~= $AND_OR ~ " (";
            $AND_OR = '';
            $unclosed++;
            next WHERE;
        }
        @bu.push: [ [ |$sql<where_args> ], $sql<where_stmt>, $AND_OR, $unclosed, $count ];
        $sql<where_stmt> ~= $AND_OR ~ ' ' ~ $quote_col;
        my $ok = $op.add_operator_with_value( $sql, $clause, $quote_col );
        if ! $ok {
            ( $sql<where_args>, $sql<where_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
            next WHERE;
        }
        $count++;
    }
}


method group_by ( $sql ) {
    my $clause = 'group-by';
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    $sql<group_by_stmt> = " GROUP BY";
    $sql<group_by_cols> = [];
    $sql<select_cols> = [];
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my $expand_sign = $!i<expand_signs>[$sign_idx];
    my @pre = Any, $!i<ok>, $expand_sign ?? $expand_sign !! |();
    my @choices = |@pre, |$sql<cols>;

    GROUP_BY: loop {
        $sql<group_by_stmt> = " GROUP BY " ~ $sql<group_by_cols>.join: ', ';
        $ax.print_sql( $sql, '' );
        # Choose
        my @idx = $tc.choose-multi(
            @choices,
            |$!i<lyt_h>, :meta-items( |( 0 .. @pre.end - 1 ) ), :no-spacebar( @pre.end, ), :1index,
            :2include-highlighted
        );
        if ! @idx[0] {
            if $sql<group_by_cols>.elems {
                $sql<group_by_cols>.pop;
                next GROUP_BY;
            }
            $sql<group_by_stmt> = " GROUP BY " ~ $sql<group_by_cols>.join: ', ';
            return;
        }
        elsif @choices[@idx[0]] eq $!i<ok> {
            @idx.shift;
            $sql<group_by_cols>.append: @choices[@idx];
            if ! $sql<group_by_cols>.elems {
                $sql<group_by_stmt> = '';
            }
            else {
                $sql<group_by_stmt> = " GROUP BY " ~ $sql<group_by_cols>.join: ', ';
            }
            return 1;
        }
        elsif @choices[@idx[0]] eq $expand_sign {
            my $ext = App::DBBrowser::Table::Extensions.new( :$!i, :$!o, :$!d );
            my $ext_col = $ext.extended_col( $sql, $clause );
            if $ext_col.defined {
                $sql<group_by_cols>.push: $ext_col;
            }
            next GROUP_BY;
        }
        $sql<group_by_cols>.append: @choices[@idx];
    }
}


method having ( $sql ) {
    my $clause = 'having';
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $op = App::DBBrowser::Table::Substatements::Operators.new( :$!i, :$!o, :$!d );
    my $AND_OR = '';
    $sql<having_args> = [];
    $sql<having_stmt> = " HAVING";
    my $unclosed = 0;
    my $count = 0;
    my @bu;

    HAVING: loop {
        my @pre = Any, $!i<ok>;
        my @choices = |$!i<aggregate>, |$sql<aggr_cols>.map: { '@' ~ $_ };
        if $!o<enable><parentheses> {
            @choices.unshift, $unclosed ?? ')' !! '(';
        }
        $ax.print_sql( $sql, '' );
        # Choose
        my $aggr = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_h>
        );
        if ! $aggr.defined {
            if @bu {
                ( $sql<having_args>, $sql<having_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
                next HAVING;
            }
            return;
        }
        if $aggr eq $!i<ok> {
            if $count == 0 {
                $sql<having_stmt> = '';
            }
            if $unclosed == 1 { # close an open parentheses automatically on OK
                $sql<having_stmt> ~= ")";
                $unclosed = 0;
            }
            return 1;
        }
        if $aggr eq ')' {
            @bu.push: [ [ |$sql<having_args> ], $sql<having_stmt>, $AND_OR, $unclosed, $count ];
            $sql<having_stmt> ~= ")";
            $unclosed--;
            next HAVING;
        }
        if $count > 0 && $sql<having_stmt> !~~ / \( $ / {
            $ax.print_sql( $sql, '' );
            # Choose
            $AND_OR = $tc.choose(
                [ Any, $!and, $!or ],
                |$!i<lyt_h>
            );
            if ! $AND_OR.defined {
                next HAVING;
            }
            $AND_OR = ' ' ~ $AND_OR;
        }
        if $aggr eq '(' {
            @bu.push: [ [ |$sql<having_args> ], $sql<having_stmt>, $AND_OR, $unclosed, $count ];
            $sql<having_stmt> ~= $AND_OR ~ " (";
            $AND_OR = '';
            $unclosed++;
            next HAVING;
        }
        @bu.push: [ [ |$sql<having_args> ], $sql<having_stmt>, $AND_OR, $unclosed, $count ];
        $sql<having_stmt> ~= $AND_OR;
        my $quote_aggr = $op.build_having_col( $sql, $aggr );
        if ! $quote_aggr.defined {
            ( $sql<having_args>, $sql<having_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
            next HAVING;
        }
        my $ok = $op.add_operator_with_value( $sql, $clause, $quote_aggr );
        if ! $ok {
            ( $sql<having_args>, $sql<having_stmt>, $AND_OR, $unclosed, $count ) = |@bu.pop;
            next HAVING;
        }
        $count++;
    }
}


method order_by ( $sql ) {
    my $clause = 'order-by';
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my $expand_sign = $!i<expand_signs>[$sign_idx];
    my @pre = Any, $!i<ok>, $expand_sign ?? $expand_sign !! |();
    my @cols;
    if $sql<aggr_cols>.elems || $sql<group_by_cols>.elems {
        @cols = |$sql<group_by_cols>, |$sql<aggr_cols>;
    }
    else {
        @cols = |$sql<cols>;
    }
    my $col_sep = ' ';
    $sql<order_by_stmt> = " ORDER BY";
    my @bu;

    ORDER_BY: loop {
        $ax.print_sql( $sql, '' );
        # Choose
        my $col = $tc.choose(
            [ |@pre, |@cols ],
            |$!i<lyt_h>
        );
        if ! $col.defined {
            if @bu {
                ( $sql<order_by_stmt>, $col_sep ) = |@bu.pop;
                next ORDER_BY;
            }
            return
        }
        if $col eq $!i<ok> {
            if $col_sep eq ' ' {
                $sql<order_by_stmt> = '';
            }
            return 1;
        }
        elsif $col eq $expand_sign {
            my $ext = App::DBBrowser::Table::Extensions.new( :$!i, :$!o, :$!d );
            my $ext_col = $ext.extended_col( $sql, $clause );
            if ! $ext_col.defined {
                if @bu {
                    ( $sql<order_by_stmt>, $col_sep ) = |@bu.pop;
                }
                next ORDER_BY;
            }
            $col = $ext_col;
        }
        @bu.push: [ $sql<order_by_stmt>, $col_sep ];
        $sql<order_by_stmt> ~= $col_sep ~ $col;
        $ax.print_sql( $sql, '' );
        # Choose
        my $direction = $tc.choose(
            [ Any, $!asc, $!desc ],
            |$!i<lyt_h>
        );
        if ! $direction.defined {
            ( $sql<order_by_stmt>, $col_sep ) = |@bu.pop;
            next ORDER_BY;
        }
        $sql<order_by_stmt> ~= ' ' ~ $direction;
        $col_sep = ', ';
    }
}


method limit_offset ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my @pre = Any, $!i<ok>;
    $sql<limit_stmt>  = '';
    $sql<offset_stmt> = '';
    my @bu;

    LIMIT: loop {
        my ( $limit, $offset ) = ( 'LIMIT', 'OFFSET' );
        $ax.print_sql( $sql, '' );
        # Choose
        my $choice = $tc.choose(
            [ |@pre, $limit, $offset ],
            |$!i<lyt_h>
        );
        if ! $choice.defined {
            if @bu {
                ( $sql<limit_stmt>, $sql<offset_stmt> )  = |@bu.pop;
                next LIMIT;
            }
            return;
        }
        if $choice eq $!i<ok> {
            return 1;
        }
        @bu.push: [ $sql<limit_stmt>, $sql<offset_stmt> ];
        my $digits = 7;
        if $choice eq $limit {
            $sql<limit_stmt> = " LIMIT";
            $ax.print_sql( $sql, '' );
            # Choose_a_number
            my $limit = $tu.choose-a-number( $digits,
                :name<LIMIT:>, :0clear-screen
            );
            if ! $limit.defined {
                ( $sql<limit_stmt>, $sql<offset_stmt> ) = |@bu.pop;
                next LIMIT;
            }
            $sql<limit_stmt> ~=  sprintf ' %d', $limit;
        }
        if $choice eq $offset {
            if ! $sql<limit_stmt> {
                $sql<limit_stmt> = " LIMIT " ~ ( $!o<G><max-rows> || '9223372036854775807'  ) if $!i<driver> eq 'SQLite';   # 2 ** 63 - 1
                # MySQL 5.7 Reference Manual - SELECT Syntax - Limit clause: SELECT * FROM tbl LIMIT 95,18446744073709551615;
                $sql<limit_stmt> = " LIMIT " ~ ( $!o<G><max-rows> || '18446744073709551615' ) if $!i<driver> eq 'mysql';    # 2 ** 64 - 1
            }
            $sql<offset_stmt> = " OFFSET";
            $ax.print_sql( $sql, '' );
            # Choose_a_number
            my $offset = $tu.choose-a-number( $digits,
                :name<OFFSET:>, :0clear-screen
            );
            if ! $offset.defined {
                ( $sql<limit_stmt>, $sql<offset_stmt> ) = |@bu.pop;
                next LIMIT;
            }
            $sql<offset_stmt> ~= sprintf ' %d', $offset;
        }
    }
}



