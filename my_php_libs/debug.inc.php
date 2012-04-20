<?php
/**
 * Debugging, Code Performance Tuning and Benchmarking
 *
 * In all PHP code this debugging library is loaded that provides
 * some useful debugging functions:
 * 
 * <ul>
 *   <li>bug() - like var_dump(), but it makes the output more visible and outputs the calling function, file and line number
 *   <li>trace_dump() - prints a concise caller trace of the function calling path to that point
 *   <li>START_TIMER(), END_TIMER(), ABORT_TIMER(), PAUSE_TIMER(), RESUME_TIMER() - Benchmarking functions described below 
 * </ul>
 * 
 * The benchmarking functions are great for profiling your code
 * to see how often certain portions of code are getting run and
 * how long each takes. For example if you're wondering why a
 * page is so slow and you suspect a certain function, you could
 * put a "START_TIMER('my_cul_func');" at the beginning of that
 * function and an "END_TIMER('my_cul_func');" at the end of the
 * function. These function calls just store a few timestamps
 * each time you call them and add up the total time spend
 * between a "START" and an "END" for each tag name which you
 * pass to it. the PAUSE and RESUME are for if you want to ignore
 * a piece in the middle of your function. On the remote case
 * that you start a timer, but something happens and you don't
 * want to end it you can call ABORT_TIMER.  In the main
 * controller.php it has a trigger to print out a report of these
 * timers at the end of the page. It looks something like this:
 *
 * <code>
 * TIMERS:
 * all_global   0.037470s       x 1     averaging 0.037470s     which is 26/s   totalling 100.00% of all_global
 * my_cul_func  0.012606s       x 11    averaging 0.001146s     which is 872/s  totalling 33.64% of all_global
 * </code>
 * 
 * This shows you that your function was called 11 times during
 * that page's execution totaling 12 thousandths of second, and
 * averaging about 1 thousandth of a second for each. Also to put
 * it in perspective (and show the biggest loser) It also shows
 * you what percent of the total page's execution time your block
 * is making up. In this case a full third of total execution
 * time is coming from this function.
 * 
 * Since some benchmarking (like SQL queries) should be
 * benchmarked frequently, instead of removing all the TIMER
 * calls when you are done, the TIMER functions all allow a
 * second argument to be passed
 * (e.g. "START_TIMER('my_cul_func',CHECKOUT_DEBUG);" used as a
 * boolean value. If the second argument is "false" then it
 * ignores the call and doesn't do any timing. This is handy for
 * defining a constant somewhere (I suggest at the top of the
 * {@link global.inc.php}) like CHECKOUT_DEBUG which is ususally "false",
 * but whenever you want to see the debugging output to see
 * what's taking so long, you can go in and change the constant
 * definition to "true" for a minute.
 * 
 * There is already a "SQL_DEBUG" constant set up like this that
 * benchmarks the dbh_query_bind() and dbh_do_bind()
 * functions. This is a common one that I recommend people turn
 * on from time to time. As an example, I turned it on after
 * completing the "Admin user page" and it was running more than
 * 80,000 SQL queries just to display that page. It all still
 * loaded just over a second, but on a loaded system this would
 * be a problem. With a few quick optimizations it was reduced to
 * only a handful of queries and took less than 2 tenths of a
 * second.
 *
 * All debugging functions check the global variable $BUG_ON
 * (boolean) before running.  The bootstrap and globally loaded
 * files detect which environment you are currently executing and
 * set $BUG_ON to 'false' unless you are in an alpha development
 * sandbox.  This is a convenient double-check to make sure
 * debugging code doeesn't accidentally show up for live
 * end-users.
 *
 *
 * @author Dave Buchanan <dave@elikirk.com>
 * @package EliKirk
 * @version $Id: debug.inc.php,v 1.5 2011/05/23 16:28:50 dave Exp $
 */

$GLOBALS['ENV_MODE'] = ( ( ! empty( $GLOBALS['ENV_MODE_BY_TRUSTED_IP'] ) )
                         ? ( ( array_search($GLOBALS['ENV_MODE_BY_TRUSTED_IP'], $_SERVER['REMOTE_ADDR']) !== false ) ? 'alpha' : 'live' )
                         : ( isset($_SERVER['ENV_MODE']) ? $_SERVER['ENV_MODE'] : 'alpha')
                         );

