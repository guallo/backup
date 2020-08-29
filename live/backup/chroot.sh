#!/usr/bin/bash

chroot_mount() {
    local root_fs_uuid="$1"
    
    local chroot_dir
    chroot_dir="$(mktemp --directory)" || return 1
    
    {
        mount "/dev/disk/by-uuid/$root_fs_uuid" "$chroot_dir" && \
        mount --bind /dev/ "$chroot_dir/dev/" && \
        mount --bind /dev/pts/ "$chroot_dir/dev/pts/" && \
        mount --bind /proc/ "$chroot_dir/proc/" && \
        mount --bind /sys/ "$chroot_dir/sys/"
    } > /dev/null
    
    if (($?)); then
        chroot_umount "$chroot_dir"
        rmdir "$chroot_dir"
        return 2
    fi
    
    echo "$chroot_dir"
}

chroot_umount() {
    local chroot_dir="$1"
    
    local exit_code=0
    
    umount "$chroot_dir/sys/" || exit_code=1
    umount "$chroot_dir/proc/" || exit_code=1
    umount "$chroot_dir/dev/pts/" || exit_code=1
    umount "$chroot_dir/dev/" || exit_code=1
    umount "$chroot_dir" || exit_code=1
    
    return $exit_code
}
