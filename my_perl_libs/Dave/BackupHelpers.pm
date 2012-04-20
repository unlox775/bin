package Dave::BackupHelpers;

#########################
###  Dave/BackupHelpers.pm
###  Version : $Id: BackupHelpers.pm,v 1.2 2009/09/02 15:37:12 dave Exp $
###
###  Lib for shared backup functions
#########################

#########################
###  Package Config

######  Exporter Parameters
###  Get the Library and use it
use Exporter;
use vars qw( @ISA @EXPORT_OK %EXPORT_TAGS );
@ISA = ('Exporter');

###  Define the Exported Symbols
@EXPORT_OK = qw( &mirror_ssh_direct_rsync
                 &mirror_ssh_no_remote_rsync
                 &mirror_ftp
                 &mirror_ftp_with_pretar

                 $test_mode
                 $vb
              );
%EXPORT_TAGS = (common => [qw( &mirror_ssh_direct_rsync
                               &mirror_ssh_no_remote_rsync
                               &mirror_ftp
                               &mirror_ftp_with_pretar

                               $test_mode
                               $vb
                            )]);

our $SSHFS = '/Applications/MacFusion.app/Contents/PlugIns/sshfs.mfplugin/Contents/Resources/sshfs-static';
our $FTPFS = '/Applications/MacFusion.app/Contents/PlugIns/ftpfs.mfplugin/Contents/Resources/curlftpfs_static_mg';


sub our_system { print @_,"\n" if $test_mode;  return system(@_); }

sub mirror_ssh_direct_rsync {
    my ( $settings ) = @_;
    
    $remote_host_string = defined($settings->{'remote_host_string'}) ? $settings->{'remote_host_string'} : "$settings->{remote_username}\@$settings->{remote_host}:";
    
    foreach my $mirror ( @{$settings->{'mirrors'}} ) { 
        $exclude_dirs = ( ( UNIVERSAL::isa($mirror->{'size_only_dirs'},'ARRAY')
                            && @{$mirror->{'size_only_dirs'}}
                          )
                          ? ('--exclude='. join(' --exclude=', @{$mirror->{'size_only_dirs'}})) 
                          : ''
            );
        $exclude_file = $mirror->{'exclude_file'} ? ('--exclude-from='.$mirror->{'exclude_file'}) : '';

        if ( ! -d $mirror->{local_dir} ) {
            print "\n\n----------------   Local dir didn't exist...  Making dir.\n" if $vb;
            our_system("mkdir -p $mirror->{local_dir}") if ! $test_mode;
        }

        ###  Main backup
        if ( ! $mirror->{skip_full_mirror} ) {
            print "\n\n----------------   Mirroring $settings->{remote_account_name}, $mirror->{remote_dir} dir\n" if $vb;
            our_system(        "rsync $test_mode -a $vb $exclude_dirs --delete         $exclude_file           $remote_host_string$mirror->{remote_dir}/.      $mirror->{local_dir}/."
                               ." 2>&1 | egrep -v '(setsockopt IP_TOS [0-9]+: Invalid argument)'"
                      );
        }
    
        ###  Handle Size-Only Dirs
        if ( UNIVERSAL::isa($mirror->{'size_only_dirs'},'ARRAY')
             && @{$mirror->{'size_only_dirs'}}
            ) {
            $size_only_exclude_file = defined($mirror->{'size_only_exclude_file'}) ? $mirror->{'size_only_exclude_file'} : $mirror->{'exclude_file'};
            $size_only_exclude_file = $size_only_exclude_file ? ('--exclude-from='.$size_only_exclude_file) : '';
            foreach my $dir ( @{$mirror->{'size_only_dirs'}} ) { 
                if ( ! -d "$mirror->{local_dir}/$dir" ) {
                    print "\n\n----------------   Local dir didn't exist...  Making dir.\n" if $vb;
                    our_system("mkdir -p $mirror->{local_dir}/$dir") if ! $test_mode;
                }

                print "\n\n----------------   Mirroring $settings->{remote_account_name}, $dir (no update times, size-only check)\n" if $vb;
                our_system("rsync $test_mode -rlpgoD $vb --delete-excluded --size-only $size_only_exclude_file $remote_host_string$mirror->{remote_dir}/$dir/. $mirror->{local_dir}/$dir/."
                           ." 2>&1 | egrep -v '(some files could not be transferred|aaa_ignore_|setsockopt IP_TOS [0-9]+: Invalid argument)'"
                    );
            }
        }
    }
}


