# physical partitions configuration
DISK_EFI_PART="/dev/sdx1"
DISK_ROOT_PART="/dev/sdx2"

# root (LVM2) partition configuration
LUKS_ROOT_NAME="cryptlvm"
LVM_LV_SWAP_SIZE="16G"
LVM_LV_ROOT_SIZE="40%FREE"
LVM_LV_HOME_SIZE="100%FREE"
LVM_VG_NAME="gentoo-vg"
LVM_LV_NAME="gentoo"

# Gentoo stage3 configuration
GENTOO_MIRROR="https://mirror.wheel.sk/gentoo"
GENTOO_ARCH="amd64"
STAGE3_VARIANT="musl-hardened"
STAGE3_BASENAME="stage3-$GENTOO_ARCH-$STAGE3_VARIANT"

# Secure boot configuration
SBOOT_CN_PREFIX="Bentobox"
SBOOT_KEY_DIR="/root/secureboot"

# Setup configuration
ROOT_MOUNTPOINT="/mnt/gentoo"

HOSTNAME="gentoo"
TIMEZONE="Europe/Bratislava"
KEYMAP="us"
PROFILE="37" # default/linux/amd64/17.0/musl/hardened
#PROFILE="38" # default/linux/amd64/17.0/musl/hardened/selinux

MUSL="true"
HARDENING="true"
USERNAME="jinx"
