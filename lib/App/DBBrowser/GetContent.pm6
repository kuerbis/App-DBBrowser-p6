use v6;
unit class App::DBBrowser::GetContent;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Choose::Screen :clear;
use Term::Choose::Util;
use Term::Form;

use App::DBBrowser::Auxil;
use App::DBBrowser::GetContent::Filter;
use App::DBBrowser::GetContent::ParseFile;
# use App::DBBrowser::Opt::Set; required

has $.i;
has $.o;
has $.d;


method !_print_args ( $sql ) {
    if $!i<stmt_types>.elems == 1 {
        my $ax  = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
        $ax.print_sql( $sql );
    }
    else {
        my $max = 9;
        my @tmp = 'Table Data:';
        my $ax  = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
        my $arg_rows = $ax.insert_into_args_info_format( $sql, '' );
        @tmp.push: |$arg_rows;
        my $str = @tmp.join( "\n" ) ~ "\n\n";
        print clear;
        print $str;
    }
}


method from_col_by_col ( $sql ) {
    $sql<insert_into_args> = [];
    my $tc = Term::Choose.new( |$!i<default> );
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my $col_names = $sql<insert_into_cols>;
    if ! $col_names.elems {
        self!_print_args( $sql );
        # Choose a number
        my $col_count = $tu.choose-a-number( 3,
            :name( 'Number of columns: ' ), :1small-first, :confirm<Confirm>, :back<Back>, :0clear-screen
        );
        if ! $col_count {
            return;
        }
        $col_names = [ |( 1 .. $col_count ).map: { 'c' ~ $_ } ];
        my $col_number = 0;
        my Array @fields = |$col_names.map: { [ ++$col_number, $_.defined ?? "$_" !! '' ] }; ##
        # Fill_form
        my $form = $tf.fill-form(
            @fields,
            :prompt( 'Col names:' ), :2auto-up, :confirm( '  CONFIRM' ), :back( '  BACK   ' )
        );
        if ! $form {
            return;
        }
        $col_names = [ |$form.map: { .[1] } ]; # not quoted
        $sql<insert_into_args>.unshift: $col_names;
    }

    ROWS: loop {
        my $row_idxs = $sql<insert_into_args>.elems;

        COLS: for $col_names.list -> $col_name {
            self!_print_args( $sql );
            # Readline
            my $col = $tf.readline( $col_name ~ ': ' );
            $sql<insert_into_args>[$row_idxs].push: $col;
        }
        my $default = 0;
        if $sql<insert_into_args>.elems {
            $default = $sql<insert_into_args>[*-1].grep( *.chars ) ?? 2 !! 3;
        }

        ASK: loop {
            self!_print_args( $sql );
            my ( $add, $del ) = ( 'Add', 'Del' );
            my @pre = Any, $!i<ok>;
            my @choices = |@pre, $add, $del;
            # Choose
            my $add_row = $tc.choose(
                @choices,
                |$!i<lyt_h>, :prompt( '' ), :$default
            );
            if ! $add_row.defined {
                if $sql<insert_into_args>.elems {
                    $sql<insert_into_args> = [];
                    next ASK;
                }
                $sql<insert_into_args> = [];
                return;
            }
            elsif $add_row eq $!i<ok> {
                if ! $sql<insert_into_args>.elems {
                    return;
                }
                my $bu = [ |$sql<insert_into_args> ];
                my $cf = App::DBBrowser::GetContent::Filter.new( :$!i, :$!o, :$!d );
                my $ok = $cf.input_filter( $sql, 1 );
                if ! $ok {
                    # Choose
                    my $idx = $tc.choose(
                        [ 'NO', 'YES'  ],
                        |$!i<lyt_h>, :prompt( 'Discard all entered data?' ), :1index
                    );
                    if $idx {
                        $sql<insert_into_args> = [];
                        return;
                    }
                    $sql<insert_into_args> = $bu;
                };
                return 1;
            }
            elsif $add_row eq $del {
                if ! $sql<insert_into_args>.elems {
                    return;
                }
                $default = 0;
                $sql<insert_into_args>.pop;
                next ASK;
            }
            last ASK;
        }
    }
}


sub _options_copy_and_paste {
    my $groups = [
        { name => 'group_insert', text => "- Insert Data" },
    ];
    my $options = [
        { name => '_parse_copy',   text => "- Parse Tool",     section => 'insert' },
        { name => '_split_config', text => "- split settings", section => 'split'  },
        { name => '_csv_char',     text => "- CSV settings-a", section => 'csv'    },
        { name => '_csv_options',  text => "- CSV settings-b", section => 'csv'    },
    ];
    return $groups, $options;
}


