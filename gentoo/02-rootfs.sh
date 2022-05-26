#!/usr/bin/env bash
source common.sh
source config.sh

[[ -f "$1" ]] \
    || die "Usage: $0 /path/to/stage3.tar.xz"

set -euo pipefail

extract_rootfs() {
    local STAGE3_FILE="$(realpath "$1")"
    [[ -f "$STAGE3_FILE" ]] \
        || die "Stage3 archive does not exist"

    pushd "$ROOT_MOUNTPOINT" \
		|| die "Could not move to '$ROOT_MOUNTPOINT'"

    find . -mindepth 1 -maxdepth 1 -not -name 'lost+found' \
            | grep -q . \
            && die "Root directory '$ROOT_MOUNTPOINT' is not empty"

    # Extract tarball
	einfo "Extracting stage3 tarball to '$ROOT_MOUNTPOINT'"
	tar xpf "$STAGE3_FILE" --xattrs --numeric-owner \
		|| die "Error while extracting tarball"

    popd
}

mount_fs() {
    einfo "Mounting root filesystem"
    mkdir -p "$ROOT_MOUNTPOINT"
    mount "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-root" "$ROOT_MOUNTPOINT"
}

mount_other_fs() {
    einfo "Mounting EFI filesystem"
    mkdir -p "$ROOT_MOUNTPOINT/boot/efi"
    mount "$DISK_EFI_PART" "$ROOT_MOUNTPOINT/boot/efi"

    einfo "Mounting home filesystem"
    mkdir -p "$ROOT_MOUNTPOINT/home"
    mount "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-home" "$ROOT_MOUNTPOINT/home"

    einfo "Mounting swap filesystem"
    swapon "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-swap"
}

mount_fs
extract_rootfs $1
mount_other_fs