$GLOBALS['BUG_ON']   = ( preg_match('/^alpha/', $GLOBALS['ENV_MODE']) ) ? true : false;
if ( class_exists("Globals") ) $GLOBALS['BUG_ON'] = Globals::isDev() ? true : false;

$GLOBALS['TIMER_LOG'] = array();

// Debugging Setup
if ( $GLOBALS['BUG_ON'] ) ini_set('display_errors', true);
/**
 * trace_dump() - Print a stack trace with useful information
 *
 * This prints a trace of the calling stack (other than the call
 * to trace_dump() itself.)  For each call it prints the function
 * name and (when available) the file name and line number.  It
 * prints with one call per line (in HTML format), in an output
 * similar to that of {@link bug()}.
 *
 * Like the other functions it checks $BUG_ON.  This means stray
 * debugging accidentally rolled out live will not be printed.
 * If you don't want this check (e.g. you are trying to debug on
 * Live (shame shame!), then use the "force" version {@link
 * FORCE_TRACE_DUMP()}.
 *
 * @param array $trace   An optional {@link debug_backtrace()} output you already happened to have already because you already had called it.  Saves having to re-call it.
 */
function trace_dump($trace = null) {
    global $BUG_ON;
    if ( ! $BUG_ON) return true;

    if ( ! $trace ) {
        $trace = debug_backtrace();
        array_shift($trace);
    }
    print '<b style="display: block; color: red; margin: 0; padding: 0; text-align: left">Trace:<br/> '.
        array_reduce($trace, create_function('$str,$tr','return $str .= "&nbsp;&nbsp;&nbsp;&nbsp;". $tr["function"] ." called ". (isset($tr["file"]) ? "at ". $tr["file"] . " on line ". $tr["line"] : "internally") ."\n<br/>";')) ."</b>";
}
/**
 * FORCE_BUG() - Print a stack trace, no matter what.  To {@link trace_dump()} what {@link FORCE_BUG()} is to {@link bug()}
 */
function FORCE_TRACE_DUMP() { global $BUG_ON;  $tmp = $BUG_ON;  $BUG_ON = true;  $a = func_get_args();  call_user_func_array('trace_dump', $a);  $BUG_ON = $tmp; }
function trace_blame_line($skip_funcs = array(), $level = 1) {
    $trace = debug_backtrace();
    while( isset($trace[$level + 1]) && ( in_array($trace[$level + 1]['function'], $skip_funcs ) || ! isset($trace[$level]['file']) ) ) $level++;
    return '<b>'. (isset($trace[$level + 1]) ? $trace[$level + 1]['function'].'()' : 'main') . '</b> in <b>'. $trace[$level]['file'] . '</b> on line <b>'. $trace[$level]['line'] ."</b><br/>\n";
}
/**
 * bug() - Debug one or more values
 *
 * Prints a format similar to var_dump, but includes the
 * referring file and line number.  This is often Very useful
 * when you get to the end of debuggiung a very difficult problem
 * and have added debugging calls to several files.  You just
 * pull up all the files and line numbers in the output to remove
 * each debug value.  It also formats the text in a fixed width
 * style, aligned left, in an easily visible red.
 *
 * It prints an HTML content type header if headers haven't
 * already been sent.
 *
 * Like the other functions it checks $BUG_ON.  This means stray
 * debugging accidentally rolled out live will not be printed.
 * If you don't want this check (e.g. you are trying to debug on
 * Live (shame shame!), then use the "force" version {@link
 * FORCE_BUG()}.
 *
 * @param mixed $stuff_to_debug  This can be one or multiple args
 */
