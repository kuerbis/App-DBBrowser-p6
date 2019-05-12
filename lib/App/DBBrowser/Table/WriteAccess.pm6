use v6;
unit class App::DBBrowser::Table::WriteAccess;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;

use Term::Choose;
use Term::Choose::Screen :hide-cursor; ## Term::TablePrint :1loop
use Term::Choose::Util :insert-sep;
use Term::TablePrint :print-table;

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;
#use App::DBBrowser::GetContent; # required
use App::DBBrowser::Table::Substatements;

has $.i;
has $.o;
has $.d;


method table_write_access ( $sql is rw ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $sb = App::DBBrowser::Table::Substatements.new( :$!i, :$!o, :$!d );
    my @stmt_types;
    if ! $!i<special_table> {
        @stmt_types.push: 'Insert' if $!o<enable><insert-into>;
        @stmt_types.push: 'Update' if $!o<enable><update>;
        @stmt_types.push: 'Delete' if $!o<enable><delete>;
    }
    elsif $!i<special_table> eq 'join' && $!i<driver> eq 'mysql' {
        @stmt_types.push: 'Update' if $!o<G><enable><update>;
    }
    if ! @stmt_types {
        return;
    }

    STMT_TYPE: loop {
        # Choose
        my $stmt_type = $tc.choose(
            [ Any, |@stmt_types.map: { "- $_" } ],
            |$!i<lyt_v>, :prompt( 'Choose SQL type:' ), :1clear-screen
        );
        if ! $stmt_type.defined {
            return;
        }
        $stmt_type ~~ s/ ^ '-' \s //;
        $!i<stmt_types> = [ $stmt_type ];
        $ax.reset_sql( $sql );
        if $stmt_type eq 'Insert' {
            my $ok = self!_build_insert_stmt( $sql );
            if $ok {
                $ok = self.commit_sql( $sql );
            }
            next STMT_TYPE;
        }
        my $sub_stmts = {
            Delete => [ <commit     where> ],
            Update => [ <commit set where> ],
        };
        my %cu = (
            commit => '  CONFIRM Stmt',
            set    => '- SET',
            where  => '- WHERE',
        );
        my $old_idx = 0;

        CUSTOMIZE: loop {
            my @choices = Any, |%cu{ |$sub_stmts{$stmt_type} };
            $ax.print_sql( $sql, [ $stmt_type ] );
            # Choose
            my $idx = $tc.choose(
                @choices,
                |$!i<lyt_v>, :prompt( 'Customize:' ), :1index, :default( $old_idx ), :undef( $!i<_back> )
            );
            if ! $idx.defined || ! @choices[$idx].defined {
                next STMT_TYPE;
            }
            my $custom = @choices[$idx];
            if $!o<G><menu_memory> {
                if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                    $old_idx = 0;
                    next CUSTOMIZE;
                }
                $old_idx = $idx;
            }
            my $backup_sql = $ax.backup_href( $sql );
            given $custom {
                when %cu{'set'} {
                    my $ok = $sb.set( $sql );
                    if ! $ok {
                        $sql = $backup_sql;
                    }
                }
                when %cu{'where'} {
                    my $ok = $sb.where( $sql );
                    if ! $ok {
                        $sql = $backup_sql;
                    }
                }
                when %cu{'commit'} {
                    my $ok = self.commit_sql( $sql );
                    next STMT_TYPE;
                }
                default {
                    die "$custom: no such value in the hash \%cu";
                }
            }
        }
    }
}


method commit_sql ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $dbh = $!d<dbh>;
    my $waiting = 'DB work ... ';
    $ax.print_sql( $sql, $waiting );
    my $stmt_type = $!i<stmt_types>[*-1];
    my $rows_to_execute = [];
    my $count_affected;
    if $stmt_type eq 'Insert' {
        return 1 if ! $sql<insert_into_args>.elems;
        $rows_to_execute = $sql<insert_into_args>;
        $count_affected = $rows_to_execute.elems;
    }
    else {
        $rows_to_execute = [ [ |$sql<set_args>, |$sql<where_args> ], ];
        my @all_arrayref;
        try {
            my $sth = $dbh.prepare( "SELECT * FROM " ~ $sql<table> ~ $sql<where_stmt> );
            $sth.execute( |$sql<where_args> );
            my $col_names = $sth.column-names();
            @all_arrayref = $sth.allrows();
            $count_affected = @all_arrayref.elems;
            @all_arrayref.unshift: $col_names;
            CATCH { default {
                $ax.print_error_message( $_, "Fetching info: affected records ...\n" ~ $stmt_type ); ####
            }}
        }
        my $prompt = $ax.print_sql( $sql );
        $prompt ~= "Affected records:";
        if @all_arrayref.elems > 1 {
            print-table(
                @all_arrayref,
                |$!o<table>, :$prompt, :1grid, :0max-rows, :1keep-header, :table-expand( $!o<G><info-expand> ) # :2grid
            );
            hide-cursor(); ## loop 
        }
    }
    $ax.print_sql( $sql, $waiting );
    #my $transaction;
    #eval {
    #    $dbh.<AutoCommit> = 1;
    #    $transaction = $dbh.begin_work;
    #} or do {
    #    $dbh.<AutoCommit> = 1;
    #    $transaction = 0;
    #};
    my $transaction = 0;
    if $transaction {
        return self!_transaction( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting );
    }
    else {
        return self!_auto_commit( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting );
    }
}


