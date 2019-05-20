use v6;
unit class App::DBBrowser::GetContent::ParseFile;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

#use Text::CSV;   # required

#use Term::Choose;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.d;


#sub ignore_2012 ( Int $code, Str $str, Int $pos, Int $rec, Int $fld ) {
#    if $code == 2012 { # ignore this error
#        Text::CSV.SetDiag(0);
#    }
#    else {
#        my $error_inpunt = $csv.error_input();
#        my $message =  "Text::CSV:\n";
#        $message ~= "Input: $str" if $str.defined; # ?
#        $message ~= "$code $str - pos:$pos rec:$rec fld:$fld";
#        my $tc = Term::Choose.new( :1loop );
#        $tc.pause(
#            [ 'Press ENTER' ],
#            :prompt( $message )
#        );
#        return;
#    }
#}

sub _unescape ( $str ) {
    my %map = :t( "\t" ), :n( "\n" ), :r( "\r" ), :f( "\f" ), :b( "\b" ), :a( "\a" ), :e( "\e" );
    return $str.subst( /\\(<[tnrfbae]>)/, { %map{$0} }, :1g );
}


method parse_file_Text_CSV ( $sql, $file ) { # 0
    #$!d<sheet_name>:delete; # no spreadsheet reading yet
    my $waiting = 'Parsing file ... ';
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    $ax.print_sql( $sql, $waiting );
    my $rows_of_cols = [];
    my %options = |$!o<csv>.keys.map: { $_ => _unescape $!o<csv>{$_} };
    require Text::CSV;
    my $csv = ::('Text::CSV').new( |%options );
    my $fh = $file.IO.open :r;
    #$csv.callbacks( error => \&ignore_2012 ); #
    $sql<insert_into_args> = $csv.getline_all( $fh );
    $fh.close;
    $ax.print_sql( $sql, $waiting );
    return 1;
}


method parse_file_split ( $sql, $file ) { # 1
    #$!d<sheet_name>:delete; # no spreadsheet reading yet
    my $waiting = 'Parsing file ... ';
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :$!d );
    $ax.print_sql( $sql, $waiting );
    my $record_lead  = _unescape $!o<split><record-l-trim>;
    my $record_trail = _unescape $!o<split><record-r-trim>;
    my $field_lead   = _unescape $!o<split><field-l-trim>;
    my $field_trail  = _unescape $!o<split><field-r-trim>;
    my $record_sep = _unescape $!o<split><record-sep>;
    my $field_sep  = _unescape $!o<split><field-sep>;
    my $rows_of_cols = [];
    for $file.IO.slurp.split( / $record_sep / ) -> $row {
        if $record_lead.chars {
            $row.=subst( / ^ $record_lead /, '' );
        }
        if $record_trail.chars {
            $row.=subst( / $record_trail $ /, '' );
        }
        $rows_of_cols.push: [
            |$row.split( / $field_sep / ).map: {
                if $field_lead.chars {
                    s/ ^ $field_lead //;
                }
                if $field_trail.chars {
                    s/ $field_trail $ //;
                }
                $_
            }
        ];
    }
    $sql<insert_into_args> = $rows_of_cols;
    $ax.print_sql( $sql, $waiting );
    return 1;
}



