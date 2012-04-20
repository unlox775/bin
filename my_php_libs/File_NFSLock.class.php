<?php

/*  File_NFSLock - bdpO - NFS compatible (safe) locking utility
 *  
 *  $Id: File_NFSLock.class.php,v 1.9 2011/05/23 16:28:50 dave Exp $
 *  
 *  Copyright (C) 2010, Dave Buchanan
 *                      dos@joesvolcano.net
 *                      http://joesvolcano.net/open_source/
 *  
 *                      Paul T Seamons
 *                      paul@seamons.com
 *                      http://seamons.com/
 *  
 *                      Rob B Brown
 *                      bbb@cpan.org
 *  
 *  This package may be distributed under the terms of either the
 *  GNU General Public License
 *    or the
 *  Perl Artistic License
 *  
 *  All rights reserved.
 *  
 *  See the FULL Documentation at the bottom of this file...
 *  
 **********************************************************/

define('NFS_LOCK_SH', 1);
define('NFS_LOCK_EX', 2);
define('NFS_LOCK_NB', 4);
define('NFS_LOCK_EX_OR_NB', 2 | 4);

class File_NFSLock {

    ### Convert lock_type to a number
    var $TYPES = array( 'BLOCKING'    => NFS_LOCK_EX,
                        'BL'          => NFS_LOCK_EX,
                        'EXCLUSIVE'   => NFS_LOCK_EX,
                        'EX'          => NFS_LOCK_EX,
                        'NONBLOCKING' => NFS_LOCK_EX_OR_NB,
                        'NB'          => NFS_LOCK_EX_OR_NB,
                        'SHARED'      => NFS_LOCK_SH,
                        'SH'          => NFS_LOCK_SH,
                        );
    var $LOCK_EXTENSION = '.NFSLock'; # customizable extension
    var $HOSTNAME = null;
    var $SHARE_BIT = 1;
    var $errstr = null;
    var $rand_file = null;
    var $unlocked = true;
    public $lock_success = false;

