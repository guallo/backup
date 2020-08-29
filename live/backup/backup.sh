#!/usr/bin/bash

if [ "$BASH" = "" ]; then
    echo "error: it must be executed with bash" >&2
    exit 1;
fi

LIVE_MEDIUM="$(mount | grep -Po '(?<= on ).+(?= type iso9660)' | head -n 1)"
LIVE_BACKUP_HOME="$(dirname "$(realpath "$BASH_SOURCE")")"

source "$LIVE_BACKUP_HOME/backup_config.sh"
source "$LIVE_BACKUP_HOME/util.sh"
source "$LIVE_BACKUP_HOME/chroot.sh"
source "$LIVE_BACKUP_HOME/mount_.sh"
source "$LIVE_BACKUP_HOME/copy.sh"

USAGE="
Usage:
    # bash $0   [--dest-dir-url DEST_DIR_URL] \\
                [--dest-credentials-file-path DEST_CREDENTIALS_FILE_PATH] \\
                [--retry-timeout RETRY_TIMEOUT] \\
                [--blocks-num BLOCKS_NUM] \\
                [--post-hook-executable-path POST_HOOK_EXECUTABLE_PATH]
    
    $ bash $0   --help
    
    --dest-dir-url DEST_DIR_URL
        default to '$DEST_DIR_URL'
    
    --dest-credentials-file-path DEST_CREDENTIALS_FILE_PATH
        Path to file with the credentials (if needed) to access the URL
        of the directory where to place the backup (see --dest-dir-url).
        
        The path can start with the {{live_medium}} placeholder
        to refer to a file relative to the iso's mount point.

        An empty path ('') means no credentials.
        Default to '$DEST_CREDENTIALS_FILE_PATH'.
    
    --retry-timeout RETRY_TIMEOUT
        default to '$RETRY_TIMEOUT'
    
    --blocks-num BLOCKS_NUM
        Number of blocks to backup for each disk.
        
        An empty value ('') means all blocks (i.e. the whole disk).
        Default to '$BLOCKS_NUM'.
    
    --post-hook-executable-path POST_HOOK_EXECUTABLE_PATH
        Path to a program file to be executed after the backup process.
        
        That program file will be given execution permission before 
        been called as ./post_hook_executable with the user root from 
        a working directory created by the command 'mktemp -d'.
        
        The following environment variables are available:
            - BACKUP_EXIT_CODE: the exit status code of the backup process.
            - BACKUP_STDERR: the captured stderr stream of the backup process.
        
        The path can start with the {{live_medium}} placeholder
        to refer to a program file relative to the iso's mount point.
        
        An empty path ('') means no post hook.
        Default to '$POST_HOOK_EXECUTABLE_PATH'.
    
    --help
        display this help and exit
"

install_deps() {
    wait_for "apt-get update >/dev/null 2>&1" && \
    wait_for "apt-get -y install dialog >/dev/null 2>&1" && \
    wait_for "apt-get -y install python3 >/dev/null 2>&1" && \
    wait_for "apt-get -y install sshfs >/dev/null 2>&1"
}

retry_until_install_deps() {
    local retry_timeout="$1"
    
    timeout_ "$retry_timeout" "until install_deps; do :; done"
    local exit_status=$?
    (($exit_status)) && echo "Timed out" >&2
    return $exit_status
}

