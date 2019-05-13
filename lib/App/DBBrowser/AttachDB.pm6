use v6;
unit class App::DBBrowser::AttachDB;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use Term::Choose;
use Term::Form;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.d;


method attach_db {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $tf = Term::Form.new( :1loop );
    my $cur_attached;
    if ! $!i<f_attached_db>.IO.z { ## .
        my $h_ref = $ax.read_json( $!i<f_attached_db> );
        $cur_attached = $h_ref{$!d<db>} || [];
    }
    my $choices = [ Any, |$!d<user_dbs>, |$!d<sys_dbs> ];
    my $new_attached = [];

    ATTACH: loop {

        DB: loop {
            my @tmp_info = $!d<db_string>;
            for ( |$cur_attached, |$new_attached ) -> $ref { ##
                @tmp_info.push: sprintf "ATTACH DATABASE %s AS %s", |$ref;
            }
            @tmp_info.push: '';
            my $info = @tmp_info.join: "\n";
            my $prompt = "ATTACH DATABASE"; # \n
            my $db = $tc.choose(
                $choices,
                :$prompt, :$info, :undef( $!i<back> ), :1clear-screen
            );
            if ! $db.defined {
                if $new_attached.elems {
                    $new_attached.shift;
                    next DB;
                }
                return;
            }
            @tmp_info.push: "ATTACH DATABASE $db AS";
            $info = @tmp_info.join: "\n";

            ALIAS: loop {
                my $alias = $tf.readline( 'alias: ', :$info, :1clear-screen );
                if ! $alias.chars {
                    last ALIAS;
                }
                elsif $alias eq ( |$cur_attached, |$new_attached ).map({ $_[1] }).any {
                    my $prompt = "alias '$alias' already used:";
                    my $retry = $tc.choose(
                        [ Any, 'New alias' ],
                        :$prompt, :$info, :undef( $!i<back> ), :1clear-screen
                    );
                    last ALIAS if ! $retry.defined;
                    next ALIAS;
                }
                else {
                    $new_attached.push: [ $db, $alias ]; # 2 x $db with different $alias ?
                    last ALIAS;
                }
            }

            POP_ATTACHED: loop {
                my @tmp_info = $!d<db_string>;
                @tmp_info.push: ( |$cur_attached, |$new_attached ).map: { "ATTACH DATABASE $_[0] AS $_[1]" };
                @tmp_info.push: '';
                my $info = @tmp_info.join: "\n";
                my $prompt = 'Choose:';
                my ( $ok, $more ) = ( 'OK', '++' );
                my $choice = $tc.choose(
                    [ Any, $ok, $more ],
                    :$prompt, :$info, :undef( '<<' ), :1clear-screen
                );
                if ! $choice.defined {
                    if $new_attached.elems > 1 {
                        $new_attached.pop;
                        next POP_ATTACHED;
                    }
                    return;
                }
                elsif $choice eq $ok {
                    if ! $new_attached.elems {
                        return;
                    }
                    my $h_ref = $ax.read_json( $!i<f_attached_db> );
                    $h_ref.{$!d<db>} = [ ( |$cur_attached, |$new_attached  ).sort ];
                    $ax.write_json( $!i<f_attached_db>, $h_ref );
                    return 1;
                }
                elsif $choice eq $more {
                    next DB;
                }
            }
        }
    }
}


method detach_db {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    my $tc = Term::Choose.new( |$!i<default> );
    my $attached_db;
    if ! $!i<f_attached_db>.IO.z { ##
        my $h_ref = $ax.read_json( $!i<f_attached_db> );
        $attached_db = $h_ref.{$!d<db>} // [];
    }
    my @chosen;

    loop {
        my @tmp_info = ( $!d<db_string>, 'Detach:' );

        for @chosen -> $detach { ##
            @tmp_info.push: sprintf 'DETACH DATABASE %s (%s)', $detach[1], $detach[0];
        }
        my $info = @tmp_info.join: "\n";
        my @choices;
        for $attached_db.list -> $elem { ##
            @choices.push: sprintf '- %s  (%s)', |$elem[1,0];
        }
        my $prompt = "\n" ~ 'Choose:';
        my @pre = Any, $!i<_confirm>;
        # Choose
        my $idx = $tc.choose(
            [ |@pre, |@choices ],
            |$!i<lyt_v_clear>, :$prompt, :$info, :1index
        );
        if ! $idx {
            return;
        }
        elsif $idx == @pre.end {
            my $h_ref = $ax.read_json( $!i<f_attached_db> );
            if $attached_db.elems {
                $h_ref.{$!d<db>} = $attached_db;
            }
            else {
                $h_ref.{$!d<db>}:delete;
            }
            $ax.write_json( $!i<f_attached_db>, $h_ref );
            return 1;
        }
        @chosen.push: $attached_db.splice: $idx - @pre.elems, 1;
    }
}