    function __construct($file, $lock_type = null, $blocking_timeout = null, $stale_lock_timeout = null ) {
      ###  Allow params passed by array
      $args = func_get_args();
      if ( count( $args ) == 1 && is_array($args[0]) ) {
          if ( isset( $args[0]['file']               ) ) $file                 = $args[0]['file'];
          if ( isset( $args[0]['lock_type']          ) ) $lock_type            = $args[0]['lock_type'];
          if ( isset( $args[0]['blocking_timeout']   ) ) $blocking_timeout     = $args[0]['blocking_timeout'];
          if ( isset( $args[0]['stale_lock_timeout'] ) ) $stale_lock_timeout   = $args[0]['stale_lock_timeout'];
          if ( isset( $args[0]['lock_extension']     ) ) $this->LOCK_EXTENSION = $args[0]['lock_extension'];
      }
    
      list( $this->file, $this->lock_type, $this->blocking_timeout, $this->stale_lock_timeout ) = 
          array( $file, $lock_type, $blocking_timeout, $stale_lock_timeout );
      if ( empty($this->file) )               $this->file               = '';
      if ( empty($this->lock_type) )          $this->lock_type          = 0;
      if ( empty($this->blocking_timeout) )   $this->blocking_timeout   = 0;
      if ( empty($this->stale_lock_timeout) ) $this->stale_lock_timeout = 0;
      $this->lock_pid = getmypid();
      $this->unlocked = true;
######  Disabled Signals for now
###        foreach ($CATCH_SIGS as $signal ) {
###          if (!$SIG[$signal] ||
###              $SIG[$signal] == "DEFAULT") {
###            $SIG[$signal] = $graceful_sig;
###          }
###        }
    
      ### force lock_type to be numerical
      if( $this->lock_type &&
          ! preg_match('/^\d+/', $this->lock_type) &&
          array_key_exists( $this->TYPES[$this->lock_type] ) ){
        $this->lock_type = $this->TYPES[$this->lock_type];
      }
    
      ### need the hostname
      if ( function_exists('gethostname') ) $this->HOSTNAME = gethostname();
      else                                  $this->HOSTNAME = php_uname("n");
      if ( empty($this->HOSTNAME) )         $this->HOSTNAME = `hostanme`; # one last try...
    
      ### quick usage check
      if ( strlen($this->file) == 0 ) 
          return trigger_error(($errstr = "Usage: \$f = $class->new('/pathtofile/file',\n"
             ."'BLOCKING|EXCLUSIVE|NONBLOCKING|SHARED', [blocking_timeout, stale_lock_timeout]);\n"
              ."(You passed \"$this->file\" and \"$this->lock_type\")"), E_USER_ERROR);

      if ( empty( $this->lock_type ) && preg_match('/^\d+$/', $this->lock_type, $m) ) 
      return trigger_error(($errstr = "Unrecognized lock_type operation setting [$this->lock_type]"), E_USER_ERROR);
    
      ### choose a random filename
      $this->rand_file = $this->rand_file( $this->file );
    
      ### choose the lock filename
      $this->lock_file = $this->file . $this->LOCK_EXTENSION;
    
      $quit_time = ( ( ! empty( $this->blocking_timeout ) &&
                     ( ($this->lock_type & NFS_LOCK_NB) == 0) )
                     ? ( time() + $this->blocking_timeout )
                     : 0
                     );
    
      ### remove an old lockfile if it is older than the stale_timeout
      if( file_exists($this->lock_file) &&
          $this->stale_lock_timeout > 0 &&
          time() - filemtime($this->lock_file) > $this->stale_lock_timeout ){
          unlink( $this->lock_file );
      }
    
      while (true) {
        ### open the temporary file
        if ( ! $this->create_magic() ) return false;
    
        if ( ( $this->lock_type & NFS_LOCK_EX ) != 0 ) {
            if ( $this->do_lock() ) break;
        } else if ( ( $this->lock_type & NFS_LOCK_SH ) != 0 ) {
            if ( $this->do_lock_shared() ) break;
        } else {
          $errstr = "Unknown lock_type [$this->lock_type]";
          return false;
        }
    
        ### Lock failed!
    
        ### I know this may be a race condition, but it's okay.  It is just a
        ### stab in the dark to possibly find long dead processes.
    
        ### If lock exists and is readable, see who is mooching on the lock
    
        clearstatcache();
        if ( file_exists($this->lock_file) ) { 
          @$_FH = fopen($this->lock_file,'r+');
          if ( $_FH !== false ) {
    
            $mine = array();
            $them = array();
            $dead = array();
      
            @$stat = stat($this->lock_file);  $has_lock_exclusive = (($stat[2]         & $this->SHARE_BIT) == 0) ? true : false;
            $try_lock_exclusive =                                  (($this->lock_type & NFS_LOCK_SH) == 0         ) ? true : false;
      
            $buffer = '';
            while ( ( $read = fread($_FH, 4096) ) || strlen($buffer) != 0 ) {
                if ( $read !== false ) $buffer .= $read;
                if ( strpos( $buffer, "\n") === false && $read !== false ) continue; # skip until we have a full line, or EOF
                $lines = explode("\n", $buffer);
                $buffer = ( $read !== false ) ? array_pop($lines) : '';
                foreach ( $lines as $line ) { # replacement for : "while(defined($line=<_FH>)"
                    if (preg_match('/^\Q'. $this->HOSTNAME .'\E (\d+) /', $line, $m)) {
                    $pid = $m[1];
                    if ($pid == getmypid()) {       # This is me.
                      array_push( $mine, $line );
                    }else if(posix_kill( $pid, 0 ) ) {  # Still running on this host.
                      array_push( $them, $line );
                    }else{                  # Finished running on this host.
                      array_push( $dead, $line );
                    }
                  } else {                  # Running on another host, so
                    array_push( $them, $line );      #  assume it is still running.
                  }
                }
                if ( $read === false && strlen($buffer) == 0 ) break; # save an fread()
            }
      
            ### If there was at least one stale lock discovered...
            if (! empty( $dead ) ) {
              # Lock lock_file to avoid a race condition.
              $lock = new File_NFSLock( array( 'file'               => $this->lock_file,
                                                'lock_type'          => NFS_LOCK_EX,
                                                'blocking_timeout'   => 62,
                                                'stale_lock_timeout' => 60,
                                                'lock_extension'     => '.shared',
                                                ));
      
              ### Rescan in case lock contents were modified between time stale lock
              ###  was discovered and lockfile lock was acquired.
              fseek($_FH, 0, SEEK_CUR);
              $content = '';
              $buffer = '';
              while ( ( $read = fread($_FH, 4096) ) || strlen($buffer) != 0 ) {
                  if ( $read !== false ) $buffer .= $read;
                  if ( strpos( $buffer, "\n") === false && $read !== false ) continue; # skip until we have a full line, or EOF
                  $lines = explode("\n", $buffer);
                  $buffer = ( $read !== false ) ? array_pop($lines) : '';
                  foreach ( $lines as $line ) { # replacement for : "while(defined($line=<_FH>)"
                      if (preg_match('/^\Q'. $this->HOSTNAME .'\E (\d+) /', $line, $m)) {
                      $pid = $m[1];
                      if (!posix_kill( $pid, 0)) continue;  # Skip dead locks from this host
                    }
                    $content .= $line;          # Save valid locks
                  }
                  if ( $read === false && strlen($buffer) == 0 ) break; # save an fread()
              }
      
              ### Save any valid locks or wipe file.
              if( strlen($content) != 0 ){
                  fseek(     $_FH, 0, SEEK_SET);
                  fwrite(    $_FH, $content);
                  ftruncate( $_FH, strlen($content));
                  fclose(    $_FH);
              }else{
                  fclose( $_FH);
                  unlink( $this->lock_file );
              }
      
            ### No "dead" or stale locks found.
            } else {
                fclose( $_FH );
            }
      
            ### If attempting to acquire the same type of lock
            ###  that it is already locked with, and I've already
            ###  locked it myself, then it is safe to lock again.
            ### Just kick out successfully without really locking.
            ### Assumes locks will be released in the reverse
            ###  order from how they were established.
            if ($try_lock_exclusive == $has_lock_exclusive && $mine){
                $this->lock_success = true;
                return true;
            }
          }
        }
    
        ### If non-blocking, then kick out now.
        ### ($errstr might already be set to the reason.)
        if ( ( $this->lock_type & NFS_LOCK_NB ) != 0 ) {
          if ( empty($errstr) ) $errstr = "NONBLOCKING lock failed!";
          return false;
        }
    
        ### wait a moment
        sleep(1);
    
        ### but don't wait past the time out
        if( ! empty( $quit_time ) && (time() > $quit_time) ){
          $errstr = "Timed out waiting for blocking lock";
          return false;
        }
    
        # BLOCKING Lock, So Keep Trying
      }
    
      ### clear up the NFS cache
      $this->uncache();
    
      ### Yes, the lock has been aquired.
      $this->unlocked = false;
    
      $this->lock_success = true;
      return true;
    }
    
