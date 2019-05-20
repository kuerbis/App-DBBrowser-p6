use v6;
unit class App::DBBrowser::DB;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use App::DBBrowser::Auxil;

has $.i;
has $.o;
has $.P; # !
has @.methods;


method new ( :$i, :$o ) {
    my $db_module = $i<plugin>;
    my sub load-module {
        require ::( $db_module ) ;
        my $instance = ::( $db_module ).new(
            :$i,
            :$o,
        );
        return $instance ;
    }
    my $plugin = load-module();
    #my @methods = $plugin.^methods.map: { .gist };
    my @methods = $plugin.^methods>>.gist;
    self.bless( :P($plugin), :@methods, :$o, :$i );
}


### PLUGIN Routines

## mandatory:

method get_db_driver {
    my $db_type = $!P.get_db_driver();
    return $db_type;
}


method get_databases {
    if ( $!i<arg_dbs> // [] ).elems {
        return $!i<arg_dbs>, [];
    }
    my ( $user_db, $system_db ) = $!P.get_databases();
    return $user_db // [], $system_db // [];
}


method get_db_handle ( $db ) {
    my $dbh = $!P.get_db_handle( $db );
    if $!P.get_db_driver eq 'SQLite' {
#        $dbh.sqlite_create_function( 'regexp', 3, -> $regex, $string, $case_sensitive {
#                $string = '' if ! $string.defined;
#                return $string ~~ m/ <$regex> / if $case_sensitive;
#                return $string ~~ m:i/ <$regex> /; #:
#            }
#        );
#        $dbh.sqlite_create_function( 'truncate', 2, -> $number, $places {
#                return if ! $number.defined;
#                return $number if ! $number ~~ Numeric; #look_like_a_number
#                return sprintf "%.*f", $places, ( $number * 10 ** $places ) div 10 ** $places;
#            }
#        );
#        $dbh.sqlite_create_function( 'bit_length', 1, -> $s {
#                return $s.encode.elems;
#            }
#        );
#        $dbh.sqlite_create_function( 'char_length', 1, 1, -> $s {
#                return $s.chars;
#            }
#        );
    }
    return $dbh;
}



## optional:

method read_login_data {
    my $data;
    if @!methods.any eq 'read_login_data' {
        $data = $!P.read_login_data();
    }
    return $data // [];
}


method env_variables {
    my $env_variables;
    if @!methods.any eq 'env_variables' {
        $env_variables = $!P.env_variables();
    }
    return $env_variables // [];
}


method set_attributes {
    my $attributes;
    if @!methods.any eq 'set_attributes' {
        $attributes = $!P.set_attributes();
    }
    return $attributes // [];
}


## optional and buildin:

method get_schemas ( $dbh, $db ) {
    my ( $user_schemas, $system_schemas );
    if @!methods.any eq 'get_schemas' {
        ( $user_schemas, $system_schemas ) = $!P.get_schemas( $dbh, $db );
        return $user_schemas // [], $system_schemas // [];
    }

    given $!P.get_db_driver {
        when 'SQLite' {
            $user_schemas = [ 'main' ]; # [ undef ];
        }
        when 'mysql' | 'MariaDB' {
            # MySQL 5.7 Reference Manual  /  MySQL Glossary:
            # In MySQL, physically, a schema is synonymous with a database.
            # You can substitute the keyword SCHEMA instead of DATABASE in MySQL SQL syntax,
            $user_schemas = [ $db ];
        }
        when 'Pg' {
            #my $sth = $dbh->table_info( undef, '%', undef, undef );
            ## pg_schema: the unquoted name of the schema
            #my $info = $sth->fetchall_hashref( 'pg_schema' );
            #my $qr = qr/^(?:pg_|information_schema$)/;
            #for my $schema ( keys %$info ) {
            #    if ( $schema =~ /$qr/ ) {
            #        push @$sys_schema, $schema;
            #    }
            #    else {
            #        push @$user_schema, $schema;
            #    }
            #}
            my $stmt = "SELECT schema_name FROM information_schema.schemata ORDER BY schema_name";
            my $sth = $dbh.prepare( $stmt );
            $sth.execute();
            my %datas = $sth.allrows( :hash-of-array );
            my $system_regex = / ^ [ 'pg_' || 'information_schema' $ ] /;
            for %datas<schema_name>.list -> $schema {
                if $schema ~~ $system_regex {
                    $system_schemas.push: $schema;
                }
                else {
                    $user_schemas.push: $schema;
                }
            }
        }
        #default {
        #    my $sth = $dbh->table_info( undef, '%', undef, undef );
        #    my $info = $sth->fetchall_hashref( 'TABLE_SCHEM' );
        #    $user_schema = [ keys %$info ];
        #}
    }
    return $user_schemas // [], $system_schemas // [];
}


