use v6;
unit class App::DBBrowser:ver<0.0.3>;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Choose::Screen :clear, :hide-cursor, :show-cursor, :clr-to-bot;
use Term::TablePrint :print-table;

#use App::DBBrowser::AttachDB;    # required
use App::DBBrowser::Auxil;
#use App::DBBrowser::CreateTable; # required
use App::DBBrowser::DB;
#use App::DBBrowser::Join;        # required
#use App::DBBrowser::Opt::DBSet;  # required
use App::DBBrowser::Opt::Get;
#use App::DBBrowser::Opt::Set;    # required
#use App::DBBrowser::Subqueries;  # required ###
use App::DBBrowser::Table;
#use App::DBBrowser::Union;       # required


has $.help;
has $.search;
has @.sqlite_databases;

has $!d;
has $!o;
has $!i = %(
    default     => %( :1loop, :prompt( 'Choose:' ),  :undef( '<<' ) ),
    lyt_h       => %( :0order, :2justify ),
    lyt_v       => %( :undef( '  BACK' ), :2layout ),
    lyt_v_clear => %( :undef( '  BACK' ), :2layout, :1clear-screen ),

    quit      => 'QUIT',
    back      => 'BACK',
    confirm   => 'CONFIRM',
    _quit     => '  QUIT',
    _back     => '  BACK',
    _continue => '  CONTINUE',
    _confirm  => '  CONFIRM',
    _reset    => '  RESET',
    ok        => '-OK-',

    expand_signs     => [ '',  'f()', 'SQ',       '%%' ],
    expand_signs_set => [ '',  'f()', 'SQ', '=N', '%%' ],

    aggregate => [ "AVG(X)", "COUNT(X)", "COUNT(*)", "GROUP_CONCAT(X)", "MAX(X)", "MIN(X)", "SUM(X)" ],
);


method !init {
    $!i<home_dir> = $*HOME;
    if ! $!i<home_dir>.d {
        say "'Could not find the home directory!";
        say "'browse-db' requires a home directory.";
        show-cursor();
        clr-to-bot();
        exit;
    }
    $!i<app_dir> = $!i<home_dir>.add( '.config' ).add( 'browse-db6' );
    if ! $!i<app_dir>.IO.d {
        $!i<app_dir>.IO.mkdir;
    }
    $!i<conf_file_fmt>    = $!i<app_dir>.IO.add: 'config_%s6.json';
    $!i<db_cache_file>    = $!i<app_dir>.IO.add: 'cache_SQLite_files6.json';
    $!i<f_settings>       = $!i<app_dir>.IO.add: 'general_settings6.json';
    $!i<f_tmp_copy_paste> = $!i<app_dir>.IO.add: 'tmp_copy_and_paste6.csv'; #
    $!i<f_subqueries>     = $!i<app_dir>.IO.add: 'subqueries6.json'; #
    $!i<f_dir_history>    = $!i<app_dir>.IO.add: 'dir_history6.json'; #
    $!i<f_attached_db>    = $!i<app_dir>.IO.add: 'attached_DB6.json';
    $!i<help>          = $!help;
    $!i<sqlite_search> = $!search;

    #try {
        my $r_opt = App::DBBrowser::Opt::Get.new( :$!i, :$!o );
        $!o = $r_opt.read_config_files();
        if $!i<help> {
            $!i<default><mouse> = $!o<table><mouse>;
            require App::DBBrowser::Opt::Set;
            my $w_opt = App::DBBrowser::Opt::Set.new( :$!i, :$!o );
            $!o = $w_opt.set_options;
        }
     #   CATCH { default { ###    
     #       my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
     #       $ax.print_error_message( $_, 'Options' );
     #       my $r_opt = App::DBBrowser::Opt::Get.new( :$!i );
     #       $!o = $r_opt.defaults();
     #   }}
    #}
    $!i<default><mouse> = $!o<table><mouse>;
}


END {
    #show-cursor(); 
    #clr-to-bot();
}