    function __destruct() {
      $this->unlock();
    }
    
    function unlock() {
      if ( ! $this->unlocked) {
        if ( file_exists($this->rand_file) ) unlink( $this->rand_file );
        if( ( $this->lock_type & NFS_LOCK_SH) != 0 ){
            $retval = $this->do_unlock_shared();
        }else{
            $retval = $this->do_unlock();
        }
        $this->unlocked = true;
######  Disabled Signals for now
###          foreach ($CATCH_SIGS as $signal ) {
###            if ($SIG[$signal] &&
###                ($SIG[$signal] == $graceful_sig)) {
###              # Revert handler back to how it used to be.
###              # Unfortunately, this will restore the
###              # handler back even if there are other
###              # locks still in tact, but for most cases,
###              # it will still be an improvement.
###              delete $SIG[$signal];
###            }
###          }
        return $retval;
      }
      return true;
    }
    
    ###----------------------------------------------------------------###
    
    # concepts for these routines were taken from Mail__Box which
    # took the concepts from Mail__Folder
    
    
    function rand_file($file) {
        return "$file.tmp.". time()%10000 .'.'. getmypid() .'.'. floor(rand(0,10000));
    }
    
    function create_magic($append_file = null) {
      if ( is_null($append_file) ) $append_file = $this->rand_file;
      $this->errstr = null;
      if ( empty($this->lock_line) ) $this->lock_line = $this->HOSTNAME." $this->lock_pid ".time()." ".floor(rand(0,10000))."\n";
      @$success = file_put_contents($append_file, $this->lock_line, FILE_APPEND);
      if ( $success === false ) {
          $this->errstr = "Couldn't open \"$append_file\" [$!]";
          return false;
      }
      return true;
    }
    
