<?php

/**
 * sort_arrays() - Sorts an array of assoc arrays by the named keys(s)
 *
 * This is a quick way to sort a bunch of arrays by named keys.
 * It can do complex sorts off multiple fields and do DESC sorts
 * as well.
 *
 * @param string $array     The source array to sort
 * @param string $criteria  a single field name, an array of fields to sort by, or an array of 2-dimensional arrays: (fieldname, ASC|DESC|bool (true = Descending))
 * @return string
 */
function &sort_arrays($array, $criteria) { $a = sort_objects($array, $criteria);  return $a; }
/**
 * sort_objects() - Sorts an array of objects by object property(s)
 *
 * This is a quick way to sort a bunch of objects by object
 * properties.  It can do complex sorts off multiple fields and
 * do DESC sorts as well.
 *
 * If the fieldname ends with '()', (e.g. "myCol()" ), then instead
 * of object properties, that method is called without parameters.
 * This is useful when the properties are private and have "getters".
 *
 * Caveat: When at all possible use database-side sorts.  This
 * sort engine is rather expensive in comparison...
 *
 * @param string $array     The source array to sort
 * @param string $criteria  a single field name, an array of fields to sort by, or an array of 2-dimensional arrays: (fieldname, ASC|DESC|bool (true = Descending))
 * @return string
 */
function &sort_objects($array, $criteria) {
    global $sort_objects_criteria;
    START_TIMER('sort_objects', SORT_PROFILE);

    if ( ! is_array($criteria) ) $criteria = array( $criteria );
    $sort_objects_criteria = array();  foreach ( $criteria as $crit ) { $sort_objects_criteria[] = is_array($crit) ? array( $crit[0], ! empty($crit[1]) ) : array( $crit, false ); }
    $first = reset($array);
    usort($array,(is_array($first) ? 'sort_arrays_sorter' : 'sort_objects_sorter') );

    END_TIMER('sort_objects', SORT_PROFILE);
    return $array;
}

function sort_objects_sorter($a,$b) {
    global $sort_objects_criteria;
    
    foreach ($sort_objects_criteria as $crit) {
		$by_method = false;
		if ( substr($crit[0], -2) == '()' ) { $col = substr($crit[0], 0, strlen($crit[0])-2);  $by_method = true; } 
        else $col = $crit[0];
		if ( $by_method )
			$cmp  = ( ($crit[1] && strtoupper($crit[1]) != 'ASC') || strtoupper($crit[1]) != 'DESC' ) ? strnatcasecmp( $b->$col(), $a->$col() ) : strnatcasecmp( $a->$col(), $b->$col() );
        else $cmp = ( ($crit[1] && strtoupper($crit[1]) != 'ASC') || strtoupper($crit[1]) != 'DESC' ) ? strnatcasecmp( $b->$col,   $a->$col   ) : strnatcasecmp( $a->$col,   $b->$col   );
		
        if ( $cmp != 0 ) return $cmp;
    }
    return 0;
}

function sort_arrays_sorter($a,$b) {
    global $sort_objects_criteria;
    
    foreach ($sort_objects_criteria as $crit) {
        $col = $crit[0];
        $cmp = ( ($crit[1] && strtoupper($crit[1]) != 'ASC') || strtoupper($crit[1]) != 'DESC' ) ? strnatcasecmp( $b[$col], $a[$col] ) : strnatcasecmp( $a[$col], $b[$col] );
        if ( $cmp != 0 ) return $cmp;
    }
    return 0;
}