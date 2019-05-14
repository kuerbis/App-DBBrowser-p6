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


method get_db_handle ( $db ) {
    #my $get_db_opt = App::DBBrowser::Opt::DBGet.new( :$!o, :$!i );
    #my $attributes  = $get_db_opt.attributes( $db );
    my $dbh = DBIish.connect( $!driver, :database( $db ) ); #, |$attributes );
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


method set_attributes {
    return [];
}

