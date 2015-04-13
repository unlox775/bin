<?php

///  Useful util
function db_quote($str) { return is_null($str) ? 'NULL' : (is_numeric($str) ? $str : "'". mysql_real_escape_string( $str ) ."'"); }

function coalesce() { foreach( func_get_args() as $v ) if (! is_null($v) ) return $v; }
function _or()      { foreach( func_get_args() as $v ) if (!   empty($v) ) return $v; }
