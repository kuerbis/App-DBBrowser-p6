use v6;
unit class App::DBBrowser::Table::Substatements::Operators;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
no precompilation;

use Term::Choose;
use Term::Form;

use App::DBBrowser::DB;
use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Extensions;

has $.i;
has $.o;
has $.d;


method build_having_col ( $sql, $aggr is copy ) {
    my $quote_aggr;
    if $aggr eq $sql<aggr_cols>.map({ '@' ~ $_ }).any {
        $quote_aggr = $aggr.subst( / ^ \@ /, '' );
        $sql<having_stmt> ~= ' ' ~ $quote_aggr;
    }
    elsif $aggr eq 'COUNT(*)' {
        $quote_aggr = $aggr;
        $sql<having_stmt> ~= ' ' ~ $quote_aggr;
    }
    else {
        $aggr ~~ s/ \( \S \) $ //;
        $sql<having_stmt> ~= ' ' ~ $aggr ~ "(";
        $quote_aggr          =       $aggr ~ "(";
        my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
        my $tc = Term::Choose.new( |$!i<default> );
        $ax.print_sql( $sql, '' );
        # Choose
        my $quote_col = $tc.choose(
            [ Any, |$sql<cols> ],
            |$!i<lyt_h>
        );
        if ! $quote_col.defined {
            return;
        }
        $sql<having_stmt> ~= $quote_col ~ ")";
        $quote_aggr       ~= $quote_col ~ ")";
    }
    return $quote_aggr;
}


method add_operator_with_value ( $sql, $clause, $quote_col ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my $stmt = $clause ~ '_stmt';
    my $args = $clause ~ '_args';
    my $sign_idx = $!o<enable>{'expand-' ~ $clause};
    my $expand_sign;
    my @operators;
    my @operators_ext;
    if $clause eq 'set' {
        $expand_sign = $!i<expand_signs_set>[$sign_idx];
        @operators = " = ";
        @operators_ext = " = ";
    }
    else {
        $expand_sign = '=' ~ $!i<expand_signs>[$sign_idx];
        #@operators = |$!o<G><operators>;
        if $!i<driver> eq 'SQLite' {
            # DBIish: sqlite3_create_function not yet available
            @operators = |$!o<G><operators>.grep({ ! /REGEX/ });
        }
        else {
            @operators = |$!o<G><operators>;
        }
        @operators_ext = " = ", " != ", " < ", " > ", " >= ", " <= ", "IN", "NOT IN";
    }
    if $sign_idx {
        @operators.unshift: $expand_sign;
    }
    my $ext_col;

    OPERATOR: loop {
        my $op;
        if @operators.elems == 1 {
            $op = @operators[0];
        }
        else {
            my @pre = Any;
            $ax.print_sql( $sql, '' );
            # Choose
            $op = $tc.choose(
                [ |@pre, |@operators ],
                |$!i<lyt_h>
            );
            if ! $op.defined {
                return;
            }
        }
        my $bu_stmt = $sql{$stmt};
        if $op eq $expand_sign {
            if @operators_ext.elems == 1 {
                $op = @operators_ext[0];
            }
            else {
                my @pre = Any;
                $sql{$stmt} ~= ' ? Func/SQ';
                $ax.print_sql( $sql, '' );
                # Choose
                $op = $tc.choose(
                    [ |@pre, |@operators_ext ],
                    |$!i<lyt_h>
                );
                if ! $op.defined {
                    $sql{$stmt} = $bu_stmt;

                    next OPERATOR;
                }
                $op.=trim;
                $sql{$stmt} = $bu_stmt ~ ' ' ~ $op;
                $ax.print_sql( $sql, '' );
            }
            my $ext = App::DBBrowser::Table::Extensions.new( :$!i, :$!o, :$!d );
            $ext_col = $ext.extended_col( $sql, $clause );
            $sql{$stmt} = $bu_stmt;
            if ! $ext_col.defined {
                next OPERATOR;
            }
        }
        $op.=trim;
        my $ok;
        given $op {
            when / ^ IS \s [ NOT \s ]? NULL $ / {
                $sql{$stmt} ~= ' ' ~ $op;
                $ok = 1;
            }
            when / \s '%'? col '%'? $ / {
                $ok = self!col_op( $sql, $op, $stmt );
            }
            when / REGEXP [_i]? $  / {
                $ok = self!regex_op( $sql, $op, $stmt, $args, $quote_col );
            }
            when / ^ [ NOT \s ]? IN $ / {
                $ok = self!in_op( $sql, $op, $stmt, $args, $ext_col );
            }
            when / ^ [ NOT \s ]? BETWEEN $ / {
                $ok = self!between_op( $sql, $op, $stmt, $args );
            }
            default {
                $ok = self!default_op( $sql, $op, $stmt, $args, $ext_col );
            }
        }
        if ! $ok {
            $sql{$stmt} = $bu_stmt;
            next OPERATOR;
        }
        last OPERATOR;
    }
    return 1;
}