method run {
    signal(SIGINT).tap: {
        $!i<f_tmp_copy_paste>.IO.unlink if $!i<f_tmp_copy_paste>.defined && $!i<f_tmp_copy_paste>.IO.e;
        %*ENV<TC_RESET_AUTO_UP>:delete  if %*ENV<TC_RESET_AUTO_UP>:exists;
        show-cursor();
        clr-to-bot();
        #"^C".note;
        "\n".note;
        exit 1;
    };
    hide-cursor();
    self!init();
    my $tc = Term::Choose.new( |$!i<default> );
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $auto_one = 0;
    my $old_idx_plugin = 0;
    clear();

    PLUGIN: loop {

        my $plugin;
        if $!o<G><plugins>.elems == 1 {
            $auto_one++;
            $plugin = $!o<G><plugins>[0];
        }
        else {
            my @choices_plugins = Any, |$!o<G><plugins>.map: { "- $_" };
            # Choose
            my $idx_plugin = $tc.choose(
                @choices_plugins,
                |$!i<lyt_v_clear>, :prompt( 'DB Plugin: ' ), :1index, :default( $old_idx_plugin ), :undef( $!i<_quit> )
            );
            if $idx_plugin.defined {
                $plugin = @choices_plugins[$idx_plugin];
            }
            if ! $plugin.defined {
                last PLUGIN;
            }
            if $!o<G><menu_memory> {
                if $old_idx_plugin == $idx_plugin && ! %*ENV<TC_RESET_AUTO_UP> {
                    $old_idx_plugin = 0;
                    next PLUGIN;
                }
                $old_idx_plugin = $idx_plugin;
            }
            $plugin ~~ s/ ^ <[ - \s ]> \s //;
        }
        $plugin = 'App::DBBrowser::DB::' ~ $plugin;
        $!i<plugin> = $plugin;
        my $plui;
        try {
            $plui = App::DBBrowser::DB.new( :$!i, :$!o );
            $!i<driver> = $plui.get_db_driver();
            ( $!i<quote-char>, $!i<sep-char> ) = $plui.identifier_chars();
            if $!i<driver> eq 'Pg' {
                $!i<aggregate>[3] = "STRING_AGG(X)"; # GROUP_CONCAT(X)
            }
            CATCH { default {
                $ax.print_error_message( $_, 'Load plugin' );
                next PLUGIN if $!o<G><plugins>.elems > 1;
                last PLUGIN;
            }}
        }

        # DATABASES

        my @databases;
        my $prefix = $!i<driver> eq 'SQLite' ?? '' !! '- ';
        try {
            my ( $user_dbs, $sys_dbs ) = $plui.get_databases();
            $!d<user_dbs> = $user_dbs;
            $!d<sys_dbs>  = $sys_dbs;
            if $prefix {
                @databases = |$user_dbs.map({ $prefix ~ $_ }), $!o<G><meta-data> ?? |$sys_dbs.map({ '  ' ~ $_ }) !! |();
            }
            else {
                @databases = |$user_dbs, $!o<G><meta-data> ?? |$sys_dbs !! |();
            }
            $!i<sqlite_search> = 0 if $!i<sqlite_search>;
            CATCH { default {
                $ax.print_error_message( $_, 'Get databases' );
                $!i<login_error> = 1;
                next PLUGIN if $!o<G><plugins>.elems > 1;
                last PLUGIN;
            }}
        }

        if ! @databases.elems {
            $tc.pause(
                [ 'Enter' ],
                :prompt( 'No Databases!' )
            );
            next PLUGIN if $!o<G><plugins>.elems > 1;
            last PLUGIN;
        }
        my $db;
        my $old_idx_db = 0;

        DATABASE: loop {

            if $!i<redo_db> {
                $db = $!i<redo_db>:delete;
                $db = $prefix ~ $db if $prefix;
            }
            elsif @databases.elems == 1 {
                $db = @databases[0];
                $auto_one++ if $auto_one == 1;
            }
            else {
                my $back;
                if $prefix {
                    $back = $auto_one ?? $!i<_quit> !! $!i<_back>;
                }
                else {
                    $back = $auto_one ?? $!i<quit> !! $!i<back>;
                }
                my @choices_db = Any, |@databases;
                # Choose
                my $idx_db = $tc.choose(
                    @choices_db,
                    |$!i<lyt_v_clear>, :prompt( 'Choose Database:' ), :1index, :default( $old_idx_db ), :undef( $back )
                );
                $db = Any;
                if $idx_db.defined {
                    $db = @choices_db[$idx_db];
                }
                if ! $db.defined {
                    next PLUGIN if $!o<G><plugins>.elems > 1;
                    last PLUGIN;
                }
                if $!o<G><menu-memory> {
                    if $old_idx_db == $idx_db && ! %*ENV<TC_RESET_AUTO_UP> {
                        $old_idx_db = 0;
                        next DATABASE;
                    }
                    $old_idx_db = $idx_db;
                }
            }
            $db ~~ s/ ^ <[ - \s ]> \s // if $prefix;
            $!d<db> = $db;

            # DB-HANDLE

            my $dbh;
            try {
                $dbh = $plui.get_db_handle( $db );
                $!d<dbh> = $dbh;
                CATCH { default {
                    $ax.print_error_message( $_, 'Get database handle' );
                    # remove database from @databases
                    $!i<login_error> = 1;
                    $dbh.dispose() if $dbh.defined; # || $dbh<Active>;
                    next DATABASE  if @databases.elems      > 1;
                    next PLUGIN    if $!o<G><plugins>.elems > 1;
                    last PLUGIN;
                }}
            }

            $!i<db_attached>   = 0;
            if $!i<driver> eq 'SQLite' && ! $!i<f_attached_db>.IO.z {
                my $h_ref = $ax.read_json( $!i<f_attached_db> );
                my $attached_db = $h_ref{$db} // [];
                if $attached_db.elems {
                    for $attached_db.list -> $ref {
                        my $stmt = sprintf "ATTACH DATABASE %s AS %s", $ax.quote-identifier( $ref[0] ), $ax.quote( $ref[1] );
                        $dbh.do( $stmt );
                    }
                    $!i<db_attached> = 1;
                    if $!i<backup_option_qualified>:!exists {
                        $!i<backup_option_qualified> = $!o<G><qualified-table-name>;
                    }
                    $!o<G><qualified-table-name> = 1; # if attached db: enable qualified table name automatically
                }
            }
            if $!i<backup_option_qualified>:exists && ! $!i<db_attached> {
                $!o<G><qualified-table-name> = $!i<backup_option_qualified>:delete;
            }
            $!i<lyt_history> = [];
            $plui = App::DBBrowser::DB.new( :$!i, :$!o );

            # SCHEMAS

            my @schemas;
            my ( $user_schemas, $sys_schemas ) = ( [], [] );
            try {
                ( $user_schemas, $sys_schemas ) = $plui.get_schemas( $dbh, $db );
                @schemas = |$user_schemas.map: { "- $_" };
                if $!o<G><meta-data> {
                    @schemas.push: |$sys_schemas.map: { "  $_" };
                }
                CATCH { default {
                    $ax.print_error_message( $_, 'Get schemas' );
                    $dbh.dispose();
                    next DATABASE  if @databases.elems      > 1;
                    next PLUGIN    if $!o<G><plugins>.elems > 1;
                    last PLUGIN;
                }}
            }
            my $old_idx_sch = 0;

            SCHEMA: loop {

                my $db_string = 'DB ' ~ $db.IO.basename ~ '';
                my $schema;
                if $!i<redo_schema> {
                    $schema = $!i<redo_schema>:delete;
                }
                elsif ! @schemas.elems {
                    if $!i<driver> eq 'Pg' {
                        # no @schemas if 'add meta data' is disabled with no user-schemas
                        # with an undefined schema 'information_schema' would be used
                        @schemas = 'public';
                        $schema = @schemas[0];
                    }
                }
                elsif @schemas.elems == 1 {
                    $schema = @schemas[0];
                    $schema ~~ s/ ^ <[ - \s ]> \s //;
                    $auto_one++ if $auto_one == 2
                }
                else {
                    my $back   = $auto_one == 2 ?? $!i<_quit> !! $!i<_back>;
                    my $prompt = $db_string ~ ' - choose Schema:';
                    my $choices_schema = [ Any, |@schemas ];
                    # Choose
                    my $idx_sch = $tc.choose(
                        $choices_schema,
                        |$!i<lyt_v_clear>, :$prompt, :1index, :default( $old_idx_sch ), :undef( $back )
                    );
                    if $idx_sch.defined {
                        $schema = $choices_schema[$idx_sch];
                    }
                    if ! $schema.defined {
                        $dbh.dispose();
                        next DATABASE  if @databases.elems      > 1;
                        next PLUGIN    if $!o<G><plugins>.elems > 1;
                        last PLUGIN;
                    }
                    if $!o<G><menu-memory> {
                        if $old_idx_sch == $idx_sch && ! %*ENV<TC_RESET_AUTO_UP> {
                            $old_idx_sch = 0;
                            next SCHEMA;
                        }
                        $old_idx_sch = $idx_sch;
                    }
                    $schema ~~ s/ ^ <[ - \s ]> \s //;
                }
                $db_string = 'DB ' ~ $db.IO.basename ~ ( @schemas.elems > 1 ?? '.' ~ $schema !! '' ) ~ '';
                $!d<schema>       = $schema;
                $!d<user_schemas> = $user_schemas;
                $!d<sys_schemas>  = $sys_schemas;
                $!d<db_string>    = $db_string;

                # TABLES

                my $tables_info;
                try {
                    # if a SQLite database has databases attached, set $schema to Any so 'table_info' in 'tables_data'
                    # returns also the tables from the attached databases
                    $tables_info = $plui.tables_data( $dbh, $!i<db_attached> ?? Str !! $schema );
                    CATCH { default {
                        $ax.print_error_message( $_, 'Get tables' );
                        next SCHEMA    if @schemas.elems        > 1;
                        $dbh.dispose();
                        next DATABASE  if @databases.elems      > 1;
                        next PLUGIN    if $!o<G><plugins>.elems > 1;
                        last PLUGIN;
                    }}
                }
                my ( $user_tables, $sys_tables ) = ( [], [] );
                for $tables_info.keys -> $table {
                    if $tables_info{$table}[3] ~~ / SYSTEM / {
                        $sys_tables.push: $table;
                    }
                    else {
                        $user_tables.push: $table;
                    }
                }
                #if $!i<backup_option_qualified> {
                #    for @user_tables -> $table {
                #        my $tmp = $tables_info{$table}:delete;
                #        $table = '[' ~ $tmp[1] ~ ']' ~ $tmp[2];
                #        $tables_info{$table} = $tmp;
                #    }
                #}
                $!d<tables_info> = $tables_info;
                $!d<user_tables> = $user_tables;
                $!d<sys_tables>  = $sys_tables;
                my $old_idx_tbl = 1;

                TABLE: loop {

                    my ( $join, $union, $from_subquery, $db_setting ) = ( '  Join', '  Union', '  Derived', '  DB settings' );
                    my $hidden = $db_string;
                    my $table;
                    if $!i<redo_table> {
                        $table = $!i<redo_table>:delete;
                    }
                    else {
                        my @choices_table = $hidden, Any, |$user_tables.sort.map: { "- $_" };
                        @choices_table.push: |$sys_tables.sort.map: { "  $_" } if $!o<G><meta-data>;
                        @choices_table.push: $from_subquery                    if $!o<enable><m-derived>; #-
                        @choices_table.push: $join                             if $!o<enable><join>;
                        @choices_table.push: $union                            if $!o<enable><union>;
                        @choices_table.push: $db_setting                       if $!o<enable><db-settings>;
                        my $back = $auto_one == 3 ?? $!i<_quit> !! $!i<_back>;
                        # Choose
                        my $idx_tbl = $tc.choose(
                            @choices_table,
                            |$!i<lyt_v_clear>, :prompt( '' ), :1index, :default( $old_idx_tbl ), :undef( $back )
                        );
                        if $idx_tbl.defined {
                            $table = @choices_table[$idx_tbl];
                        }
                        if ! $table.defined {
                            next SCHEMA     if @schemas.elems        > 1;
                            $dbh.dispose(); #
                            next DATABASE   if @databases.elems      > 1;
                            next PLUGIN     if $!o<G><plugins>.elems > 1;
                            last PLUGIN;
                        }
                        if $!o<G><menu-memory> {
                            if $old_idx_tbl == $idx_tbl && ! %*ENV<TC_RESET_AUTO_UP> {
                                $old_idx_tbl = 1;
                                next TABLE;
                            }
                            $old_idx_tbl = $idx_tbl;
                        }
                    }
                    if $table eq $db_setting {
                        my $changed;
                        try {
                            require App::DBBrowser::Opt::DBSet;
                            my $w_db_opt = App::DBBrowser::Opt::DBSet.new( $!i, $!o );
                            $changed = $w_db_opt.database_setting( $db );
                            CATCH { default {
                                $ax.print_error_message( $_, 'Database settings' );
                                next TABLE;
                            }}
                        }
                        if $changed {
                            $!i<redo_db> = $db;
                            $!i<redo_schema> = $schema;
                            $dbh.dispose(); # reconnects #
                            next DATABASE;
                        }
                        next TABLE;
                    }
                    if $table eq $hidden {
                        self!create_drop_or_attach( $table );
                        if $!i<redo_db> {
                            $dbh.dispose();
                            next DATABASE;
                        }
                        elsif $!i<redo_schema> {
                            next SCHEMA;
                        }
                        next TABLE;
                    }
                    my ( $qt_table, $qt_columns );
                    if $table eq $join {
                        require App::DBBrowser::Join;
                        my $new_j = App::DBBrowser::Join.new( :$!i, :$!o, :$!d );
                        $!i<special_table> = 'join';
                        try {
                            ( $qt_table, $qt_columns ) = $new_j.join_tables();
                            CATCH { default {
                                $ax.print_error_message( $_, 'Join' );
                                next TABLE;
                            }}
                        }
                        next TABLE if ! $qt_table.defined;
                    }
                    elsif $table eq $union {
                        require App::DBBrowser::Union;
                        my $new_u = App::DBBrowser::Union.new( :$!i, :$!o, :$!d );
                        $!i<special_table> = 'union';
                        try {
                            ( $qt_table, $qt_columns ) = $new_u.union_tables();
                            CATCH { default {
                                $ax.print_error_message( $_, 'Union' );
                                next TABLE;
                            }}
                        }
                        next TABLE if ! $qt_table.defined;
                    }
                    elsif $table eq $from_subquery {
                        $!i<special_table> = 'subquery';
                        try {
                            ( $qt_table, $qt_columns ) = self!derived_table();
                            CATCH { default {
                                $ax.print_error_message( $_, 'Derived table' );
                                next TABLE;
                            }}
                        }
                        next TABLE if ! $qt_table.defined;
                    }
                    else {
                        $!i<special_table> = '';
                        try {
                            $table.=subst( / ^ <[ - \s ]> \s /, '' );
                            $!d<table> = $table;
                            $qt_table = $ax.quote_table( $!d<tables_info>{$table} );
                            my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $qt_table ~ " LIMIT 0" );
                            if $!i<driver> ne 'SQLite' {
                                $sth.execute();
                            }
                            $!d<cols> = $sth.column-names();
                            $sth.finish();
                            $qt_columns = $ax.quote_simple_many( $!d<cols> );
                            CATCH { default {
                                $ax.print_error_message( $_, 'Ordinary table' );
                                next TABLE;
                            }}
                        }
                    }
                    $!i<old_idx_hidden>:delete if $!i<old_idx_hidden>:exists; ###
                    self!browse_the_table( $qt_table, $qt_columns );
                }
            }
        }
    }
    # END of App
    %*ENV<TC_RESET_AUTO_UP>:delete;
    show-cursor();
    clr-to-bot();
}