restore_grub() {
    local host_system_info_file_path="$LIVE_MEDIUM/live/host-system-info"

    local exit_code=1
    
    local root_fs_uuid
    local grub_line_mark
    local grub_menu_entry_config_file_path
    local grub_default_config_file_path
    
    root_fs_uuid="$(grep -Po '(?<=^root_fs_uuid=).*' "$host_system_info_file_path")" && \
    grub_line_mark="$(grep -Po '(?<=^grub_line_mark=).*' "$host_system_info_file_path")" && \
    grub_menu_entry_config_file_path="$(grep -Po '(?<=^grub_menu_entry_config_file_path=).*' "$host_system_info_file_path")" && \
    grub_default_config_file_path="$(grep -Po '(?<=^grub_default_config_file_path=).*' "$host_system_info_file_path")"
    
    if ! (($?)); then
        local chroot_dir
        chroot_dir="$(chroot_mount "$root_fs_uuid")"
        
        if ! (($?)); then
            local script_path
            script_path="$(mktemp --tmpdir="$chroot_dir/tmp/")"
            
            if ! (($?)); then
                cat << EOF > "$script_path"
#!/usr/bin/bash

current_grub_menu_entry_config="\$(cat "$grub_menu_entry_config_file_path")" && \
original_grub_menu_entry_config="\$(grep -vF "$grub_line_mark" "$grub_menu_entry_config_file_path")"
if ((\$?)); then
    return 1
fi

echo "\$original_grub_menu_entry_config" > "$grub_menu_entry_config_file_path"
if ((\$?)); then
    echo "\$current_grub_menu_entry_config" > "$grub_menu_entry_config_file_path"
    return 1
fi

current_grub_default_config="\$(cat "$grub_default_config_file_path")" && \
original_grub_default_config="\$(grep -vF "$grub_line_mark" "$grub_default_config_file_path")"
if ((\$?)); then
    echo "\$current_grub_menu_entry_config" > "$grub_menu_entry_config_file_path"
    return 1
fi

echo "\$original_grub_default_config" > "$grub_default_config_file_path"
if ((\$?)); then
    echo "\$current_grub_menu_entry_config" > "$grub_menu_entry_config_file_path"
    echo "\$current_grub_default_config" > "$grub_default_config_file_path"
    return 1
fi

update-grub
if ((\$?)); then
    echo "\$current_grub_menu_entry_config" > "$grub_menu_entry_config_file_path"
    echo "\$current_grub_default_config" > "$grub_default_config_file_path"
    update-grub
    return 1
fi

exit 0
EOF
                
                if ! (($?)); then
                    chmod +x "$script_path"
                    
                    if ! (($?)); then
                        local chroot_rel_script_path
                        chroot_rel_script_path="$(realpath \
                                                --relative-to="$chroot_dir" \
                                                "$script_path")"
                        
                        if ! (($?)); then
                            chroot "$chroot_dir" "/$chroot_rel_script_path"
                            
                            if ! (($?)); then
                                exit_code=0
                            fi
                        fi
                    fi
                fi
                
                rm -f "$script_path"
            fi
            
            chroot_umount "$chroot_dir"
            rmdir "$chroot_dir"
        fi
    fi
    
    return $exit_code
}

read_dest_credentials() {
    local dest_credentials_file_path="$1"
    
    if [ -n "$dest_credentials_file_path" ]; then
        dest_credentials_file_path="$(sed "s#{{live_medium}}#$LIVE_MEDIUM#g" <<< "$dest_credentials_file_path")"
        
        cat "$dest_credentials_file_path"
    else
        echo ""
    fi
}