    function do_lock() {
      $errstr = null;
      $lock_file = $this->lock_file;
      $rand_file = $this->rand_file;
      $chmod = 0600;
      if ( ! chmod( $rand_file, $chmod ) )
        return trigger_error("I need ability to chmod files to adequatetly perform locking", E_USER_ERROR);
    
      ### try a hard link, if it worked
      ### two files are pointing to $rand_file
      @link( $rand_file, $lock_file ); # ignore file exists warnings on this line (tho WHY????!!!)
      clearstatcache();
      $stat = stat( $rand_file );
      $success = ( file_exists($rand_file) && $stat[3] == 2 );
      unlink( $rand_file );
    
      return $success;
    }
    
    function do_lock_shared() {
      $errstr = null;
      $lock_file  = $this->lock_file;
      $rand_file  = $this->rand_file;
    
      ### chmod local file to make sure we know before
      $chmod = 0600;
      $chmod |= $this->SHARE_BIT;
      if ( ! chmod( $rand_file, $chmod) )
        return trigger_error("I need ability to chmod files to adequatetly perform locking", E_USER_ERROR);
    
      ### lock the locking process
      $lock = new File_NFSLock( array( 'file'               => $lock_file,
                                       'lock_type'          => NFS_LOCK_EX,
                                       'blocking_timeout'   => 62,
                                       'stale_lock_timeout' => 60,
                                       'lock_extension'     => '.shared',
                                       ));
      # The ".shared" lock will be released as this status
      # is returned, whether or not the status is successful.
    
      ### If I didn't have exclusive and the shared bit is not
      ### set, I have failed
    
      ### Try to create $lock_file from the special
      ### file with the magic $this->SHARE_BIT set.
      $success = link( $lock_file, $rand_file );
      unlink( $rand_file );
      clearstatcache();
      $stat = stat( $lock_file );
      if ( empty( $success ) &&
           file_exists($lock_file) &&
           ( $stat[2] & $this->SHARE_BIT) != $this->SHARE_BIT ){
    
        $errstr = 'Exclusive lock exists.';
        return false;
    
      } else if ( empty( $success ) ) {
        ### Shared lock exists, append lock
        $this->create_magic ($this->lock_file);
      }
    
      # Success
      return true;
    }
    
    function do_unlock() {
        return unlink( $this->lock_file );
    }
    
    function do_unlock_shared() {
      $errstr = null;
      $lock_file = $this->lock_file;
      $lock_line = $this->lock_line;
    
      ### lock the locking process
      $lock = new File_NFSLock( array( 'file'               => $lock_file,
                                       'lock_type'          => NFS_LOCK_EX,
                                       'blocking_timeout'   => 62,
                                       'stale_lock_timeout' => 60,
                                       'lock_extension'     => '.shared',
                                       ));
    
      ### get the handle on the lock file
      if( ! ( $_FH = fopen($lock_file,'r+') ) ){
        if( ! file_exists($lock_file) ){
          return true;
        }else{
          return trigger_error("Could not open for writing shared lock file $lock_file ($!)", E_USER_ERROR);
        }
      }
    
      ### read existing file
      $content = '';
      $buffer = '';
      while ( ( $read = fread($_FH, 4096) ) || strlen($buffer) != 0 ) {
          if ( $read !== false ) $buffer .= $read;
          if ( strpos( $buffer, "\n") === false && $read !== false ) continue; # skip until we have a full line, or EOF
          $lines = explode("\n", $buffer);
          $buffer = ( $read !== false ) ? array_pop($lines) : '';
          foreach ( $lines as $line ) { # replacement for : "while(defined($line=<_FH>)"
            if ( $line == $lock_line ) continue;
            $content .= $line;
          }
          if ( $read === false && strlen($buffer) == 0 ) break; # save an fread()
      }
    
      ### other shared locks exist
      if( strlen($content) != 0 ){
        fseek(     $_FH, 0, SEEK_SET);
        fwrite(    $_FH, $content);
        ftruncate( $_FH, strlen($content));
        fclose(    $_FH);
          
      ### only I exist
      }else{
        fclose( $_FH);
        unlink( $lock_file );
      }
    
    }
    