method !browse_the_table ( $qt_table, $qt_columns ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $pt = Term::TablePrint.new();
    my $sql = {};
    $ax.reset_sql( $sql );
    $sql<table> = $qt_table;
    $sql<cols> = $qt_columns;
    $!i<stmt_types> = [ 'Select' ];
    #$ax.print_sql( $sql ); # ?

    PRINT_TABLE: loop {
        my $all_arrayref;
        try {
            my $tt = App::DBBrowser::Table.new( :$!i, :$!o, :$!d );
            #( $all_arrayref, $sql ) = $tt.on_table( $sql ); ### 
            $all_arrayref = $tt.on_table( $sql );
            CATCH { default {
                $ax.print_error_message( $_, 'Print table' );
                last PRINT_TABLE;
            }}
        }
        if ! $all_arrayref.defined {
            last PRINT_TABLE;
        }

        print-table( $all_arrayref, |$!o<table> );
        hide-cursor(); ## loop 
        $!o<table><max-rows>:delete;
    }
}


method !create_drop_or_attach ( $table ) {
    my $old_idx;
    if $!i<old_idx_hidden>:exists {
        $old_idx = $!i<old_idx_hidden>:delete;
    }
    else {
        $old_idx = 0;
    }
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );

    HIDDEN: loop {
        my ( $create_table,    $drop_table,    $create_view,    $drop_view,    $attach_databases, $detach_databases ) = (
           '- CREATE Table', '- DROP Table', '- CREATE View', '- DROP View', '- Attach DB',     '- Detach DB',
        );
        my @choices;
        @choices.push: $create_table if $!o<enable><create-table>;
        @choices.push: $create_view  if $!o<enable><create-view>;
        @choices.push: $drop_table   if $!o<enable><drop-table>;
        @choices.push: $drop_view    if $!o<enable><drop-view>;
        if $!i<driver> eq 'SQLite' { # no attached databases in sqlite_master
            @choices.push: $attach_databases;
            @choices.push: $detach_databases if $!i<db_attached>;
        }
        if ! @choices.elems {
            return;
        }
        my @pre = Any;
        # Choose
        my $idx = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_v_clear>, :prompt( $!d<db_string> ), :1index, :default( $old_idx ), :undef( '  <=' )
        );
        if ! $idx {
            return;
        }
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 0;
                next HIDDEN;
            }
            $old_idx = $idx;
        }
        die if $idx < @pre.elems;
        my $choice = @choices[$idx-@pre.elems];
        if $choice ~~ / ^ '-' \s [ DROP || CREATE ] \s / {
            require App::DBBrowser::CreateTable;
            my $ct = App::DBBrowser::CreateTable.new( :$!i, :$!o, :$!d );
            if $choice eq $create_table {
                try {
                    $ct.create_table();
                    CATCH { default {
                        $ax.print_error_message( $_, 'Create Table' );
                    }}
                }
            }
            elsif $choice eq $create_view {
                try {
                    $ct.create_view();
                    CATCH { default {
                        $ax.print_error_message( $_, 'Create View' );
                    }}
                }
            }
            elsif $choice eq $drop_table {
                try {
                    $ct.drop_table();
                    CATCH { default {
                        $ax.print_error_message( $_, 'Drop Table' );
                    }}
                }
            }
            elsif $choice eq $drop_view {
                try {
                    $ct.drop_view();
                    CATCH { default {
                        $ax.print_error_message( $_, 'Drop View' );
                    }}
                }
            }
            $!i<old_idx_hidden> = $old_idx;
            $!i<redo_db>     = $!d<db>;
            $!i<redo_schema> = $!d<schema>;
            $!i<redo_table>  = $table;
            return;
        }
        elsif $choice eq $attach_databases || $choice eq $detach_databases {
            require App::DBBrowser::AttachDB;
            my $att = App::DBBrowser::AttachDB.new( :$!i, :$!o, :$!d );
            my $changed;
            if $choice eq $attach_databases {
                try {
                    $changed = $att.attach_db();
                    CATCH { default {
                        $ax.print_error_message( $_, 'Attach DB' );
                        next HIDDEN;
                    }}
                }
            }
            elsif $choice eq $detach_databases {
                try {
                    $changed = $att.detach_db();
                    CATCH { default { 
                        $ax.print_error_message( $_, 'Detach DB' );
                        next HIDDEN;
                    }}
                }
            }
            if ! $changed {
                next HIDDEN;
            }
            else {
                $!i<old_idx_hidden> = $old_idx;
                $!i<redo_db>     = $!d<db>;
                $!i<redo_schema> = $!d<schema>;
                $!i<redo_table>  = $table;
                return;
            }
        }
    }
}


