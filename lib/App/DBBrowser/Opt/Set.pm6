use v6;
unit class App::DBBrowser::Opt::Set;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

#use Pod::To::Text;     # required
#use Pod::load          # required

use Term::Choose;
use Term::Choose::Screen :clear, :clr-to-bot, :show-cursor;
use Term::Choose::Util :insert-sep;
use Term::Form;

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;
use App::DBBrowser::Opt::Get;
use App::DBBrowser::Opt::DBSet;


has $.o;
has $.i;

has $!avail_operators = [
    "REGEXP", "REGEXP_i", "NOT REGEXP", "NOT REGEXP_i", "LIKE", "NOT LIKE", "IS NULL", "IS NOT NULL",
    "IN", "NOT IN", "BETWEEN", "NOT BETWEEN", " = ", " != ", " <> ", " < ", " > ", " >= ", " <= ",
    " = col", " != col", " <> col", " < col", " > col", " >= col", " <= col",
    "LIKE %col%", "NOT LIKE %col%",  "LIKE col%", "NOT LIKE col%", "LIKE %col", "NOT LIKE %col"
];

has $!write_config;


sub _groups {
    my $groups = [
        { name => 'group_help',     text => "  HELP"        },
        { name => 'group_path',     text => "  Path"        },
        { name => 'group_database', text => "- DB Options" },
        { name => 'group_behavior', text => "- Behavior"    },
        { name => 'group_enable',   text => "- Extensions"  },
        { name => 'group_sql',      text => "- SQL",        },
        { name => 'group_output',   text => "- Output"      },
        { name => 'group_insert',   text => "- Insert Data" },
    ];
    return $groups;
}


sub _options ( $group ) {
    my $groups = {
        group_help => [
            { name => 'help', text => "  HELP", section => 'help' },
        ],
        group_path => [
            { name => 'path', text => "  Path", section => 'path' },
        ],
        group_database => [
            { name => 'plugins',      text => "- DB plugins",  section => 'G' },
            { name => '_db_defaults', text => "- DB settings", section => '' },
        ],
        group_behavior => [
            { name => '_menu_memory',  text => "- Menu memory",  section => 'G'     },
            { name => '_keep_header',  text => "- Keep header",  section => 'table' },
            { name => '_table_expand', text => "- Table expand", section => 'table' },
            { name => '_info_expand',  text => "- Info expand",  section => 'G'     },
            { name => '_mouse',        text => "- Mouse mode",   section => 'table' },
        ],
        group_enable => [
            { name => '_e_table',         text => "- Tables menu",   section => 'enable' },
            { name => '_e_join',          text => "- Join menu",     section => 'enable' },
            { name => '_e_union',         text => "- Union menu",    section => 'enable' },
            { name => '_e_substatements', text => "- Substatements", section => 'enable' },
            { name => '_e_parentheses',   text => "- Parentheses",   section => 'enable' },
            { name => '_e_write_access',  text => "- Write access",  section => 'enable' },
        ],
        group_sql => [
            { name => '_meta',                   text => "- Metadata",       section => 'G' },
            { name => 'operators',               text => "- Operators",      section => 'G' },
            { name => '_alias',                  text => "- Alias",          section => 'alias' },
            { name => '_sql_identifiers',        text => "- Identifiers",    section => 'G' },
            { name => '_autoincrement_col_name', text => "- Auto increment", section => 'create' },
#            { name => '_data_type_guessing',     text => "- Data types",     section => 'create' }, # not yet available
            { name => 'max-rows',                text => "- Max Rows",       section => 'G' },
        ],
        group_output => [
            { name => 'min-col-width',       text => "- Colwidth",      section => 'table' },
            { name => 'progress-bar',        text => "- ProgressBar",   section => 'table' },
            { name => 'tab-width',           text => "- Tabwidth",      section => 'table' },
            { name => '_grid',               text => "- Grid",          section => 'table' },
            { name => '_color',              text => "- Color",         section => 'table' },
            { name => '_binary_filter',      text => "- Binary filter", section => 'table' },
            { name => '_squash_spaces',      text => "- Squash spaces", section => 'table' },
            { name => '_set_string',         text => "- Set string",    section => 'table' },
#            { name => '_file_find_warnings', text => "- Warnings",      section => 'G' },
        ],
        group_insert => [
            { name => '_parse_file',    text => "- Parse file",     section => 'insert' },
            { name => '_parse_copy',    text => "- Parse C & P",    section => 'insert' },
            { name => '_split_config',  text => "- split settings", section => 'split'  },
            { name => '_csv_char',      text => "- CSV settings-a", section => 'csv'    },
            { name => '_csv_options',   text => "- CSV settings-b", section => 'csv'    },
            { name => '_file_encoding', text => "- File encoding",  section => 'insert' },
            { name => 'history-dirs',   text => "- File history",   section => 'insert' },
        ],
    };
    return $groups{$group};
}