method !_transaction ( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $dbh = $!d<dbh>;
    my $rolled_back;
    #try {
        my $sth = $dbh.prepare(
            $ax.get_stmt( $sql, $stmt_type, 'prepare' )
        );
        for $rows_to_execute.list -> $values { ##
            $sth.execute( |$values );
        }
        my $commit_ok = sprintf '  %s %s "%s"', 'COMMIT', insert-sep( $count_affected, $!o<G><thsd-sep> ), $stmt_type;
        $ax.print_sql( $sql );
        # Choose
        my $choice = $tc.choose(
            [ Any,  $commit_ok ],
            |$!i<lyt_v>
        );
        $ax.print_sql( $sql, $waiting );
        if ! $choice.defined || $choice ne $commit_ok {
            $dbh.rollback;
            $rolled_back = 1;
        }
        else {;
            $dbh.commit;
        }
    #    CATCH { default {
    #        $ax.print_error_message( $_, "Commit: Rolling back ..." );
    #        $dbh.rollback;
    #        $rolled_back = 1;
    #    }}
    #}
    if $rolled_back {
        return;
    }
    return 1;
}


method !_auto_commit ( $sql, $stmt_type, $rows_to_execute, $count_affected, $waiting ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $dbh = $!d<dbh>;
    my $commit_ok = sprintf '  %s %s "%s"', 'EXECUTE', insert-sep( $count_affected, $!o<G><thsd-sep> ), $stmt_type;
    $ax.print_sql( $sql ); #
    # Choose
    my $choice = $tc.choose(
        [ Any,  $commit_ok ],
        |$!i<lyt_v>, :prompt( '' )
    );
    $ax.print_sql( $sql, $waiting );
    if ! $choice.defined || $choice ne $commit_ok {
        return;
    }
    try {
        my $stmt = $ax.get_stmt( $sql, $stmt_type, 'prepare' );
        my $sth = $dbh.prepare( $stmt );
        for $rows_to_execute.list -> $values { ##
            $sth.execute( |$values );
        }
        CATCH { default {
            $ax.print_error_message( $_, 'Auto Commit' );
            return;
        }}
    }
    return 1;
}


method !_build_insert_stmt ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $tc = Term::Choose.new( |$!i<default> );
    $ax.reset_sql( $sql );
    my @cu_keys = ( qw/insert_col insert_copy insert_file/ );
    my %cu = (
        insert_col  => '- Plain',
        insert_file => '- From File',
        insert_copy => '- Copy & Paste',
    );
    my $old_idx = 0;

    MENU: loop {
        my @choices = Any, |%cu{@cu_keys};
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :1index, :default( $old_idx ), :undef( '  <=' )
        );
        if ! $idx.defined || ! @choices.[$idx].defined {
            return;
        }
        my $custom = @choices[$idx];
        if $!o<G><menu_memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 0;
                next MENU;
            }
            $old_idx = $idx;
        }
        my $cols_ok = self!_insert_into_stmt_columns( $sql );
        if ! $cols_ok {
            next MENU;
        }
        my $insert_ok;
        require App::DBBrowser::GetContent;
        my $gc = App::DBBrowser::GetContent.new( :$!i, :$!o, :$!d );
        if $custom eq %cu<insert_col> {
            $insert_ok = $gc.from_col_by_col( $sql );
        }
        elsif $custom eq %cu<insert_copy> {
            $insert_ok = $gc.from_copy_and_paste( $sql );
        }
        elsif $custom eq %cu<insert_file> {
            $insert_ok = $gc.from_file( $sql );
        }
        if ! $insert_ok {
            next MENU;
        }
        return 1
    }
}


method !_insert_into_stmt_columns ( $sql ) {
    my $ax  = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $tc = Term::Choose.new( |$!i<default> );
    $sql<insert_into_cols> = [];
    my @cols = |$sql<cols>;
    if $plui.first_column_is_autoincrement( $!d<dbh>, $!d<schema>, $!d<table> ) {
        @cols.shift;
    }
    my $bu_cols = [ @cols ];

    COL_NAMES: loop {
        $ax.print_sql( $sql );
        my @pre = Any, $!i<ok>;
        my @choices = |@pre, |@cols;
        # Choose
        my @idx = $tc.choose-multi(
            @choices,
            |$!i<lyt_h>, :prompt( 'Columns:' ), :1index, :meta-items( |( 0 .. @pre.end ) ), :2include-highlighted
        );
        if ! @idx[0] {
            if ! $sql<insert_into_cols>.elems {
                return;
            }
            $sql<insert_into_cols> = [];
            @cols = |$bu_cols;
            next COL_NAMES;
        }
        if @idx[0] == 1 {
            @idx.shift;
            $sql<insert_into_cols>.push: |@choices[@idx];
            if ! $sql<insert_into_cols>.elems {
                $sql<insert_into_cols> = $bu_cols;
            }
            return 1;
        }
        $sql<insert_into_cols>.push: |@choices[@idx];
        my $c = 0;
        for @idx -> $i {
            last if ! @cols.elems;
            my $ni = $i - ( @pre.elems + $c );
            @cols.splice: $ni, 1;
            ++$c;
        }
    }
}




