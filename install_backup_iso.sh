#!/usr/bin/bash

if [ "$BASH" = "" ]; then
    echo "error: it must be executed with bash" >&2
    exit 1;
fi

BACKUP_HOME="$(dirname "$(realpath "$BASH_SOURCE")")"

source "$BACKUP_HOME/backup_iso_config.sh"
source "$BACKUP_HOME/util.sh"
source "$BACKUP_HOME/download_file.sh"
source "$BACKUP_HOME/iso_9660.sh"

USAGE="
Usage:
    # bash $0   [--dest-dir-url DEST_DIR_URL] \\
                [--ssh-known-hosts-file-path SSH_KNOWN_HOSTS_FILE_PATH] \\
                [--dest-credentials-file-path DEST_CREDENTIALS_FILE_PATH] \\
                [--blocks-num BLOCKS_NUM] \\
                [--post-hook-executable-path POST_HOOK_EXECUTABLE_PATH] \\
                [--original-iso-url ORIGINAL_ISO_URL] \\
                [--backup-iso-path BACKUP_ISO_PATH] \\
                [--backup-iso-mode BACKUP_ISO_MODE] \\
                [--grub-timeout GRUB_TIMEOUT] \\
                [--grub-timeout-style GRUB_TIMEOUT_STYLE] \\
                [--grub-menu-entry-config-file-path GRUB_MENU_ENTRY_CONFIG_FILE_PATH] \\
                [--grub-default-config-file-path GRUB_DEFAULT_CONFIG_FILE_PATH] \\
                [--apt-get-assume-yes]
    
    $ bash $0   --help
    
    --dest-dir-url DEST_DIR_URL
        default to '$DEST_DIR_URL'
    
    --ssh-known-hosts-file-path SSH_KNOWN_HOSTS_FILE_PATH
        an empty path ('') means to use an empty 'ssh_known_hosts' file.
        Default to '$SSH_KNOWN_HOSTS_FILE_PATH'
    
    --dest-credentials-file-path DEST_CREDENTIALS_FILE_PATH
        Path to file with the credentials (if needed) to access the URL
        of the directory where to place the backup (see --dest-dir-url).
        
        An empty path ('') means no credentials.
        Default to '$DEST_CREDENTIALS_FILE_PATH'.
    
    --blocks-num BLOCKS_NUM
        Number of blocks to backup for each disk.
        
        An empty value ('') means all blocks (i.e. the whole disk).
        Default to '$BLOCKS_NUM'.
    
    --post-hook-executable-path POST_HOOK_EXECUTABLE_PATH
        Path to a program file to be executed after the backup process.
        
        That program file will be given execution permission before 
        been called as ./post_hook_executable with the user root from 
        a working directory created by the command 'mktemp -d' in the
        live system.
        
        The following environment variables are available:
            - BACKUP_EXIT_CODE: the exit status code of the backup process.
            - BACKUP_STDERR: the captured stderr stream of the backup process.
        
        An empty path ('') means no post hook.
        Default to '$POST_HOOK_EXECUTABLE_PATH'.
    
    --original-iso-url ORIGINAL_ISO_URL
        default to '$ORIGINAL_ISO_URL'
    
    --backup-iso-path BACKUP_ISO_PATH
        default to '$BACKUP_ISO_PATH'
    
    --backup-iso-mode BACKUP_ISO_MODE
        default to '$BACKUP_ISO_MODE'
    
    --grub-timeout GRUB_TIMEOUT
        default to '$GRUB_TIMEOUT'
    
    --grub-timeout-style GRUB_TIMEOUT_STYLE
        default to '$GRUB_TIMEOUT_STYLE'
    
    --grub-menu-entry-config-file-path GRUB_MENU_ENTRY_CONFIG_FILE_PATH
        default to '$GRUB_MENU_ENTRY_CONFIG_FILE_PATH'
    
    --grub-default-config-file-path GRUB_DEFAULT_CONFIG_FILE_PATH
        default to '$GRUB_DEFAULT_CONFIG_FILE_PATH'
    
    --apt-get-assume-yes
    
    --help
        display this help and exit
