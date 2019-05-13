use v6;
unit class App::DBBrowser::Table::Functions;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
no precompilation;

use Term::Choose;
use Term::Choose::Util;
use Term::Form;

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;

has $.i;
has $.o;
has $.d;


method col_function ( $sql, $clause ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $changed = 0;
    my $cols;
    if $clause eq 'select' && ( |$sql<group_by_cols> || |$sql<aggr_cols> ) {
        $cols = [ |$sql<group_by_cols>, |$sql<aggr_cols> ];
    }
    elsif $clause eq 'having' {
        $cols = [ |$sql<aggr_cols> ];
    }
    else {
        $cols = [ |$sql<cols> ];
    }
    my $functions_args = {
        Bit_Length          => 1,
        Char_Length         => 1,
        Concat              => 9, # Concatenate
        Epoch_to_Date       => 1,
        Epoch_to_DateTime   => 1,
        Truncate            => 1,
    };
    #my @functions_sorted = <Concat Truncate Bit_Length Char_Length Epoch_to_Date Epoch_to_DateTime>;
    my @functions_sorted;
    if $!i<driver> eq 'SQLite' { # DBIish: sqlite3_create_function not available (truncate bit_length, char_length)
        @functions_sorted = <Concat Epoch_to_Date Epoch_to_DateTime>;
    }
    else {
        @functions_sorted = <Concat Truncate Bit_Length Char_Length Epoch_to_Date Epoch_to_DateTime>;
    }

    SCALAR_FUNC: loop {
        # Choose
        my $function = $tc.choose(
            [ Any, |@functions_sorted.map: { "  $_" } ],
            |$!i<lyt_v>, :prompt( 'Function:' ), :undef( '  <=' ) # <= BACK
        );
        if ! $function.defined {
            return;
        }
        $function ~~ s/ ^ \s\s //;
        my $arg_count = $functions_args{$function};
        my $col = self!choose_columns( $sql, $function, $arg_count, $cols ); # cols - col
        if ! $col.defined {
            next SCALAR_FUNC;
        }
        my $col_with_func = self!prepare_col_func( $function, $col );
        if ! $col_with_func.defined {
            next SCALAR_FUNC;
        }
        return $col_with_func;
    }
}

method !choose_columns ( $sql, $function, $arg_count, $cols ) {
    if ! $arg_count {
        return;
    }
    elsif $arg_count == 1 {
        my $tc = Term::Choose.new( |$!i<default> );
        # Choose
        return $tc.choose(
            [ Any, |$cols ],
            |$!i<lyt_h>, :prompt( $function ~ ': ' ), :undef( '<<' )
        );
    }
    else {
        my $tu = Term::Choose::Util.new( |$!i<default> );
        # Choose
        return $tu.choose-a-subset(
            $cols,
            :1layout, :name( $function ~ ': ' ), :sofar-separator<,>, :1keep-chosen
        );
    }
}


method !prepare_col_func ( $func, $qt_col ) { # $qt_col -> $arg
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $quote_f;
    if $func ~~ / ^ Epoch_to_Date [ Time ]? $ / {
        my $prompt = $func eq 'Epoch_to_Date' ?? 'DATE' !! 'DATETIME';
        $prompt ~= "($qt_col)\nInterval:";
        my ( $microseconds, $milliseconds, $seconds ) = (
            '  ****************   Micro-Second',
            '  *************      Milli-Second',
            '  **********               Second' );
        my $tc = Term::Choose.new( |$!i<default> );
        my $choices = [ Any, $microseconds, $milliseconds, $seconds ];
        # Choose
        my $interval = $tc.choose(
            $choices,
            |$!i<lyt_v>, :$prompt
        );
        return if ! $interval.defined;
        my $div = $interval eq $microseconds ?? 1000000 !!
                  $interval eq $milliseconds ?? 1000 !! 1;
        if $func eq 'Epoch_to_DateTime' {
            $quote_f = $plui.epoch_to_datetime( $qt_col, $div );
        }
        else {
            $quote_f = $plui.epoch_to_date( $qt_col, $div );
        }
    }
    elsif $func eq 'Truncate' {
        my $tu = Term::Choose::Util.new( |$!i<default> );
        my $info = $func ~ ': ' ~ $qt_col;
        my $name = "Decimal places: ";
        my $precision = $tu.choose-a-number( 2, :$info, :$name, :1small-first, :0clear-screen );
        return if ! $precision.defined;
        $quote_f = $plui.truncate( $qt_col, $precision );
    }
    elsif $func eq 'Bit_Length' {
        $quote_f = $plui.bit_length( $qt_col );
    }
    elsif $func eq 'Char_Length' {
        $quote_f = $plui.char_length( $qt_col );
    }
    elsif $func eq 'Concat' {
        my $info = "\n" ~ 'Concat( ' ~ $qt_col.join( ',' ) ~ ' )';
        my $tf = Term::Form.new( :1loop );
        my $sep = $tf.readline( 'Separator: ', :$info );
        return if ! $sep.defined;
        $quote_f = $plui.concatenate( $qt_col, $sep );
    }
    return $quote_f;
}