function bug() {
    global $BUG_ON;
    if ( ! $BUG_ON) return true;

    if ( ! headers_sent() ) {
        header('Content-type: text/html');
    }
    $tr = debug_backtrace();
    $level = 0;
    while( isset($tr[$level + 1]) && ( in_array($tr[$level + 1]['function'], array('FORCE_BUG') ) || ! isset($tr[$level]['file']) ) ) $level++;
    print '<br/><b style="display: block; color: red; margin: 0; padding: 0; text-align: left">File: '. $tr[$level]['file'] .", line ". $tr[$level]['line'] ."</b>\n";
    print '<xmp style="color: red; margin: 0; padding: 0; text-align:left">';
    var_export( func_get_args() );
    print "</xmp>";
}
/**
 * FORCE_BUG() - Debug one or more values, and ignore if $BUG_ON may be false
 *
 * Debugs regardless of environment.  Use with caution.
 *
 * @param mixed $stuff_to_debug  This can be one or multiple args
 * @see bug()
 */
function FORCE_BUG() { global $BUG_ON;  $tmp = $BUG_ON;  $BUG_ON = true;  $a = func_get_args();  call_user_func_array('bug', $a);  $BUG_ON = $tmp; }


#########################
###  Error System Hook

if ( defined('ERROR_LIB_BASE') ) {
    require_once(ERROR_LIB_BASE .'/debug.inc.php');
}

#########################
###  Benchmarking / Timer functions

$BUG_TIME_I = 0;
$BUG_TIMERS = array();  $BUG_TIMESEQ = array();  $BUG_TIMEX = array();

/**
 * reset_timers() - Reset benchmarking values, counts and data
 */
function reset_timers() {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX;
    if ( ! $BUG_ON ) return true;
    $BUG_TIMERS = array();  $BUG_TIMESEQ = array();  $BUG_TIMEX = array();
    START_TIMER('all_global');
}

/**
 * START_TIMER() - Mark a start time for a benchmarking timer
 * @param mixed $tag        This is a name you choose for this benchmarking tag.  It will be printed back out when {@link report_timers()} is called along with number of times called and elapsed time.
 * @param boolean $THIS_ON    If a false value is passed, then the call will be ignored.  A true value does not override a false $BUG_ON value.  See global debug constants note in {@link debug.inc.php main docs}.
 */
function START_TIMER($tag, $THIS_ON = true) {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ( ! $BUG_ON || ! $THIS_ON ) && ! isset($TIMER_LOG[$tag]) ) return true;
    if ( isset($BUG_TIMERS[$tag]) && is_array($BUG_TIMERS[$tag]) ) return false;
    $BUG_TIMERS[$tag] = array((isset($BUG_TIMERS[$tag]) ? $BUG_TIMERS[$tag] : 0), microtime(true));
    if ( ! isset($BUG_TIMESEQ[$tag]) ) $BUG_TIMESEQ[$tag] = $BUG_TIME_I++;
    if ( ! isset($BUG_TIMEX[$tag])   ) $BUG_TIMEX[$tag] = array(0,0);
    $BUG_TIMEX[$tag][0]++;
}
/**
 * END_TIMER() - End a benchmark timer and record the elapsed time and instance count
 * @param mixed $tag        This is a name you choose for this benchmarking tag.  It will be printed back out when {@link report_timers()} is called along with number of times called and elapsed time.
 * @param boolean $THIS_ON    If a false value is passed, then the call will be ignored.  A true value does not override a false $BUG_ON value.  See global debug constants note in {@link debug.inc.php main docs}.
 */
function END_TIMER($tag, $THIS_ON = true) {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ( ! $BUG_ON || ! $THIS_ON ) && ! isset($TIMER_LOG[$tag]) ) return true;
    if ( ! isset($BUG_TIMERS[$tag]) || ! is_array($BUG_TIMERS[$tag]) ) return false;
    $BUG_TIMERS[$tag] = $BUG_TIMERS[$tag][0] + (microtime(true) - $BUG_TIMERS[$tag][1]);
    $BUG_TIMEX[$tag][1]++;
}
/**
 * ABORT_TIMER() - Abort a timer, and reset the timer count back to what it was
 * @param mixed $tag        This is a name you choose for this benchmarking tag.  It will be printed back out when {@link report_timers()} is called along with number of times called and elapsed time.
 * @param boolean $THIS_ON    If a false value is passed, then the call will be ignored.  A true value does not override a false $BUG_ON value.  See global debug constants note in {@link debug.inc.php main docs}.
 */
