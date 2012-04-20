#!/usr/bin/perl -w

die "You need to run this from within a wordpress root dir (i.e. there is a ./wp-content)" unless -d './wp-content';

print "Making Dir and putting stuff in...";
print `mkdir -p custom_local/other_wp-content`;
print `mv wp-config.php custom_local/`;
print `ln -sn ~/bin/wordpress_utils/respread_tentacles.pl custom_local/respread_tentacles.pl`;
print `mv wp-content/plugins wp-content/themes custom_local/`;
print `mv wp-content/uploads                   custom_local/other_wp-content/`;


print "\n\nMoving out Dist stuff...";
print `mkdir wp-content/plugins wp-content/themes`;
print `mv custom_local/plugins/akismet custom_local/plugins/hello.php wp-content/plugins/`;
print `mv custom_local/themes/classic custom_local/themes/default     wp-content/themes/`;


print "\n\nRunning Respread Tentacles...";
chdir './custom_local/';
exec './respread_tentacles.pl';


