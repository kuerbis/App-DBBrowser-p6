use v6;
unit class App::DBBrowser::Union;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;

use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries; # required

has $.i;
has $.o;
has $.d;


method union_tables {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    $!i<stmt_types> = [ 'Union' ];
    my $tables = [ |$!d<user_tables>, |$!d<sys_tables> ];
    ( $!d<col_names>, $!d<col_types> ) = $ax.column_names_and_types( $tables );
    my $union = {
        used_tables    => [],
        subselect_data => [],
        saved_cols     => []
    };
    my $unique_char = 'A';
    my Array @bu;

    UNION_TABLE: while ( 1 ) {
        my $enough_tables = '  Enough TABLES';
        my $from_subquery = '  Derived';
        my $all_tables    = '  All Tables';
        my @pre  = Any, $enough_tables;
        my @post;
        @post.push: $from_subquery if $!o<enable><u-derived>;
        @post.push: $all_tables    if $!o<enable><union-all>;
        my $used = ' (used)';
        my @tmp_tables;
        for $tables.list -> $table {
            if $table eq $union<used_tables>.any {
                @tmp_tables.push: '- ' ~ $table ~ $used;
            }
            else {
                @tmp_tables.push: '- ' ~ $table;
            }
        }
        my $prompt = 'Choose UNION table:';
        my @choices  = |@pre, |@tmp_tables, |@post;
        $ax.print_sql( $union );
        # Choose
        my $idx_tbl = $tc.choose(
            @choices,
            |$!i<lyt_v>, :$prompt, :1index
        );
        if ! $idx_tbl.defined || ! @choices[$idx_tbl].defined {
            if @bu.elems {
                ( $union<used_tables>, $union<subselect_data>, $union<saved_cols> ) = |@bu.pop;
                next UNION_TABLE;
            }
            return;
        }
        my $union_table = @choices[$idx_tbl];
        my $qt_union_table;
        if $union_table eq $enough_tables {
            if ! $union<subselect_data>.elems {
                return;
            }
            last UNION_TABLE;
        }
        elsif $union_table eq $all_tables {
            my $ok = self!_union_all_tables( $union );
            if ! $ok {
                next UNION_TABLE;
            }
            last UNION_TABLE;
        }
        elsif $union_table eq $from_subquery {
            require App::DBBrowser::Subqueries;
            my $sq = ::('App::DBBrowser::Subqueries').new( :$!i, :$!o, :$!d );
            $union_table = $sq.choose_subquery( $union );
            if ! $union_table.defined {
                next UNION_TABLE;
            }
            my $default_alias = 'U_TBL_' ~ $unique_char++;
            my $alias = $ax.alias( 'union', $union_table, $default_alias );
            $qt_union_table = $union_table ~ " AS " ~ $ax.quote_col_qualified( [ $alias ] );
            my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $qt_union_table ~ " LIMIT 0" );
            if $!i<driver> ne 'SQLite' {
                $sth.execute();
            }
            $!d<col_names>{$union_table} = $sth.column-names();
        }
        else {
            $union_table ~~ s/ ^ '-' \s //;
            $union_table ~~ s/ $used $ //;
            $qt_union_table = $ax.quote_table( $!d<tables_info>{$union_table} );
        }
        @bu.push: [ [ |$union<used_tables> ], [ |$union<subselect_data> ], [ |$union<saved_cols> ] ];
        $union<used_tables>.push: $union_table;
        $ax.print_sql( $union );
        my $ok = self!_union_table_columns( $union, $union_table, $qt_union_table );
        if ! $ok {
            ( $union<used_tables>, $union<subselect_data>, $union<saved_cols> ) = |@bu.pop;
            next UNION_TABLE;
        }
    }
    $ax.print_sql( $union );
    my $qt_table = $ax.get_stmt( $union, 'Union', 'prepare' );
    # alias: required if mysql, Pg, ...
    my $alias = $ax.alias( 'union', '', "TABLES_UNION" );
    $qt_table ~= " AS " ~ $ax.quote_col_qualified( [ $alias ] );
    # column names in the result-set of a UNION are taken from the first query.
    my $qt_columns = $union<subselect_data>[0][1];
    return $qt_table, $qt_columns;
}


method !_union_table_columns ( $union, $union_table, $qt_union_table ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my ( $privious_cols, $void ) = ( q['^'], q[' '] );
    my $next_idx = $union<subselect_data>.elems;
    my @table_cols;
    my @bu;

    loop {
        my @pre = Any, $!i<ok>, $union<saved_cols>.elems ?? $privious_cols !! $void;
        $ax.print_sql( $union );
        # Choose
        my @chosen = $tc.choose-multi(
            [ |@pre, |$!d<col_names>{$union_table} ],
            |$!i<lyt_h>, :prompt( 'Choose Column:' ), :meta-items(  0, 1, 2 ), :2include-highlighted
        );
        if ! @chosen[0].defined {
            if @bu {
                @table_cols = @bu.pop;
                $union<subselect_data>[$next_idx] = [ $qt_union_table, $ax.quote_simple_many( @table_cols ) ];
                next;
            }
            else {
                if $union<subselect_data>.elems {
                    $union<subselect_data>.pop;
                }
                return;
            }
        }
        if @chosen[0] eq $void {
            next;
        }
        elsif @chosen[0] eq $privious_cols {
            $union<subselect_data>.push: [ $qt_union_table, $ax.quote_simple_many( $union<saved_cols> ) ];
            return 1;
        }
        elsif @chosen[0] eq $!i<ok> {
            @chosen.shift;
            if @chosen.elems {
                @table_cols.push: |@chosen;
            }
            if ! @table_cols.elems {
                @table_cols = |$!d<col_names>{$union_table};
            }
            $union<subselect_data>[$next_idx] = [ $qt_union_table, $ax.quote_simple_many( @table_cols ) ];
            $union<saved_cols> = @table_cols;
            return 1;
        }
        else {
            @bu.push: @table_cols;
            @table_cols.push: |@chosen;
            $union<subselect_data>[$next_idx] = [ $qt_union_table, $ax.quote_simple_many( @table_cols ) ];
        }
    }
}


method !_union_all_tables ( $union ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my @tables_union_auto;
    for $!d<user_tables>.list -> $table {
        if  $!d<tables_info>{$table}[3] ne 'TABLE' {
             next;
        }
        @tables_union_auto.push: $table;
    }
    my @choices = Any, |@tables_union_auto.map: { "- $_" };

    loop {
        $union<subselect_data> = [ |@tables_union_auto.map: { [ $_, [ '?' ] ] } ];
        $ax.print_sql( $union );
        # Choose
        my $idx_tbl = $tc.choose(
            @choices,
            |$!i<lyt_v>, :prompt( 'One UNION table for cols:' ), :1index
        );
        if ! $idx_tbl.defined || ! @choices[$idx_tbl].defined {
            $union<subselect_data> = [];
            return;
        }
        my $union_table = @choices[$idx_tbl].subst( / ^ '-' \s /, '' );
        my $qt_union_table = $ax.quote_table( $!d<tables_info>{$union_table} );
        my $ok = self!_union_table_columns( $union, $union_table, $qt_union_table );
        if $ok {
            last;
        }
    }
    my $qt_used_cols = $union<subselect_data>[*-1][1];
    $union<subselect_data> = [];
    for @tables_union_auto -> $union_table {
        $union<subselect_data>.push: [ $ax.quote_table( $!d<tables_info>{$union_table} ), $qt_used_cols ];
    }
    $ax.print_sql( $union );
    return 1;
}

