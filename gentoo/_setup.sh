#!/usr/bin/env bash
cd $(dirname "${BASH_SOURCE[0]}")

source common.sh
source config.sh

set -euo pipefail

[[ $EXECUTED_IN_CHROOT != "true" ]] \
	&& { echo "This script must not be executed directly!" >&2; exit 1; }

function get_cmdline() {
	DISK_ROOT_PART_UUID="$(lsblk -rno UUID "$DISK_ROOT_PART" | head -n1 2>/dev/null)"

	local cmdline
	cmdline=("root=/dev/${LVM_VG_NAME}/${LVM_LV_NAME}-root")
	cmdline+=("rd.luks.uuid=${DISK_ROOT_PART_UUID}")

	# Kernel hardening
	if [[ $HARDENING == "true" ]]; then
	    # Disable slab merging
		cmdline+=("slab_nomerge")
		# Enable sanity checks (F) and redzoning (Z)
		cmdline+=("slub_debug=FZ")
		# Enable zeroing of memory during allocation and free time (since kernel 5.3)
		cmdline+=("init_on_alloc=1 init_on_free=1")
		# Randomize page allocator freelists, improving security by making page allocations less predictable
		cmdline+=("page_alloc.shuffle=1")
		# Randomize kernel stack
		cmdline+=("randomize_kstack_offset=1")
		# Enable Kernel Page Table Isolation which mitigates Meltdown and prevents some KASLR bypasses
		cmdline+=("pti=on")
		# Disable vsyscalls as they are obsolete and have been replaced with vDSO
		cmdline+=("vsyscall=none")
		# Disables debugfs which exposes a lot of sensitive information about the kernel
		cmdline+=("debugfs=off")
		# Make kernel oops (caused by exploits) cause kernel panic (disable this when your drivers keep crashing kernel)
		cmdline+=("oops=panic")
		# Allow loading only signed kernel modules
		cmdline+=("module.sig_enforce=1")
		# Lockdown kernel in confidentiality mode
		cmdline+=("lockdown=confidentiality")
		# Cause kernel to panic on uncorrectable errors in ECC memory which could be exploited
		cmdline+=("mce=0")
		# Silence boot logs to prevent leakage of sensitive information
		cmdline+=("quiet loglevel=0")
		# Mitigate CPU vulnerabilities
		cmdline+=("spectre_v2=on spec_store_bypass_disable=on")
		cmdline+=("tsx=off tsx_async_abort=full,nosmt mds=full,nosmt l1tf=full,force nosmt=force kvm.nx_huge_pages=force")
		cmdline+=("l1tf=full,force l1d_flush=on")
		# Mitigate DMA attacks
		cmdline+=("intel_iommu=on efi=disable_early_pci_dma")
		# Disable IPv6 (can be done in sysctl as well)
		cmdline+=("ipv6.disable=1")
		# Enable SELinux
		cmdline+=("selinux=1 lsm=landlock,lockdown,yama,selinux,bpf")
	fi

	echo -n "${cmdline[*]}"
}

mount_efivars

einfo "Configuring Portage"
cat <<EOF >> /etc/portage/make.conf
MAKEOPTS="${MAKEFLAGS:--j16}"
GENTOO_MIRRORS="$GENTOO_MIRROR"
ACCEPT_LICENSE="@BINARY-REDISTRIBUTABLE"
EOF
install -m0600 -o root -g root "contrib/package.use" /etc/portage/package.use/custom \
    || die "Could not install /etc/portage/package.use/custom"
emerge-webrsync
emerge --verbose dev-vcs/git app-eselect/eselect-repository
eselect profile set --force "$PROFILE"
if [[ "$MUSL" == "true" ]]; then
    eselect repository enable musl
    emerge --sync
fi
# emerge --verbose --update --deep --newuse @world

einfo "Setting hostname"
echo "$HOSTNAME" > /etc/hostname \
    || die "Could not write /etc/hostname"

einfo "Setting timezone"
echo "$TIMEZONE" > /etc/timezone \
    || die "Could not write /etc/timezone"
emerge -v --config sys-libs/timezone-data

einfo "Setting keymap"
sed -i "/keymap=/c\\keymap=\"$KEYMAP\"" /etc/conf.d/keymaps \
    || die "Could not sed replace in /etc/conf.d/keymaps"

env_update

