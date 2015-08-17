#!/usr/bin/php
<?php

if ( file_exists('./sftp-config.json') ) { exit; }

list($x,$user,$hostname,$remote_dir,$local_dir) = $argv;

$contents = <<<EOT
{
    // The tab key will cycle through the settings when first created
    // Visit http://wbond.net/sublime_packages/sftp/settings for help
    
    // sftp, ftp or ftps
    "type": "sftp",

    "save_before_upload": true,
    "upload_on_save": true,
    "sync_down_on_open": false,
    "sync_skip_deletes": false,
    "sync_same_age": true,
    "confirm_downloads": false,
    "confirm_sync": true,
    "confirm_overwrite_newer": false,
    
    "host": "$hostname",
    "user": "$user",
    //"password": "password",
    //"port": "22",
    
    "remote_path": "/mnt/home/$user/$remote_dir/",
    "ignore_regexes": [
        "\\\\.sublime-(project|workspace)", "sftp-config(-alt\\\\d?)?\\\\.json",
        "sftp-settings\\\\.json", "/venv/", "\\\\.svn/", "\\\\.hg/", "\\\\.git/",
        "\\\\.bzr", "_darcs", "CVS", "\\\\.DS_Store", "Thumbs\\\\.db", "desktop\\\\.ini"
    ],
    "file_permissions": "664",
    "dir_permissions": "775",
    
    //"extra_list_connections": 0,

    "connect_timeout": 60,
    //"keepalive": 120,
    //"ftp_passive_mode": true,
    //"ftp_obey_passive_host": false,
    //"ssh_key_file": "~/.ssh/id_rsa",
    //"sftp_flags": ["-F", "/path/to/ssh_config"],
    
    "preserve_modification_times": true,
    //"remote_time_offset_in_hours": 0,
    //"remote_encoding": "utf-8",
    //"remote_locale": "C",
    //"allow_config_upload": false,
}
EOT;

file_put_contents('./sftp-config.json',$contents);
