use v6;
unit class App::DBBrowser::DB::Pg;

use DBIish;

use App::DBBrowser::Credentials;
use App::DBBrowser::Opt::DBGet;

has $.o;
has $.i;

has Str $!db_driver = 'Pg';


method get_db_driver {
    return $!db_driver;
}


method env_variables {
    return <DBI_DSN DBI_HOST DBI_PORT DBI_USER DBI_PASS>;
}


method read_login_data {
    return [
        %( :name<host>, :prompt<Host>,     :0secret ),
        %( :name<port>, :prompt<Port>,     :0secret ),
        %( :name<user>, :prompt<User>,     :0secret ),
        %( :name<pass>, :prompt<Password>, :1secret ),
    ];
}


method set_attributes {
    return [];
}


method get_db_handle ( $db ) {
    my $get_db_opt = App::DBBrowser::Opt::DBGet.new( :$!o, :$!i );
    my $login_data  = $get_db_opt.login_data( $db );
    my $env_var_yes = $get_db_opt.enabled_env_vars( $db );
    my $attributes  = $get_db_opt.attributes( $db );
    my $obj_db_cred = App::DBBrowser::Credentials.new( :$login_data, :$env_var_yes );
    say "DB: $db";
    my %hp;
    if %*ENV<DBI_DSN>:!exists || ! $env_var_yes<DBI_DSN> {
        my $host = $obj_db_cred.get_login( 'host' );
        if $host.defined && $host.chars {
            %hp<host> = $host;
            say "Host: $host";
        }
        my $port = $obj_db_cred.get_login( 'port' );
        if $port.defined && $port.chars {
            %hp<port> = $port.Numeric;
            say "Port: $port";
        }
    }
    my $user= $obj_db_cred.get_login( 'user' );
    say "User: $user";
    my $dbh = DBIish.connect(
        $!db_driver,
        :database( $db ),
        |%hp,
        :user( $user ),
        :password( $obj_db_cred.get_login( 'pass' ) ),
        :RaiseError,
        |$attributes
    );
    return $dbh;
}


method get_databases {
    my @regex_system_db = '^postgres$', '^template0$', '^template1$';
    my $info_database = 'postgres';
    my $dbh = self.get_db_handle( $info_database );
    my $user_db   = [];
    my $system_db = [];
    if $!o<G><meta-data> {
        my $stmt = "SELECT datname FROM pg_database ORDER BY datname";
        my $regexp = @regex_system_db.join: '|';
        my $sth = $dbh.prepare( $stmt );
        $sth.execute();
        my %datas = $sth.allrows( :hash-of-array );
        for %datas<datname>.list -> $database {
            if $database ~~ /<$regexp>/ {
                $system_db.push: $database;
            }
            else {
                $user_db.push: $database;
            }
        }
    }
    else {
        my $stmt = "SELECT datname FROM pg_database";
        $stmt ~= " WHERE " ~ ( "datname !~ ?" xx @regex_system_db ).join( " AND " );
        $stmt ~= " ORDER BY datname";
        my $sth = $dbh.prepare( $stmt );
        $sth.execute( |@regex_system_db ); #
        my %datas = $sth.allrows( :hash-of-array );
        $user_db = |%datas<datname>
    }
    $dbh.dispose();
    return $user_db, $system_db;
}


