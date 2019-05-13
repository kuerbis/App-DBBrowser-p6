use v6;
unit class App::DBBrowser::CreateTable;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

#use SQL::Type::Guess  qw(); # required

use Term::Choose;
use Term::Choose::Util :insert-sep;
use Term::Form;
use Term::TablePrint :print-table; # hide-cursor

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;
use App::DBBrowser::GetContent;
use App::DBBrowser::Table::WriteAccess;
#require App::DBBrowser::Subqueries; # required

has $.i;
has $.o;
has $.d;

has $!col_auto;
has $!constraint_auto;


method drop_table {
    return self!_choose_drop_item( 'table' );
}


method drop_view {
    return self!_choose_drop_item( 'view' );
}


method !_choose_drop_item ( $type ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $sql = {};
    $ax.reset_sql( $sql );
    my @tables = $!d<user_tables>.grep({ $!d<tables_info>{$_}[3] eq $type.uc }).sort;
    my $prompt = $!d<db_string> ~ "\n" ~ 'Drop ' ~ $type;
    # Choose
    my $table = $tc.choose(
        [ Any, |@tables.map: { "- $_" } ],
        |$!i<lyt_v_clear>, :$prompt, :undef( '  <=' )
    );
    if ! $table.defined || ! $table.chars {
        return;
    }
    $table ~~ s/ '-' \s //;
    $sql<table> = $ax.quote_table( $!d<tables_info>{$table} );
    my $drop_ok = self!_drop( $sql, $type );
    return $drop_ok;
}



method !_drop ( $sql, $type is copy ) {
    if $type ne 'view' {
        $type = 'table';
    }
    my $stmt_type = 'Drop_' ~ $type;
    $!i<stmt_types> = [ $stmt_type ];
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    $ax.print_sql( $sql );
    # Choose
    my $ok = $tc.choose(
        [ Any, $!i<_confirm> ~ ' Stmt'],
        |$!i<lyt_v>
    );
    if ! $ok {
        return;
    }
    $ax.print_sql( $sql, 'Computing: ... ' );
# begin try
    my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $sql<table> );
    $sth.execute();
    my $col_names = $sth.column-names(); # mysql: $sth.{NAME} before fetchall_arrayref
    my @all_arrayref = $sth.allrows(); ### @
    my $row_count = @all_arrayref.elems;
    @all_arrayref.unshift: $col_names;
    my $prompt = sprintf "DROP %s %s     (on last look at the %s)\n", $type.uc, $sql<table>, $type;
    print-table(
        @all_arrayref,
        |$!o<table>, :$prompt, :1grid, :0max-rows, :1keep-header, :table-expand( $!o<G><info-expand> ) #:2grid
    );
    $prompt = sprintf 'DROP %s %s  (%s %s)', $type.uc, $sql<table>, insert-sep( $row_count, $!o<G><thsd-sep> ), $row_count == 1 ?? 'row' !! 'rows';
# end try
    $prompt ~= "\n\nCONFIRM:";
    # Choose
    my $choice = $tc.choose(
        [ Any, 'YES' ],
        :$prompt, :undef( 'NO' ), :1clear-screen
    );
    $ax.print_sql( $sql );
    if $choice.defined && $choice eq 'YES' {
        my $stmt = $ax.get_stmt( $sql, $stmt_type, 'prepare' );
        $!d<dbh>.do( $stmt ) or die "$stmt failed!";
        return 1;
    }
    return;
}


