# Gentoo host workspace

This folder contains a set of scripts which
help to set up Gentoo host machine.

## Getting started

Boot from Archlinux live USB.

Partition disks:

```shell
fdisk /dev/sda
# `m` for help
# `g` to create GPT partition table
# `n` to add a partition (you need
# at least two partitions, EFI and root)
# `w` to write changes to disk
```

Install utilities and download this repository:

```shell
pacman -Sy --noconfirm git wget
git clone https://github.com/xdom/workspace
```

Run setup scripts:

```shell
./00-disk.sh
./01-stage3.sh
./02-rootfs.sh
./03-setup.sh
```

Reboot and job's done.

## Description

Every script has it's specific task.

### 00-disk.sh

Creates filesystems on already existing physical
partitions like this:

- EFI partition (`DISK_EFI_PART`)
    - Optionally creates an ext4 filesystem
- Root partition (`DISK_ROOT_PART`)
    - Creates a LUKS2 encrypted container
    - Creates an LVM volume group for the partition
    - Creates three logical volumes (root, home, swap)
    - Creates an ext4 filesystem for root and home logical volumes

### 01-stage3.sh

Downloads latest Gentoo stage3 archive specified
by `GENTOO_ARCH` and `STAGE3_VARIANT` from `GENTOO_MIRROR`.

### 02-rootfs.sh

Mounts a root LV at `ROOT_MOUNTPOINT` and extracts
the stage3 archive to it.

Then mounts boot, EFI, home and swap
volumes.

### 03-setup.sh

Binds installation scripts at tmpfs to be accessible
inside chroot. Generates `/etc/fstab` file for Gentoo.

Chroots into the `ROOT_MOUNTPOINT` and start
installation process there. More specifically:

- Configures Portage (Gentoo package management)
- Sets hostname, timezone and keymap
- Installs root partition keyfile (which will be baked into initrd)
- Installs kernel and initrd
- Installs GRUB bootloader
- Performs hardening tasks
- Installs packages
- Creates users

## TBD

- Custom Kernel configuration
- Run ansible-playbook to set up virtualization
- Using Vagrant w/SSH X forwarding and Waypipe