    function uncache($file = null) {
      if ( is_null($file) ) $file = $this->file;
      $rand_file = $this->rand_file( $file );
    
      ### hard link to the actual file which will bring it up to date
      @$success = link( $file, $rand_file) && unlink($rand_file); 
      return( $success );
    }
    
    function newpid() {
      # Detect if this is the parent or the child
      if ($this->lock_pid == getmypid()) {
        # This is the parent
    
        # Must wait for child to call newpid before processing.
        # A little patience for the child to call newpid
        $patience = time() + 10;
        while (time() < $patience) {
          if (rename("$this->lock_file.fork",$this->rand_file)) {
            # Child finished its newpid call.
            # Wipe the signal file.
            unlink( $this->rand_file );
            break;
          }
          # Brief pause before checking again
          # to avoid intensive IO across NFS.
          usleep(100000); # sleep for 0.1 seconds
        }
    
        # Fake the parent into thinking it is already
        # unlocked because the child will take care of it.
        $this->unlocked = true;
      } else {
        # This is the new child
    
        # The lock_line found in the lock_file contents
        # must be modified to reflect the new pid.
    
        # Fix lock_pid to the new pid.
        $this->lock_pid = getmypid();
        # Backup the old lock_line.
        $old_line = $this->lock_line;
        # Clear lock_line to create a fresh one.
        $this->lock_line = null;
        # Append a new lock_line to the lock_file.
        $this->create_magic($this->lock_file);
        $new_line = $this->lock_line;
        # Remove the old lock_line from lock_file.
        $this->lock_line = $old_line;
        $this->do_unlock_shared();
        # Create signal file to notify parent that
        # the lock_line entry has been delegated.
        fopen($_FH, $this->lock_file .".fork",'w');
        close($_FH);
        $this->lock_line = $new_line; #because PHP doeesn't have local scoping...
      }
    }

}

###  Non-OO Uncache function
function nfs_uncache($file) {
  if ( is_array($file) ) $file = $file['file'];
  $rand_file = File_NFSLock::rand_file( $file );

  ### hard link to the actual file which will bring it up to date
  return ( link( $file, $rand_file) && unlink($rand_file) );
}
    


