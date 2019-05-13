use v6;
unit class App::DBBrowser::Opt::DBGet;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
#no precompilation;

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;

has $.i;
has $.o;

has $!db_opt;
has $!prev_plugin = '';


method read_db_config_files {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o );
    my $plugin = $!i<plugin>;
    $plugin ~~ s/ ^ 'App::DBBrowser::DB::' //;
    my $file_name = sprintf( $!i<conf_file_fmt>, $plugin );
    my $db_opt;
    if $file_name.IO.f && ! $file_name.IO.z {
        $db_opt = $ax.read_json( $file_name ) || {};
    }
    return $db_opt;
}


method attributes ( $db? ) {
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $plugin = $!i<plugin>;
    if $!prev_plugin ne $plugin {
        $!db_opt = Any;
        $!prev_plugin = $plugin;
    }
    # attributes added by hand to the config file: attribues are
    # only used if they have entries in the set_attributes method
    $!db_opt //= self.read_db_config_files();
    my $attributes = $plui.set_attributes();
    my $attrs = {};
    if $attributes {
        for $attributes.list -> $attr {
            my $name = $attr<name>;
            $attrs{$name} = $!db_opt{$db//''}{$name} // $!db_opt{$plugin}{$name} // $attr<values>[$attr<default>];
        }
    }
    return $attrs;

}

method login_data ( $db? ) {
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $plugin = $!i<plugin>;
    if $!prev_plugin ne $plugin {
        $!db_opt = Any;
        $!prev_plugin = $plugin;
    }
    $!db_opt //= self.read_db_config_files();
    my $arg = $plui.read_login_data();
    my $data = {};
    if $arg {
        for $arg.list -> $item {
            my $name = $item<name>;
            my $secret = $item<secret>;
            # field_is_required: 1 if undefined
            my $field_is_required = $!db_opt{$db//''}{'field_' ~ $name} // $!db_opt{$plugin}{'field_' ~ $name} // 1;
            if $field_is_required && ! $!i<login_error> {
                $data{$name}<default> = $!db_opt{$db//''}{$name} // $!db_opt{$plugin}{$name} // '';
                $data{$name}<secret>  = $secret;
            }
            #else {
                # if a login error occured, the user has to enter the arguments by hand
            #}
        }
    }
    if $!i<login_error>:exists {
        $!i<login_error>:delete;
    }
    return $data;
}


method enabled_env_vars ( $db? ) {
    my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
    my $plugin = $!i<plugin>;
    if $!prev_plugin ne $plugin {
        $!db_opt = Any;
        $!prev_plugin = $plugin;
    }
    $!db_opt //= self.read_db_config_files();
    my $env_vars = $plui.env_variables();
    my $enabled_env_vars = {};
    if $env_vars {
        for $env_vars.list -> $env_var {
            $enabled_env_vars{$env_var} = $!db_opt{$db//''}{$env_var} // $!db_opt{$!i<plugin>}{$env_var};
        }
    }
    return $enabled_env_vars;
}








