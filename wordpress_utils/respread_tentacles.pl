#!/usr/bin/perl -w

die "You need to run this from within a custom_local dir (i.e. there is a ../wp-content and a ./wp-config.php)" unless -d '../wp-content' && -f './wp-config.php';

###  Plugins Dir
if (! -d '../wp-content/plugins.dist' ) {
    print "Re-linking Plugins...";
    `mkdir -p ../wp-content/plugins/widgets`;
    `mv ../wp-content/plugins ../wp-content/plugins.dist`;
    foreach (<../wp-content/plugins.dist/*>) {
        next unless m@([^/]+)$@;
        $lpiece = $1;
        print "\nPreserving Dist Plugin: ". $lpiece;
        `rm -f plugins/$lpiece;  ln -sn ../$_ plugins/$lpiece`;
    }
    `ln -sn ../custom_local/plugins ../wp-content/plugins`;
} else {
    print "Plugins dir already linked";
}

###  Themes Dir
if (! -d '../wp-content/themes.dist' ) {
    print "\n\nRe-linking Themes...";
    `mv ../wp-content/themes ../wp-content/themes.dist`;
    foreach (<../wp-content/themes.dist/*>) {
        next unless m@([^/]+)$@;
        $lpiece = $1;
        print "\nPreserving Dist Theme: ". $lpiece;
        `rm -f themes/$lpiece;  ln -sn ../$_ themes/$lpiece`;
    }
    `ln -sn ../custom_local/themes ../wp-content/themes`;
} else {
    print "\n\nThemes dir already linked";
}

###  Other wp-content stuff
print "\n\nRe-linking Other wp-content...";
foreach (<./other_wp-content/*>) {
    next unless m@([^/]+)$@;
    $lpiece = $1;
    if ( -e "../wp-content/$lpiece" ) {
        print "\nConflicting file exists (or it simply was already linked): ". $lpiece;
    } else {
        print "\nRestoring link to item: ". $lpiece;
        `ln -sn ../custom_local/other_wp-content/$lpiece ../wp-content/$lpiece`;
    }
}

###  Root dir items
if ( !    -e '../wp-config.php.dist' ) {
    print "\n\nRe-linking wp-config.php...";
    `mv ../wp-config.php ../wp-config.php.dist`        if -e '../wp-config.php' && ! -e '../wp-config.php.dist';
    `cp ../wp-config-sample.php ../wp-config.php.dist` if                          ! -e '../wp-config.php.dist';
    `ln wp-config.php ../wp-config.php`;
} else {
    print "\n\nwp-config.php already linked";
}

###  Show a diff on the config file
print "\n\nThese are the differences in the config.php";
exec 'diff -cbB ../wp-config.php.dist wp-config.php';


