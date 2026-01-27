#!/usr/bin/env python3

import re
import sys
import fnmatch
from datetime import datetime, timedelta
from dateutil import parser as date_parser
from dateutil import tz

def parse_size(size_str):
    """
    Parse a size string like "2GB", "5MB", "25K", "35TB".
    Supports common size units.
    
    Args:
        size_str: String like "2GB", "5MB", "25K", "35TB", "2.5GB"
    
    Returns:
        Integer representing size in bytes
    
    Raises:
        ValueError: If the size string cannot be parsed
    """
    # Normalize: remove spaces, convert to uppercase for unit matching
    normalized = size_str.strip().upper()
    
    # Match pattern: number (possibly decimal) followed by unit (optional)
    pattern = r'^(\d+\.?\d*)\s*([KMGT]?B?)$'
    match = re.match(pattern, normalized)
    
    if not match:
        raise ValueError(f"Invalid size format: {size_str}. Expected format: '2GB', '5MB', '25K', '35TB', etc.")
    
    value = float(match.group(1))
    unit = match.group(2).upper()
    
    # Map units to bytes
    unit_map = {
        'B': 1,
        'KB': 1024,
        'K': 1024,
        'MB': 1024 * 1024,
        'M': 1024 * 1024,
        'GB': 1024 * 1024 * 1024,
        'G': 1024 * 1024 * 1024,
        'TB': 1024 * 1024 * 1024 * 1024,
        'T': 1024 * 1024 * 1024 * 1024,
        '': 1,  # Default to bytes if no unit
    }
    
    if unit not in unit_map:
        raise ValueError(f"Unknown size unit: {unit}. Supported units: B, K/KB, M/MB, G/GB, T/TB")
    
    return int(value * unit_map[unit])


def parse_size(size_str):
    """
    Parse a size string like "2GB", "5MB", "25K", "35TB".
    Supports spaces or no spaces between number and unit.
    
    Args:
        size_str: String like "2GB", "5 MB", "25K", "35 TB", "1.5GB"
    
    Returns:
        Integer representing the size in bytes
    
    Raises:
        ValueError: If the size string cannot be parsed
    """
    # Normalize: remove spaces, make uppercase for consistency
    normalized = size_str.replace(' ', '').strip().upper()
    
    # Match pattern: number (possibly decimal) followed by size unit
    pattern = r'^(\d+\.?\d*)([KMGT]?B?)$'
    match = re.match(pattern, normalized, re.IGNORECASE)
    
    if not match:
        raise ValueError(f"Invalid size format: {size_str}. Expected format: '2GB', '5MB', '25K', '35TB', etc.")
    
    value = float(match.group(1))
    unit = match.group(2).upper()
    
    # Map units to bytes
    # Default to bytes if no unit specified
    if not unit or unit == 'B':
        multiplier = 1
    elif unit == 'K' or unit == 'KB':
        multiplier = 1024
    elif unit == 'M' or unit == 'MB':
        multiplier = 1024 * 1024
    elif unit == 'G' or unit == 'GB':
        multiplier = 1024 * 1024 * 1024
    elif unit == 'T' or unit == 'TB':
        multiplier = 1024 * 1024 * 1024 * 1024
    else:
        raise ValueError(f"Unknown size unit: {unit}. Supported units: B, K/KB, M/MB, G/GB, T/TB")
    
    return int(value * multiplier)