sub mirror_ssh_no_remote_rsync {
    my ( $settings ) = @_;

    $mount_dir = defined($settings->{'mount_dir'}) ? $settings->{'mount_dir'} : '';
    $mount_command = ( defined($settings->{'mount_command'})
                       ? $settings->{'mount_command'}
                       : "$SSHFS $settings->{remote_username}\@$settings->{remote_host}:$mount_dir /Volumes/$settings->{remote_host} -oworkaround=rename -ovolname=$settings->{remote_host}"
                       );
    
    ####  Un-mount if the dir is there...
    if ( -d "/Volumes/$settings->{remote_host}" ) {
        print "\n\n----------------   Un-mounting $settings->{remote_account_name} locally...\n" if $vb;
        our_system("/sbin/umount -f /Volumes/$settings->{remote_host}/ 2>&1 | grep -v 'not currently mounted'");
        sleep 5;
    }
    ####  Mount the FUSE FS
    if ( ! glob("/Volumes/$settings->{remote_host}/*") ) {
        print "\n\n----------------   Mounting $settings->{remote_account_name} locally as a FUSE filesystem...\n" if $vb;
        our_system("mkdir -p /Volumes/". $settings->{remote_host});
        our_system($mount_command);
        sleep 20;
    }
    else {
        return warn "\n\n\n\nERROR: UN-Mounting /Volumes/$settings->{remote_host}/ must have failed, or at least there is stuff in the mount dir, Skipping backup up of $settings->{remote_account_name}...\n\n\n\n";
    }
    ###  If it really did mount then proceed with backup...
    if ( glob("/Volumes/$settings->{remote_host}/*") ) {
        $settings->{'remote_host_string'} = "/Volumes/$settings->{remote_host}/";

        mirror_ssh_direct_rsync($settings);
    }
    else {
        return warn "\n\n\n\nERROR: Mounting /Volumes/$settings->{remote_host}/ must have failed, or at least there weren't any files or dirs in the mount dir after mount, Skipping backup up of $settings->{remote_account_name}...\n\n\n\n";
    }

    print "\n\n----------------   DONE, so Un-mounting $settings->{remote_account_name} local FUSE filesystem...\n" if $vb;
    our_system("/sbin/umount -f /Volumes/$settings->{remote_host}/ 2>&1 | grep -v 'not currently mounted'");
}


sub mirror_ftp {
    my ( $settings ) = @_;
    
    $mount_dir = defined($settings->{'mount_dir'}) ? $settings->{'mount_dir'} : '';
    $settings->{'mount_command'} = "$FTPFS ftp://$settings->{remote_username}:$settings->{remote_password}\@$settings->{remote_host}$mount_dir /Volumes/$settings->{remote_host} -ovolname=$settings->{remote_host} -o uid=501";
    return mirror_ssh_no_remote_rsync($settings);
}


sub mirror_ftp_with_pretar {
    my ( $settings ) = @_;
    
    print "\n\n----------------   Mirroring $settings->{remote_account_name}, Preparing for backup (Tarring up on the server)...\n" if $vb;
    our_system("curl -sS $settings->{pretar_http_url}  | cat - > /dev/null") if ! $test_mode;

    foreach my $mirror ( @{$settings->{'mirrors'}} ) { 
        $mirror->{'skip_full_mirror'} = 1;
        $mirror->{'remote_host_string'} = "";
    }

    return mirror_ftp($settings);
}
