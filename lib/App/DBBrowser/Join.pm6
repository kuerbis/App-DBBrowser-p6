use v6;
unit class App::DBBrowser::Join;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Form;
use Term::TablePrint;

use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries; # required

has $.i;
has $.o;
has $.d;

has $!join_types;


method join_tables {
    $!i<stmt_types> = [ 'Join' ];
    if $!i<driver> eq 'SQLite' {
        $!join_types = [ 'INNER JOIN', 'LEFT JOIN', 'CROSS JOIN' ];
    }
    elsif $!i<driver> ~~ / ^ [ mysql || MariaDB ]  $ / {
        $!join_types = [ 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'CROSS JOIN' ];
    }
    else {
        $!join_types = [ 'INNER JOIN', 'LEFT JOIN', 'RIGHT JOIN', 'FULL JOIN', 'CROSS JOIN' ];
    }
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tables = [ |$!d<tables_info>.keys.sort ];
    ( $!d<col_names>, $!d<col_types> ) = $ax.column_names_and_types( $tables );
    my $join = {};

    MASTER: while ( 1 ) {
        $join = {};
        $join<stmt> = "SELECT * FROM";
        $join<used_tables>  = [];
        $join<aliases>      = [];
        $ax.print_sql( $join );
        my $info = '  INFO';
        my $from_subquery = '  Derived';
        my @choices = |$tables.map: { "- $_" };
        @choices.push: $from_subquery if $!o<enable><j-derived>;
#        @choices.push: $info;
        my @pre = Any;
        # Choose
        my $master = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_v>, :prompt( 'Choose MASTER table:' )
        );
        if ! $master.defined {
            return;
        }
        elsif $master eq $info {
            self!_get_join_info();
            self!_print_join_info();
            next MASTER;
        }
        my $qt_master;
        if $master eq $from_subquery {
            require App::DBBrowser::Subqueries;
            my $sq = ::('App::DBBrowser::Subqueries').new( :$!i, :$!o, :$!d );
            $master = $sq.choose_subquery( $join );
            if ! $master.defined {
                next MASTER;
            }
            $qt_master = $master;
        }
        else {
            $master ~~ s/ ^ '-' \s //;
            $qt_master = $ax.quote_table( $!d<tables_info>{$master} );
        }
        $join<used_tables>.push: $master;
        $join<default_alias> = 'A';
        $ax.print_sql( $join );
        # Readline
        my $master_alias = $ax.alias( 'join', $qt_master, $join<default_alias> );
        $join<aliases>.push: [ $master, $master_alias ];
        $join<stmt> ~= " " ~ $qt_master;
        $join<stmt> ~= " AS " ~ $ax.quote_col_qualified( [ $master_alias ] );
        if $master eq $qt_master {
            my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $qt_master ~ " AS " ~ $master_alias ~ " LIMIT 0" );
            $sth.execute() if $!i<driver> ne 'SQLite';
            $!d<col_names>{$master} = $sth.column-names();
        }
        my @bu;

        JOIN: loop {
            $ax.print_sql( $join );
            my $backup_join = $ax.backup_href( $join );
            my $enough_tables = '  Enough TABLES';
            my @pre = Any, $enough_tables;
            # Choose
            my $join_type = $tc.choose(
                [ |@pre, |$!join_types.map: { "- $_" } ],
                |$!i<lyt_v>, :prompt( 'Choose Join Type:' )
            );
            if ! $join_type.defined {
                if @bu.elems {
                    ( $join<stmt>, $join<default_alias>, $join<aliases>, $join<used_tables> ) = |@bu.pop;
                    next JOIN;
                }
                next MASTER;
            }
            elsif $join_type eq $enough_tables {
                if $join<used_tables>.elems == 1 {
                    return;
                }
                last JOIN;
            }
            $join_type ~~ s/ ^ '-' \s //;
            @bu.push: [ $join<stmt>, $join<default_alias>, [ |$join<aliases> ], [ |$join<used_tables> ] ];
            $join<stmt> ~= " " ~ $join_type;
            my $ok = self!_add_slave_with_join_condition( $join, $tables, $join_type, $info );
            if ! $ok {
                ( $join<stmt>, $join<default_alias>, $join<aliases>, $join<used_tables> ) = |@bu.pop;
            }
        }
        last MASTER;
    }

    my $aliases_by_tables = {};
    for $join<aliases>.list -> $ref { ##
        $aliases_by_tables{$ref[0]}.push: $ref[1];
    }
    my $qt_columns = [];
    for $join<used_tables>.list -> $table {
        for $aliases_by_tables{$table}.list -> $alias {
            for $!d<col_names>{$table}.list -> $col {
                my $col_qt = $ax.quote_col_qualified( [ Any, $alias, $col ] );
                if $col_qt eq $qt_columns.any {
                    next;
                }
                $qt_columns.push: $col_qt;
            }
        }
    }
    my $qt_table = $join<stmt>;                             ##
    #$qt_table ~~ / ^ SELECT \s \* \s FROM \s ( .* ) $ /;    ##
    $qt_table ~~ s/ ^ SELECT \s \* \s FROM \s //;    ##
    
    return $qt_table, $qt_columns;
}