if ask "Configure secure boot?"; then
    einfo "Backing up EFI vars"
    mkdir -p "$SBOOT_KEY_DIR"
    sb_backup_dir="${SBOOT_KEY_DIR}/backup/$(date +%Y%m%d%H%M%S)"
    mkdir -p "$sb_backup_dir"
    efi-readvar -v PK -o "${sb_backup_dir}/PK.esl"
    efi-readvar -v KEK -o "${sb_backup_dir}/KEK.esl"
    efi-readvar -v db -o "${sb_backup_dir}/db.esl"
    efi-readvar -v dbx -o "${sb_backup_dir}/dbx.esl"
    
    einfo "Generating new keys"
    pushd "$SBOOT_KEY_DIR"
    uuidgen --random > GUID.txt
    # Platform key
    openssl req -newkey rsa:4096 -nodes -keyout PK.key -new -x509 -sha256 -days 3650 -subj "/CN=$SBOOT_CN_PREFIX Platform Key/" -out PK.crt
    openssl x509 -outform DER -in PK.crt -out PK.cer
    cert-to-efi-sig-list -g "$(< GUID.txt)" PK.crt PK.esl
    sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt PK PK.esl PK.auth
    # Sign an empty file to allow removing Platform Key when in "User Mode"
    sign-efi-sig-list -g "$(< GUID.txt)" -c PK.crt -k PK.key PK /dev/null rm_PK.auth
    # Key Exchange Key
    openssl req -newkey rsa:4096 -nodes -keyout KEK.key -new -x509 -sha256 -days 3650 -subj "/CN=$SBOOT_CN_PREFIX Key Exchange Key/" -out KEK.crt
    openssl x509 -outform DER -in KEK.crt -out KEK.cer
    cert-to-efi-sig-list -g "$(< GUID.txt)" KEK.crt KEK.esl
    sign-efi-sig-list -g "$(< GUID.txt)" -k PK.key -c PK.crt KEK KEK.esl KEK.auth
    # Signature Database key
    openssl req -newkey rsa:4096 -nodes -keyout db.key -new -x509 -sha256 -days 3650 -subj "/CN=$SBOOT_CN_PREFIX Signature Database Key/" -out db.crt
    openssl x509 -outform DER -in db.crt -out db.cer
    cert-to-efi-sig-list -g "$(< GUID.txt)" db.crt db.esl
    sign-efi-sig-list -g "$(< GUID.txt)" -k KEK.key -c KEK.crt db db.esl db.auth
    einfo "Secure boot keys generated"

    einfo "To enroll new keys, you need to be in setup mode, i.e. PK must be deleted from EFI firmware"
    if ask "Enroll new secure boot keys?"; then
        mkdir -p /etc/secureboot/keys/{db,dbx,KEK,PK}
        for file in PK KEK db; do
            cp "${file}.auth" /etc/secureboot/keys/$file/
        done
        sbkeysync --pk --dry-run --verbose
        ask "Continue?" \
            && sbkeysync --verbose \
            && sbkeysync --verbose --pk \
            && echo "Done"
    fi

    if ask "Sign and add Microsoft certificates to Signature Database?"; then
        ms_certs_path="$(mktemp -d)"
        pushd "$ms_certs_path"
        download "https://www.microsoft.com/pkiops/certs/MicWinProPCA2011_2011-10-19.crt" \
            MicWinProPCA2011_2011-10-19.crt
        download "https://www.microsoft.com/pkiops/certs/MicCorUEFCA2011_2011-06-27.crt" \
            MicCorUEFCA2011_2011-06-27.crt
        sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 \
            --output MS_Win_db.esl MicWinProPCA2011_2011-10-19.crt
        sbsiglist --owner 77fa9abd-0359-4d32-bd60-28f4e78f784b --type x509 \
            --output MS_UEFI_db.esl MicCorUEFCA2011_2011-06-27.crt
        cat MS_Win_db.esl MS_UEFI_db.esl > MS_db.esl
        popd
        sign-efi-sig-list -a -g 77fa9abd-0359-4d32-bd60-28f4e78f784b \
            -k KEK.key -c KEK.crt db "${ms_certs_path}/MS_db.esl" add_MS_db.auth
        rm -r "${ms_certs_path}"
        cp add_MS_db.auth /etc/secureboot/keys/db/
        sbkeysync --pk --dry-run --verbose
        ask "Continue?" \
            && sbkeysync --verbose \
            && echo "Done"
    fi
fi

