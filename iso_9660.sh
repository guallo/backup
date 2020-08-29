#!/usr/bin/bash

extract_iso_9660() {
    local iso_path="$1"
    local dest_path="$2"
    
    mkdir -p "$dest_path" && \
    bsdtar --extract --file "$iso_path" --directory "$dest_path"
}

create_iso_9660() {
    local iso_dir_path="$1"
    local dest_path="$2"
    local isohdpfx_bin_path="$3"
    # optional parameters
    local volume_id="${4:-custom live}"
    
    xorriso -outdev "$dest_path" -volid "$volume_id" -padding 0 \
            -compliance no_emul_toc -map "$iso_dir_path" / -chmod 0755 / -- \
            -boot_image isolinux dir=/isolinux -boot_image isolinux \
            system_area="$isohdpfx_bin_path" -boot_image any next \
            -boot_image any efi_path=boot/grub/efi.img -boot_image isolinux \
            partition_entry=gpt_basdat
}

extract_isohdpfx_bin_from_iso_9660() {
    local iso_path="$1"
    local dest_path="$2"
    
    dd if="$iso_path" bs=1 count=512 of="$dest_path"
}

extract_pvd_info_from_iso_9660() {
    local iso_path="$1"
    
    if [ -z "$iso_path" ]; then
        echo "error: empty iso_path" >&2
        return 1
    fi
    
    isoinfo -d -i "$iso_path"
}

extract_volume_id_from_iso_9660() {
    local iso_path="$1"
    
    extract_pvd_info_from_iso_9660 "$iso_path" | grep -Po "(?<=Volume id: ).*"
}

cat_file_from_iso_9660() {
    local iso_path="$1"
    local iso_rel_file_path="$2"
    
    local dest_path
    dest_path="$(mktemp)" || return 1
    
    xorriso -osirrox on -indev "$iso_path" -extract_single "$iso_rel_file_path" "$dest_path"
    local xorriso_exit_code=$?
    
    if (($xorriso_exit_code)); then
        rm -rf "$dest_path"
        return 2
    fi
    
    cat "$dest_path"
    local cat_exit_code=$?
    
    rm -rf "$dest_path"
    
    ((! $cat_exit_code)) || return 3
    return 0
}

inject_iso_9660() {
    local iso_path="$1"
    local dest_path="$2"
    local source_path="$3"
    local iso_rel_dest_path="$4"
    # optional parameters
    local volume_id="${5:-$(extract_volume_id_from_iso_9660 "$iso_path")}"
    
    local iso_dir_path="$(mktemp -d)"
    local isohdpfx_bin_path="$(mktemp)"
    
    extract_iso_9660 "$iso_path" "$iso_dir_path" && \
    cp -R -u "$source_path" "$iso_dir_path/$iso_rel_dest_path" && \
    extract_isohdpfx_bin_from_iso_9660 "$iso_path" "$isohdpfx_bin_path" && \
    create_iso_9660 "$iso_dir_path" "$dest_path" "$isohdpfx_bin_path" "$volume_id"
    
    local exit_status=$?
    
    rm -rf "$iso_dir_path"
    rm -f "$isohdpfx_bin_path"
    
    return $exit_status
}

matching_paths_from_iso_9660() {
    local iso_path="$1"
    local grep_iPo_regex="$2"
    
    bsdtar --list --file "$iso_path" | grep -iPo "$grep_iPo_regex"
}

vmlinuz_path_from_iso_9660() {
    local iso_path="$1"
    
    local vmlinuz_paths
    vmlinuz_paths="$(matching_paths_from_iso_9660 "$iso_path" '^live/vmlinuz.*')"
    local exit_status=$?
    echo "$vmlinuz_paths" | head -n 1
    return $exit_status
}

initrd_path_from_iso_9660() {
    local iso_path="$1"
    
    local initrd_paths
    initrd_paths="$(matching_paths_from_iso_9660 "$iso_path" '^live/initrd.*')"
    local exit_status=$?
    echo "$initrd_paths" | head -n 1
    return $exit_status
}