/*  ---   FULL DOCUMENTATION  ---
 * 
 *  ---   NAME
 *  
 *  File_NFSLock - perl module to do NFS (or not) locking
 *  
 *  ---   SYNOPSIS
 *  
 *    require_once('File_NFSLock.class.php');
 *  
 *    $file = "somefile";
 *  
 *    ### set up a lock - lasts until object looses scope
 *    $lock = new File_NFSLock( array( 'file'               => $file,
 *                                     'lock_type'          => NFS_LOCK_EX|NFS_LOCK_NB,
 *                                     'blocking_timeout'   => 10,      # 10 sec
 *                                     'stale_lock_timeout' => 30 * 60, # 30 min
 *                                     )
 *                              );
 *    if ( $lock->lock_success ) {
 *  
 *      ### OR
 *      ### $lock = new File_NFSLock($file,NFS_LOCK_EX|NFS_LOCK_NB,10,30*60);
 *  
 *      ### do write protected stuff on $file
 *      ### at this point $file is uncached from NFS (most recent)
 *      $FILE = fopen($file, "r+");
 *  
 *      ### or open it any way you like
 *      ### file_get_contents( $file, "Foo" );
 *  
 *      ### update (uncache across NFS) other files
 *      $lock->uncache("someotherfile1");
 *      nfs_uncache("someotherfile2");
 *      # $FILE2 = fopen("someotherfile1", 'r+');
 *  
 *      ### unlock it
 *      $lock->unlock();
 *      ### OR
 *      ### unset( $lock );
 *      ### OR when lock object is garbage collected, it's __destruct() will un-lock
 *    }else{
 *      return trigger_error("I couldn't lock the file [$lock->errstr]", E_USER_ERROR);
 *    }
 *  
 *  
 *  ---   DESCRIPTION
 *  
 *  Program based of concept of hard linking of files being atomic across
 *  NFS.  This concept was mentioned in Mail__Box__Locker (which was
 *  originally presented in Mail__Folder__Maildir).  Some routine flow is
 *  taken from there -- particularly the idea of creating a random local
 *  file, hard linking a common file to the local file, and then checking
 *  the nlink status.  Some ideologies were not complete (uncache
 *  mechanism, shared locking) and some coding was even incorrect (wrong
 *  stat index).  File_NFSLock was written to be light, generic,
 *  and fast.
 *  
 *  
 *  ---   USAGE
 *  
 *  Locking occurs by creating a File_NFSLock object.  If the object
 *  is created successfully, a lock is currently in place and remains in
 *  place until the lock object goes out of scope (or calls the unlock
 *  method).
 *  
 *  A lock object is created by calling the new method and passing two
 *  to four parameters in the following manner:
 *  
 *    $lock = new File_NFSLock($file,
 *                             $lock_type,
 *                             $blocking_timeout,
 *                             $stale_lock_timeout,
 *                             );
 *  
 *  Additionally, parameters may be passed as a hashref:
 *  
 *    $lock = new File_NFSLock(array(
 *      'file'               => $file,
 *      'lock_type'          => $lock_type,
 *      'blocking_timeout'   => $blocking_timeout,
 *      'stale_lock_timeout' => $stale_lock_timeout,
 *    ));
 *  
 *  ---   PARAMETERS
 *  
 *      ---  Parameter 1: file
 *      
 *      Filename of the file upon which it is anticipated that a write will
 *      happen to.  Locking will provide the most recent version (uncached)
 *      of this file upon a successful file lock.  It is not necessary
 *      for this file to exist.
 *      
 *      ---  Parameter 2: lock_type
 *      
 *      Lock type must be one of the following:
 *      
 *        BLOCKING
 *        BL
 *        EXCLUSIVE (BLOCKING)
 *        EX
 *        NONBLOCKING
 *        NB
 *        SHARED
 *        SH
 *      
 *      Or else one or more of the following joined with '|':
 *      
 *        Fcntl__NFS_LOCK_EX() (BLOCKING)
 *        Fcntl__NFS_LOCK_NB() (NONBLOCKING)
 *        Fcntl__NFS_LOCK_SH() (SHARED)
 *      
 *      Lock type determines whether the lock will be blocking, non blocking,
 *      or shared.  Blocking locks will wait until other locks are removed
 *      before the process continues.  Non blocking locks will return undef if
 *      another process currently has the lock.  Shared will allow other
 *      process to do a shared lock at the same time as long as there is not
 *      already an exclusive lock obtained.
 *      
 *      ---  Parameter 3: blocking_timeout (optional)
 *      
 *      Timeout is used in conjunction with a blocking timeout.  If specified,
 *      File_NFSLock will block up to the number of seconds specified in
 *      timeout before returning undef (could not get a lock).
 *      
 *      
 *      ---  Parameter 4: stale_lock_timeout (optional)
 *      
 *      Timeout is used to see if an existing lock file is older than the stale
 *      lock timeout.  If do_lock fails to get a lock, the modified time is checked
 *      and do_lock is attempted again.  If the stale_lock_timeout is set to low, a
 *      recursion load could exist so do_lock will only recurse 10 times (this is only
 *      a problem if the stale_lock_timeout is set too low -- on the order of one or two
 *      seconds).
 *  
 *  ---   METHODS
 *  
 *  After the $lock object is instantiated with new,
 *  as outlined above, some methods may be used for
 *  additional functionality.
 *  
 *      ---  unlock
 *      
 *        $lock->unlock;
 *      
 *      This method may be used to explicitly release a lock
 *      that is aquired.  In most cases, it is not necessary
 *      to call unlock directly since it will implicitly be
 *      called when the object leaves whatever scope it is in.
 *      
 *      ---  uncache
 *      
 *        $lock->uncache;
 *        $lock->uncache("otherfile1");
 *        nfs_uncache("otherfile2");
 *      
 *      This method is used to freshen up the contents of a
 *      file across NFS, ignoring what is contained in the
 *      NFS client cache.  It is always called from within
 *      the new constructor on the file that the lock is
 *      being attempted.  uncache may be used as either an
 *      object method or as a stand alone subroutine (named nfs_uncache()).
 *      
 *      ---  newpid
 *      
 *        $pid = fork;
 *        if ( $pid == -1) ) {
 *          # Fork Failed
 *        } else if ($pid != 0) {
 *          $lock->newpid; # Parent
 *        } else {
 *          $lock->newpid; # Child
 *        }
 *      
 *      If fork() is called after a lock has been aquired,
 *      then when the lock object leaves scope in either
 *      the parent or child, it will be released.  This
 *      behavior may be inappropriate for your application.
 *      To delegate ownership of the lock from the parent
 *      to the child, both the parent and child process
 *      must call the newpid() method after a successful
 *      fork() call.  This will prevent the parent from
 *      releasing the lock when unlock is called or when
 *      the lock object leaves scope.  This is also
 *      useful to allow the parent to fail on subsequent
 *      lock attempts if the child lock is still aquired.
 *  
 *  ---   FAILURE
 *  
 *  On failure, a class variable, "errstr", should be set and should
 *  contain the cause for the failure to get a lock.  Useful primarily for debugging.
 *  
 *  ---   LOCK_EXTENSION
 *  
 *  By default File::NFSLock will use a lock file extenstion of
 *  ".NFSLock".  This may be changed by passing in a custom array
 *  key 'lock_extension', using the array object instantiation
 *  syntax, to suit other purposes (such as compatibility in mail
 *  systems).
 *  
 *  ---   BUGS
 *  
 *  Notify dos@joesvolcano.net if you spot anything.
 *  
 *      ---  FIFO
 *      
 *      Locks are not necessarily obtained on a first come first serve basis.
 *      Not only does this not seem fair to new processes trying to obtain a lock,
 *      but it may cause a process starvation condition on heavily locked files.
 *      
 *      
 *      ---  DIRECTORIES
 *      
 *      Locks cannot be obtained on directory nodes, nor can a directory node be
 *      uncached with the uncache routine because hard links do not work with
 *      directory nodes.  Some other algorithm might be used to uncache a
 *      directory, but I am unaware of the best way to do it.  The biggest use I
 *      can see would be to avoid NFS cache of directory modified and last accessed
 *      timestamps.
 *  
 *  ---   INSTALL
 *  
 *  Uhm, for now, just put File_NFSLock.class.php somewhere that you can require() 
 *  it, and have fun!
 *  
 *  ---   AUTHORS
 *  
 *  Dave Buchanan (dos@joesvolcano.net) - Ported to PHP from Perl
 *  
 *  Paul T Seamons (paul@seamons.com) - Performed majority of the Perl
 *  programming with copious amounts of input from Rob Brown.
 *  
 *  Rob B Brown (bbb@cpan.org) - In addition to helping in the
 *  programming, Rob Brown provided most of the core testing to make sure
 *  implementation worked properly.  He is now the current maintainer.
 *  
 *  Also Mark Overmeer (mark@overmeer.net) - Author of Mail::Box::Locker,
 *  from which some key concepts for File::NFSLock were taken.
 *  
 *  Also Kevin Johnson (kjj@pobox.com) - Author of Mail::Folder::Maildir,
 *  from which Mark Overmeer based Mail::Box::Locker.
 *  
 *  ---   COPYRIGHT
 *  
 *    Copyright (C) 2001
 *    Paul T Seamons
 *    paul@seamons.com
 *    http://seamons.com/
 *  
 *    Copyright (C) 2002-2003,
 *    Rob B Brown
 *    bbb@cpan.org
 *  
 *    This package may be distributed under the terms of either the
 *    GNU General Public License
 *      or the
 *    Perl Artistic License
 *  
 *    All rights reserved.
 *  
 **********************************************************/