## buildin:

#method sql_catalog_name_separator {
#    return '.';
#}


#method sql_identifier_quote_char {
#    return '"';
#}


method identifier_chars {
    my $quote_char = '"';
    my $sep_char   = '.';
    return $quote_char, $sep_char;
}



method tables_data ( $dbh, $schema ) {
    my $table_data = {};
    my ( $table_schem, $table_name );
#    if $!P.get_db_driver eq 'Pg' {
#        $table_schem = 'pg_schema';
#        $table_name  = 'pg_table';
#        # DBD::Pg  3.7.4:
#        # The TABLE_SCHEM and TABLE_NAME will be quoted via quote_ident().
#        # Two additional fields specific to DBD::Pg are returned:
#        # pg_schema: the unquoted name of the schema
#        # pg_table: the unquoted name of the table
#    }
#    else {
        $table_schem = 'TABLE_SCHEM';
        $table_name  = 'TABLE_NAME';
#    }
    my @keys = 'TABLE_CAT', $table_schem, $table_name, 'TABLE_TYPE';
    #my $sth = $dbh->table_info( undef, $schema, undef, undef );
    #my $info = $sth->fetchall_arrayref( { map { $_ => 1 } @keys } );
    my $info = self!table_info( $dbh, $schema );
    my %duplicates;
    for $info.list -> $href {
        next if $href<TABLE_TYPE> eq 'INDEX';
        #if $href<TABLE_TYPE> ~~ /SYSTEM/ || $href<TABLE_TYPE> ~~ / ^ [ TABLE || VIEW || LOCAL\sTEMPORARY ] $ / {
        my $table = $href{$table_name};
        if ! $schema.defined && %duplicates{$table}++ {
            # the $schema is undefined if: SQLite + attached databases
            # if the $schema is undefined, then in SQL code it is always used the fully
            # qualified table name and never the table name in the hash key
            if %duplicates{$table} == 2 {
                my $tmp = $table_data{$table}:delete;
                my $first = '[' ~  $tmp[0..2].grep({ .defined && .chars }).join: ']';
                $table_data{$first} = $tmp;
            }
            $table = '[' ~ $href{@keys[0..2]}.grep({ .defined && .chars }). join: ']';
            $table_data{$table} = [ |$href{@keys} ];
        }
        else {
            $table_data{$table} = [ |$href{@keys} ];
        }
    }
    return $table_data;
}


method !table_info ( $dbh, $schema ) {
    my $tables_info = [];
    given $!P.get_db_driver {
        when 'SQLite' {
            my $sth = $dbh.prepare( "PRAGMA database_list" );
            $sth.execute;
            for $sth.allrows().list ->( $seq, $schema, $db ) {
                my $stmt = "SELECT name, type FROM $schema.sqlite_master ORDER BY name";
                my $sth = $dbh.prepare( $stmt );
                $sth.execute();
                for $sth.allrows().list -> ( $name, $type ) {
                    $tables_info.push: { TABLE_CAT => Any, TABLE_SCHEM => $schema, TABLE_NAME => $name, TABLE_TYPE => $type.uc };
                }
            }
        }
        when 'Pg' {
            my $stmt = "SELECT table_name, table_type FROM information_schema.tables WHERE table_schema = ? ORDER BY table_name"; # AND table_type = 'BASE TABLE'
            my $sth = $dbh.prepare( $stmt );
            $sth.execute( $schema );
            for $sth.allrows().list -> ( $name, $type ) { # list
                $tables_info.push: { TABLE_CAT => Any, TABLE_SCHEM => $schema, TABLE_NAME => $name, TABLE_TYPE => $type.uc };
            }
        }
    }
    return $tables_info;
}