function ABORT_TIMER($tag, $THIS_ON = true) {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ( ! $BUG_ON || ! $THIS_ON ) && ! isset($TIMER_LOG[$tag]) ) return true;
    if ( ! isset($BUG_TIMERS[$tag]) || ! is_array($BUG_TIMERS[$tag]) ) return false;
    $BUG_TIMERS[$tag] = $BUG_TIMERS[$tag][0];
    $BUG_TIMEX[$tag][0]--;
    ###  If this is the first time, then delete the keys
    if ( $BUG_TIMEX[$tag][0] == 0 ) {
        unset( $BUG_TIMERS[$tag] );
        unset( $BUG_TIMEX[$tag] );
        unset( $BUG_TIMESEQ[$tag] );
    }
}

/**
 * PAUSE_TIMER() - Pause a currently running benchmarking timer (without incrementing the instance count)
 *
 * This is useful when you are timing a sequence of code, but one
 * of the calls or processes in the sequence you don't want to
 * consider in the timer, usually because it's a longer processes
 * or variable and would make your benchmarking data less useful.
 *
 * Here's an example if it's usage:
 *
 * <code>
 * function crunch_number($a,$b,$c) {
 *     START_TIMER('crunch_number');
 *
 *     ###  First Phase
 *     foreach ( range($c,1000) as $i ) {
 *         $a = sqrt((($a+$b) % $c) + $i) * ($a *c) / (11 & $b);
 *     }
 *     PAUSE_TIMER('crunch_number');
 *     log_in_database('Half-way done crunching',$a,$b,$c);
 *     RESUME_TIMER('crunch_number');
 *     
 *     ###  Second Phase
 *     foreach ( range($b,1000) as $i ) {
 *         $b = sqrt((($b+$a) % $c) + $i) * ($b *c) / (11 & $a);
 *     }
 *     
 *     END_TIMER 'crunch_number';
 *     return(array($a,$b,$c));
 * }
 * </code>
 * @param mixed $tag        This is a name you choose for this benchmarking tag.  It will be printed back out when {@link report_timers()} is called along with number of times called and elapsed time.
 * @param boolean $THIS_ON    If a false value is passed, then the call will be ignored.  A true value does not override a false $BUG_ON value.  See global debug constants note in {@link debug.inc.php main docs}.
 */
function PAUSE_TIMER($tag, $THIS_ON = true) {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ( ! $BUG_ON || ! $THIS_ON ) && ! isset($TIMER_LOG[$tag]) ) return true;
    if ( ! isset($BUG_TIMERS[$tag]) || ! is_array($BUG_TIMERS[$tag]) ) return false;
    $BUG_TIMERS[$tag] = $BUG_TIMERS[$tag][0] + (microtime(true) - $BUG_TIMERS[$tag][1]);
}
/**
 * RESUME_TIMER() - Resumes a previously-paused benchmarking timer
 *
 * @see PAUSE_TIMER()
 * @param mixed $tag        This is a name you choose for this benchmarking tag.  It will be printed back out when {@link report_timers()} is called along with number of times called and elapsed time.
 * @param boolean $THIS_ON    If a false value is passed, then the call will be ignored.  A true value does not override a false $BUG_ON value.  See global debug constants note in {@link debug.inc.php main docs}.
 */
function RESUME_TIMER($tag, $THIS_ON = true) {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ( ! $BUG_ON || ! $THIS_ON ) && ! isset($TIMER_LOG[$tag]) ) return true;
    if ( isset($BUG_TIMERS[$tag]) && is_array($BUG_TIMERS[$tag]) ) return false;
    $BUG_TIMERS[$tag] = array((isset($BUG_TIMERS[$tag]) ? $BUG_TIMERS[$tag] : 0), microtime(true));
}

/**
 * report_timers() - Print a report of all timers
 *
 * See the {@link debug.inc.php file-level docs} for an example if this output.
 */
