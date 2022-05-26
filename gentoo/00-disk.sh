#!/usr/bin/env bash
source common.sh
source config.sh

set -euo pipefail

LUKS_ROOT_PART="/dev/mapper/$LUKS_ROOT_NAME"

lvm_size_flag() {
    [[ "$1" == *"%"* ]] && echo -n "-l" || echo -n "-L"
}

# When partition already opened, run:
# umount /mnt/gentoo
# vgchange -a n gentoo-vg
# cryptsetup close cryptlvm

if ! ask "This script formats partitions on your disk. Continue?"; then
    exit
fi

if ask "Do you want to format EFI partition '$DISK_EFI_PART'"; then
    einfo "Creating EFI filesystem"
    mkfs.fat -F32 "$DISK_EFI_PART"
else
    einfo "Skipping EFI partition formatting"
fi

einfo "Creating encrypted container on '$DISK_ROOT_PART'"
cryptsetup --type luks2 --cipher aes-xts-plain64 \
    --hash sha256 --iter-time 3000 --key-size 512 \
    --pbkdf argon2id --use-urandom --verify-passphrase \
    luksFormat "$DISK_ROOT_PART"
cryptsetup open "$DISK_ROOT_PART" "$LUKS_ROOT_NAME"

einfo "Creating LVM physical volume on '$LUKS_ROOT_PART'"
pvcreate "$LUKS_ROOT_PART"

einfo "Creating LVM volume group for '$LUKS_ROOT_PART'"
vgcreate "$LVM_VG_NAME" "$LUKS_ROOT_PART"
# vgchange -a y "$LVM_VG_NAME"

einfo "Creating LVM logical volumes in '$LVM_VG_NAME'"
lvcreate $(lvm_size_flag "$LVM_LV_SWAP_SIZE") "$LVM_LV_SWAP_SIZE" "$LVM_VG_NAME" -n "${LVM_LV_NAME}-swap"
lvcreate $(lvm_size_flag "$LVM_LV_ROOT_SIZE") "$LVM_LV_ROOT_SIZE" "$LVM_VG_NAME" -n "${LVM_LV_NAME}-root"
lvcreate $(lvm_size_flag "$LVM_LV_HOME_SIZE") "$LVM_LV_HOME_SIZE" "$LVM_VG_NAME" -n "${LVM_LV_NAME}-home"

einfo "Creating filesystems in '$LVM_VG_NAME'"
mkfs.ext4 "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-root"
mkfs.ext4 "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-home"
mkswap "/dev/$LVM_VG_NAME/${LVM_LV_NAME}-swap"

einfo "Done."