method first_column_is_autoincrement ( $dbh, $schema, $table ) {
    given $!P.get_db_driver {
        when 'SQLite' {
            my $sql = "SELECT sql FROM sqlite_master WHERE name = ?";
            #my ( $row ) = $dbh.selectrow_array( $sql, {}, $table );
            my $sth = $dbh.prepare( $sql );
            $sth.execute( $table );
            my $row = $sth.row().[0];
            $sth.finish;
            my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o, :d() );
            my $qt_table = $ax.quote-identifier( $table );
            $sth = $dbh.prepare( "SELECT * FROM " ~ $qt_table ~ " LIMIT 0" );
            my $col = $sth.column-names().[0];
            $sth.finish;
            my $qt_col = $ax.quote-identifier( $col, );
            if $row ~~ /:i ^ \s* CREATE \s+ TABLE \s+ [ $table | $qt_table ] \s+ \( \s* [ $col | $qt_col ] \s+ INTEGER \s+ PRIMARY \s+ KEY <-[,]>* \, / { # :i
                return 1;
            }
        }
        when 'mysql' | 'MariaDB' {
            my $sql = "SELECT COUNT(*) FROM information_schema.columns WHERE
                    TABLE_SCHEMA = ?
                    AND TABLE_NAME = ?
                    AND ORDINAL_POSITION = 1
                    AND DATA_TYPE = 'int'
                    AND COLUMN_DEFAULT IS NULL
                    AND IS_NULLABLE = 'NO'
                    AND EXTRA like '%auto_increment%'";
            #my ( $first_col_is_autoincrement ) = $dbh->selectrow_array( $sql, {}, $schema, $table );
            my $sth = $dbh.prepare( $sql );
            $sth.execute( $schema, $table );
            my $first_col_is_autoincrement = $sth.row().[0];
            $sth.finish;
            return $first_col_is_autoincrement;
        }
        when 'Pg' {
            my $sql = "SELECT COUNT(*) FROM information_schema.columns WHERE
                    TABLE_SCHEMA = ?
                    AND TABLE_NAME = ?
                    AND ORDINAL_POSITION = 1
                    AND DATA_TYPE = 'integer'
                    AND IS_NULLABLE = 'NO'
                    AND (
                        UPPER(column_default) LIKE 'NEXTVAL%' OR
                        UPPER(identity_generation) = 'BY DEFAULT'
                    )";
            #my ( $first_col_is_autoincrement ) = $dbh->selectrow_array( $sql, {}, $schema, $table );
            my $sth = $dbh.prepare( $sql );
            $sth.execute( $schema, $table );
            my $first_col_is_autoincrement = $sth.row().[0];
            $sth.finish;
            return $first_col_is_autoincrement;
        }
    }
    return;
}


method primary_key_autoincrement_constraint ( $dbh ) {
    # provide "primary_key_autoincrement_constraint" only if also "first_col_is_autoincrement" is available
    #return if @!methods eq 'primary_key_autoincrement_constraint';
    given $!P.get_db_driver {
        when 'SQLite' {
            return "INTEGER PRIMARY KEY";
        }
        when / ^ [ mysql || MariaDB ] $ / {
            return "INT NOT NULL AUTO_INCREMENT PRIMARY KEY";
            # mysql: NOT NULL added automatically with AUTO_INCREMENT
        }
        when 'Pg' {
            #my ( $pg_version ) = $dbh.selectrow_array( "SELECT version()" );
            my $sth = $dbh.prepare( "SELECT version()" );
            $sth.execute();
            my $pg_version = $sth.row().[0];
            $sth.finish;
            if $pg_version ~~ / ^ \S+ \s+ ( [ 0..9 ]+ ) [ \. [ 0..9 ]+ ]* \s / && $0 >= 10 {
                # since PostgreSQL version 10
                return "INT generated BY DEFAULT AS IDENTITY PRIMARY KEY";
            }
            else {
                return "SERIAL PRIMARY KEY";
            }
        }
    }
}


method primary_and_foreign_keys ( $dbh, $db, $schema, @tables ) {
    #return $pk_cols, $fks;
}


method regexp ( $col, $do_not_match, $case_sensitive ) {
    given $!P.get_db_driver {
        when 'SQLite' {
            if $do_not_match {
                return sprintf ' NOT REGEXP(?,%s,%d)', $col, $case_sensitive;
            }
            else {
                return sprintf ' REGEXP(?,%s,%d)', $col, $case_sensitive;
            }
        }
        when 'mysql' | 'MariaDB' {
            if $do_not_match {
                return ' ' ~ $col ~ ' NOT REGEXP ?'        if ! $case_sensitive;
                return ' ' ~ $col ~ ' NOT REGEXP BINARY ?' if   $case_sensitive;
            }
            else {
                return ' ' ~ $col ~ ' REGEXP ?'            if ! $case_sensitive;
                return ' ' ~ $col ~ ' REGEXP BINARY ?'     if   $case_sensitive;
            }
        }
        when 'Pg' {
            if $do_not_match {
                return ' ' ~ $col ~ '::text' ~ ' !~* ?' if ! $case_sensitive;
                return ' ' ~ $col ~ '::text' ~ ' !~ ?'  if   $case_sensitive;
            }
            else {
                return ' ' ~ $col ~ '::text' ~ ' ~* ?'  if ! $case_sensitive;
                return ' ' ~ $col ~ '::text' ~ ' ~ ?'   if   $case_sensitive;
            }
        }
    }
}


# scalar functions

method concatenate ( $arguments, $sep ) {
    my $arg;
    if $sep.defined && $sep.chars {
        my $qt_sep = "'" ~ $sep ~ "'";
        for $arguments.list {
            $arg.push: $_, $qt_sep;
        }
        $arg.pop;
    }
    else {
        $arg = $arguments
    }
    return 'concat(' ~ $arg.join( ',' ) ~ ')'  if $!P.get_db_driver eq 'mysql' | 'MariaDB';
    return $arg.join: ' || ';
}


