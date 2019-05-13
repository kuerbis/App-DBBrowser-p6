use v6;
unit class App::DBBrowser::Opt::DBSet;

CONTROL { when CX::Warn { note $_; exit 1 } }
use fatal;
no precompilation;

use Term::Choose;
use Term::Choose::Util;
use Term::Form;

use App::DBBrowser::Auxil;
use App::DBBrowser::DB;
use App::DBBrowser::Opt::DBGet;

has $.i;
has $.o;

has $!write_config;

method database_setting ( $db? ) {
    my $tc = Term::Choose.new( |$!i<default> );
    my $old_idx_sec = 0;

    SECTION: loop {
        my ( $plugin, $section );
        if $db.defined {
            $plugin = $!i<plugin>;
            $section = $db;
        }
        else {
            if $!o<G><plugins>.elems == 1 {
                $plugin = $!o<G><plugins>[0];
            }
            else {
                my @choices = Any, |$!o<G><plugins>.map: { "- $_" };
                # Choose
                my $idx_sec = $tc.choose(
                    @choices,
                    |$!i<lyt_v_clear>, :1index, :default( $old_idx_sec ), :undef( '  <=' )
                );
                if ! $idx_sec.defined || ! @choices[$idx_sec].defined {
                    return;
                }
                if $!o<G><menu-memory> {
                    if $old_idx_sec == $idx_sec && ! %*ENV<TC_RESET_AUTO_UP> {
                        $old_idx_sec = 0;
                        next SECTION;
                    }
                    $old_idx_sec = $idx_sec;
                }
                $plugin = @choices[$idx_sec];
                $plugin ~~ s/ ^ '-' \s //;
            }
            $plugin = 'App::DBBrowser::DB::' ~ $plugin;
            $!i<plugin> = $plugin;
            $section = $plugin;
        }
        my $plui = App::DBBrowser::DB.new( :$!i, :$!o );
        my $env_var    = $plui.env_variables();
        my $login_data = $plui.read_login_data();
        my $attr       = $plui.set_attributes();
        my %items = (
            :is_required( |$login_data.map: { %( name => 'field_' ~ $_<name>, prompt => $_<prompt> // $_<name>, values => [ 'NO', 'YES' ] ) } ),
            :env_variables( |$env_var.map:  { %( name => $_,                  prompt => $_,                     values => [ 'NO', 'YES' ] ) } ),
            :login_data( |$login_data.grep: { ! $_<secret> } ),
            :attributes( |$attr ),
        );

        my @groups;
        @groups.push: [ 'is_required',   "- Fields"        ] if %items<is_required>.elems;
        @groups.push: [ 'env_variables', "- ENV Variables" ] if %items<env_variables>.elems;
        @groups.push: [ 'login_data',    "- Login Data"    ] if %items<login_data>.elems;
        @groups.push: [ 'attributes',    "- Attributes"    ] if %items<attributes>.elems;
        if ! @groups.elems {
            #choose( ###
            #    [ 'No database settings available!' ],
            #    { %{$sf->{i}{lyt_m}}, prompt => 'Press ENTER' }
            #);
            return 0;
        }
        my $prompt = $db.defined ?? 'DB: ' ~ $db ~ '' !! '' ~ $plugin ~ '';
        my $r_db_opt = App::DBBrowser::Opt::DBGet.new( :$!o, :$!i );
        my $db_opt = $r_db_opt.read_db_config_files();

        my $changed = 0;
        my $old_idx_group = 0;

        GROUP: loop {
            my $reset = '  Reset DB';
            my @pre = Any;
            my @choices = |@pre, |@groups.map: { .[1] };
            @choices.push: $reset if ! $db.defined;
            # Choose
            my $idx_group = $tc.choose(
                @choices,
                |$!i<lyt_v_clear>, :$prompt, :1index, :default( $old_idx_group ), :undef( '  <=' )
            );
            if ! $idx_group.defined || ! @choices[$idx_group].defined {
                if $!write_config {
                    self!_write_db_config_files( $db_opt );
                    $!write_config = Any;
                    $changed++;
                }
                next SECTION if ! $db && $!o<G><plugins>.elems > 1;
                return $changed;
            }
            if $!o<G><menu-memory> {
                if $old_idx_group == $idx_group && ! %*ENV<TC_RESET_AUTO_UP> {
                    $old_idx_group = 0;
                    next GROUP;
                }
                $old_idx_group = $idx_group;
            }
            if @choices[$idx_group] eq $reset {
                my @databases;
                for $db_opt.keys -> $section {
                    @databases.push: $section if $section ne $plugin;
                }
                if ! @databases.elems {
                    $tc.choose(
                        [ 'No databases with customized settings.' ],
                        |$!i<lyt_v_clear>, :prompt( 'Press ENTER' )
                    );
                    next GROUP;
                }
                my $tu = Term::Choose::Util.new( |$!i<default> );
                my $choices = $tu.choose-a-subset(
                    [ @databases.sort ], #
                    :name( 'Reset DB: ' )
                );
                if ! @choices[0] {
                    next GROUP;
                }
                for @choices -> $db {
                    $db_opt{$db}:delete;
                }
                $!write_config++;
                next GROUP;;
            }
            my $group  = @groups[$idx_group-@pre.elems][0];
            if $group eq 'is_required' {
                my @sub_menu;
                for %items{$group}.list -> %item {
                    my $is_required = %item<name>;
                    @sub_menu.push: [ $is_required, '- ' ~ %item<prompt>, %item<values> ];
                    # $section == $db              else        global (plugin)        else  enabled
                    $db_opt{$section}{$is_required} //= $db_opt{$plugin}{$is_required} // 1;
                }
                my $prompt = 'Required fields (' ~ $plugin ~ '):';
                self!_settings_menu_wrap_db( $db_opt, $section, @sub_menu, $prompt );
                next GROUP;
            }
            elsif $group eq 'env_variables' {
                my @sub_menu;
                for %items{$group}.list -> $item {
                    my $env_variable = $item<name>;
                    @sub_menu.push: [ $env_variable, '- ' ~ $item<prompt>, $item<values> ];
                    # $section == $db               else        global (plugin)         else  disabled
                    $db_opt{$section}{$env_variable} //= $db_opt{$plugin}{$env_variable} // 0
                }
                my $prompt = 'Use ENV variables (' ~ $plugin ~ '):';
                self!_settings_menu_wrap_db( $db_opt, $section, @sub_menu, $prompt );
                next GROUP;
            }
            elsif $group eq 'login_data' {
                for %items{$group}.list -> $item {
                    my $opt = $item<name>;
                    # $section == $db      else        global (plugin)
                    $db_opt{$section}{$opt} //= $db_opt{$plugin}{$opt};
                }
                my $prompt = 'Default login data (' ~ $plugin ~ ')';
                self!_group_readline_db( $db_opt, $section, %items{$group}, $prompt );
            }
            elsif $group eq 'attributes' {
                my @sub_menu;
                for %items{$group}.list -> $item {
                    my $opt = $item<name>;
                    my $prompt = '- ' ~ ( $item<prompt>:exists ?? $item<prompt> !! $item<name> );
                    @sub_menu.push: [ $opt, $prompt, $item<values> ];
                    # $section == $db      else        global         else      default
                    $db_opt{$section}{$opt} //= $db_opt{$plugin}{$opt} // $item<values>[$item<default>];
                }
                my $prompt = 'Options (' ~ $plugin ~ '):';
                self!_settings_menu_wrap_db( $db_opt, $section, @sub_menu, $prompt );
                next GROUP;
            }
        }
    }
}


method !_settings_menu_wrap_db ( $db_opt, $section, @sub_menu, $prompt ) {
    my $tu = Term::Choose::Util.new( |$!i<default> );
    my $changed = $tu.settings-menu( @sub_menu, $db_opt{$section}, :$prompt );
    return if ! $changed;
    $!write_config++;
}


method !_group_readline_db ( $db_opt, $section, $items, $prompt ) {
    my $tf = Term::Form.new( :1loop );
    my $list = [ $items.map: { [
            $_<prompt>:exists ?? $_<prompt> !! $_<name>,
            $db_opt{$section}{$_<name>}
        ] }
    ];
    my $new_list = $tf.fill-form(
        $list,
        :$prompt, :2auto-up, :confirm( $!i<confirm> ), :back( $!i<back> )
    );
    if $new_list {
        for 0 .. $items.end -> $i {
            $db_opt{$section}{ $items[$i]<name> } = $new_list[$i][1];
        }
        $!write_config++;
    }
}


method !_write_db_config_files ( $db_opt ) {
    my $ax = App::DBBrowser::Auxil.new( :$!i, :$!o );
    my $plugin = $!i<plugin>;
    $plugin~~ s/ ^ 'App::DBBrowser::DB::' //;
    my $file_name = sprintf( $!i<conf_file_fmt>, $plugin );
    if $db_opt.defined && $db_opt.keys {
        $ax.write_json( $file_name, $db_opt );
    }
}