copy_disks() {
    local dest_dir
    # optional parameters
    local blocks_num
    
    local parameter_num=1
    
    while (( $# )) && [ "$1" != "--" ]; do
        if [ "$parameter_num" -eq 1 ]; then
            dest_dir="$1"
        elif [ "$parameter_num" -eq 2 ]; then
            blocks_num="$1"
        else
            echo "error: unexpected argument: $1" >&2
            return 1
        fi
        
        shift
        ((++parameter_num))
    done
    
    if [ -z "$dest_dir" ]; then
        echo "error: you must specify a non-empty destination directory" >&2
        return 1
    fi
    
    if [ "$1" = "--" ]; then
        shift
        if (( ! $# )); then
            echo "error: expected one or more disks after '--'" >&2
            return 1
        fi
    fi
    
    if (( ! $# )); then
        IFS=$'\n' disks=( $(lsdisk) )
        
        if (( ! ${#disks[@]} )); then
            echo "error: there are no disks" >&2
            return 2
        fi
        
        set -- "${disks[@]}"
    fi
    
    while (( $# )); do
        local disk="$1"
        local file_name="$(echo "$disk" | tr / -)"
        
        copy "$disk" "$dest_dir/$file_name" "" "$blocks_num"
        
        if (( $? )); then
            echo "error: failed to copy disk $disk" >&2
            return 3
        fi
        
        shift
    done
    
    return 0
}

backup() {
    local dest_dir_url="$1"
    local dest_credentials_file_path="$2"
    local blocks_num="$3"
    
    local local_dest_dir="$(mktemp --directory)" || return 1
    local dest_credentials="$(read_dest_credentials "$dest_credentials_file_path")" || return 2
    
    mount_ "$dest_dir_url" "$local_dest_dir" "$dest_credentials" || return 3
    
    local backup_dir
    backup_dir="$(mktemp --directory --tmpdir="$local_dest_dir" -t \
                "$(date +%m-%d-%YT%I-%M-%S-%p-%Z).XXX.backup")" || return 4
    
    copy_disks "$backup_dir" "$blocks_num" || return 5
    
    umount "$local_dest_dir" && rmdir "$local_dest_dir"
    
    return 0
}

post_hook() {
    local post_hook_executable_path="$1"
    local backup_exit_code="$2"
    local backup_stderr="$3"
    
    [ -z "$post_hook_executable_path" ] && return 0
    
    post_hook_executable_path="$(sed "s#{{live_medium}}#$LIVE_MEDIUM#g" <<< "$post_hook_executable_path")"
    
    local workdir
    workdir="$(mktemp --directory)" && \
    cp "$post_hook_executable_path" "$workdir/post_hook_executable" && \
    chmod +x "$workdir/post_hook_executable" && \
    (
        cd "$workdir" && \
        BACKUP_EXIT_CODE="$backup_exit_code" \
        BACKUP_STDERR="$backup_stderr" \
            ./post_hook_executable
    )
    local exit_code=$(($? ? 1 : 0))
    
    rm -rf "$workdir"
    return $exit_code
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --dest-dir-url)
                dest_dir_url="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --dest-credentials-file-path)
                dest_credentials_file_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --retry-timeout)
                retry_timeout="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --blocks-num)
                blocks_num="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --post-hook-executable-path)
                post_hook_executable_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --help)
                help="1"
                shift
                ;;
            *)
                echo "error: invalid option: $1" >&2
                echo "$USAGE" >&2
                return 2
                ;;
        esac
    done
    
    dest_dir_url="${dest_dir_url:-$DEST_DIR_URL}"
    dest_credentials_file_path="${dest_credentials_file_path:-$DEST_CREDENTIALS_FILE_PATH}"
    retry_timeout="${retry_timeout:-$RETRY_TIMEOUT}"
    blocks_num="${blocks_num:-$BLOCKS_NUM}"
    post_hook_executable_path="${post_hook_executable_path:-$POST_HOOK_EXECUTABLE_PATH}"
}

main() {
    parse_args "$@" || return 2
    
    [ "$help" = "1" ] && echo "$USAGE" && return 0
    
    check_im_root || return 3
    
    local backup_stderr_path
    backup_stderr_path="$(mktemp)" || return 4
    
    (
        retry_until_install_deps "$retry_timeout" || return 5
        
        restore_grub || return 6
        
        backup "$dest_dir_url" "$dest_credentials_file_path" "$blocks_num" || return 7
    ) 2> >(tee /dev/stderr "$backup_stderr_path" >/dev/null)
    
    local backup_exit_code=$?
    local backup_stderr="$(cat "$backup_stderr_path")"
    
    rm -f "$backup_stderr_path"
    
    post_hook "$post_hook_executable_path" "$backup_exit_code" "$backup_stderr"
    
    if (($backup_exit_code)); then
        reboot_ || return $backup_exit_code
    fi
    
    reboot_ || return 8
}

main "$@"
