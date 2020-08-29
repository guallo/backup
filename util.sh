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

fs_uuid() {
    local path="$1"
    
    local df_output
    df_output="$(df --output=source "$path")" || return 1
    
    local device="$(tail -n 1 <<< "$df_output")"
    
    lsblk --output UUID --noheadings "$device" || return 2
}