"

install_deps() {
    local assume_yes="${1:-0}"
    
    local y_option="$( (($assume_yes)) && echo -y )"
    
    local bsdtar_provider="libarchive-tools"
    local isoinfo_provider="genisoimage"
    local xorriso_provider="xorriso"
    local uuidgen_provider="uuid-runtime"
    local sftp_provider="openssh-client"
    
    apt-get $y_option install \
        $bsdtar_provider \
        $isoinfo_provider \
        $xorriso_provider \
        $uuidgen_provider \
        $sftp_provider
}

preinstall_host_system_info() {
    local grub_timeout="$1"
    local grub_timeout_style="$2"
    local grub_menu_entry_config_file_path="$3"
    local grub_default_config_file_path="$4"
    
    grub_menu_entry_config_file_path="$(realpath --canonicalize-missing "$grub_menu_entry_config_file_path")" && \
    grub_default_config_file_path="$(realpath --canonicalize-missing "$grub_default_config_file_path")" \
        || return 1
    
    local grub_menu_entry_id
    local grub_line_mark
    grub_menu_entry_id="uuid_$(uuidgen)" && \
    grub_line_mark="$(uuidgen)" \
        || return 2
    
    local root_fs_uuid
    root_fs_uuid="$(fs_uuid /)" || return 3
    
    cat << EOF > "$BACKUP_HOME/live/host-system-info" || return 4
grub_menu_entry_id=$grub_menu_entry_id
grub_timeout=$grub_timeout
grub_timeout_style=$grub_timeout_style
grub_line_mark=$grub_line_mark
grub_menu_entry_config_file_path=$grub_menu_entry_config_file_path
grub_default_config_file_path=$grub_default_config_file_path
root_fs_uuid=$root_fs_uuid
EOF
}

preinstall_file() {
    local file_path="$1"
    local live_rel_dest_path="$2"
    
    local dest_path="$BACKUP_HOME/live/$live_rel_dest_path"
    
    if [ -n "$file_path" ]; then
        cp -f "$file_path" "$dest_path"
    else
        > "$dest_path"
    fi
}

eval_0010_backup_config_hook_tpl() {
    local dest_dir_url="$1"; shift
    local dest_credentials_file_path="$1"; shift
    local blocks_num="$1"; shift
    local post_hook_executable_path="$1"; shift
    
    local backup_config_hook_tpl="$(cat "$BACKUP_HOME/0010-backup.config-hook.tpl")"
    
    backup_config_hook_tpl="$(sed "s#{{dest_dir_url}}#$dest_dir_url#g" <<< "$backup_config_hook_tpl")"
    backup_config_hook_tpl="$(sed "s#{{dest_credentials_file_path}}#$dest_credentials_file_path#g" <<< "$backup_config_hook_tpl")"
    backup_config_hook_tpl="$(sed "s#{{blocks_num}}#$blocks_num#g" <<< "$backup_config_hook_tpl")"
    backup_config_hook_tpl="$(sed "s#{{post_hook_executable_path}}#$post_hook_executable_path#g" <<< "$backup_config_hook_tpl")"
    
    echo "$backup_config_hook_tpl"
}

preinstall_0010_backup_config_hook() {
    local dest_dir_url="$1"; shift
    local dest_credentials_file_path="$1"; shift
    local blocks_num="$1"; shift
    local post_hook_executable_path="$1"; shift
    
    preinstall_file "$dest_credentials_file_path" "dest-credentials" && \
    preinstall_file "$post_hook_executable_path" "post-hook" && \
    eval_0010_backup_config_hook_tpl \
        "$dest_dir_url" "{{live_medium}}/live/dest-credentials" \
        "$blocks_num" "{{live_medium}}/live/post-hook" \
        > "$BACKUP_HOME/live/config-hooks/0010-backup"
}

