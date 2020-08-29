#!/usr/bin/bash

if [ "$BASH" = "" ]; then
    echo "error: it must be executed with bash" >&2
    exit 1;
fi

BACKUP_HOME="$(dirname "$(realpath "$BASH_SOURCE")")"

source "$BACKUP_HOME/backup_config.sh"
source "$BACKUP_HOME/util.sh"
source "$BACKUP_HOME/iso_9660.sh"
source "$BACKUP_HOME/grub.sh"

USAGE="
Usage:
    # bash $0   [--backup-iso-path BACKUP_ISO_PATH] \\
                [--pre-hook-executable-path PRE_HOOK_EXECUTABLE_PATH] \\
                [--apt-get-assume-yes]
    
    $ bash $0   --help
    
    --backup-iso-path BACKUP_ISO_PATH
        default to '$BACKUP_ISO_PATH'
    
    --pre-hook-executable-path PRE_HOOK_EXECUTABLE_PATH
        Path to a program file to be executed before rebooting to start
        the backup process.
        
        If the pre-hook exits with non-zero status code the backup process
        will be cancelled. If the process previous to backup (and previous
        to the pre-hook) exits with non-zero status code (see environment
        variable PRE_BACKUP_EXIT_CODE below) the backup process will be
        cancelled too regarless of the exit code of the pre-hook.
        
        That program file will be given execution permission before
        been called as ./pre_hook_executable with the user root from
        a working directory created by the command 'mktemp -d' in the
        current system (not the live system).
        
        The following environment variables are available to the pre-hook:
            - PRE_BACKUP_EXIT_CODE: the exit status code of the process
                previous to backup.
            - PRE_BACKUP_STDERR: the captured stderr stream of the process
                previous to backup.
        
        An empty path ('') means no pre-hook.
        Default to '$PRE_HOOK_EXECUTABLE_PATH'.
    
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
    
    apt-get $y_option install \
        $bsdtar_provider \
        $isoinfo_provider \
        $xorriso_provider \
        $uuidgen_provider
}

install_backup_iso_grub_menu_entry() {
    local backup_iso_path="$1"
    local id_="$2"
    local timeout="$3"
    local style="$4"
    local menu_entry_config_file_path="$5"
    local default_config_file_path="$6"
    local line_mark="$7"
    
    local current_menu_entry_config
    local menu_entry
    current_menu_entry_config="$(cat "$menu_entry_config_file_path")" && \
    menu_entry="$(iso_grub_menu_entry "$backup_iso_path" "$id_" "" \
                    "hooks=medium noeject" "$line_mark")"
    if (($?)); then
        return 1
    fi
    
    echo "$menu_entry" >> "$menu_entry_config_file_path"
    if (($?)); then
        echo "$current_menu_entry_config" > "$menu_entry_config_file_path"
        return 1
    fi
    
    local current_default_config
    local default_menu_entry
    local menu_entry_timeout
    current_default_config="$(cat "$default_config_file_path")" && \
    default_menu_entry="$(grub_default "$id_" "$line_mark")" && \
    menu_entry_timeout="$(grub_timeout "$timeout" "$style" "$line_mark")"
    if (($?)); then
        echo "$current_menu_entry_config" > "$menu_entry_config_file_path"
        return 1
    fi
    
    cat << EOF >> "$default_config_file_path"
$default_menu_entry
$menu_entry_timeout
EOF
    if (($?)); then
        echo "$current_menu_entry_config" > "$menu_entry_config_file_path"
        echo "$current_default_config" > "$default_config_file_path"
        return 1
    fi
    
    update-grub
    if (($?)); then
        echo "$current_menu_entry_config" > "$menu_entry_config_file_path"
        echo "$current_default_config" > "$default_config_file_path"
        update-grub
        return 1
    fi
    
    return 0
}

pre_hook() {
    local pre_hook_executable_path="$1"
    local pre_backup_exit_code="$2"
    local pre_backup_stderr="$3"
    
    [ -z "$pre_hook_executable_path" ] && return 0
    
    local workdir
    workdir="$(mktemp --directory)" && \
    cp "$pre_hook_executable_path" "$workdir/pre_hook_executable" && \
    chmod +x "$workdir/pre_hook_executable" && \
    (
        cd "$workdir" && \
        PRE_BACKUP_EXIT_CODE="$pre_backup_exit_code" \
        PRE_BACKUP_STDERR="$pre_backup_stderr" \
            ./pre_hook_executable
    )
    local exit_code=$?
    
    rm -rf "$workdir"
    return $exit_code
}

parse_args() {
    while (( $# )); do
        case "$1" in
            --backup-iso-path)
                backup_iso_path="$2"
                shift 2 || {
                    echo "error: missing $1's value" >&2 &&
                    echo "$USAGE" >&2 &&
                    return 1;}
                ;;
            --pre-hook-executable-path)
                pre_hook_executable_path="$2"
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
    
    backup_iso_path="${backup_iso_path:-$BACKUP_ISO_PATH}"
    pre_hook_executable_path="${pre_hook_executable_path:-$PRE_HOOK_EXECUTABLE_PATH}"
}

main() {
    parse_args "$@" || return 2
    
    [ "$help" = "1" ] && echo "$USAGE" && return 0
    
    check_im_root || return 3
    
    local pre_backup_stderr_path
    pre_backup_stderr_path="$(mktemp)" || return 4
    
    (
        install_deps "$apt_get_assume_yes" || return 5
        
        local host_system_info
        host_system_info="$(cat_file_from_iso_9660 "$backup_iso_path" "live/host-system-info")" \
            || return 6
        
        local grub_menu_entry_id
        local grub_timeout
        local grub_timeout_style
        local grub_menu_entry_config_file_path
        local grub_default_config_file_path
        local grub_line_mark
        
        grub_menu_entry_id="$(grep -Po '(?<=^grub_menu_entry_id=).*' <<<"$host_system_info")" && \
        grub_timeout="$(grep -Po '(?<=^grub_timeout=).*' <<<"$host_system_info")" && \
        grub_timeout_style="$(grep -Po '(?<=^grub_timeout_style=).*' <<<"$host_system_info")" && \
        grub_menu_entry_config_file_path="$(grep -Po '(?<=^grub_menu_entry_config_file_path=).*' <<<"$host_system_info")" && \
        grub_default_config_file_path="$(grep -Po '(?<=^grub_default_config_file_path=).*' <<<"$host_system_info")" && \
        grub_line_mark="$(grep -Po '(?<=^grub_line_mark=).*' <<<"$host_system_info")" \
            || return 7
        
        install_backup_iso_grub_menu_entry \
            "$backup_iso_path" "$grub_menu_entry_id" "$grub_timeout" \
            "$grub_timeout_style" "$grub_menu_entry_config_file_path" \
            "$grub_default_config_file_path" "$grub_line_mark" \
            || return 8
    ) 2> >(tee /dev/stderr "$pre_backup_stderr_path" > /dev/null)
    
    local pre_backup_exit_code=$?
    local pre_backup_stderr="$(cat "$pre_backup_stderr_path")"
    
    rm -f "$pre_backup_stderr_path"
    
    pre_hook "$pre_hook_executable_path" "$pre_backup_exit_code" "$pre_backup_stderr"
    local pre_hook_exit_code=$?
    
    (($pre_backup_exit_code)) && return $pre_backup_exit_code
    
    (($pre_hook_exit_code)) && return 9
    
    reboot_ || return 10
}

main "$@"
