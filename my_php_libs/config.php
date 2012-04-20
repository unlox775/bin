<?php

#########################
###  Globals

define( 'PROJECT_PROJECT_TIMERS', false);

###  Directory Locations
$SYSTEM_PROJECT_BASE = '/shared/accounts/m/mrsfields2/projects';
$PROJECT_SAFE_BASE = '/shared/accounts/m/mrsfields2/projects/logs';
$SYSTEM_TAGS_DB = $SYSTEM_PROJECT_BASE. '/tags_db.sq3';
$_SERVER['PROJECT_SVN_BASE'] = realpath( dirname(__FILE__) .'/../../'); # Just get it from out relative location

###  Determining which environment we are on...
function onAlpha() { return    preg_match('/dev/',  $_SERVER['HTTP_HOST']) ? true : false; }
function onBeta()  { return    preg_match('/beta/', $_SERVER['HTTP_HOST']) ? true : false; }
function onLive()  { return ( ! onAlpha() && ! onBeta() ) ? true : false; }

######  Sandbox Configuration
###  Staging Areas
$QA_ROLLOUT_PHASE_HOST   = '';
$PROD_ROLLOUT_PHASE_HOST = '';
$URL_BASE = '';
$PROJECT_STAGING_AREAS =
    array( array( 'label' => 'QA Staging Area',
                  'host'  => 'beta.admin.mrsfields.com',
                  'test_by_func' => 'onBeta',
                  ),
           array( 'label' => 'Live Production',
                  'host'  => 'admin.mrsfields.com',
                  'test_by_func' => 'onLive',
                  ),
           );
$PROJECT_SANDBOX_AREAS =
    array( array( 'label' => 'Tom',
                  'host'  => 'tom.dev.admin.mrsfields.com',
                  'test_uri_regex' => '/(^|\.)tom\./',
                  ),
           array( 'label' => 'Dave',
                  'host'  => 'dave.dev.admin.mrsfields.com',
                  'test_uri_regex' => '/(^|\.)dave\./',
                  ),
           array( 'label' => 'Korea',
                  'host'  => 'korea.dev.admin.mrsfields.com',
                  'test_uri_regex' => '/(^|\.)korea\./',
                  ),
           );
