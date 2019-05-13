use v6;
unit class App::DBBrowser::Auxil;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
no precompilation;

use JSON::Fast;

use Term::Choose;
use Term::Choose::LineFold :to-printwidth, :line-fold, :print-columns;
use Term::Choose::Screen :clear, :get-term-size;
use Term::Choose::Util :insert-sep;
use Term::Form;

has $.i;
has $.o;
has $.d;


method installed_modules { # ### 
    my @curs       = $*REPO.repo-chain.grep( *.?prefix.?e );
    my @repo-dirs  = @curs>>.prefix;
    my @dist-dirs  = |@repo-dirs.map( *.child( 'dist' ) ).grep( *.e );
    my @dist-files = |@dist-dirs.map( *.IO.dir.grep( *.IO.f ).Slip );
    my $dists = gather for @dist-files -> $file {
        if try { Distribution.new( |%( from-json( $file.IO.slurp ) ) ) } -> $dist {
            my $cur = @curs.first: { .prefix eq $file.parent.parent }
            take $_ for $dist.hash<provides>.keys;
        }
    }
}


method get_stmt ( $sql, $stmt_type, $used_for ) {
    my $in = $used_for eq 'print' ?? ' ' !! '';
    my $table = $sql<table>;
    my @tmp;
    if $stmt_type eq 'Drop_table' {
        @tmp = "DROP TABLE $table";
    }
    elsif $stmt_type eq 'Drop_view' {
        @tmp = "DROP VIEW $table";
    }
    elsif $stmt_type eq 'Create_table' {
        @tmp = sprintf "CREATE TABLE $table (%s)", $sql<create_table_cols>.map({ $_ // '' }).join: ', '; #
    }
    elsif $stmt_type eq 'Create_view' {
        @tmp = sprintf "CREATE VIEW $table AS " ~ $sql<view_select_stmt>;
    }
    elsif $stmt_type eq 'Select' {
        @tmp = "SELECT" ~ $sql<distinct_stmt> ~ self!select_cols( $sql );
        @tmp.push: " FROM " ~ $table;
        @tmp.push: $in ~ $sql<where_stmt>    if $sql<where_stmt>;
        @tmp.push: $in ~ $sql<group_by_stmt> if $sql<group_by_stmt>;
        @tmp.push: $in ~ $sql<having_stmt>   if $sql<having_stmt>;
        @tmp.push: $in ~ $sql<order_by_stmt> if $sql<order_by_stmt>;
        @tmp.push: $in ~ $sql<limit_stmt>    if $sql<limit_stmt>;
        @tmp.push: $in ~ $sql<offset_stmt>   if $sql<offset_stmt>;
    }
    elsif $stmt_type eq 'Delete' {
        @tmp = "DELETE FROM " ~ $table;
        @tmp.push: $in ~ $sql<where_stmt> if $sql<where_stmt>;
    }
    elsif $stmt_type eq 'Update' {
        @tmp = "UPDATE " ~ $table;
        @tmp.push: $in ~ $sql<set_stmt>   if $sql<set_stmt>;
        @tmp.push: $in ~ $sql<where_stmt> if $sql<where_stmt>;
    }
    elsif $stmt_type eq 'Insert' {
        @tmp = sprintf "INSERT INTO $table (%s)", $sql<insert_into_cols>.join: ', ';
        if $used_for eq 'prepare' {
            @tmp.push: sprintf " VALUES(%s)", ( ( '?' ) xx $sql<insert_into_cols>.elems ).join: ', ';
        }
        else {
            @tmp.push: "  VALUES(";
            my $arg_rows = self.insert_into_args_info_format( $sql, ' ' x 4 );
            @tmp.push: |$arg_rows;
            @tmp.push: "  )";
        }
    }
    elsif $stmt_type eq 'Join' {
        @tmp = $sql<stmt>.split( / <?before \s [ INNER || LEFT || RIGHT || FULL || CROSS ] \s JOIN > / ).map: { $in ~ $_ };
        @tmp[0] ~~ s/ ^ \s //;
    }
    elsif $stmt_type eq 'Union' {
        @tmp = $used_for eq 'print' ?? "SELECT * FROM (" !! "(";
        my $count = 0;
        for $sql<subselect_data>.list -> $ref {
            ++$count;
            my $str = $in x 2 ~ "SELECT " ~ $ref[1].join: ', ';
            $str ~= " FROM " ~ $ref[0];
            if $count < $sql<subselect_data>.elems {
                $str ~= " UNION ALL ";
            }
            @tmp.push: $str;
        }
        @tmp.push: ")";
    }
    if $used_for eq 'prepare' {
        return @tmp.join: '';
    }
    else {
        return @tmp.join( "\n" ) ~ "\n";
    }
}


method insert_into_args_info_format ( $sql, $indent ) {
    my $begin = 5;
    my $max = 12;
    my $end = 0;
    if $max < $begin {
        $begin = $max;
    }
    else {
        $end = $max - $begin;
    }
    $begin--;
    $end--;
    my $list_sep = ', ';
    my $last_i = $sql<insert_into_args>.end;
    my $tmp = [];
    if $sql<insert_into_args>.elems > $max + 3 {
        for $sql<insert_into_args>[^$begin] -> $row { # ^
            $tmp.push: $indent ~ $row.map( { $_ // '' } ).join: $list_sep;
        }
        $tmp.push: $indent ~ '...';
        $tmp.push: $indent ~ '...';
        for $sql<insert_into_args>[ $last_i - $end .. $last_i ] -> $row {
            $tmp.push: $indent ~ $row.map( { $_ // '' } ).join: $list_sep;
        }
        my $row_count = $sql<insert_into_args>.elems;
        $tmp.push: $indent ~ '[' ~ insert-sep( $row_count, $!o<G><thsd-sep> ) ~ ' rows]';
    }
    else {
        for $sql<insert_into_args>.list -> $row {
            $tmp.push: $indent ~ $row.map( { $_ // '' } ).join: $list_sep;
        }
    }
    return $tmp;
}


method !select_cols ( $sql ) {
    my @cols = $sql<select_cols>.elems ?? |$sql<select_cols> !! ( |$sql<group_by_cols>, |$sql<aggr_cols> );
    if ! @cols.elems {
        if $!i<special_table> eq 'join' {
            # So that qualified col names are used in the prepare stmt
            return ' ' ~ $sql<cols>.join: ', ';
        }
        else {
            return " *";
        }
    }
    elsif ! $sql<alias>.keys {
        return ' ' ~ @cols.join: ', ';
    }
    else {
        my @cols_alias;
        for @cols {
            if $sql<alias>{$_}:exists && $sql<alias>{$_}.defined && $sql<alias>{$_}.chars {
                @cols_alias.push: $_ ~ " AS " ~ $sql<alias>{$_};
            }
            else {
                @cols_alias.push: $_;
            }
        }
        return ' ' ~ @cols_alias.join: ', ';
    }
}


method print_sql ( $sql, $waiting = Str, :$return_str) {
    my $str = '';
    for $!i<stmt_types>.list -> $stmt_type {
         $str ~= self.get_stmt( $sql, $stmt_type, 'print' );
    }
    my $filled = self.stmt_placeholder_to_value(
        $str,
        [ |( $sql<set_args> // [] ), |( $sql<where_args> // [] ), |( $sql<having_args> // [] ) ] #  join and union: //[]
    );
    if $filled.defined {
        $str = $filled
    }
    $str ~= "\n";
    $str = line-fold( $str, get-term-size().[0] - 2, '', ' ' x 4 ).join: "\n";
    if $return_str {
        return $str;
    }
    clear();
    print $str;
    #print line_fold( $str, term_width() - 2, '', ' ' x 4 );
    if $waiting.defined {
        #curs_set( 0 );
        print $waiting;
    }
}


method stmt_placeholder_to_value ( $stmt is copy, $args, $quote = 0 ) {
    if ! $args.elems {
        return $stmt;
    }
    my regex placeholder { <?after [ \, || \s || \( ] > \? <?before [ \, || \s || \) || $ ] > }
    for $args.list -> $arg {
        my $arg_copy;
        if $quote && $arg && $arg !~~ Numeric {
            $arg_copy = $!d<dbh>.quote( $arg );
        }
        else {
            $arg_copy = $arg;
        }
        $stmt ~~ s/ <placeholder> /$arg_copy/;
    }
    if $stmt ~~ / <placeholder> / {
        return;
    }
    return $stmt;
}


method alias ( $type, $identifier is copy, $default? ) {
    my $term_w = get-term-size().[0];
    my $info = '';
    if $identifier eq '' { # Union
        $identifier ~= 'UNION Alias: ';
    }
    elsif print-columns( $identifier ~ ' AS ' ) > $term_w / 3 {
        $info = 'Alias: ' ~ "\n" ~ $identifier;
        $identifier = 'AS ';
    }
    else {
        $info = 'Alias: ';
        $identifier ~= ' AS ';
    }
    my $alias;
    if $!o<alias>{$type} {
        my $tf = Term::Form.new( :1loop );
        # Readline
        $alias = $tf.readline( $identifier, :$info );
    }
    if ! $alias.defined || ! $alias.chars {
        if $default.defined {
            $alias = $default;
        }
        else {
            return;
        }
    }
    if $!i<driver> eq 'Pg' && ! $!o<G><quote-identifiers> {
        return $alias.lc;
    }
    return $alias;
}


method quote ( $str ) {
    return "'" ~ $str ~ "'";
}


method quote-identifier ( *@identifier_components ) {
    my $q = $!i<quote-char>;
    return @identifier_components.grep({ .defined && .chars }).map({ "$q$_$q" }).join: $!i<sep-char>;
}


method quote_table ( $td ) {
    my @idx = $!o<G><qualified-table-name> ?? |( 0 .. 2 ) !! 2;
    if $!o<G><quote-identifiers> {
        #return $!d<dbh>.quote-identifier( $td[@idx] );
        return self.quote-identifier( $td[@idx] );
    }
    return $td[@idx].grep({ .defined && .chars }).join: $!i<sep-char>;
}


method quote_col_qualified ( $cd ) {
    if $!o<G><quote-identifiers> {
        #return $!d<dbh>.quote-identifier( $cd );
        return self.quote-identifier( |$cd );
    }
    return $cd.grep({ .defined && .chars }).join: $!i<sep_char>;;
}


method quote_simple_many ( $list ) {
    if $!o<G><quote-identifiers> {
        #return [ $list.map: { $!d<dbh>.quote-identifier( $_ ) } ];
        return [ $list.map: { self.quote-identifier( $_ ) } ];
    }
    return [ |$list ];
}


method backup_href ( $href ) {
    #my $backup = {};
    #for $href.keys {
    #    if ref $href{$_} eq 'ARRAY' {
    #        $backup{$_} = [ |$href{$_} ];
    #    }
    #    elsif ref $href{$_} eq 'HASH' {
    #        $backup{$_} = { |$href{$_} };
    #    }
    #    else {
    #        $backup{$_} = $href{$_};
    #    }
    #}
    #return $backup;
    return clone ( $href )
}


method reset_sql ( $sql ) {
    my $backup = {};
    for <db schema table cols> -> $y {
        $backup{$y} = $sql{$y} if $sql{$y}:exists;
    }
    $sql.keys.map: { $sql{$_}:delete }; # not $sql = {} so $sql is still pointing to the outer $sql
    my @string = <distinct_stmt set_stmt where_stmt group_by_stmt having_stmt order_by_stmt limit_stmt offset_stmt>;
    my @array  = <cols group_by_cols aggr_cols
                     select_cols
                     set_args where_args having_args
                     insert_into_cols insert_into_args
                     create_table_cols>;
    my @hash = <alias>;
    $sql{@string} = '' xx @string.elems;
    $sql{@array}  = [] xx @array.elems;
    $sql{@hash}   = {} xx @hash.elems;
    for $backup.keys -> $y {
        $sql{$y} = $backup{$y};
    }
}

method print_error_message ( $e, $info? is copy ) {
    if $info {
        say $info ~ ':';
    }
    $*ERR.say: $e.message;
    for $e.backtrace.reverse {
        next if ! .subname;
        next if .subname.starts-with('<unit');
        next if .subname.starts-with('MAIN');
        next if .file.starts-with('SETTING::');
        $*ERR.say: "  in block {.subname} at {.file} line {.line}";
    }
    my $tc = Term::Choose.new( |$!i<default> );
    $tc.pause(
        [ 'Press ENTER to continue' ],
        :prompt( '' )
    );
    #hide-cursor();
}


method column_names_and_types ( $tables ) {
    my ( $col_names, $col_types );
    for $tables.list -> $table {
        my $sth = $!d<dbh>.prepare( "SELECT * FROM " ~ self.quote_table( $!d<tables_info>{$table} ) ~ " LIMIT 0" );
        $sth.execute(); # if $!i<driver> ne 'SQLite'; ###
        $col_names{$table} ||= $sth.column-names();
        $col_types{$table} ||= $sth.column-types();
        $sth.finish; #
    }
    return $col_names, $col_types;
}


method write_json ( $file, %perl ) {
    my $json = to-json( %perl );
    spurt $file, $json;
}


method read_json ( $file ) {
    return {} if ! $file.IO.f;
    my $json = slurp $file;
    return {} if ! $json;
    try {
        my %perl = from-json( $json );
        CATCH {
            die "In '$file':\n$_";
        }
        return %perl;
    }
}



sub clone ( %orig ) is export {
    return %orig.deepmap( -> $c is copy { $c } );
}


#sub clone ( %orig ) is export {
#    my %new;
#    for %orig.kv -> $k1, $v1 {
#        if $v1 !~~ Hash {
#            if $v1 ~~ Array {
#                %new{$k1} = [ |$v1 ];
#            }
#            else {
#                %new{$k1} = $v1;
#            }
#            next;
#        }
#        for %orig{$k1}.kv -> $k2, $v2 {
#            if $v2 !~~ Hash {
#                if $v2 ~~ Array {
#                    %new{$k1}{$k2} = [ |$v2 ];
#                }
#                else {
#                    %new{$k1}{$k2} = $v2;
#                }
#                next;
#            }
#            for %orig{$k1}{$k2}.kv -> $k3, $v3 {
#                if $v3 ~~ Array {
#                    %new{$k1}{$k2}{$k3} = [ |$v3 ];
#                }
#                else {
#                    %new{$k1}{$k2}{$k3} = $v3;
#                }
#            }
#        }
#    }
#    return %new;
#}

