use v6;
unit class App::DBBrowser::DB::SQLite;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use File::Find;
use DBIish;

use Term::Choose;
use Term::Choose::Screen :clear;
use Term::Choose::Util;

use App::DBBrowser::Auxil;
#use App::DBBrowser::Opt::DBGet; # no data in set_attributes

has $.o;
has $.i;

has Str $!driver = 'SQLite'; #


method get_db_driver {
    return $!driver;
}


method set_attributes {
    return [];
}


method set_and_quote_char {
    my $SQL_CATALOG_NAME_SEPARATOR = '.';
    my $SQL_IDENTIFIER_QUOTE_CHAR = '"';

}


method get_db_handle ( $db ) {
    #my $get_db_opt = App::DBBrowser::Opt::DBGet.new( :$!o, :$!i );
    #my $attributes  = $get_db_opt.attributes( $db );
    my $dbh = DBIish.connect( $!driver, :database( $db ) ); #, |$attributes );
#    $dbh.sqlite_create_function( 'regexp', 3, -> $regex, $string, $case_sensitive {
#            $string = '' if ! $string.defined;
#            return $string ~~ m/ <$regex> / if $case_sensitive;
#            return $string ~~ m:i/ <$regex> /; #:
#        }
#    );
#    $dbh.sqlite_create_function( 'truncate', 2, -> $number, $places {
#            return if ! $number.defined;
#            return $number if ! $number ~~ Numeric; #look_like_a_number
#            return sprintf "%.*f", $places, ( $number * 10 ** $places ) div 10 ** $places;
#        }
#    );
#    $dbh.sqlite_create_function( 'bit_length', 1, -> $s {
#            return $s.encode.elems;
#        }
#    );
#    $dbh.sqlite_create_function( 'char_length', 1, 1, -> $s {
#            return $s.chars;
#        }
#    );
    return $dbh;
}


method get_databases {
    my $cache_sqlite_files = $!i<db_cache_file>;
    my $ax = App::DBBrowser::Auxil.new(); ##
    my %db_cache = $ax.read_json( $cache_sqlite_files );
    my @dirs = |(%db_cache<directories> // []);
    if ! @dirs.elems {
        @dirs = $!i<home_dir>;
    }
    my $databases = %db_cache<databases> || [];
    if ! $!i<sqlite_search> && $databases.elems {
        return $databases, [];
    }
    my ( $ok, $change ) = ( '- Confirm', '- Change' );
    my $tc = Term::Choose.new( |$!i<default> );
    my $choice = $tc.choose(
        [ Any, $ok, $change ],
        :prompt( 'Search path: ' ~ @dirs.join: ', ' ), :info( 'SQLite Databases' ), :2layout, :undef( '  BACK' ),
        :1clear-screen
    );
    if ! $choice.defined {
        return $databases;
    }
    if $choice eq $change {
        my $info = 'Del ' ~ @dirs.join: ', ';
        my $name = ' OK ';
        my $tu = Term::Choose::Util.new( |$!i<default> );
        my @new_dirs := $tu.choose-dirs( :info( "Where to search for databases?\n" ~ $info ), :$name );
        if @new_dirs.elems {
            @dirs := @new_dirs;
        }
    }
    $databases = [];
    clear();
     # hide cursor
    print "\rSearching: ...\r";
    
    try {
        for @dirs -> $dir {
            my $files = find(
                type        => 'file',
                keep-going  => True,
                dir         => $dir,
            );
            for $files.list -> $file {

                $file.Str.say;
                my $fh = open $file, :bin;
                #LEAVE $fh.close;
                my $blob = $fh.read( 13 );
                if $fh.defined {
                    $fh.close;
                }
                if $blob.decode( 'utf8-c8' ) eq 'SQLite format' {
                #if $blob.decode eq 'SQLite format' {
                    $databases.push: $file.Str;
                }
            }
        }
        CATCH { default {
            if .defined {
                #my $error = .message.Str;
                my $tc = Term::Choose.new( :1loop );
                $tc.pause(
                    [ 'Continue with ENTER', ],
                    :prompt( .message )
                );
            }
        }}
    }
    print "\rSearching: finished.\r";
    %db_cache<directories> = @dirs.map({ .Str });
    if $databases.elems {
        $databases .= sort;
        %db_cache<databases> = $databases;
    }
    $ax.write_json( $cache_sqlite_files, %db_cache ); ##
    return $databases, [];
}


method get_schemas ( $dbh, $db ) {
    return [ 'main' ], [];
}


method table_info ( $dbh, $schema? ) {
    #if ! $schema.defined {
    my $sth = $dbh.prepare( "PRAGMA database_list" );
    $sth.execute;
    my $tables_info = [];
    for $sth.allrows().list ->( $seq, $schema, $db ) {
        my $stmt = "SELECT name, type FROM $schema.sqlite_master ORDER BY name";
        my $sth = $dbh.prepare( $stmt );
        $sth.execute();
        for $sth.allrows().list -> ( $name, $type ) {
            $tables_info.push: { TABLE_CAT => Any, TABLE_SCHEM => $schema, TABLE_NAME => $name, TABLE_TYPE => $type.uc };
        }
    }
    return $tables_info;
    #}
}


method primary_key_auto {
    return "INTEGER PRIMARY KEY";
}


method primary_and_foreign_keys ( $dbh, $db, $schema, @tables ) {
   # my %pk_cols;
   # my %fks;
   # for @tables -> $table {
   #     for $dbh.selectall_arrayref( "pragma foreign_key_list( $table )" ) -> @c {
   #         %fks{$table}{@c[0]}<foreign_key_col>  [@c[1]] = @c[3];
   #         %fks{$table}{@c[0]}<reference_key_col>[@c[1]] = @c[4];
   #         %fks{$table}{@c[0]}<reference_table> = @c[2];
   #     }
   #     %pk_cols{$table} = [ $dbh->primary_key( Any, $schema, $table ) ];
   # }
   # return %pk_cols, %fks;
}


method sql_regexp ( $quote_col, $do_not_match_regexp, $case_sensitive ) {
    #if $do_not_match_regexp {
    #    return sprintf ' NOT REGEXP(?,%s,%d)', $quote_col, $case_sensitive;
    #}
    #else {
    #    return sprintf ' REGEXP(?,%s,%d)', $quote_col, $case_sensitive;
    #}
}


method concatenate ( @arg ) {
    return @arg.join: ' || ';
}



# scalar functions

method epoch_to_datetime ( $col, $interval ) {
    return;
    #return "DATETIME($col/$interval,'unixepoch','localtime')";
}

method epoch_to_date ( $col, $interval ) {
    return;
    #return "DATE($col/$interval,'unixepoch','localtime')";
}

method truncate ( $col, $precision ) {
    return;
    #return "TRUNCATE($col,$precision)";
}

method bit_length ( $col ) {
    return;
    #return "BIT_LENGTH($col)";
}

method char_length ( $col ) {
    return;
    #return "CHAR_LENGTH($col)";
}