method create_view {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    require App::DBBrowser::Subqueries;
    my $sq = ::("App::DBBrowser::Subqueries").new( :$!i, :$!o, :$!d ); # You cannot create an instance of this type (Subqueries)
    my $tf = Term::Form.new( :1loop );
    my $sql = {};
    $ax.reset_sql( $sql );
    $!i<stmt_types> = [ 'Create_view' ];

    VIEW_NAME: loop {
        $sql<table> = '?';
        $sql<view_select_stmt> = '';
        $ax.print_sql( $sql );
        # Readline
        my $view = $tf.readline( 'View name: ' );
        if ! $view.chars {
            return;
        }
        $sql<table> = $ax.quote_table( [ Any, $!d<schema>, $view, 'VIEW' ] );

        SELECT_STMT: loop {
            $sql<view_select_stmt> = '?';
            $ax.print_sql( $sql );
            my $select_statment = $sq.choose_subquery( $sql );
            if ! $select_statment.defined {
                next VIEW_NAME;
            }
            if $select_statment ~~ s/ ^ ( <[ \s ( ]>+ ) <?before :i SELECT \s > // {
                my $count = 0 + $0.comb: '(';
                while $count-- {
                    $select_statment ~~ s/ \s* \) \s* $ //;
                }
            }
            $sql<view_select_stmt> = $select_statment;
            #$ax.print_sql( $sql );
            my $ok_create_view = self!_create( $sql, 'view' );
            if ! $ok_create_view {
                next SELECT_STMT;
            }
            return 1;
        }
    }
}


method create_table {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $gc = App::DBBrowser::GetContent.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $sql = {};
    $ax.reset_sql( $sql );
    my @cu_keys = <create_table_plain create_table_form_file create_table_form_copy>;
    my %cu = :create_table_plain(     '- Plain'        ),
             :create_table_form_copy( '- Copy & Paste' ),
             :create_table_form_file( '- From File'    );
    my $old_idx = 0;

    MENU: loop {
        $sql<table> = '';
        $sql<insert_into_args> = [];
        $sql<insert_into_cols> = [];
        $sql<create_table_cols> = [];
        $!i<stmt_types> = [ 'Create_table' ];
        my @choices = Any, |%cu{@cu_keys};
        my $prompt = $!d<db_string> ~ "\n" ~ 'Create table';
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v_clear>, :$prompt, :1index, :default( $old_idx ), :undef( '  <=' )
        );
        if ! $idx.defined || ! @choices[$idx].defined {
            return;
        }
        my $custom = @choices.[$idx];
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 0;
                next MENU;
            }
            $old_idx = $idx;
        }
        $!i<stmt_types>.push: 'Insert';
        my $ok_input;
        if $custom eq %cu<create_table_plain> {
            $ok_input = $gc.from_col_by_col( $sql );
        }
        elsif $custom eq %cu<create_table_form_copy> {
            $ok_input = $gc.from_copy_and_paste( $sql );
        }
        elsif $custom eq %cu<create_table_form_file> {
            $ok_input = $gc.from_file( $sql );
        }
        if ! $ok_input {
            next MENU;
        }
        TABLE: loop {
            my $ok_table_name = self!_set_table_name( $sql );
            if ! $ok_table_name {
                next MENU;
            }
            my $ok_columns = self!_set_columns( $sql );
            if ! $ok_columns {
                $sql<table> = '';
                next TABLE;
            }
            last TABLE;
        }
        my $ok_create_table = self!_create( $sql, 'table' );
        if ! $ok_create_table {
            next MENU;
        }
        if $sql<insert_into_args>.elems {
            my $ok_insert = self!_insert_data( $sql );
            if ! $ok_insert {
                my $drop_ok = self!_drop( $sql, 'TABLE' );
                if ! $drop_ok {
                    return;
                }
            }
        }
        return 1;
    }
}


method !_create ( $sql, $type ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    $ax.print_sql( $sql );
    # Choose
    my $create_table_ok = $tc.choose(
        [ Any, '- YES' ],
        |$!i<lyt_v>,:prompt( "Create $type $sql<table>?" ), :undef( '- NO' )
    );
    if ! $create_table_ok {
        return;
    }
    my $stmt = $ax.get_stmt( $sql, 'Create_' ~ $type, 'prepare' );
    try {
        $!d<dbh>.do( $stmt );
        CATCH { default {
            $ax.print_error_message( $_, 'Create table' );
            return;
        }}
    }
    if $sql<create_table_cols>:exists {
        $sql<create_table_cols>:delete;
    }
    return 1;
}