function report_timers() {
    global $BUG_ON, $BUG_TIME_I, $BUG_TIMERS, $BUG_TIMESEQ, $BUG_TIMEX, $TIMER_LOG;
    if ( ! $BUG_ON && count($TIMER_LOG) == 0) return true;

    if ( ! empty( $BUG_TIMERS )
         && ( count($BUG_TIMERS) != 1
              || ! isset($BUG_TIMERS['all_global'])
             )
        ) {
        END_TIMER('all_global');

        ###  Print out logs if requested
        if ( count($TIMER_LOG) ) {
            foreach ( $TIMER_LOG as $key => $ary ) { 
                if ( is_array($ary) ) list($log, $format) = $ary;
                else { $log = $ary;  $format = 'default'; }

                $the_time = is_array($BUG_TIMERS[$key]) ? $BUG_TIMERS[$key][0] : $BUG_TIMERS[$key];

                ###  Formats (we ignore errors writing, too bad if they didn't do their homework)
                if ( $format == 'csv_w_uri' ) file_put_contents($log, '"'. date("Y-m-d H:i:s", time()) .'",'. sprintf("%.6f", $the_time) .",". $BUG_TIMEX[$key][0] .',"'. $_SERVER['REQUEST_URI'] .'"'."\n", FILE_APPEND);
                else                          file_put_contents($log,                          time()   .",". sprintf("%.6f", $the_time) .",". $BUG_TIMEX[$key][0] ."\n", FILE_APPEND);
            }
        }

        ###  Print a Table report of the timers
        if ( $BUG_ON ) {
            $nl = isset( $_SERVER['REQUEST_METHOD'] ) ? "</td></tr><tr><td>\n" : "\n";
            $sp = isset( $_SERVER['REQUEST_METHOD'] ) ? "&nbsp;" : " ";
            $tmp_ary = array_keys( $BUG_TIMERS );
            usort($tmp_ary,create_function('$a,$b','global $BUG_TIMESEQ;  return( ($BUG_TIMESEQ[$a] == $BUG_TIMESEQ[$b]) ? 0 : ($BUG_TIMESEQ[$a] < $BUG_TIMESEQ[$b]) ? -1 : 1);'));
            $report_ary = array();
            foreach ( $tmp_ary as $_ ) {
                $the_time = is_array($BUG_TIMERS[$_]) ? $BUG_TIMERS[$_][0] : $BUG_TIMERS[$_];
                $report_ary[] =
                    array( $_,
                           ( sprintf("%.6f",$the_time) ."s" ),
                           ( "x$sp". $BUG_TIMEX[$_][0]
                             . ( ($BUG_TIMEX[$_][1] != $BUG_TIMEX[$_][0]) ? ("$sp/$sp". $BUG_TIMEX[$_][1]) : '' ) . "$sp$sp"
                               ),
                           ( "averaging$sp" . sprintf("%.6f", ($the_time / $BUG_TIMEX[$_][0])) ."s" ),
                           ( "which". $sp ."is$sp" . sprintf("%.6d", (1 / ($the_time / $BUG_TIMEX[$_][0]))) . "/s" ),
                           ( "totalling$sp"
                             . ($BUG_TIMERS['all_global'] ? sprintf("%.2f",($the_time / $BUG_TIMERS['all_global']) * 100) : '' ) . "%$sp"."of$sp"."all_global"
                               )
                        );
            }
            
            ###  HTML table output
            if ( $_SERVER['REQUEST_METHOD'] ) {
                print '<br/><div style="display: block; color: red; margin: 0; padding: 0; text-align: left"><table width="60%"><tr><td>';
                print "TIMERS:$nl";
                foreach ( $report_ary as $line ) {
                    print join("</td><td>\n", $line). $nl;
                }
                print "</td></tr></table></div>";
            }
            ###  Command-line output
            else {
                $f_widths = array( 23, 11, 10, 20, 17, false );
                foreach ( $report_ary as $line ) {
                    $join_ary = array(); foreach ($line as $i => $str) { $join_ary[] = bug_fill_width($f_widths[$i]); }
                    print join(" ", $join_ary);
                }
            }
        }
    }
}

function bug_fill_width($str,$w) {
    if ( $w === false ) return $str;
    while(strlen($str) < $w) $str .= ' ';
}

reset_timers();