create_empty_backup_iso() {
    local backup_iso_path="$1"
    local backup_iso_mode="$2"
    
    if [ -f "$backup_iso_path" ]; then
        local total_bytes=$(stat --printf="%s" "$backup_iso_path")
        
        if [ "$total_bytes" -ne 0 ]; then
            echo "error: $backup_iso_path is not empty" >&2
            return 1
        fi
    else
        touch "$backup_iso_path" || return 2
    fi
    
    chmod "$backup_iso_mode" "$backup_iso_path" || return 3
}

install_backup_iso() {
    local original_iso_url="$1"
    local backup_iso_path="$2"
    local backup_iso_mode="$3"
    
    local original_iso_path
    original_iso_path="$(mktemp)" || return 1
    
    download_file "$original_iso_url" "$original_iso_path" || return 2
    
    create_empty_backup_iso "$backup_iso_path" "$backup_iso_mode" || return 3
    
    inject_iso_9660 \
        "$original_iso_path" "$backup_iso_path" "$BACKUP_HOME/live/" "./" \
        "backup" \
        || return 4
    
    rm -f "$original_iso_path"
    return 0
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
            --ssh-known-hosts-file-path)
                ssh_known_hosts_file_path="$2"
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
            --original-iso-url)
                original_iso_url="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --backup-iso-path)
                backup_iso_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --backup-iso-mode)
                backup_iso_mode="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --grub-timeout)
                grub_timeout="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --grub-timeout-style)
                grub_timeout_style="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --grub-menu-entry-config-file-path)
                grub_menu_entry_config_file_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --grub-default-config-file-path)
                grub_default_config_file_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --apt-get-assume-yes)
                apt_get_assume_yes="1"
                shift
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
    ssh_known_hosts_file_path="${ssh_known_hosts_file_path:-$SSH_KNOWN_HOSTS_FILE_PATH}"
    dest_credentials_file_path="${dest_credentials_file_path:-$DEST_CREDENTIALS_FILE_PATH}"
    blocks_num="${blocks_num:-$BLOCKS_NUM}"
    post_hook_executable_path="${post_hook_executable_path:-$POST_HOOK_EXECUTABLE_PATH}"
    original_iso_url="${original_iso_url:-$ORIGINAL_ISO_URL}"
    backup_iso_path="${backup_iso_path:-$BACKUP_ISO_PATH}"
    backup_iso_mode="${backup_iso_mode:-$BACKUP_ISO_MODE}"
    grub_timeout="${grub_timeout:-$GRUB_TIMEOUT}"
    grub_timeout_style="${grub_timeout_style:-$GRUB_TIMEOUT_STYLE}"
    grub_menu_entry_config_file_path="${grub_menu_entry_config_file_path:-$GRUB_MENU_ENTRY_CONFIG_FILE_PATH}"
    grub_default_config_file_path="${grub_default_config_file_path:-$GRUB_DEFAULT_CONFIG_FILE_PATH}"
}

main() {
    parse_args "$@" || return 2
    
    [ "$help" = "1" ] && echo "$USAGE" && return 0
    
    check_im_root || return 3
    
    install_deps "$apt_get_assume_yes" || return 4
    
    preinstall_host_system_info \
        "$grub_timeout" "$grub_timeout_style" \
        "$grub_menu_entry_config_file_path" "$grub_default_config_file_path" \
        || return 5
    
    preinstall_file \
        "$ssh_known_hosts_file_path" "ssh-known-hosts" \
        || return 6
    
    preinstall_0010_backup_config_hook \
        "$dest_dir_url" "$dest_credentials_file_path" "$blocks_num" \
        "$post_hook_executable_path" \
        || return 7
    
    install_backup_iso \
        "$original_iso_url" "$backup_iso_path" "$backup_iso_mode" \
        || return 8
}

main "$@"