method set_options ( $arg_groups = _groups(), $arg_options? ) { ###
    my $tc = Term::Choose.new( |$!i<default> );
    if ! $!o || ! $!o.keys { ##
        my $r_opt = App::DBBrowser::Opt::Get.new( :$!o, :$!i );
        $!o = $r_opt.read_config_files();
    }
    clear();
    my $groups;
    if $arg_groups {
        $groups = [ |$arg_groups ]; ##
    }
    else {
        $groups = _groups();
    }
    my $grp_old_idx = 0;

    GROUP: loop {
        my $group;
        if $groups.elems == 1 {
            $group = $groups[0]<name>;
        }
        else {
            my @pre  = Any, $!i<_continue>;
            my @choices = |@pre, |$groups.map: { $_<text> };
            # Choose
            my $grp_idx = $tc.choose(
                @choices,
                |$!i<lyt_v>, :1index, :default( $grp_old_idx ), :undef( $!i<_quit> )
            );
            if ! $grp_idx {
                if $!write_config {
                    self!write_config_files();
                    $!write_config = Any; #:delete;
                }
                clr-to-bot();
                show-cursor();
                exit();
            }
            if $!o<G><menu-memory> {
                if $grp_old_idx == $grp_idx && ! %*ENV<TC_RESET_AUTO_UP> {
                    $grp_old_idx = 0;
                    next GROUP;
                }
                $grp_old_idx = $grp_idx;
            }
            else {
                if $grp_old_idx != 0 {
                    $grp_old_idx = 0;
                    next GROUP;
                }
            }
            if @choices[$grp_idx] eq $!i<_continue> {
                if $!write_config {
                    self!write_config_files();
                    $!write_config = Any; #:delete;
                }
                return $!o;
            }
            $group = $groups[$grp_idx-@pre.elems]<name>;
        };
        my $options;
        if $arg_options {
            $options = [ |$arg_options ]; ###
        }
        else {
            $options = _options( $group );
        }
        my $opt_old_idx = 0;

        OPTION: loop {
            my ( $section, $opt );
            if $options.elems == 1 {
                $section = $options[0]<section>;
                $opt     = $options[0]<name>;
            }
            else {
                my @pre  = Any;
                my @choices = |@pre, |$options.map: { $_<text> };
                # Choose
                my $opt_idx = $tc.choose(
                    @choices,
                    |$!i<lyt_v>, :1index, :default( $opt_old_idx ), :undef( '  <=' )
                );
                if ! $opt_idx {
                    if $groups.elems == 1 {
                        if $!write_config {
                            self!write_config_files();
                            $!write_config = Any; #:delete;
                        }
                        return $!o;
                    }
                    next GROUP;
                }
                if $!o<G><menu-memory> {
                    if $opt_old_idx == $opt_idx && ! %*ENV<TC_RESET_AUTO_UP> {
                        $opt_old_idx = 0;
                        next OPTION;
                    }
                    $opt_old_idx = $opt_idx;
                }
                else {
                    if $opt_old_idx != 0 {
                        $opt_old_idx = 0;
                        next OPTION;
                    }
                }
                $section = $options[$opt_idx-@pre.elems]<section>;
                $opt     = $options[$opt_idx-@pre.elems]<name>;
            }
            my ( $no, $yes ) = ( 'NO', 'YES' );
            if $opt eq 'help' {
                run( 'browse-db', '--man' );
                #my $bin-code = $?DISTRIBUTION.content( 'bin/browse-db' ).open.slurp;
                #my $pod = $bin-code.subst( / ^ .+ \n <?before '=begin pod'> /, '' );
            }
            elsif $opt eq 'path' {
                my @path =
                    'INFO',
                    #'version : ' ~ $main::VERSION,
                    '  bin  : ' ~ $*PROGRAM-NAME,
                    'app-dir: ' ~ $!i<app_dir>;
                $tc.pause(
                    ( 'ENTER', ),
                    :prompt( @path.join: "\n" ), :1clear-screen
                );
            }
            elsif $opt eq '_db_defaults' {
                my $odb = App::DBBrowser::Opt::DBSet.new( :$!i, :$!o );
                $odb.database_setting();
            }
            elsif $opt eq 'plugins' {
                my %installed_plugins = :1SQLite, :1Pg;
                my $proc = run( 'zef', '--installed', 'list', :out, :err );
                for $proc.out.slurp.split( "\n" ) -> $module { # slurp.split
                #my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o );
                #my $installed = $ax.installed_modules();
                #for $installed.list -> $module {
                    if $module ~~ / ^ 'App::DBBrowser::DB::' / {
                        my $plugin = $module.subst( / ^ 'App::DBBrowser::DB::' /, '' );
                        %installed_plugins{$plugin}++;
                    }
                }
                my $prompt = 'Choose DB plugins';
                self!choose_a_subset_wrap( $section, $opt, [ %installed_plugins.keys.sort ], $prompt );
            }
            elsif $opt eq 'operators' {
                my $prompt = 'Choose operators';
                self!choose_a_subset_wrap( $section, $opt, $!avail_operators, $prompt );
            }

            elsif $opt eq '_file_encoding' {
                my $items = [
                    { name => 'file-encoding', prompt => "file-encoding" },
                ];
                my $prompt = 'Encoding CSV files';
                self!group_readline( $section, $items, $prompt );
            }
            elsif $opt eq '_csv_char' {
                my $items = [
                    { name => 'sep-char',    prompt => "sep-char   " },
                    { name => 'quote-char',  prompt => "quote-char " },
                    { name => 'escape-char', prompt => "escape-char" },
                    { name => 'eol',         prompt => "eol        " },
                ];
                my $prompt = 'Text::CSV a';
                self!group_readline( $section, $items, $prompt );
            }
            elsif $opt eq '_split_config' {
                my $items = [
                    { name => 'field-sep',     prompt => "Field separator  " },
                    { name => 'field-l-trim',  prompt => "Trim field left  " },
                    { name => 'field-r-trim',  prompt => "Trim field right " },
                    { name => 'record-sep',    prompt => "Record separator " },
                    { name => 'record-l-trim', prompt => "Trim record left " },
                    { name => 'record-r-trim', prompt => "Trim record right" },

                ];
                my $prompt = 'Config \'split\' mode';
                self!group_readline( $section, $items, $prompt );
            }
            elsif $opt eq '_set_string' {
                my $items = [
                    { name => 'decimal-separator', prompt => "Decimal separator" },
                    { name => 'undef',             prompt => "Undefined field  " },
                ];
                my $prompt = 'Set strings';
                self!group_readline( $section, $items, $prompt );
            }
            elsif $opt eq '_autoincrement_col_name' {
                my $items = [
                    { name => 'autoincrement-col-name', prompt => "AI column name" },
                ];
                my $prompt = 'Default auto increment column name';
                self!group_readline( $section, $items, $prompt );
            }
            elsif $opt eq 'history-dirs' {
                my $digits = 2;
                my $prompt = 'Search history - Max dirs: ';
                self!choose_a_number_wrap( $section, $opt, $prompt, $digits, 1 );
            }
            elsif $opt eq 'tab-width' {
                my $digits = 3;
                my $prompt = 'Set the tab width ';
                self!choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif $opt eq 'min-col-width' {
                my $digits = 3;
                my $prompt = 'Set the minimum column width ';
                self!choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif $opt eq 'progress-bar' {
                my $digits = 7;
                my $prompt = 'Set the threshold for the progress bar ';
                self!choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }

            elsif $opt eq 'max-rows' {
                my $digits = 7;
                my $prompt = 'Set the SQL auto LIMIT ';
                self!choose_a_number_wrap( $section, $opt, $prompt, $digits, 0 );
            }
            elsif $opt eq '_parse_file' {
                my $prompt = 'Parsing "File"';
                # @sub_menu = ( (), );
                my @sub_menu = (
                    ( 'file-parse-mode', "- Use:", ( 'Text::CSV', 'split' ) ), # , 'Spreadsheet::Read'
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_parse_copy' {
                my $prompt = 'Parsing "Copy & Paste"';
                my @sub_menu = (
                    ( 'copy-parse-mode', "- Use:", ( 'Text::CSV', 'split' ) ), # , 'Spreadsheet::Read'
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_csv_options' {
                my $prompt = 'Text::CSV b';
                my @sub_menu = (
                    ( 'allow-loose-escapes', "- allow-loose-escapes", ( $no, $yes ) ),
                    ( 'allow-loose-quotes',  "- allow-loose-quotes",  ( $no, $yes ) ),
                    ( 'allow-whitespace',    "- allow_-whitespace",   ( $no, $yes ) ),
                    ( 'blank-is-undef',      "- blank-is-undef",      ( $no, $yes ) ),
                    ( 'binary',              "- binary",              ( $no, $yes ) ),
                    ( 'empty-is-undef',      "- empty-is-undef",      ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_grid' {
                my $prompt = '"Grid"';
                my @sub_menu = (
                    ( 'grid', "- Grid", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }

            elsif $opt eq '_color' {
                my $prompt = '"ANSI color escapes"';
                my @sub_menu = (
                    ( 'color', "- ANSI color escapes", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_binary_filter' {
                my $prompt = 'Print "BNRY" instead of binary data';
                my @sub_menu = (
                    ( 'binary-filter', "- Binary filter", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_squash_spaces' {
                my $prompt = '"Remove leading and trailing spaces and squash consecutive spaces"';
                my @sub_menu = (
                    ( 'squash-spaces', "- Squash spaces", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
#            elsif $opt eq '_file_find_warnings' {
#                my $prompt = '"SQLite database search"';
#                my @sub_menu = (
#                    ( 'file-find-warnings', "- Enable \"File::Find\" warnings", ( $no, $yes ) )
#                );
#                self!settings_menu_wrap( $section, @sub_menu, $prompt );
#            }
            elsif $opt eq '_meta' {
                my $prompt = 'DB/schemas/tables ';
                my @sub_menu = (
                    ( 'meta-data', "- Add metadata", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_alias' {
                my $prompt = 'Alias for:';
                my @sub_menu = (
                    ( 'aggregate',  "- Aggregate",  ( $no, $yes ) ), # s - p
                    ( 'functions',  "- Functions",  ( $no, $yes ) ),
                    ( 'join',       "- Join",       ( $no, $yes ) ),
                    ( 'subqueries', "- Subqueries", ( $no, $yes ) ),
                    ( 'union',      "- Union",      ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_menu_memory' {
                my $prompt = 'Choose: ';
                my @sub_menu = (
                    ( 'menu-memory', "- Menu memory", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_keep_header' {
                my $prompt = '"Header each Page"';
                my @sub_menu = (
                    ( 'keep-header', "- Keep header", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_table_expand' {
                my $prompt = 'Choose: ';
                my @sub_menu = (
                    ( 'table-expand', "- Expand table rows",   ( $no, $yes ~ ' - fast back', $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_info_expand' {
                my $prompt = 'Choose: ';
                my @sub_menu = (
                    ( 'info-expand', "- Expand info-table rows",   ( $no, $yes ~ ' - fast back', $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_mouse' {
                my $prompt = 'Choose: ';
                my @sub_menu = (
                    ( 'mouse', "- Mouse mode", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_table' {
                my $prompt = 'Extend Tables Menu:';
                my @sub_menu = (
                    ( 'm-derived',   "- Add Derived",     ( $no, $yes ) ),
                    ( 'join',        "- Add Join",        ( $no, $yes ) ),
                    ( 'union',       "- Add Union",       ( $no, $yes ) ),
                    ( 'db-settings', "- Add DB settings", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_join' {
                my $prompt = 'Extend Join Menu:';
                my @sub_menu = (
                    ( 'j-derived', "- Add Derived", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_union' {
                my $prompt = 'Extend Union Menu:';
                my @sub_menu = (
                    ( 'u-derived', "- Add Derived",   ( $no, $yes ) ),
                    ( 'union-all', "- Add Union All", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_substatements' {
                my $prompt = 'Substatement Additions:';
                my @sub_menu = (
                    ( 'expand-select',   "- SELECT",   ( 'None', 'Func', 'SQ',       'Func/SQ'    ) ),
                    ( 'expand-where',    "- WHERE",    ( 'None', 'Func', 'SQ',       'Func/SQ'    ) ),
                    ( 'expand-group-by', "- GROUB BY", ( 'None', 'Func', 'SQ',       'Func/SQ'    ) ),
                    ( 'expand-having',   "- HAVING",   ( 'None', 'Func', 'SQ',       'Func/SQ'    ) ),
                    ( 'expand-order-by', "- ORDER BY", ( 'None', 'Func', 'SQ',       'Func/SQ'    ) ),
                    ( 'expand-set',      "- SET",      ( 'None', 'Func', 'SQ', '=N', 'Func/SQ/=N' ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_parentheses' {
                my $prompt = 'Parentheses in WHERE/HAVING:';
                my @sub_menu = (
                    ( 'parentheses', "- Add Parentheses", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_e_write_access' {
                my $prompt = 'Write access: ';
                my @sub_menu = (
                    ( 'insert-into',  "- Insert records", ( $no, $yes ) ),
                    ( 'update',       "- Update records", ( $no, $yes ) ),
                    ( 'delete',       "- Delete records", ( $no, $yes ) ),
                    ( 'create-table', "- Create table",   ( $no, $yes ) ),
                    ( 'drop-table',   "- Drop   table",   ( $no, $yes ) ),
                    ( 'create-view',  "- Create view",    ( $no, $yes ) ),
                    ( 'drop-view',    "- Drop   view",    ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_sql_identifiers' {
                my $prompt = 'Choose: ';
                my @sub_menu = (
                    ( 'qualified-table-name', "- Qualified table names", ( $no, $yes ) ),
                    ( 'quote-identifiers',    "- Quote identifiers",     ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            elsif $opt eq '_data_type_guessing' {
                my $prompt = 'Data type guessing';
                my @sub_menu = (
                    ( 'data-type-guessing', "- Enable data type guessing", ( $no, $yes ) ),
                );
                self!settings_menu_wrap( $section, @sub_menu, $prompt );
            }
            else {
                die "Unknown option: $opt";
            }
            if $options.elems == 1 {
                if $groups.elems == 1 {
                    if $!write_config {
                        self!write_config_files();
                        $!write_config = Any; #:delete;
                    }
                    return $!o;
                }
                else {
                    next GROUP;
                }
            }
        }
    }
}


method !settings_menu_wrap ( $section, @sub_menu, $prompt ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $changed = $tu.settings-menu( @sub_menu, $!o{$section}, :$prompt );
    return if ! $changed;
    $!write_config++;
}


method !choose_a_subset_wrap ( $section, $opt, $available, $prompt ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $current = $!o{$section}{$opt};
    # Choose_list
    my $info = 'Cur: ' ~ $current.join: ', ';
    my $name = 'New: ';
    my $list = $tu.choose-a-subset(
        $available,
        :$info, :$name, :$prompt, :prefix( '- ' ), :0index, :0keep-chosen,
        :1clear-screen, :back( $!i<back> ), :confirm( $!i<confirm> )
    );
    return if ! $list.defined;
    return if ! $list.elems;
    $!o{$section}{$opt} = $list;
    $!write_config++;
    return;
}


method !choose_a_number_wrap ( $section, $opt, $prompt, $digits, $small-first ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $current = $!o{$section}{$opt};
    my $w = $digits + (( $digits - 1 ) div 3 ) * $!o<G><thsd-sep>.chars; # div
    my $info = 'Cur: ' ~ sprintf( "%*s", $w, insert-sep( $current, $!o<G><thsd-sep> ) );
    my $name = 'New: ';
    #$info = $prompt ~ "\n" ~ $info;
    # Choose_a_number
    my $choice = $tu.choose-a-number(
        $digits,
        :$prompt, :$name, :$info, :1clear-screen, :$small-first
    );
    return if ! $choice.defined;
    $!o{$section}{$opt} = $choice;
    $!write_config++;
    return;
}


method !group_readline ( $section, $items, $prompt ) {
    my $tf = Term::Form.new( :1loop );
    my $list = [ $items.map: { [ $_<prompt>:exists ?? $_<prompt> !! $_<name>, $!o{$section}{$_<name>} ] } ];
    my $new_list = $tf.fill-form(
        $list,
        :$prompt, :2auto-up, :confirm( $!i<confirm> ), :back( $!i<back> )
    );
    if $new_list {
        for ^$items.end -> $i {
            $!o{$section}{$items[$i]<name>} = $new_list[$i][1];
        }
        $!write_config++;
    }
}


method !choose_a_dir_wrap ( $section, $opt ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $info = '';
    if $!o{$section}{$opt}.defined {
        $info = '<< ' ~ $!o{$section}{$opt};
    }
    # Choose_a_dir
    my $dir = $tu.choose-a-dir( :$info, :name( 'OK ' ) );
    return if ! $dir.chars;
    $!o{$section}{$opt} = $dir;
    $!write_config++;
    return;
}


method !write_config_files {
    my $tmp = {};
    for $!o.keys -> $section {
        for $!o{$section}.keys -> $opt {
            $tmp{$section}{$opt} = $!o{$section}{$opt};
        }
    }
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o );
    my $file_name = $!i<f_settings>;
    $ax.write_json( $file_name, $tmp  );
}