method !_add_slave_with_join_condition ( $join, $tables, $join_type, $info ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $used = ' (used)';
    my $from_subquery = '  Derived';
    my @choices;
    for $tables.list -> $table {
        if $table eq $join<used_tables>.any {
            @choices.push: '- ' ~ $table ~ $used;
        }
        else {
            @choices.push: '- ' ~ $table;
        }
    }
    @choices.push: $from_subquery if $!o<enable><j-derived>;
    @choices.push: $info;
    my @pre = Any;
    my @bu;

    SLAVE: while ( 1 ) {
        $ax.print_sql( $join );
        # Choose
        my $slave = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_v>, :prompt( 'Add a SLAVE table:' ), :undef( $!i<_reset> )
        );
        if ! $slave.defined {
            if @bu.elems {
                ( $join<stmt>, $join<default_alias>, $join<aliases>, $join<used_tables> ) = |@bu.pop;
                next SLAVE;
            }
            return;
        }
        elsif $slave eq $info {
            self!_get_join_info();
            self!_print_join_info();
            next SLAVE;
        }
        my $qt_slave;
        if $slave eq $from_subquery {
            require App::DBBrowser::Subqueries;
            my $sq = ::('App::DBBrowser::Subqueries').new( :$!i, :$!o, :$!d );
            $slave = $sq.choose_subquery( $join );
            if ! $slave.defined {
                next SLAVE;
            }
            $qt_slave = $slave;
        }
        else {
            $slave ~~ s/ ^ '-' \s //;
            $slave ~~ s/ $used $ //;
            $qt_slave = $ax.quote_table( $!d<tables_info>{$slave} );
        }
        @bu.push: [ $join<stmt>, $join<default_alias>, [ |$join<aliases> ], [ |$join<used_tables> ] ];
        $join<used_tables>.push: $slave;
        $ax.print_sql( $join );
        # Readline
        my $slave_alias = $ax.alias( 'join', $qt_slave, ++$join<default_alias> );
        $join<stmt> ~= " " ~ $qt_slave;
        $join<stmt> ~= " AS " ~ $ax.quote_col_qualified( [ $slave_alias ] );
        $join<aliases>.push: [ $slave, $slave_alias ];
        $ax.print_sql( $join );
        if $slave eq $qt_slave {
            my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $qt_slave ~ " AS " ~ $slave_alias ~ " LIMIT 0" );
            $sth.execute() if $!i<driver> ne 'SQLite';
            $!d<col_names>{$slave} = $sth.column-names();
        }
        if $join_type ne 'CROSS JOIN' {
            my $ok = self!_add_join_condition( $join, $tables, $slave, $slave_alias );
            if ! $ok {
                ( $join<stmt>, $join<default_alias>, $join<aliases>, $join<used_tables> ) = |@bu.pop;
                next SLAVE;
            }
        }
        $join<used_tables>.push: $slave;
        $ax.print_sql( $join );
        return 1;
    }
}


method !_add_join_condition ( $join, $tables, $slave, $slave_alias ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    my $aliases_by_tables = {};
    for $join<aliases>.list -> $ref { ##
        $aliases_by_tables{$ref[0]}.push: $ref[1];
    }
    my %avail_pk_cols;
    for $join<used_tables>.list -> $used_table {
        for $aliases_by_tables{$used_table}.list -> $alias {
            next if $used_table eq $slave && $alias eq $slave_alias;
            for $!d<col_names>{$used_table}.list -> $col {
                %avail_pk_cols{ $alias ~ '.' ~ $col } = $ax.quote_col_qualified( [ Any, $alias, $col ] );
            }
        }
    }
    my %avail_fk_cols;
    for $!d<col_names>{$slave}.list -> $col {
        %avail_fk_cols{ $slave_alias ~ '.' ~ $col } = $ax.quote_col_qualified( [ Any, $slave_alias, $col ] );
    }
    $join<stmt> ~= " ON";
    my $bu_stmt = $join<stmt>;
    my $AND = '';
    my @bu;

    JOIN_PREDICATE: loop {
        my @pre = Any, $AND ?? $!i<_confirm> !! |();
        my $fk_pre = '  ';

        PRIMARY_KEY: loop {
            $ax.print_sql( $join );
            # Choose
            my $pk_col = $tc.choose(
                [ |@pre,
                  |%avail_pk_cols.keys.sort.map({    '- ' ~ $_ }),
                  |%avail_fk_cols.keys.sort.map({ $fk_pre ~ $_ }),
                ],
                |$!i<lyt_v>, :prompt( 'Choose PRIMARY KEY column:' ), :undef( $!i<_back> )
            );
            if ! $pk_col.defined {
                if @bu.elems {
                    ( $join<stmt>, $AND ) = |@bu.pop;
                    last PRIMARY_KEY;
                }
                return;
            }
            elsif $pk_col eq $!i<_confirm> {
                if ! $AND {
                    return;
                }
                my $condition = $join<stmt>;            ##
                $condition ~~ s/ ^ $bu_stmt \s //;       ##
                $join<stmt> = $bu_stmt;
                $ax.print_sql( $join );
                # Readline
                $condition = $tf.readline( 'Edit: ', :default( $condition ), :1show-context );
                if ! $condition.defined {
                    return;
                }
                $join<stmt> = $bu_stmt ~ " " ~ $condition;
                return 1;
            }
            elsif $pk_col eq %avail_fk_cols.keys.map({ $fk_pre ~ $_ }).any {
                next PRIMARY_KEY;
            }
            $pk_col ~~ s/ ^ '-' \s //;
            @bu.push: [ $join<stmt>, $AND ];
            $join<stmt> ~= $AND;
            $join<stmt> ~= " " ~ %avail_pk_cols{$pk_col} ~ " " ~ '=';
            last PRIMARY_KEY;
        }

        FOREIGN_KEY: loop {
            $ax.print_sql( $join );
            # Choose
            my $fk_col = $tc.choose(
                [ Any, |%avail_fk_cols.keys.sort.map: { "- $_" } ],
                |$!i<lyt_v>, :prompt( 'Choose FOREIGN KEY column:' ), :undef( $!i<_back> )
            );
            if ! $fk_col.defined {
                ( $join<stmt>, $AND ) = |@bu.pop;
                next JOIN_PREDICATE;
            }
            $fk_col ~~ s/ ^ '-' \s //;
            @bu.push: [ $join<stmt>, $AND ];
            $join<stmt> ~= " " ~ %avail_fk_cols{$fk_col};
            $AND = " AND";
            next JOIN_PREDICATE;
        }
    }
}


