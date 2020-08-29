#!/usr/bin/bash

sftp_download_file() {
    local host="$1"
    local file_path="$2"
    # optional parameters
    local user="$3"
    local dest_path="$4"
    local port="$5"
    
    local user_part="$([ x"$user" != x"" ] && echo "$user@" || echo "")"
    
    if [ x"$port" != x"" ]; then
        sftp -P "$port" "$user_part$host:$file_path" "$dest_path"
    else
        sftp "$user_part$host:$file_path" "$dest_path"
    fi
}

file_download_file() {
    local file_path="$1"
    local dest_path="${2:-.}"
    
    cp "$file_path" "$dest_path"
}

download_file() {
    local url="$1"
    local dest_path="$2"
    
    if [[ "$url" =~ ^(sftp)://(([^@:/]+)@)?([^:/]+)(:([0-9]+))?(/.*)$ ]]; then
        local host="${BASH_REMATCH[4]}"
        local file_path="${BASH_REMATCH[7]}"
        local user="${BASH_REMATCH[3]}"
        local port="${BASH_REMATCH[6]}"
        sftp_download_file "$host" "$file_path" "$user" "$dest_path" "$port"
    elif [[ "$url" =~ ^(file)://(/.*)$ ]]; then
        local file_path="${BASH_REMATCH[2]}"
        file_download_file "$file_path" "$dest_path"
    else
        echo "unsupported url: $url" >&2
        return 1
    fi
}
