use v6;
unit class App::DBBrowser::Table;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;

use Term::Choose;
use Term::Choose::Screen :clear;

use App::DBBrowser::Auxil;
use App::DBBrowser::Table::Substatements;

has $.i;
has $.o;
has $.d;


method on_table ( $sql is rw ) { ##
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $sb = App::DBBrowser::Table::Substatements.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $sub_stmts = <print_tbl select aggregate distinct where group_by having order_by limit reset>;
    my $cu = {
        hidden    => 'Customize:',
        print_tbl => 'Print TABLE',
        select    => '- SELECT',
        aggregate => '- AGGREGATE',
        distinct  => '- DISTINCT',
        where     => '- WHERE',
        group_by  => '- GROUP BY',
        having    => '- HAVING',
        order_by  => '- ORDER BY',
        limit     => '- LIMIT',
        reset     => '  Reset',
    };
    $!i<stmt_types> = [ 'Select' ];
    my Int $old_idx = 1;

    CUSTOMIZE: while ( 1 ) {
        my @choices = $cu<hidden>, Any, |$cu{|$sub_stmts};
        $ax.print_sql( $sql, '' );
        # Choose
        my $idx = $tc.choose(
            @choices,
            |$!i<lyt_v>, :prompt( '' ), :1index, :default( $old_idx ), :undef( $!i<back> )
        );
        if ! $idx.defined || ! @choices[$idx].defined {
            last CUSTOMIZE;
        }
        my $custom = @choices[$idx];
        if $!o<G><menu-memory> {
            if $old_idx == $idx && ! %*ENV<TC_RESET_AUTO_UP> {
                $old_idx = 1;
                next CUSTOMIZE;
            }
            $old_idx = $idx;
        }
        my $backup_sql = $ax.backup_href( $sql );
        if ( $custom eq $cu<reset> ) {
            $ax.reset_sql( $sql );
            $old_idx = 1;
        }
        elsif $custom eq $cu<select> {
            my $ok = $sb.select( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<distinct> {
            my $ok = $sb.distinct( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<aggregate> {
            my $ok = $sb.aggregate( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<where> {
            my $ok = $sb.where( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<group_by> {
            my $ok = $sb.group_by( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<having> {
            my $ok = $sb.having( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<order_by> {
            my $ok = $sb.order_by( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<limit> {
            my $ok = $sb.limit_offset( $sql );
            if ! $ok {
                $sql = $backup_sql;
            }
        }
        elsif $custom eq $cu<hidden> {
            require App::DBBrowser::Table::WriteAccess;
            my $write = App::DBBrowser::Table::WriteAccess.new( :$!i, :$!o, :$!d );
            $write.table_write_access( $sql );
            $!i<stmt_types> = [ 'Select' ];
            $old_idx = 1;
            $sql = $backup_sql;
        }
        elsif $custom eq $cu<print_tbl> {
            clear();
            print "\rComputing: ...\r" if $!o<table><progress-bar>;
            my $statement = $ax.get_stmt( $sql, 'Select', 'prepare' );
            my @arguments = |$sql<where_args>, |$sql<having_args>;
            $!i<history>{$!d<db>}<main>.unshift: [ $statement, @arguments ];
            if $!i<history>{$!d<db>}<main>.end > 50 {
                $!i<history>{$!d<db>}<main> = [ $!i<history>{$!d<db>}<main>[^50] ]
            }
            if $!o<G><max-rows> && ! $sql<limit_stmt> {
                $statement ~= " LIMIT " ~ $!o<G><max-rows>;
                $!o<table><max-rows> = $!o<G><max-rows>;
            }
            else {
                $!o<table><max-rows> = 0;
            }
            my $sth = $!d<dbh>.prepare( $statement );
            $sth.execute( @arguments );
            my @rows = $sth.allrows(); ###
            my $col_names = $sth.column-names();
            $sth.finish;
            @rows.unshift: $col_names;
            return @rows; #, $sql;
            #return $col_names, @rows, $sql;
        }
        else {
            die "'$custom': no such value in the hash \$cu";
        }
    }
}



