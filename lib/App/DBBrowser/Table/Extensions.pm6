use v6;
unit class App::DBBrowser::Table::Extensions;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;

use Term::Choose;


use App::DBBrowser::Auxil;
#use App::DBBrowser::Subqueries;        # required
#use App::DBBrowser::Table::Functions;  # required

has $.i;
has $.o;
has $.d;


method extended_col ( $sql, $clause ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my ( $none, $function, $subquery, $all ) = |$!i<expand_signs>;
    my $set_to_null = '=N';
    my @values;
    if $clause eq 'set' {
        @values = Any, [ $function ], [ $subquery ], [ $set_to_null ], [ $function, $subquery, $set_to_null ];
    }
    else {
        @values = Any, [ $function ], [ $subquery ], [ $function, $subquery ];
    }
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my @types := @values[$sign_idx];
    my $type;
    if @types == 1 {
        $type = @types[0];
    }
    else {
        # Choose
        $type = $tc.choose(
            [ Any, |@types ],
            |$!i<lyt_h>, :undef( '<<' )
        );
        if ! $type.defined {
            return;
        }
    }
    my ( $ext_col, $alias_type );
    if $type eq $subquery {
        require App::DBBrowser::Subqueries;
        my $sq = App::DBBrowser::Subqueries.new( :$!i, :$!o, :$!d ); # works
        my $subq = $sq.choose_subquery( $sql );
        if ! $subq.defined {
            return;
        }
        $ext_col = $subq;
        $alias_type = 'subqueries';
    }
    elsif $type eq $function {
        require App::DBBrowser::Table::Functions;
        my $fc = App::DBBrowser::Table::Functions.new( :$!i, :$!o, :$!d );
        my $func = $fc.col_function( $sql, $clause );
        if ! $func.defined {
            return;
        }
        $ext_col = $func;
        $alias_type = 'functions';
    }
    elsif $type eq $set_to_null {
        return "NULL";
    }
    if $clause !~~ m:i/ ^ [ set || where || having || group_by || order_by ] $ / {
        my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
        my $alias = $ax.alias( $alias_type, $ext_col );
        if $alias.defined && $alias.chars {
            $sql<alias>{$ext_col} = $ax.quote_col_qualified( [ $alias ] );
        }
    }
    return $ext_col;
}



