#!/usr/bin/bash

check_im_root() {
    if [ "$(id -u)" != "0" ]; then
        echo "error: it must be executed as root" >&2
        return 1;
    fi
}

reboot_() {
    systemctl reboot
}

lsdisk() {
    lsblk --output NAME,TYPE --noheadings --list --paths | grep -Po '^.*\S(?=\s+disk$)'
}

timeout_() {
    local secs="$1"
    local command="$2"
    local kill_secs="${3:-3}"
    
    (
        trap - SIGTERM SIGKILL
        
        eval "$command" &
        local command_pid=$!
        
        (
            sleep "$secs"
            kill -SIGTERM $command_pid 2> /dev/null
            sleep "$kill_secs"
            kill -SIGKILL $command_pid 2> /dev/null
        ) &
        local timer_pid=$!
        
        wait $command_pid
        local exit_status=$?
        
        kill -SIGTERM $timer_pid 2> /dev/null
        wait $timer_pid
        
        return $exit_status
    )
}

wait_for() {
    local command="$1"
    local message="${2:-$command }"
    local check_interval_millis="${3:-500}"
    local char_interval_millis="${4:-100}"
    
    eval "$command" &
    
    local chars='/-\|'
    local i=0
    local time_millis=$(($(date +%s%N) / 1000000))
    local check_time_millis=$time_millis
    local char_time_millis=$time_millis
    local next_time_millis
    local sleep_millis
    local sleep_secs
    
    echo -ne "$message "
    while true; do
        time_millis=$(($(date +%s%N) / 1000000))
        
        if (($time_millis >= $char_time_millis)); then
            echo -ne "\b${chars:$i:1}"
            ((++i == ${#chars})) && i=0
            char_time_millis=$(($time_millis + $char_interval_millis))
        fi
        
        if (($time_millis >= $check_time_millis)); then
            if ! ps -p "$!" >/dev/null 2>&1; then
                break
            fi
            check_time_millis=$(($time_millis + $check_interval_millis))
        fi
        
        next_time_millis=$(($char_time_millis < $check_time_millis
                            ? $char_time_millis
                            : $check_time_millis))
        
        sleep_millis=$(($next_time_millis - $time_millis))
        sleep_secs="$(awk "BEGIN {printf \"%.3f\",$sleep_millis/1000}")"
        
        sleep "$sleep_secs"
    done
    wait $!
    local exit_status=$?
    
    echo -ne "\b"
    
    if [ $exit_status -eq 0 ]; then
        echo -e "\e[92m[done]\e[0m"
    else
        echo -e "\e[91m[exit $exit_status]\e[0m"
    fi
    
    return $exit_status
}

bytes() {
    local magnitud="$1"
    local unit="$2"
    
    local unit_to_factor_map="
    c: 1
    w: 2
    b: 512
    kB: 1000
    K: 1024
    MB: 1000*1000
    M: 1024*1024
    xM: 1024*1024
    GB: 1000*1000*1000
    G: 1024*1024*1024
    T: 1024*1024*1024*1024
    P: 1024*1024*1024*1024*1024
    E: 1024*1024*1024*1024*1024*1024
    Z: 1024*1024*1024*1024*1024*1024*1024
    Y: 1024*1024*1024*1024*1024*1024*1024*1024
    "
    
    local factor="$(grep -P "\\b$unit\\b" <<<"$unit_to_factor_map" | 
                    cut -d : -f 2 | tr -d '[:blank:]')"
    
    awk "BEGIN {printf \"%d\n\",$factor*$magnitud}"
}

bytes_repr() {
    local bytes="$1"
    
    if [ -z "$bytes" ] || [ -n "${bytes//[0-9]/}" ]; then
        echo "error: argument 'bytes' must be a non-negative integer." >&2
        return 1
    fi
    
    local units=(         "byte" "kB"   "MB"        "GB"             "TB"                  "infinite")
    local units_in_bytes=("1"    "1000" "1000*1000" "1000*1000*1000" "1000*1000*1000*1000" "2**63-1")
    
    local i
    for ((i=1; i<${#units[@]}; ++i)); do
        if [ $bytes -lt $((${units_in_bytes[i]})) ]; then
            local magnitude=$(awk "BEGIN {printf \"%.1f\",$bytes/(${units_in_bytes[i - 1]})}")
            magnitude=$(echo "$magnitude" | grep -Po '^(\d+(?=\.0+$)|.+)')
            local unit="${units[i - 1]}"
            [ "$unit" = "byte" ] && [ "$magnitude" != "1" ] && unit="${unit}s"
            break
        fi
    done
    
    if [ "$unit" = "" ]; then
        echo "1 ${units[-1]}"
    else
        echo "$magnitude $unit"
    fi
}

delta_time_repr() {
    local secs="$1"
    
    if [ -z "$secs" ] || [ -n "${secs//[0-9]/}" ]; then
        echo "error: argument 'secs' must be a non-negative integer." >&2
        return 1
    fi
    
    local units=(        "second" "minute" "hour"  "day"      "week"       "month"       "year"         "infinite")
    local units_in_secs=("1"      "60"     "60*60" "60*60*24" "60*60*24*7" "60*60*24*30" "60*60*24*365" "2**63-1")
    
    local i
    for ((i=1; i<${#units[@]}; ++i)); do
        if [ $secs -lt $((${units_in_secs[i]})) ]; then
            local magnitude=$(awk "BEGIN {printf \"%.1f\",$secs/(${units_in_secs[i - 1]})}")
            magnitude=$(echo "$magnitude" | grep -Po '^(\d+(?=\.0+$)|.+)')
            local unit="${units[i - 1]}"
            [ "$magnitude" != "1" ] && unit="${unit}s"
            break
        fi
    done
    
    if [ "$unit" = "" ]; then
        echo "1 ${units[-1]}"
    else
        echo "$magnitude $unit"
    fi
}