method !_insert_data ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    $!i<stmt_types> = [ 'Insert' ];
    my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $sql<table> ~ " LIMIT 0" );
    if $!i<driver> ne 'SQLite' {
        $sth.execute();
    }
    my @columns = |$sth.column-names; # |
    if $!col_auto.chars {
        @columns.shift;
    }
    $sql<insert_into_cols> = $ax.quote_simple_many( @columns );
    $ax.print_sql( $sql );
    my $tw = App::DBBrowser::Table::WriteAccess.new( :$!i, :$!o, :$!d );
    my $commit_ok = $tw.commit_sql( $sql );
    return $commit_ok;
}


method !_set_table_name ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my $table;
    my $c = 0;

    loop {
        $ax.print_sql( $sql );
        my $info = '';
        my $default = '';
        if $!d<file_name>.defined {
            my $file = ( $!d<file_name>:delete ).IO.basename; ##
            $info = sprintf "File: '%s'", $file;
            $default = $file.subst( / \. <-[\.]> ** 1..4 $ /, '' );
        }
        if $!d<sheet_name>.defined && $!d<sheet_name>.chars {
            $default ~= '_' ~ $!d<sheet_name>:delete;
        }
        $default ~~ s:g/ \s /_/; # ::
        # Readline
        $table = $tf.readline( 'Table name: ', :$info, :$default );
        if ! $table.chars {
            return;
        }
        $sql<table> = $ax.quote_table( [ Any, $!d<schema>, $table ] );
        if $sql<table> eq  $!d<tables_info>.keys.map({ $ax.quote_table( $!d<tables_info>{$_} ) }).none {
            return 1;
        }
        $ax.print_sql( $sql );
        my $prompt = "Table $sql<table> already exists.";
        my $choice = $tc.choose(
            [ Any, 'New name' ],
            |$!i<lyt_h>, :$prompt, :2layout, :0justify, :undef( 'BACK' )
        );
        if ! $choice.defined {
            return;
        }
    }
}


method !_set_columns ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $row_count = $sql<insert_into_args>.elems;
    my $first_row = $sql<insert_into_args>[0];

    HEADER_ROW: loop {
        if $row_count == 1 + $sql<insert_into_args>.elems {
            $sql<insert_into_args>.unshift: $first_row;
        }
        $sql<create_table_cols> = [];
        $sql<insert_into_cols>  = [];
        $ax.print_sql( $sql );
        my $header_row = self!_header_row( $sql );
        if ! $header_row {
            return;
        }

        AI_COL: loop {
            $sql<create_table_cols> = [ @$header_row ];  # not quoted
            $sql<insert_into_cols>  = [ @$header_row ];  # not quoted
            $ax.print_sql( $sql );
            my $ok_ai = self!_autoincrement_column( $sql);
            if ! $ok_ai {
                next HEADER_ROW;
            }
            my @bu_cols_with_ai = |$sql<create_table_cols>;

            COL_NAMES: loop {
                $ax.print_sql( $sql );
                my $ok_names = self!_column_names( $sql );
                if ! $ok_names {
                    $sql<create_table_cols> = [ @bu_cols_with_ai ];
                    next AI_COL;
                }
                $ax.print_sql( $sql );
                if $sql<create_table_cols>.grep( ! *.chars ).any {
                    $tc.choose(
                        [ 'Column with no name!' ],
                        :prompt( 'Continue with ENTER' )
                    );
                    next COL_NAMES;
                }
                if $sql<create_table_cols>.repeated().elems {
                    $tc.choose(
                        [ 'Duplicate column name!' ],
                        :prompt( 'Continue with ENTER' )
                    );
                    next COL_NAMES;
                }
                my @bu_cols_with_name = |$sql<create_table_cols>;

                DATA_TYPES: loop {
                    my $ok_data_types = self!_data_types( $sql );
                    if ! $ok_data_types {
                        $sql<create_table_cols> = [ @bu_cols_with_name ];
                        next COL_NAMES;
                    }
                    last DATA_TYPES;
                }
                last COL_NAMES;
            }
            last AI_COL;
        }
        last HEADER_ROW;
    }
    $ax.print_sql( $sql );
    return 1;
}

