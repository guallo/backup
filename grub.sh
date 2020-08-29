#!/usr/bin/bash

source "$BACKUP_HOME/util.sh"
source "$BACKUP_HOME/iso_9660.sh"

iso_grub_menu_entry() {
    local iso_path="$(realpath "$1")"
    local entry_id="${2:-$(uuidgen)}"
    local entry_title="${3:-$(extract_volume_id_from_iso_9660 "$iso_path") (from $iso_path)}"
    local extra_kernel_params="$4"
    local line_comment="$5"
    
    local fs_uuid
    fs_uuid="$(fs_uuid "$iso_path")" || return 1
    
    local iso_rel_vmlinuz_path
    iso_rel_vmlinuz_path="$(vmlinuz_path_from_iso_9660 "$iso_path")" || return 2
    
    local iso_rel_initrd_path
    iso_rel_initrd_path="$(initrd_path_from_iso_9660 "$iso_path")" || return 3
    
    cat << EOF
menuentry "$entry_title" --id "$entry_id" {  # $line_comment
  set iso_path="$iso_path"  # $line_comment
  loopback loop "\$iso_path"  # $line_comment
  linux "(loop)/$iso_rel_vmlinuz_path" boot=live components splash quiet "fromiso=/dev/disk/by-uuid/$fs_uuid\$iso_path" $extra_kernel_params  # $line_comment
  initrd "(loop)/$iso_rel_initrd_path"  # $line_comment
}  # $line_comment
EOF
}

grub_default() {
    local default="${1:-0}"
    local line_comment="$2"
    
    cat << EOF
GRUB_DEFAULT="$default"  # $line_comment
EOF
}

grub_timeout() {
    local timeout="${1:-5}"
    local style="${2:-menu}"
    local line_comment="$3"
    
    cat << EOF
GRUB_TIMEOUT_STYLE=$style  # $line_comment
GRUB_TIMEOUT=$timeout  # $line_comment
EOF
}