method !col_op ( $sql, $op, $stmt ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $arg;
    if $op ~~ / ^ ( .+ ) \s ( '%'? col '%'? ) $ / {
        $op = $0;
        $arg = $1;
    }
    $sql{$stmt} ~= ' ' ~ $op;
    $ax.print_sql( $sql, '' );
    my $quote_col;
    #if defined $ext_col ) {   #
    #    $quote_col = $ext_col;  #
    #}                           #
    #else {                      #
        if $stmt eq 'having_stmt' {
            my @pre = Any, $!i<ok>;
            my @choices = |$!i<aggregate>, |$sql<aggr_cols>.map: { '@' ~ $_ };
            # Choose
            my $aggr = $tc.choose(
                [ |@pre, |@choices ],
                |$!i<lyt_h>
            );
            if ! $aggr.defined {
                return;
            }
            if $aggr eq $!i<ok> {
            }
            my $backup_tmp = $sql{$stmt};
            $quote_col =  self.build_having_col( $sql, $aggr );
            $sql{$stmt} = $backup_tmp;
        }
        else {
            # Choose
            $quote_col = $tc.choose(
                $sql<cols>,
                |$!i<lyt_h>, :prompt<Col:>
            );
        }
        if ! $quote_col.defined {
            return;
        }
    #}                           #
    if $arg !~~ / '%' / {
        $sql{$stmt} ~= ' ' ~ $quote_col;
    }
    else {
        try {
            my $plui = App::DBBrowser::DB.new( $!i, $!o );
            my @el = ( $arg ~~ m/ ^ ( '%'? ) ( col )( '%'? ) $ / ).grep( *.chars ).map: { "'$_'" };
            my $qt_arg = $plui.concatenate( @el );
            $qt_arg ~~ s/ \'col\' /$quote_col/;
            $sql{$stmt} ~= ' ' ~ $qt_arg;
        }
        CATCH {
            $ax.print_error_message( .Str, $op ~ ' ' ~ $arg );
            return;
        }
    }
    return 1
}


method !regex_op ( $sql, $op, $stmt, $args, $quote_col ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $ax.print_sql( $sql, '' );
    $sql{$stmt} ~~ s/ [ <?after \( > || \s ] $quote_col $ //;
    my $do_not_match_regexp = $op ~~ / ^ NOT /      ?? 1 !! 0;
    my $case_sensitive      = $op ~~ / REGEXP_i $ / ?? 0 !! 1;
    my $regex_op;
    try {
        my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
        $regex_op = $plui.regexp( $quote_col, $do_not_match_regexp, $case_sensitive );
    }
    CATCH {
        $ax.print_error_message( .Str, $op );
        return;
    }
    #if $ext_col {                       #
    #    $regex_op ~~ s/ \? /$ext_col/;  #
    #    $sql{$stmt} ~= $regex_op;       #
    #    return 1;                       #
    #}                                   #
    if $sql{$stmt} ~~ / \( $ / {
        $regex_op ~~ s/ ^ \s //;
    }
    $sql{$stmt} ~= $regex_op;
    $sql{$args}.push: '...';
    $ax.print_sql( $sql, '' );
    # Readline
    my $value = $tf.readline( 'Pattern: ' );
    if ! $value.defined {
        return;
    }
    $value = '^$' if ! $value.chars;
    $sql{$args}.pop;
    $sql{$args}.push: $value;
    return 1
}


method !in_op ( $sql, $op, $stmt, $args, $ext_col ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $sql{$stmt} ~= ' ' ~ $op;
    if $ext_col {                                 #
        $ext_col ~~ s:g/ ^ \s* \( || \) \s* $ //; # # ::
        $sql{$stmt} ~= '(' ~ $ext_col ~ ')';      #
        return 1;                                 #
    }                                             #
    my $col_sep = '';
    $sql{$stmt} ~= '(';

    IN: loop {
        $ax.print_sql( $sql, '' );
        # Readline
        my $value = $tf.readline( 'Value: ' );
        if ! $value.defined {
            return;
        }
        if $value eq '' {
            if $col_sep eq '' {
                return;
            }
            $sql{$stmt} ~= ')';
            return 1;
        }
        $sql{$stmt} ~= $col_sep ~ '?';
        $sql{$args}.push: $value;
        $col_sep = ',';
    }
}


method !between_op ( $sql, $op, $stmt, $args ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $sql{$stmt} ~= ' ' ~ $op;
    #if $ext_col ) {                       #
    #    $sql{$stmt} ~= ' ' ~ $ext_col;    #
    #    return 1;                         #
    #}                                     #
    $ax.print_sql( $sql, '' );
    # Readline
    my $value_1 = $tf.readline( 'Value 1: ' );
    if ! $value_1.defined {
        return;
    }
    $sql{$stmt} ~= ' ' ~ '?' ~ ' AND';
    $sql{$args}.push: $value_1;
    $ax.print_sql( $sql, '' );
    # Readline
    my $value_2 = $tf.readline( 'Value 2: ' );
    if ! $value_2.defined {
        return;
    }
    $sql{$stmt} ~= ' ' ~ '?';
    $sql{$args}.push: $value_2;
    return 1;
}


method !default_op ( $sql, $op, $stmt, $args, $ext_col ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tf = Term::Form.new( :1loop );
    $sql{$stmt} ~= ' ' ~ $op;
    if $ext_col {                       #
        $sql{$stmt} ~= ' ' ~ $ext_col;  #
        return 1;                       #
    }                                   #
    $ax.print_sql( $sql, '' );
    my $prompt = $op ~~ / ^ [ NOT \s ]? LIKE $ / ?? 'Pattern: ' !! 'Value: '; #
    # Readline
    my $value = $tf.readline( $prompt );
    if ! $value.defined {
        return;
    }
    try {
        if $value ~~ / ^ <[ 0 .. 9 \. \- \+ ]>+ $ / { # ###
            $value .= Numeric;
        }
    }
    $sql{$stmt} ~= ' ' ~ '?';
    $sql{$args}.push: $value;
    return 1;
}

