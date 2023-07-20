#!/bin/bash

prev_display_count=$(system_profiler SPDisplaysDataType | grep -c "Resolution:")

while true; do
  sleep 5
  current_display_count=$(system_profiler SPDisplaysDataType | grep -c "Resolution:")
  
  if [ "$prev_display_count" -ne "$current_display_count" ]; then
    ~/bin/dock_monitors_toggle
  fi
  
  prev_display_count=$current_display_count
done
