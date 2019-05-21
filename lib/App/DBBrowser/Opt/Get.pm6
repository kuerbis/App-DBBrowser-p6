use v6;
unit class App::DBBrowser::Opt::Get;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use App::DBBrowser::Auxil;


has $.o;
has $.i;


method defaults ( $section?, $key? ) { ###
    my $defaults = {
        G => {
            info-expand          => 0,
            max-rows             => 200_000,
            menu-memory          => 1,
            meta-data            => 0,
            operators            => [ "REGEXP", "REGEXP_i", " = ", " != ", " < ", " > ", "IS NULL", "IS NOT NULL" ],
            plugins              => [ 'SQLite', 'Pg' ], # 'mysql':  DBIish: DBDish::mysql needs 'mysqlclient', not found
            qualified-table-name => 0,
            quote-identifiers    => 1,
            thsd-sep             => ',',
#            file-find-warnings   => 0,
        },
        alias => {
            aggregate  => 0,
            functions  => 0,
            join       => 0,
            union      => 0,
            subqueries => 0,
        },
        enable => {
            create-table => 0,
            create-view  => 0,
            drop-table   => 0,
            drop-view    => 0,

            insert-into => 0,
            update      => 0,
            delete      => 0,

            expand-select   => 0,
            expand-where    => 0,
            expand-group-by => 0,
            expand-having   => 0,
            expand-order-by => 0,
            expand-set      => 0,

            parentheses => 0,

            m-derived   => 0, #-
            join        => 0,
            union       => 0,
            db-settings => 0,

            j-derived  => 0,

            u-derived => 0,
            union-all => 0,
        },
        table => {
            binary-filter     => 0,
            binary-string     => 'BNRY',
            codepage-mapping  => 0, # not an option, always 0
            color             => 0,
            decimal-separator => '.',
            grid              => 1,
            keep-header       => 1,
            min-col-width     => 30,
            mouse             => 0,
            progress-bar      => 40_000,
            squash-spaces     => 0,
            tab-width         => 2,
            table-expand      => 1,
            undef             => '',
        },
        insert => {
            copy-parse-mode => 1,
            file-encoding   => 'UTF-8',
            file-parse-mode => 0,
            history-dirs    => 4,
        },
        create => {
            autoincrement-col-name => 'Id',
            data-type-guessing     => 1,
        },
        split => {
            record-sep    => '\n',
            record-l-trim => '',
            record-r-trim => '',
            field-sep     => ',',
            field-l-trim  => '\s+',
            field-r-trim  => '\s+',
        },
        csv => {
            sep-char            => ',',
            quote-char          => '"',
            escape-char         => '"',
            eol                 => '',

            allow-loose-escapes => 0,
            allow-loose-quotes  => 0,
            allow-whitespace    => 0,
            auto-diag           => 1,
            blank-is-undef      => 1,
            binary              => 1,
            empty-is-undef      => 0,
        }
    };
    return $defaults                   if ! $section;
    return $defaults{$section}         if ! $key;
    return $defaults{$section}{$key};
}


method read_config_files {
    my $o = self.defaults();
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o );
    my $file_name = $!i<f_settings>;
    if $file_name.IO.f && ! $file_name.IO.z {
        my $tmp = $ax.read_json: $file_name;
        for $tmp.keys -> $section {
            for $tmp{$section}.keys -> $opt {
                $o{$section}{$opt} = $tmp{$section}{$opt} if $o{$section}{$opt}:exists;
            }
        }
    }
    return $o;
}