method from_copy_and_paste ( $sql ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $pf = App::DBBrowser::GetContent::ParseFile.new( :$!i, :$!o, :$!d );
    my $cf = App::DBBrowser::GetContent::Filter.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    my $parse_mode_idx = $!o<insert><copy-parse-mode>;
    my $file = $!i<f_tmp_copy_paste>;
    my $info = $ax.print_sql( $sql, :1return_str ) ~ "\n" ~ 'Multi row:';

    try {
        $file.IO.spurt: $tf.copy_and_paste( :$info );
        CATCH { default {
            $ax.print_error_message( $_, $!i<stmt_types>.join( ', ' ) ~ ' ' ~ 'copy & paste' ); ##
            if $file.IO.e {
                $file.IO.unlink;
            }
            return;
        }}
    }
    if $file.IO.z {
        $sql<insert_into_args> = [];
        return;
    }

    PARSE: loop {
        $sql<insert_into_args> = [];
        my $parse_ok;
        if $parse_mode_idx == 0 {
            $parse_ok = $pf.parse_file_Text_CSV( $sql, $file );
        }
        elsif $parse_mode_idx == 1 {
            $parse_ok = $pf.parse_file_split( $sql, $file );
        }
        if ! $parse_ok {
            die "Error __parse_file!"; #
        };
        if ! $sql<insert_into_args>.grep( *.elems > 0 ).elems {
            $sql<insert_into_args> = [];
            return;
        }
        my $filter_ok = $cf.input_filter( $sql, 1 );
        if ! $filter_ok {
            return;
        }
        elsif $filter_ok == -1 {
            require App::DBBrowser::Opt::Set;
            my $w_opt = ::('App::DBBrowser::Opt::Set').new( :$!i, :$!o );
            my ( $groups, $options ) = _options_copy_and_paste();
            $!o = $w_opt.set_options( $groups, $options );
            $parse_mode_idx = $!o<insert><copy-parse-mode>;
            next PARSE;
        }
        last PARSE;
    }
    $file.IO.unlink;
    return 1;
}


method !_parse_settings_file ( $i ) {
    given $i {
        when 0 { return '(Text::CSV - sep[' ~ $!o<csv><sep-char>    ~ '])' }
        when 1 { return '(split - sep['     ~ $!o<split><field-sep> ~ '])' }
    }
}


sub _options_file ( $file_plus ) {
    my $groups = [
        { name => 'group_insert', text => "- Insert Data" },
    ];
    my $options = [
        { name => '_parse_file',    text => "- Parse Tool",     section => 'insert' },
        { name => '_split_config',  text => "- split settings", section => 'split'  },
        { name => '_csv_char',      text => "- CSV settings-a", section => 'csv'    },
        { name => '_csv_options',   text => "- CSV settings-b", section => 'csv'    },

    ];
    if $file_plus {
        $options.push:
            { name => '_file_encoding', text => "- File Encoding",  section => 'insert' },
            { name => 'history-dirs',   text => "- Dir History",    section => 'insert' };
    }
    return $groups, $options;
}