def parse_time_range(time_range_str):
    """
    Parse a time range string like "5 hours", "3 days", "2.5 days", "3 months".
    Supports spaces or dashes as separators.
    
    Args:
        time_range_str: String like "5 hours", "3-days", "2.5 days", "3 months"
    
    Returns:
        timedelta object representing the time range
    
    Raises:
        ValueError: If the time range string cannot be parsed
    """
    # Normalize: replace dashes with spaces, then split
    normalized = time_range_str.replace('-', ' ').strip()
    
    # Match pattern: number (possibly decimal) followed by time unit
    pattern = r'^(\d+\.?\d*)\s+(\w+)$'
    match = re.match(pattern, normalized, re.IGNORECASE)
    
    if not match:
        raise ValueError(f"Invalid time range format: {time_range_str}. Expected format: '5 hours', '3 days', '2.5 days', etc.")
    
    value = float(match.group(1))
    unit = match.group(2).lower()
    
    # Map units to timedelta
    unit_map = {
        'second': timedelta(seconds=1),
        'seconds': timedelta(seconds=1),
        'sec': timedelta(seconds=1),
        'secs': timedelta(seconds=1),
        's': timedelta(seconds=1),
        'minute': timedelta(minutes=1),
        'minutes': timedelta(minutes=1),
        'min': timedelta(minutes=1),
        'mins': timedelta(minutes=1),
        'm': timedelta(minutes=1),
        'hour': timedelta(hours=1),
        'hours': timedelta(hours=1),
        'hr': timedelta(hours=1),
        'hrs': timedelta(hours=1),
        'h': timedelta(hours=1),
        'day': timedelta(days=1),
        'days': timedelta(days=1),
        'd': timedelta(days=1),
        'week': timedelta(weeks=1),
        'weeks': timedelta(weeks=1),
        'w': timedelta(weeks=1),
        'month': timedelta(days=30),  # Approximate
        'months': timedelta(days=30),  # Approximate
        'mon': timedelta(days=30),
        'mons': timedelta(days=30),
        'year': timedelta(days=365),  # Approximate
        'years': timedelta(days=365),  # Approximate
        'yr': timedelta(days=365),
        'yrs': timedelta(days=365),
        'y': timedelta(days=365),
    }
    
    if unit not in unit_map:
        raise ValueError(f"Unknown time unit: {unit}. Supported units: seconds, minutes, hours, days, weeks, months, years")
    
    return value * unit_map[unit]


def parse_newer_than_date(date_str):
    """
    Parse a date string in format YYYY-MM-DD or YYYY-MM-DD-HH-MM-SS.
    Optionally supports timezone in ISO format.
    
    Args:
        date_str: Date string like "2025-12-01" or "2025-12-01-14-30-00" or "2025-12-01T14:30:00Z"
    
    Returns:
        datetime object (timezone-aware if timezone provided, otherwise naive)
    
    Raises:
        ValueError: If the date string cannot be parsed
    """
    # Try ISO format first (handles timezone)
    try:
        return date_parser.isoparse(date_str)
    except (ValueError, TypeError):
        pass
    
    # Try custom format: YYYY-MM-DD-HH-MM-SS
    pattern1 = r'^(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})$'
    match1 = re.match(pattern1, date_str)
    if match1:
        year, month, day, hour, minute, second = map(int, match1.groups())
        return datetime(year, month, day, hour, minute, second)
    
    # Try format: YYYY-MM-DD
    pattern2 = r'^(\d{4})-(\d{2})-(\d{2})$'
    match2 = re.match(pattern2, date_str)
    if match2:
        year, month, day = map(int, match2.groups())
        return datetime(year, month, day)
    
    # Try dateutil parser as fallback
    try:
        return date_parser.parse(date_str)
    except (ValueError, TypeError) as e:
        raise ValueError(f"Invalid date format: {date_str}. Expected YYYY-MM-DD or YYYY-MM-DD-HH-MM-SS or ISO format") from e


def filter_objects_by_time(objects, time_range=None, newer_than=None):
    """
    Filter S3 objects by their LastModified timestamp.
    
    Args:
        objects: List of S3 object dicts (must have 'LastModified' key)
        time_range: Optional timedelta for time range filter
        newer_than: Optional datetime for start time filter
    
    Returns:
        Filtered list of objects
    """
    if not objects:
        return objects
    
    # Check if objects have timezone-aware timestamps (S3 LastModified is always UTC)
    sample_obj = objects[0]
    sample_last_modified = sample_obj.get('LastModified')
    has_tz = sample_last_modified.tzinfo is not None if sample_last_modified else False
    
    # Determine start and end times
    if newer_than:
        # If newer_than is naive but objects are timezone-aware, make it UTC
        if newer_than.tzinfo is None and has_tz:
            newer_than = newer_than.replace(tzinfo=tz.UTC)
        # If newer_than is timezone-aware but objects are naive, make it naive
        elif newer_than.tzinfo and not has_tz:
            newer_than = newer_than.replace(tzinfo=None)
        start_time = newer_than
        if time_range:
            end_time = start_time + time_range
        else:
            # Use current time as end
            end_time = datetime.now(tz.UTC) if has_tz else datetime.now()
    elif time_range:
        # Use most recent time range
        end_time = datetime.now(tz.UTC) if has_tz else datetime.now()
        start_time = end_time - time_range
    else:
        # No filtering
        return objects
    
    # Ensure start_time and end_time match the timezone of the objects
    if has_tz and start_time.tzinfo is None:
        start_time = start_time.replace(tzinfo=tz.UTC)
        end_time = end_time.replace(tzinfo=tz.UTC)
    elif not has_tz and start_time.tzinfo:
        start_time = start_time.replace(tzinfo=None)
        end_time = end_time.replace(tzinfo=None)
    
    filtered = []
    for obj in objects:
        last_modified = obj.get('LastModified')
        if not last_modified:
            continue
        
        if start_time <= last_modified <= end_time:
            filtered.append(obj)
    
    return filtered


def sanitize_for_filename(text, max_length=15):
    """
    Sanitize text for use in filenames.
    Replaces special characters with underscores and collapses multiple underscores.
    
    Args:
        text: String to sanitize
        max_length: Maximum length of the sanitized string
    
    Returns:
        Sanitized string
    """
    # Replace special characters with underscores
    sanitized = re.sub(r'[^a-zA-Z0-9]', '_', text)
    # Collapse multiple underscores to single underscore
    sanitized = re.sub(r'_+', '_', sanitized)
    # Remove leading/trailing underscores
    sanitized = sanitized.strip('_')
    # Truncate to max_length
    if len(sanitized) > max_length:
        sanitized = sanitized[:max_length]
    return sanitized


def generate_zip_name(bucket_name, object_keys, time_range=None, newer_than=None, max_key_length=15):
    """
    Generate an automatic ZIP filename based on bucket, object keys, and time filters.
    
    Args:
        bucket_name: S3 bucket name
        object_keys: List of object key strings (or patterns)
        time_range: Optional timedelta for time range
        newer_than: Optional datetime for start time
        max_key_length: Maximum length for object key part in filename
    
    Returns:
        Generated ZIP filename string
    """
    parts = []
    
    # Start with date
    if newer_than:
        date_str = newer_than.strftime('%Y-%m-%d')
    else:
        date_str = datetime.now().strftime('%Y-%m-%d')
    parts.append(date_str)
    
    # Add time range if provided
    if time_range:
        # Convert timedelta to human-readable string
        total_seconds = time_range.total_seconds()
        if total_seconds < 60:
            range_str = f"{int(total_seconds)}s"
        elif total_seconds < 3600:
            range_str = f"{int(total_seconds/60)}m"
        elif total_seconds < 86400:
            range_str = f"{int(total_seconds/3600)}h"
        elif total_seconds < 2592000:  # ~30 days
            range_str = f"{int(total_seconds/86400)}d"
        elif total_seconds < 31536000:  # ~365 days
            range_str = f"{int(total_seconds/2592000)}mo"
        else:
            range_str = f"{int(total_seconds/31536000)}y"
        parts.append(range_str)
    
    # Add bucket name (sanitized)
    parts.append(sanitize_for_filename(bucket_name, max_key_length))
    
    # Add object keys (sanitized, truncated)
    if object_keys:
        if len(object_keys) == 1:
            key_part = sanitize_for_filename(object_keys[0], max_key_length)
            if key_part:
                parts.append(key_part)
        else:
            # Multiple keys - use first one and add ETC
            key_part = sanitize_for_filename(object_keys[0], max_key_length - 4)  # Reserve space for _ETC
            if key_part:
                parts.append(f"{key_part}_ETC")
    
    filename = '_'.join(parts) + '.zip'
    
    # Ensure filename isn't too long (max 255 chars for most filesystems)
    if len(filename) > 200:
        # Truncate middle parts if needed
        bucket_part = parts[-2] if len(parts) > 2 else ''
        key_part = parts[-1] if len(parts) > 1 else ''
        # Keep date and range, truncate bucket and key
        if len(parts) >= 2:
            filename = '_'.join(parts[:2]) + '_' + sanitize_for_filename(bucket_part, 20) + '_' + sanitize_for_filename(key_part, 20) + '.zip'
        else:
            filename = '_'.join(parts) + '.zip'
        if len(filename) > 200:
            filename = filename[:200] + '.zip'
    
    return filename


