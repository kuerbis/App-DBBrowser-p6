use v6;
unit class App::DBBrowser::Credentials;

use Term::Form;


has $.login_data;
has $.enabled_env_vars;


method get_login ( $key ) {
    if $!login_data{$key}:!exists {
        return;
    }
    my $default = $!login_data{$key}<default>;
    my $no-echo = $!login_data{$key}<secret>;
    my $env_var = 'DBI_' ~ $key.uc;
    if %*ENV{$env_var}:exists && $!enabled_env_vars{$env_var} {
        return %*ENV{$env_var}; #
    }
    elsif $default.defined && $default.chars {
        return $default;
    }
    else {
        my $prompt = $key.tc ~ ': ';
        my $tf = Term::Form.new( :1loop );
        # Readline
        my $new = $tf.readline( $prompt, :$no-echo );
        return $new;
    }
}