method from_file ( $sql ) {
    my $pf = App::DBBrowser::GetContent::ParseFile.new( :$!i, :$!o, :$!d );
    my $cf = App::DBBrowser::GetContent::Filter.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );

    DIR: loop {
        my $dir = self!_directory();
        if ! $dir.defined {
            return;
        }
        my @files;
        for $dir.IO.dir().sort -> $file_io {
            next if $file_io ~~ / ^\. /;
            next if ! $file_io.f;
            @files.push: $file_io.Str;
        }
        my $parse_mode_idx = $!o<insert><file-parse-mode>;
        my $old_idx = 1;

        FILE: loop {
            my $hidden = 'Choose File ' ~ self!_parse_settings_file( $parse_mode_idx );
            my @pre = $hidden, Any;
            my @choices = |@pre, |@files;
            # Choose
            my $idx = $tc.choose(
                @choices,
                :prompt( '' ), :2layout, :1index, :default( $old_idx ), :undef( '  <=' ), :1clear-screen
            );
            if ! $idx.defined || ! @choices[$idx].defined {
                return if $!o<insert><history-dirs> == 1;
                next DIR;
            }
            if $!o<G><menu-memory> {
                if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                    $old_idx = 1;
                    next FILE;
                }
                $old_idx = $idx;
            }
            if @choices[$idx] eq $hidden {
                require App::DBBrowser::Opt::Set;
                my $w_opt = ::('App::DBBrowser::Opt::Set').new( :$!i, :$!o );
                my ( $groups, $options ) = _options_file( 1 );
                $!o = $w_opt.set_options( $groups, $options );
                $parse_mode_idx = $!o<insert><file-parse-mode>;
                next FILE;
            }
            my $file_io = @files[$idx-@pre.elems].IO;

            PARSE: loop {
                $sql<insert_into_args> = [];
                my $fh = $file_io.open :r, :enc( $!o<insert><file_encoding> );
                my $parse_ok;
                if $parse_mode_idx == 0 {
                    #try {
                        $parse_ok = $pf.parse_file_Text_CSV( $sql, $fh );
                    #    CATCH { default {
                    #    # ...
                    #    }}
                    #}
                }
                elsif $parse_mode_idx == 1 {
                    #try {
                        $parse_ok = $pf.parse_file_split( $sql, $fh );
                    #    CATCH { default {
                    #    # ...
                    #    }}
                    #}
                }
                if ! $parse_ok {
                    next FILE;
                }
                if ! $sql<insert_into_args>.elems {
                    $tc.pause(
                        [ 'empty file!' ],
                        :prompt( 'Press ENTER' )
                    );
                    $fh.close;
                    next FILE;
                }
                my $filter_ok = $cf.input_filter( $sql, 0 );
                if ! $filter_ok {
                    next FILE;
                }
                elsif $filter_ok == -1 {
                    require App::DBBrowser::Opt::Set;
                    my $w_opt = ::('App::DBBrowser::Opt::Set').new( :$!i, :$!o );
                    my ( $groups, $options ) = _options_file( 0 );
                    $!o = $w_opt.set_options( $groups, $options );
                    $parse_mode_idx = $!o<insert><file-parse-mode>;
                    next PARSE;
                }
                $!d<file_name> = $file_io.Str;
                return 1;
            }
        }
    }
}


method !_directory {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
     my $tc = Term::Choose.new( |$!i<default> );
    if ! $!o<insert><history-dirs> {
        return self!_new_dir_search();
    }
    elsif $!o<insert><history-dirs> == 1 {
        my $h_ref = $ax.read_json: $!i<f_dir_history>;
        if ( $h_ref<dirs> // [] ).elems { ##
            return $h_ref<dirs>[0].IO;
        }
    }
    $!i<old_dir_idx> //= 0;

    DIR: loop {
        my $h_ref = $ax.read_json: $!i<f_dir_history>;
        my @dirs = |( $h_ref<dirs> // [] ).sort; ###
        my $prompt = sprintf "Choose a dir:";
        my @pre = Any, '  NEW search';
        # Choose
        my $idx = $tc.choose(
            [ |@pre, |@dirs.map: { '- ' ~ $_ } ],
            :$prompt, :2layout, :1index, :default( $!i<old_dir_idx> ), :undef( '  <=' ), :1clear-screen
        );
        if ! $idx {
            return;
        }
        if $!o<G><menu-memory> {
            if $!i<old_dir_idx> == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $!i<old_dir_idx> = 0;
                next DIR;
            }
            $!i<old_dir_idx> = $idx;
        }
        my $dir;
        if $idx == @pre.end {
            # Choose
            my $dir_io = self!_new_dir_search();
            if ! $dir_io.defined || ! $dir_io.chars {
                next DIR;
            }
            $dir = $dir_io.Str;
        }
        else {
            $dir = @dirs[$idx-@pre.elems];
        }
        self!_add_to_history( $dir );
        return $dir;
    }
}


method !_new_dir_search {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $dir = ( $!i<tmp_files_dir> || $!i<home_dir> ).Str; ###
    # Choose
    my $chosen_dir_ec = $tu.choose-a-dir( :$dir, :1clear-screen ); # ### choose-a-dir: dir -> Str or IO
    if $chosen_dir_ec {
        $!i<tmp_files_dir> = $chosen_dir_ec.Str;
    }
    return $chosen_dir_ec;
}


method !_add_to_history ( Str $dir ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $h_ref = $ax.read_json: $!i<f_dir_history>;
    my $dirs = $h_ref<dirs>;
    $dirs.unshift: $dir;
    $dirs = [ |$dirs.unique ];
    while $dirs.elems > $!o<insert><history-dirs> {
        $dirs.pop;
    }
    $h_ref<dirs> = $dirs;
    $ax.write_json: $!i<f_dir_history>, $h_ref;
}