method epoch_to_datetime ( $col, $interval ) {
    return "DATETIME($col/$interval,'unixepoch','localtime')"     if $!P.get_db_driver eq 'SQLite';
    # mysql: FROM_UNIXTIME doesn't work with negative timestamps
    return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d %H:%i:%s')"    if $!P.get_db_driver eq 'mysql' | 'MariaDB';
    return "TO_TIMESTAMP({$col}::bigint/$interval)::timestamp"    if $!P.get_db_driver eq 'Pg';
}


method epoch_to_date ( $col, $interval ) {
    return "DATE($col/$interval,'unixepoch','localtime')"    if $!P.get_db_driver eq 'SQLite';
    return "FROM_UNIXTIME($col/$interval,'%Y-%m-%d')"        if $!P.get_db_driver eq 'mysql' | 'MariaDB';
    return "TO_TIMESTAMP({$col}::bigint/$interval)::date"    if $!P.get_db_driver eq 'Pg';
}


method truncate ( $col, $precision ) {
    return "TRUNC($col,$precision)"    if $!P.get_db_driver eq 'Pg';
    return "TRUNCATE($col,$precision)";
}


method bit_length ( $col ) {
    return "BIT_LENGTH($col)";
}


method char_length ( $col ) {
    return "CHAR_LENGTH($col)";
}



=begin pod

=head1 NAME

App::DBBrowser::DB - Database plugin documentation.

=head1 DESCRIPTION

NO yet possible to write userdefined plugins.

This documentation is a first draft and has no meaning yet.

Column names passed as arguments to plugin methods are already quoted.

To the plugin are passed to named parameter;

    has $.o;
    has $.i;

=head1 METHODS

=head2 Mandatory methods

=head3 get_db_driver

Returns the name of the database driver (C<SQLite> or C<Pg>).

=head3 get_databases

If C<$o<meta-data>> is true, C<get_databases> returns the "user-databases" as an array and the "system-databases" as an
array.

=head3 get_db_handle

C<get_db_handle> is called with one argument: the database name.

It returns a C<DBIish> database handle.

=head2 Optional methods

=head3 get_schemas

It is called with one argument: the database name.

If C<$o<meta-data>> is true, C<get_schemas> returns the "user-schemas" as an array and the "system-schemas" as an array.

If C<$o<meta-data>> is not true, C<get_schemas> returns only the "user-schemas" as an array.

=head3 read_login_data

Returns an AoH. The hashes have two or three key-value pairs:

    method read_login_data {
        return [
            %( :name<host>, :prompt<Host>,     :0keep_secret ),
            %( :name<port>, :prompt<Port>,     :0keep_secret ),
            %( :name<user>, :prompt<User>,     :0keep_secret ),
            %( :name<pass>, :prompt<Password>, :1keep_secret ),
        ];
    }

C<name> holds the field name for example like "user" or "host".
The value of C<prompt> is used as the prompt string, when the user is asked for the data. The C<prompt> entry is
optional. If C<prompt> doesn't exist, the value of C<name> is used instead.

If C<keep_secret> is true, the user input should not be echoed to the terminal. Also the data is not stored in the
plugin configuration file if C<keep_secret> is true.

=head3 env_variables

Returns an list of environment variables.

An example C<env_variables> method:

    method env_variables {
        return <DBI_DSN DBI_HOST DBI_PORT DBI_USER DBI_PASS>;
    }

=head3 set_attributes

Returns Returns an AoH. The hashes have two or three key-value pairs:

    method set_attributes {
        return [
            %( :name<attribute-name>, :0default, :values( 0, 1 ) ),
            %( :name<attribute-name>, :1default, :values( 0, 1, 3 ) ),
        ];
    }

The values set with the methods C<read_login_data>, C<env_variables> and C<attributes> can be accessed with:

    use App::DBBrowser::Opt::DBGet;

    my $new = App::DBBrowser::Opt::DBGet.new();

    my $attr = $new.attributes( $db );

    my $login_data = $.new.$login_data( $db );

    my $enabled_env_vars = $new.enabled_env_vars( $db );

These methods take one optional argument: the database name.

=head1 AUTHOR

Matthäus Kiem <cuer2s@gmail.com>

=head1 CREDITS

Thanks to the people from L<Perl-Community.de|http://www.perl-community.de>, from
L<stackoverflow|http://stackoverflow.com> and from L<#perl6 on irc.freenode.net|irc://irc.freenode.net/#perl6> for the
help.

=head1 LICENSE AND COPYRIGHT

Copyright (C) 2019 Matthäus Kiem.

This library is free software; you can redistribute it and/or modify it under the Artistic License 2.0.

=end pod


