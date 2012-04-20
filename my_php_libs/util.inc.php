<?php

///  Useful util
function db_quote($str) { return is_null($str) ? 'NULL' : (is_numeric($str) ? $str : "'". mysql_real_escape_string( $str ) ."'"); }