method !derived_table {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    require App::DBBrowser::Subqueries;
    #use App::DBBrowser::Subqueries;
    my $sq = ::("App::DBBrowser::Subqueries").new( :$!i, :$!o, :$!d ); # You cannot create an instance of this type (Subqueries)
    $!i<stmt_types> = [ 'Select' ];
    my $tmp = { table => '()' };
    $ax.reset_sql( $tmp );
    $ax.print_sql( $tmp );
    my $qt_table = $sq.choose_subquery( $tmp );
    if ! $qt_table.defined {
        return;
    }
    my $alias = $ax.alias( 'subqueries', $qt_table, 'From_SQ' );
    $qt_table ~= " AS " ~ $ax.quote_col_qualified( [ $alias ] );
    $tmp<table> = $qt_table;
    $ax.print_sql( $tmp );
    my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ $qt_table ~ " LIMIT 0" );
    if $!i<driver> ne 'SQLite' {
        $sth.execute();
    }
    $!d<cols> = $sth.column-names();
    $sth.finish();
    my $qt_columns = $ax.quote_simple_many( $!d<cols> );
    return $qt_table, $qt_columns;
}





=begin pod

=head1 NAME

App::DBBrowser - Browse SQLite/PostgreSQL databases and their tables interactively.

=head1 VERSION

Version 0.001

=head1 DESCRIPTION

See L<browse-db> for further information.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod

