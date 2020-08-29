#!/usr/bin/bash

source "$LIVE_BACKUP_HOME/util.sh"

copy() {
    local src_file="$1"
    local dest_file="$2"
    local block_size_bytes="${3:-512}"
    local blocks_num="$4"
    local stats_interval_secs="${5:-1}"
    
    if [ -z "$block_size_bytes" ] || [ -n "${block_size_bytes//[0-9]/}" ] || \
            [ -z "${block_size_bytes//0/}" ]; then
        echo "error: argument 'block_size_bytes' must be a positive integer." >&2
        return 91
    fi
    
    if [ -z "$stats_interval_secs" ] || [ -n "${stats_interval_secs//[0-9.]/}" ] || \
            grep -qP '\.\.' <<<"${stats_interval_secs//[^.]/}"; then
        echo "error: argument 'stats_interval_secs' must be a non-negative number." >&2
        return 91
    fi
    
    if [ -n "${blocks_num//[0-9]/}" ]; then
        echo "error: argument 'blocks_num' must be a non-negative integer." >&2
        return 91
    fi
    
    local src_file_realpath="$(realpath "$src_file")"
    local dest_file_realpath="$(realpath "$dest_file")"
    
    local total_bytes
    
    if [ -f "$src_file" ]; then
        total_bytes=$(stat --printf="%s" "$src_file") || return 92
    elif [ -b "$src_file" ]; then
        total_bytes=$(blockdev --getsize64 "$src_file") || return 92
    else
        echo "error: unsupported file: $src_file" >&2
        return 93
    fi
    
    if [ -n "$blocks_num" ]; then
        total_bytes=$(( $blocks_num * $block_size_bytes < $total_bytes
                            ? $blocks_num * $block_size_bytes
                            : $total_bytes ))
    fi
    
    local total_bytes_repr="$(bytes_repr "$total_bytes")"
    local exit_status_file="$(mktemp)"
    
    (
        trap '
            kill "$dd_pid" "$dd_signaler_pid" 2>/dev/null
            echo 130 >"$exit_status_file"
        ' SIGINT
        
        dd_startup_time=0.1
        
        while true; do
            if [ -z "$blocks_num" ]; then
                dd if="$src_file" of="$dest_file" bs="$block_size_bytes" conv=fsync 2>&1 >/dev/null &
            else
                dd if="$src_file" of="$dest_file" bs="$block_size_bytes" count="$blocks_num" conv=fsync 2>&1 >/dev/null &
            fi
            dd_pid=$!
            
            sleep $dd_startup_time && \
                while kill -SIGUSR1 $dd_pid 2>/dev/null; do
                    sleep "$stats_interval_secs"
                done &
            dd_signaler_pid=$!
            
            wait $dd_pid
            dd_exit_status=$?
            echo $dd_exit_status >"$exit_status_file"
            
            kill $dd_signaler_pid 2>/dev/null
            wait $dd_signaler_pid
            
            # 138 == 128 + 10 (SIGUSR1)
            if (($dd_exit_status != 138)); then
                break
            fi
            
            dd_startup_time=$(awk "BEGIN {printf \"%.1f\",$dd_startup_time+0.1}")
        done
    ) |
    python3 -c '
import os
import re
import sys

def stderr_to_devnull_and_exit(exit_status):
    devnull_fd = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull_fd, sys.stderr.fileno())
    exit(exit_status)

num = r"\d+(?:\.\d+)?"
num_word = rf"{num} [a-zA-Z]+"

dd_stats_pattern = re.compile(
    r"\d+\+\d+ records (?:in|out)"
    r"|"
    rf"\d+ bytes? (?:\({num_word}(?:, {num_word})*\) )?copied, {num} s, {num_word}/s"
)

try:
    try:
        while True:
            try:
                dd_stderr_line = input()
            except EOFError:
                break
            
            last_end = 0
            
            for match in re.finditer(dd_stats_pattern, dd_stderr_line):
                dd_error = dd_stderr_line[last_end: match.start()]
                if dd_error:
                    print(dd_error, file=sys.stderr, flush=True)
                
                dd_stats = match.group(0)
                print(dd_stats, file=sys.stdout, flush=True)
                
                last_end = match.end()
            
            dd_error = dd_stderr_line[last_end:]
            if dd_error:
                print(dd_error, file=sys.stderr, flush=True)
    except BrokenPipeError:
        stderr_to_devnull_and_exit(1)
except KeyboardInterrupt:
    stderr_to_devnull_and_exit(130)
    ' |
    grep --line-buffered -P 'bytes?' |
    (
        while IFS="" read -r stats_line; do
            copied_bytes=$(echo "$stats_line" | grep -Po '^\d+(?= bytes?)')
            remaining_bytes=$(($total_bytes - $copied_bytes))
            copy_percent=$( (($total_bytes)) && awk "BEGIN {printf \"%d\",$copied_bytes/$total_bytes*100}" || echo "100")
            copied_bytes_repr=$(echo "$stats_line" | grep -Po '^\d+ bytes?(?= copied)|(?<=\()[^,)]+')
            ellapsed_time_secs=$(echo "$stats_line" | grep -Po '\d+(\.\d+)?(?=\s+s\b)')
            ellapsed_time_secs=$(echo "$ellapsed_time_secs" | grep -Po '^\d+')
            ellapsed_time_repr="$(delta_time_repr "$ellapsed_time_secs")"
            speed_repr="$(echo "$stats_line" | grep -Po '(?<=, )[^,]+$')"
            speed_magnitud=$(echo "$speed_repr" | grep -Po '\d+(\.\d+)?')
            speed_unit_per_secs=$(echo "$speed_repr" | grep -Po '\w+(?=/s)')
            bytes_per_secs=$(bytes "$speed_magnitud" "$speed_unit_per_secs")
            
            if (($bytes_per_secs)); then
                remaining_time_secs=$(($remaining_bytes / $bytes_per_secs))
                remaining_time_repr="$(delta_time_repr "$remaining_time_secs")"
            elif ((!$remaining_bytes)); then
                remaining_time_secs=0
                remaining_time_repr="$(delta_time_repr "$remaining_time_secs")"
            else
                remaining_time_secs=
                remaining_time_repr="unknown"
            fi
            
            echo "XXX"
            echo "$copy_percent"
            echo
            echo "           From: $src_file_realpath"
            echo "             To: $dest_file_realpath"
            echo
            echo "       Progress: $copied_bytes_repr/$total_bytes_repr"
            echo "          Speed: $speed_repr"
            echo "  Ellapsed time: $ellapsed_time_repr"
            echo " Remaining time: $remaining_time_repr"
            echo "XXX"
        done
    ) |
    dialog --no-lines --no-collapse --title "Copying..." --gauge "" 15 74
    
    local exit_status
    read exit_status <"$exit_status_file"
    rm -f "$exit_status_file"
    return "$exit_status"
}
