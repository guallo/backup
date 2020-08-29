#!/usr/bin/bash

mount_sftp() {
    local dest_dir="$1"
    local host="$2"
    # optional parameters
    local src_dir="$3"
    local user="$4"
    local password="$5"
    local port="$6"
    
    local user_part="$([ -n "$user" ] && echo "$user@")"
    
    if [ -n "$password" ]; then
        if [ -n "$port" ]; then
            sshfs "$user_part$host:$src_dir" "$dest_dir" -p "$port" \
                -o StrictHostKeyChecking=yes -o password_stdin <<< "$password"
        else
            sshfs "$user_part$host:$src_dir" "$dest_dir" \
                -o StrictHostKeyChecking=yes -o password_stdin <<< "$password"
        fi
    else
        if [ -n "$port" ]; then
            sshfs "$user_part$host:$src_dir" "$dest_dir" -p "$port" \
                -o StrictHostKeyChecking=yes
        else
            sshfs "$user_part$host:$src_dir" "$dest_dir" \
                -o StrictHostKeyChecking=yes
        fi
    fi
}

mount_dir() {
    local src_dir="$1"
    local dest_dir="$2"
    
    mount --bind "$src_dir" "$dest_dir"
}

mount_() {
    local url="$1"
    local dest_dir="$2"
    # optional parameters
    local credentials="$3"
    
    if [[ "$url" =~ ^(sftp)://(([^@:/]+)@)?([^:/]+)(:([0-9]+))?(/.*)?$ ]]; then
        local host="${BASH_REMATCH[4]}"
        local src_dir="${BASH_REMATCH[7]}"
        local user="${BASH_REMATCH[3]}"
        local port="${BASH_REMATCH[6]}"
        mount_sftp "$dest_dir" "$host" "$src_dir" "$user" "$credentials" "$port" \
            || return 1
    elif [[ "$url" =~ ^(file)://(/.*)$ ]]; then
        local src_dir="${BASH_REMATCH[2]}"
        mount_dir "$src_dir" "$dest_dir" || return 1
    else
        echo "unsupported url: $url" >&2
        return 2
    fi
}