einfo "Installing kernel"
# TODO: Think about using mkinitcpio (needs build or portage overlay)
# TODO: Extract to contrib/ folder
mkdir -p /etc/dracut.conf.d
cat <<EOF > /etc/dracut.conf.d/crypt.conf
add_dracutmodules+=" crypt dm lvm "
EOF
cat <<EOF > /etc/dracut.conf.d/gpu.conf
add_drivers+=" amdgpu "
EOF
# FIXME: Add support for LZ4 compression (both build-time and compile into kernel)
cat <<EOF > /etc/dracut.conf.d/cmdline.conf
#compress="lz4"
kernel_cmdline="$(get_cmdline)"
EOF
cat <<EOF > /etc/dracut.conf.d/secureboot.conf
uefi="yes"
uefi_stub="/usr/lib/systemd/boot/efi/linuxx64.efi.stub"
uefi_secureboot_key="/root/secureboot/db.key"
uefi_secureboot_cert="/root/secureboot/db.crt"
EOF
emerge --verbose sys-fs/cryptsetup \
    sys-apps/systemd-utils \
    sys-kernel/installkernel-gentoo \
    sys-kernel/gentoo-kernel-bin \
    sys-kernel/linux-firmware \
    sys-firmware/intel-microcode \
    sys-boot/efibootmgr \
    app-crypt/efitools \
    app-crypt/sbsigntools

# FIXME: Set up secure boot
# FIXME: Set up something like mkinitcpio-chkcryptoboot

einfo "Installing bootloader"
efi_disk=$(lsblk -ndo pkname "$DISK_EFI_PART")
efi_bin="/boot/efi/EFI/gentoo/gentoo-x64.efi"
latest_kernel=$(ls -A1t /boot/vmlinuz* | head -n 1)
mkdir -p "${efi_bin%*/}"
mv "${latest_kernel}" "${efi_bin}"
efibootmgr --verbose --create --disk "$efi_disk" \
	--part "${DISK_EFI_PART: -1}" --label "Gentoo" \
	--loader "\\EFI\\Linux\\${efi_bin##*/}" # \
	# --unicode "$(get_cmdline)"
cat > "/usr/local/bin/gen-efibootmgr.sh" <<EOF
#!/bin/bash
efibootmgr --verbose --create --disk "$efi_disk" \
	--part "${DISK_EFI_PART: -1}" --label "Gentoo" \
	--loader "\\EFI\\Linux\\${efi_bin##*/}" # \
	# --unicode "$(get_cmdline)"
EOF

einfo "Hardening doas"
cat <<EOF > /etc/doas.conf
permit admin as root
EOF

einfo "Installing system packages"
emerge --verbose net-firewall/nftables \
    app-shells/zsh \
    app-admin/doas

einfo "Hardening"
# FIXME: Harden fstab (readonly boot, noexec, nosuid, nodev, hidepid, etc)
# FIXME: Install and harden sshd
# FIXME: Set up nftables firewall
einfo "Hardening sysctl parameters"
install -m0600 -o root -g root "contrib/99-hardening.conf" /etc/sysctl.d/99-hardening.conf \
    || die "Could not install /etc/sysctl.d/99-hardening.conf"

einfo "Hardening accounts"
mkdir -p /etc/pam.d
echo "password required pam_unix.so sha512 shadow nullok rounds=65536" >> /etc/pam.d/passwd
echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su
echo "auth required pam_wheel.so use_uid" >> /etc/pam.d/su-l
chmod -R go-rwx /home/*
chmod -R go-rwx /boot /usr/src /lib/modules /usr/lib/modules || true

if ask "Install additional packages?"; then
    einfo "Installing additional packages"
    emerge --verbose app-admin/ansible \
        sys-auth/seatd \
        gui-wm/sway \
        x11-terms/alacritty
    # FIXME: Move to ansible script
    #emerge --verbose gui-apps/waypipe \
    #    net-dns/dnsmasq \
    #    net-firewall/nftables \
    #    sys-apps/dmidecode \
    #    app-emulation/libvirt \
    #    app-emulation/qemu \
    #    app-emulation/vagrant
fi

einfo "Configuring users"
useradd -m -G users,wheel,audio,portage,video,seat -s /bin/bash admin
useradd -m -G users,audio,video,seat -s /bin/zsh "$USERNAME"
passwd admin
passwd "$USERNAME"

# FIXME: Lock root user
passwd -l root
