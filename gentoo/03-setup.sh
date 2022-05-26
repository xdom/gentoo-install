#!/usr/bin/env bash
source common.sh
source config.sh

set -euo pipefail

GENTOO_INSTALL_REPO_BIND="/tmp/gentoo-install/bind"

bind_repo_dir() {
# Use new location by default
	export GENTOO_INSTALL_REPO_DIR="$GENTOO_INSTALL_REPO_BIND"
    GENTOO_INSTALL_REPO_DIR_ORIGINAL="$(cd $(dirname "${BASH_SOURCE[0]}") && pwd)"

	# Bind the repo dir to a location in /tmp,
	# so it can be accessed from within the chroot
	mountpoint -q -- "$GENTOO_INSTALL_REPO_BIND" \
		&& return

	# Mount root device
	einfo "Bind mounting repo directory"
	mkdir -p "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not create mountpoint directory '$GENTOO_INSTALL_REPO_BIND'"
	mount --bind "$GENTOO_INSTALL_REPO_DIR_ORIGINAL" "$GENTOO_INSTALL_REPO_BIND" \
		|| die "Could not bind mount '$GENTOO_INSTALL_REPO_DIR_ORIGINAL' to '$GENTOO_INSTALL_REPO_BIND'"
}

generate_fstab() {
    einfo "Generating fstab"
    genfstab -U "$ROOT_MOUNTPOINT" > "${ROOT_MOUNTPOINT}/etc/fstab"
}

# $1: root directory
# $@: command...
gentoo_chroot() {
	if [[ $# -eq 1 ]]; then
		einfo "To later unmount all virtual filesystems, simply use umount -l ${1@Q}"
		gentoo_chroot "$1" /bin/bash --init-file <(echo 'init_bash')
	fi

	[[ ${EXECUTED_IN_CHROOT-false} == "false" ]] \
		|| die "Already in chroot"

	local chroot_dir="$1"
	shift

	# Bind repo directory to tmp
	bind_repo_dir

	# Copy resolv.conf
	einfo "Preparing chroot environment"
	install --mode=0644 /etc/resolv.conf "$chroot_dir/etc/resolv.conf" \
		|| die "Could not copy resolv.conf"

	# Mount virtual filesystems
	einfo "Mounting virtual filesystems"
	(
		mountpoint -q -- "$chroot_dir/proc" || mount -t proc /proc "$chroot_dir/proc" || exit 1
		mountpoint -q -- "$chroot_dir/tmp"  || mount --rbind /tmp  "$chroot_dir/tmp"  || exit 1
		mountpoint -q -- "$chroot_dir/sys"  || {
			mount --rbind /sys  "$chroot_dir/sys" &&
			mount --make-rslave "$chroot_dir/sys"; } || exit 1
		mountpoint -q -- "$chroot_dir/dev"  || {
			mount --rbind /dev  "$chroot_dir/dev" &&
			mount --make-rslave "$chroot_dir/dev"; } || exit 1
	) || die "Could not mount virtual filesystems"

	# Execute command
	einfo "Chrooting..."
	EXECUTED_IN_CHROOT=true \
		exec chroot -- "$chroot_dir" "$GENTOO_INSTALL_REPO_DIR/dispatch-chroot.sh" "$@" \
			|| die "Failed to chroot into '$chroot_dir'."
}

bind_repo_dir
mount_efivars
generate_fstab
gentoo_chroot "$ROOT_MOUNTPOINT" "$GENTOO_INSTALL_REPO_DIR/_setup.sh"