method !_print_join_info {
    my $pk = $!d<pk_info>;
    my $fk = $!d<fk_info>;
    my $aref = [ [ <PK_TABLE PK_COLUMN>, ' ', <FK_TABLE FK_COLUMN> ], ];
    my $r = 1;
    for $pk.sort.keys -> $t { # .list
        $aref[$r][0] = $pk{$t}<TABLE_NAME>;
        $aref[$r][1] = $pk{$t}<COLUMN_NAME>.join: ', ';
        if $fk{$t}<FKCOLUMN_NAME>.defined && $fk{$t}<FKCOLUMN_NAME>.elems {
            $aref[$r][2] = 'ON';
            $aref[$r][3] = $fk{$t}<FKTABLE_NAME>;
            $aref[$r][4] = $fk{$t}<FKCOLUMN_NAME>.join: ', ';
        }
        else {
            $aref[$r][2] = '';
            $aref[$r][3] = '';
            $aref[$r][4] = '';
        }
        $r++;
    }
    my $tt = Term::TablePrint.new( :1loop );
    $tt.print-table( $aref, :0keep-header, :3tab-width, :1grid ); # hide-cursor
}


method !_get_join_info {
    return if $!d<pk_info>;
    my $td = $!d<tables_info>;
    my $tables = $!d<user_tables>; ###
    my $pk = {};
    for $tables.list -> $table {
        my $sth = $!d<dbh>.primary_key_info( $td{$table} );
        next if ! $sth.defined;
        while my $ref = $sth.fetchrow_hashref() {
            next if ! defined $ref;
            #$pk{$table}<TABLE_SCHEM> = $ref<TABLE_SCHEM>;
            $pk{$table}<TABLE_NAME>  = $ref<TABLE_NAME>;
            $pk{$table}<COLUMN_NAME>.push: $ref<COLUMN_NAME>;
            #$pk{$table}<KEY_SEQ>.push: $ref<KEY_SEQ>.defined ?? $ref<KEY_SEQ> !! $ref<ORDINAL_POSITION>;
        }
    }
    my $fk = {};
    for $tables.list -> $table {
        my $sth = $!d<dbh>.foreign_key_info( $td{$table}, Any, Any, Any );
        next if ! $sth.defined;
        while my $ref = $sth.fetchrow_hashref() {
            next if ! defined $ref;
            #$fk{$table}<FKTABLE_SCHEM> = $ref<FKTABLE_SCHEM>.defined    ?? $ref<FKTABLE_SCHEM> !! $ref<FK_TABLE_SCHEM>;
            $fk{$table}<FKTABLE_NAME>  =  $ref<FKTABLE_NAME>.defined     ?? $ref<FKTABLE_NAME>  !! $ref<FK_TABLE_NAME>;
            $fk{$table}<FKCOLUMN_NAME>.push: $ref<FKCOLUMN_NAME>.defined ?? $ref<FKCOLUMN_NAME> !! $ref<FK_COLUMN_NAME>;
            #$fk{$table}<KEY_SEQ>.push:      $ref<KEY_SEQ>.defined       ?? $ref<KEY_SEQ>       !! $ref<ORDINAL_POSITION>;
        }
    }
    $!d<pk_info> = $pk;
    $!d<fk_info> = $fk;
}