def convert_glob_to_regex(pattern, case_insensitive=False):
    """
    Convert a glob pattern (including ** for recursive matching) to a regex pattern.
    Handles ** for recursive directory matching.
    
    Args:
        pattern: Glob pattern string (may contain *, ?, **, [])
        case_insensitive: If True, make the regex case-insensitive
    
    Returns:
        Compiled regex pattern
    """
    import re
    
    # Convert ** to regex that matches any number of directories
    # ** matches zero or more directories
    # We need to handle **/ and /** and ** in the middle
    
    # First, escape special regex characters except *, ?, [, ]
    regex = ''
    i = 0
    while i < len(pattern):
        if pattern[i:i+2] == '**':
            # Handle ** - matches zero or more directories
            # Check what comes before and after
            if i == 0 or pattern[i-1] == '/':
                # ** at start or after /
                if i+2 < len(pattern) and pattern[i+2] == '/':
                    # **/ - matches zero or more directories followed by /
                    # Allow zero directories (so file.png matches when pattern is dir/**/*.png)
                    regex += r'(?:[^/]+/)*'
                    i += 3
                else:
                    # ** at end or **something - matches zero or more directories and files
                    regex += r'.*'
                    i += 2
            else:
                # ** in middle (not after /)
                regex += r'.*'
                i += 2
        elif pattern[i] == '*':
            # Single * - matches any characters except /
            regex += r'[^/]*'
            i += 1
        elif pattern[i] == '?':
            # ? - matches any single character except /
            regex += r'[^/]'
            i += 1
        elif pattern[i] == '[':
            # Character class - pass through as-is
            j = i + 1
            if j < len(pattern) and pattern[j] == '!':
                j += 1
            if j < len(pattern) and pattern[j] == ']':
                j += 1
            while j < len(pattern) and pattern[j] != ']':
                j += 1
            if j < len(pattern):
                regex += pattern[i:j+1]
                i = j + 1
            else:
                # Unclosed bracket, treat as literal
                regex += re.escape(pattern[i])
                i += 1
        elif pattern[i] == '/':
            # Directory separator - literal
            regex += '/'
            i += 1
        else:
            # Literal character - escape if needed
            regex += re.escape(pattern[i])
            i += 1
    
    # Anchor to start and end
    regex = '^' + regex + '$'
    
    # Compile with case-insensitive flag if needed
    flags = re.IGNORECASE if case_insensitive else 0
    return re.compile(regex, flags)


