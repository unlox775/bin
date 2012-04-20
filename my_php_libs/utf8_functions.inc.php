function utf8_charat($str, $idx) {
  $count = 0;
  $theChar = '';
  for ($i = 0; $i < strlen($str); ++$i) {
    if ((ord($str[$i]) & 0xC0) != 0x80) {
      if ( $count == $idx ) return $theChar;
      ++$count;
    }
    if ( $count == $idx ) $theChar .= substr($str, $i, 1);
  }
  return $count;
}

