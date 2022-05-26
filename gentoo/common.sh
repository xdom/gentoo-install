function elog() {
	echo "$*" >&2
}

function einfo() {
	echo -e "\033[1;33m$*\033[0m" >&2
}

function ewarn() {
	echo -e "\033[[1;31m! \033[1;33m$*\033[0m" >&2
}

function eerror() {
	echo -e "\033[1;31merror:\033[0m $*" >&2
}

function die() {
	eerror "$*"
	[[ -v GENTOO_INSTALL_REPO_SCRIPT_PID && $$ -ne $GENTOO_INSTALL_REPO_SCRIPT_PID ]] \
		&& kill "$GENTOO_INSTALL_REPO_SCRIPT_PID"
	exit 1
}

function download_stdout() {
    curl --silent --ssl-reqd --tlsv1.2 -- "$1"
}

function download() {
    curl --silent --progress-bar --ssl-reqd --tlsv1.2 --output "$2" -- "$1"
}

function touch_or_die() {
	touch "$2" \
		|| die "Could not touch '$2'"
	chmod "$1" "$2"
}

function mount_efivars() {
	# Skip if already mounted
	mountpoint -q -- "/sys/firmware/efi/efivars" \
		&& return

	# Mount efivars
	einfo "Mounting efivars"
	mount -t efivarfs efivarfs "/sys/firmware/efi/efivars" \
		|| die "Could not mount efivarfs"
}

function env_update() {
	env-update \
		|| die "Error in env-update"
	source /etc/profile \
		|| die "Could not source /etc/profile"
	umask 0077
}

function flush_stdin() {
	local empty_stdin
	# Unused variable is intentional.
	# shellcheck disable=SC2034
	while read -r -t 0.01 empty_stdin; do true; done
}

function ask() {
	local response
	while true; do
		flush_stdin
		read -r -p "$* (Y/n) " response \
			|| die "Error in read"
		case "${response,,}" in
			'') return 0 ;;
			y|yes) return 0 ;;
			n|no) return 1 ;;
			*) continue ;;
		esac
	done
}