def expand_glob_patterns(s3, bucket_name, object_keys, time_range=None, newer_than=None, verbose=True, case_insensitive=False):
    """
    Expand glob patterns in object keys to actual S3 object keys.
    Optionally filter by time range and newer_than date.
    
    CRITICAL: Time filtering is applied DURING listing to avoid scanning billions of files.
    Only objects within the time window are checked against glob patterns.
    
    Args:
        s3: boto3 S3 client
        bucket_name: S3 bucket name
        object_keys: List of object key strings (may contain glob patterns with *, ?, or ** for recursive matching)
        case_insensitive: If True, pattern matching is case-insensitive (default: False)
        time_range: Optional timedelta for time range filter
        newer_than: Optional datetime for start time filter
        verbose: If True, print progress information (default: True)
    
    Returns:
        List of S3 object dicts (with 'Key', 'LastModified', 'Size', etc.)
        These are full object dicts to enable time filtering.
    """
    import botocore.exceptions
    
    # Calculate time window FIRST (before any listing)
    start_time = None
    end_time = None
    has_time_filter = False
    
    if time_range or newer_than:
        has_time_filter = True
        # Determine time window using same logic as filter_objects_by_time
        # Check what timezone S3 objects use (they're always UTC)
        sample_utc = datetime.now(tz.UTC)
        has_tz = True  # S3 LastModified is always timezone-aware UTC
        
        if newer_than:
            # If newer_than is naive, make it UTC
            if newer_than.tzinfo is None:
                newer_than = newer_than.replace(tzinfo=tz.UTC)
            else:
                # Convert to UTC if needed
                newer_than = newer_than.astimezone(tz.UTC)
            start_time = newer_than
            if time_range:
                end_time = start_time + time_range
            else:
                end_time = datetime.now(tz.UTC)
        elif time_range:
            # Use most recent time range
            end_time = datetime.now(tz.UTC)
            start_time = end_time - time_range
        
        # Ensure both are UTC
        if start_time.tzinfo is None:
            start_time = start_time.replace(tzinfo=tz.UTC)
        if end_time.tzinfo is None:
            end_time = end_time.replace(tzinfo=tz.UTC)
    
    expanded_objects = []  # Store full objects to enable time filtering
    
    # Separate glob patterns from exact keys
    glob_patterns = []
    exact_keys = []
    
    for key in object_keys:
        if '*' in key or '?' in key or '**' in key:
            glob_patterns.append(key)
        else:
            exact_keys.append(key)
    
    # Group glob patterns by prefix to avoid duplicate scans
    # Patterns with the same prefix will be scanned once and all patterns applied
    prefix_groups = {}
    for pattern in glob_patterns:
        # Extract prefix (everything before first wildcard)
        # Handle ** specially - prefix is everything before **
        if '**' in pattern:
            prefix = pattern.split('**')[0]
        else:
            prefix = pattern.split('*')[0].split('?')[0]
        
        # Remove trailing / from prefix if present (for consistency)
        prefix = prefix.rstrip('/')
        if not prefix:
            prefix = ""
        
        if prefix not in prefix_groups:
            prefix_groups[prefix] = []
        prefix_groups[prefix].append(pattern)
    
    # Process each prefix group (scan once, apply all patterns)
    for prefix, patterns in prefix_groups.items():
        if verbose:
            if len(patterns) > 1:
                print(f"Expanding {len(patterns)} glob patterns with shared prefix '{prefix}':")
                for p in patterns:
                    print(f"  - {p}")
            else:
                print(f"Expanding glob pattern: {patterns[0]}")
            
            # Show strategy - prioritize time filtering if available
            if has_time_filter:
                if prefix:
                    print(f"  Strategy: Listing files in prefix '{prefix}' (S3 API), applying TIME FILTER FIRST (critical for large buckets), then {len(patterns)} glob pattern(s)")
                else:
                    print(f"  Strategy: Listing all files (S3 API), applying TIME FILTER FIRST (critical for large buckets), then {len(patterns)} glob pattern(s)")
                print(f"  Time window: {start_time.isoformat()} to {end_time.isoformat()} (UTC)")
            else:
                if prefix:
                    print(f"  Strategy: Listing all files in prefix '{prefix}' (S3 API filter), then applying {len(patterns)} glob pattern(s) (client-side filter)")
                else:
                    print(f"  Strategy: Listing all files in bucket (S3 API), then applying {len(patterns)} glob pattern(s) (client-side filter)")
            print(f"  S3 API parameters: Bucket={bucket_name}, Prefix={prefix if prefix else '(none)'}")
        
        # Compile regex patterns for all patterns in this group
        compiled_patterns = []
        for pattern in patterns:
            # Check if pattern needs ** handling (use regex) or can use fnmatch
            if '**' in pattern:
                compiled_patterns.append(('regex', convert_glob_to_regex(pattern, case_insensitive)))
            else:
                # Use fnmatch for simple patterns (faster)
                if case_insensitive:
                    compiled_patterns.append(('regex', convert_glob_to_regex(pattern, case_insensitive)))
                else:
                    compiled_patterns.append(('fnmatch', pattern))
        
        # List objects with the prefix (scan once for all patterns)
        paginator = s3.get_paginator('list_objects_v2')
        page_iterator = paginator.paginate(Bucket=bucket_name, Prefix=prefix if prefix else None)
        
        matching_objects = []
        total_scanned = 0
        total_time_filtered = 0  # Count objects filtered out by time
        page_num = 0
        last_match_count = 0  # Track last match count for progress updates
        
        try:
            for page in page_iterator:
                page_num += 1
                try:
                    page_contents = page.get('Contents', [])
                except Exception as e:
                    # Check if it's a token expiration error
                    error_msg = str(e).lower()
                    if 'expired' in error_msg or 'token' in error_msg or 'authentication' in error_msg:
                        if verbose:
                            print(f"\n  Error: Authentication token expired during listing (after {total_scanned} files scanned).")
                            print(f"  This can happen during very long-running operations.")
                            print(f"  Please refresh your SSO token and re-run the command.")
                        raise
                    else:
                        raise
                
                for obj in page_contents:
                    total_scanned += 1
                    obj_key = obj['Key']
                    last_modified = obj.get('LastModified')
                    
                    # Apply ALL filters together - object must pass BOTH time filter AND at least one glob pattern
                    # Time filter is checked first for efficiency (saves glob pattern matching)
                    passes_time_filter = True
                    if has_time_filter and last_modified:
                        # Check if object is within time window
                        if not (start_time <= last_modified <= end_time):
                            passes_time_filter = False
                            total_time_filtered += 1
                    
                    # Only check glob patterns if object passed time filter (or no time filter)
                    passes_glob_filter = False
                    if passes_time_filter:
                        # Check against all patterns in this group - match if ANY pattern matches
                        for pattern_type, pattern in compiled_patterns:
                            if pattern_type == 'regex':
                                if pattern.search(obj_key):
                                    passes_glob_filter = True
                                    break
                            else:  # fnmatch
                                if fnmatch.fnmatch(obj_key, pattern):
                                    passes_glob_filter = True
                                    break
                    
                    # Only add to matching_objects if object passed ALL filters
                    # matching_objects contains ONLY objects that passed both time filter AND at least one glob pattern
                    if passes_time_filter and passes_glob_filter:
                        matching_objects.append(obj)
                    
                    # Show progress with line overwriting (update frequently)
                    # Update every 100 files scanned, or every time we find a match, or every 1000 time-filtered
                    should_update = False
                    if verbose:
                        if total_scanned % 100 == 0:  # Every 100 files
                            should_update = True
                        elif len(matching_objects) != last_match_count:  # Every match (object that passed ALL filters)
                            should_update = True
                            last_match_count = len(matching_objects)
                        elif total_time_filtered > 0 and total_time_filtered % 1000 == 0:  # Every 1000 filtered
                            should_update = True
                    
                    if should_update:
                        matching_count = len(matching_objects)
                        progress_line = f"\r  Progress: Page {page_num}, scanned {total_scanned} files, {total_time_filtered} filtered by time, {matching_count} matching objects found (passed ALL filters)..."
                        sys.stdout.write(progress_line)
                        sys.stdout.flush()
            
            # Clear progress line and show final result
            if verbose:
                sys.stdout.write('\r' + ' ' * 100 + '\r')  # Clear line (wider clear)
                if has_time_filter:
                    print(f"  Completed: Scanned {total_scanned} files across {page_num} pages")
                    print(f"  Results: {total_time_filtered} filtered out by time, {len(matching_objects)} matching objects (passed BOTH time filter AND glob pattern)")
                else:
                    print(f"  Completed: Scanned {total_scanned} files across {page_num} pages, found {len(matching_objects)} matching objects (passed glob pattern)")
            
        except KeyboardInterrupt:
            if verbose:
                sys.stdout.write('\r' + ' ' * 100 + '\r')  # Clear progress line
                print(f"\n  Interrupted: Scanned {total_scanned} files across {page_num} pages")
                if has_time_filter:
                    print(f"  Results so far: {total_time_filtered} filtered by time, {len(matching_objects)} matching objects found (passed BOTH time filter AND glob pattern)")
                else:
                    print(f"  Results so far: {len(matching_objects)} matching objects found (passed glob pattern)")
            raise
        
        if matching_objects:
            expanded_objects.extend(matching_objects)
        else:
            if verbose:
                print(f"  No objects found matching any of the {len(patterns)} pattern(s)")
    
    # Handle exact keys (no glob patterns)
    for key in exact_keys:
        if verbose:
            print(f"Fetching object metadata: {key}")
        try:
            obj = s3.head_object(Bucket=bucket_name, Key=key)
            last_modified = obj.get('LastModified')
            
            # Apply time filter if specified
            if has_time_filter and last_modified:
                if not (start_time <= last_modified <= end_time):
                    if verbose:
                        print(f"  Skipped: {key} (outside time window)")
                    continue
            
            # Create object dict similar to list_objects_v2 response
            expanded_objects.append({
                'Key': key,
                'LastModified': obj['LastModified'],
                'Size': obj['ContentLength']
            })
            if verbose:
                print(f"  Found: {key}")
        except botocore.exceptions.ClientError as e:
            error_code = e.response.get('Error', {}).get('Code', '')
            if error_code == '404' or error_code == 'NoSuchKey':
                if verbose:
                    print(f"  Warning: Object not found: {key}")
            else:
                if verbose:
                    print(f"  Warning: Could not retrieve object {key}: {e}")
        except Exception as e:
            if verbose:
                print(f"  Warning: Could not retrieve object {key}: {e}")
    
    # No need for additional time filtering - it was already applied during listing
    return expanded_objects
