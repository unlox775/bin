<?php
/**
 * dbh_bind() - Quick way to set the global DBH...
 *
 * Call this once at the top, to set the database handle for everything else to use...
 *
 * @param string $dbh      The PDO databse handle to be used by the other functions
 */
function dbh_bind( $dbh ) {
    $GLOBALS['orm_dbh'] = $dbh;
}

###  Stuff that SimpleORM Also defines...
if ( ! function_exists( 'dbh_query_bind' ) ) {

    // Debugging
    define('ORM_SQL_PROFILE', true);
    define('ORM_SQL_DEBUG', false);
    define('ORM_SQL_WRITE_DEBUG', false);

    /**
     * dbh_query_bind() - Run a read-only SQL query with bound parameters
     *
     * @param string $sql      The SQL query to run
     * @param mixed $params   this can either be called passing an array of bind params, or just by passing the bind params as args after the SQL arg
     * @return PDOStatement
     */
    function dbh_query_bind( $sql ) {
        if ( isset( $GLOBALS['orm_dbh'] ) ) $use_dbh = $GLOBALS['orm_dbh'];
        if ( ORM_SQL_PROFILE ) START_TIMER('dbh_query_bind');
        $bind_params = array_slice( func_get_args(), 1 );
        ###  Allow params passed in an array or as args
        if ( is_a( $bind_params[ count($bind_params) - 1 ], 'PDO' ) || is_a( $bind_params[ count($bind_params) - 1 ], 'PhoneyPDO' ) ) $use_dbh = array_pop($bind_params);
        if ( ! isset( $GLOBALS['orm_dbh'] ) ) $GLOBALS['orm_dbh'] = $use_dbh; # steal their DBH for global use, hehehe
        if ( count( $bind_params ) == 1 && is_array(array_shift(array_values($bind_params))) ) { $bind_params = array_shift(array_values($bind_params)); };
#    if (ORM_SQL_DEBUG) trace_dump();
        reverse_t_bools($bind_params);
        if (ORM_SQL_DEBUG) bug($sql, $bind_params);
        try { 
            $sth = $use_dbh->prepare($sql);
            $rv = $sth->execute($bind_params);
        } catch (PDOException $e) {
            trace_dump();
            $err_msg = 'There was an error running a SQL statement, ['. $sql .'] with ('. join(',',$bind_params) .'): '. $e->getMessage() .' in ' . trace_blame_line();
            if ( strlen($err_msg) > 1024 ) {
                bug($err_msg,$sql,$bind_params,$e->getMessage());
                $sql = substr($sql,0,1020 + strlen($sql) - strlen($err_msg) ).'...';
            }
            trigger_error( 'There was an error running a SQL statement, ['. $sql .'] with ('. join(',',$bind_params) .'): '. $e->getMessage() .' in ' . trace_blame_line(), E_USER_ERROR);
            return false;
        }
        if ( ORM_SQL_PROFILE ) END_TIMER('dbh_query_bind');
        return $sth;
    }
    /**
     * dbh_do_bind() - Execute a (possibly write access) SQL query with bound parameters
     *
     * @param string $sql      The SQL query to run
     * @param mixed $params   this can either be called passing an array of bind params, or just by passing the bind params as args after the SQL arg
     * @return PDOStatement
     */
    function dbh_do_bind( $sql ) {
        if ( isset( $GLOBALS['orm_dbh'] ) ) $use_dbh = $GLOBALS['orm_dbh'];
        if ( ORM_SQL_PROFILE ) START_TIMER('dbh_do_bind');
        $bind_params = array_slice( func_get_args(), 1 );
        ###  Allow params passed in an array or as args
        if ( is_a( $bind_params[ count($bind_params) - 1 ], 'PDO' ) || is_a( $bind_params[ count($bind_params) - 1 ], 'PhoneyPDO' ) ) $use_dbh = array_pop($bind_params);
        if ( ! isset( $GLOBALS['orm_dbh'] ) ) $GLOBALS['orm_dbh'] = $use_dbh; # steal their DBH for global use, hehehe
        if ( count( $bind_params ) == 1 && is_array(array_shift(array_values($bind_params))) ) { $bind_params = array_shift(array_values($bind_params)); };
    
        reverse_t_bools($bind_params);
        if (ORM_SQL_DEBUG || ORM_SQL_WRITE_DEBUG) bug($sql, $bind_params);
        try { 
            $sth = $use_dbh->prepare($sql);
            $rv = $sth->execute($bind_params);
        } catch (PDOException $e) {
            trace_dump();
            $err_msg = 'There was an error running a SQL statement, ['. $sql .'] with ('. join(',',$bind_params) .'): '. $e->getMessage() .' in ' . trace_blame_line();
            if ( strlen($err_msg) > 1024 ) {
                bug($err_msg,$sql,$bind_params,$e->getMessage());
                $sql = substr($sql,0,1020 + strlen($sql) - strlen($err_msg) ).'...';
            }
            trigger_error( 'There was an error running a SQL statement, ['. $sql .'] with ('. join(',',$bind_params) .'): '. $e->getMessage() .' in ' . trace_blame_line(), E_USER_ERROR);
            return false;
        }
        if ( ORM_SQL_PROFILE ) END_TIMER('dbh_do_bind');
        return $rv;
    }
    function reverse_t_bools(&$ary) { if (! is_array($ary)) return;  foreach($ary as $k => $v) { if ($v === true) $ary[$k] = 't';  if ($v === false) $ary[$k] = 'f'; } }

}