method !_header_row ( $sql ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $header_row;
    my ( $first_row, $user_input ) = ( '- First row', '- Add row' );
    # Choose
    my $choice = $tc.choose(
        [ Any, $first_row, $user_input ],
        |$!i<lyt_v>, :prompt( 'Header:' )
    );
    if ! $choice.defined {
        return;
    }
    elsif $choice eq $first_row {
        $header_row = $sql<insert_into_args>.shift;
    }
    else {
        for ( $!i<idx_added_cols> // [] ).list -> $col_idx {
            $sql<insert_into_args>[0][$col_idx] = Any;
        }
        my $c = 0;
        $header_row = [ $sql<insert_into_args>[0].map: { 'c' ~ ++$c } ];
    }
    return $header_row;
}

method !_autoincrement_column ( $sql ) {
    my $tc = Term::Choose.new( |$!i<default> );
    $!col_auto = '';
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    if $!constraint_auto = $plui.primary_key_autoincrement_constraint( $!d<dbh> ) {
        $!col_auto = $!o<create><autoincrement-col-name>;
    }
    if $!col_auto {
        my ( $no, $yes ) = ( '- NO ', '- YES' );
        # Choose
        my $choice = $tc.choose(
            [ Any, $yes, $no  ],
            |$!i<lyt_v>, :prompt( 'Add AUTO INCREMENT column:' )
        );
        if ! $choice.defined {
            return;
        }
        elsif $choice eq $no {
            $!col_auto = '';
        }
        else {
            $sql<create_table_cols>.unshift: $!col_auto;
        }
    }
    return 1;
}

method !_column_names ( $sql ) {
    my $tf = Term::Form.new( :1loop );
    my $col_number = 0;
    my $fields = [ |$sql<create_table_cols>.map: { [ ++$col_number, $_.defined ?? "$_" !! '' ] } ];
    # Fill_form
    my $form = $tf.fill-form(
        $fields,
        :prompt( 'Col names:' ), :2auto-up, :confirm( '  CONFIRM' ), :back( '  BACK   ' )
    );
    if ! $form {
        return;
    }
    $sql<create_table_cols> = [ |$form.map: { .[1] } ]; # not quoted
    return 1;
}

method !_data_types ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $sql<create_table_cols> = $ax.quote_simple_many( $sql<create_table_cols> ); # now quoted
    $sql<insert_into_cols> = [ |$sql<create_table_cols> ];
    if $!col_auto.chars {
        $sql<insert_into_cols>.shift;
    }
    my $data_types;
    my $fields;
    #if $!o<create><data-type-guessing> {
    #    $ax.print_sql( $sql, 'Guessing data types ... ' );
    #    $data_types = self!_guess_data_type( $sql );
    #}
    if $data_types.defined {
        $fields = [ |$sql<insert_into_cols>.map: { [ $_, $data_types{$_} ] } ];
    }
    else {
        $fields = [ |$sql<insert_into_cols>.map: { [ $_, '' ] } ];
    }
    my $read-only = [];
    if $!col_auto.chars {
        $fields.unshift: [ $ax.quote_col_qualified( [ $!col_auto ] ), $!constraint_auto ];
        $read-only = [ 0 ];
    }
    $ax.print_sql( $sql );
    # Fill_form
    my $col_name_and_type = $tf.fill-form(
        $fields,
        :prompt( 'Data types:' ), :2auto-up, :$read-only, :confirm( '  CONFIRM' ), :back( '  BACK   ' )
    );
    if ! $col_name_and_type {
        return;
    }
    $sql<create_table_cols> = [ |$col_name_and_type.map: { .grep( *.defined ).join: ' ' } ];
    return 1;
}

#method !_guess_data_type ( $sql ) {
#    require SQL::Type::Guess;
#    my $header = $sql<insert_into_cols>;
#    my $table  = $sql<insert_into_args>;
#    my @aoh;
#    for $table.list -> $row {
#        @aoh.push: { ( 0 .. $row.end ).map: { $header[$_] => $row[$_] } };
#    }
#    my $g = SQL::Type::Guess.new();
#    $g.guess( @aoh );
#    my $tmp = $g.column_type;
#    return { |$tmp.keys.map: { $_ => $tmp{$_}.uc } };
#}




