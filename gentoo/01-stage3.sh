#!/usr/bin/env bash
source common.sh
source config.sh

set -euo pipefail

download_stage3() {
    local TMP_DIR="$PWD/stage3"
    mkdir -p "$TMP_DIR"
	cd "$TMP_DIR" \
		|| die "Could not cd into '$TMP_DIR'"

    local STAGE3_BASEURL="$GENTOO_MIRROR/releases/$GENTOO_ARCH/autobuilds"
    local STAGE3_LATEST="$STAGE3_BASEURL/latest-$STAGE3_BASENAME.txt"

	# Fetch latest stage3 version
    einfo "Fetching version of latest $STAGE3_BASENAME tarball"
	local CURRENT_STAGE3="$(download_stdout "$STAGE3_LATEST" \
        | grep -v '^#' | head -n1 | cut -d' ' -f1 \
        || die "Could not retrieve latest stage3 tarball version")"
    elog "$CURRENT_STAGE3"
    local CURRENT_STAGE3_FILE="${CURRENT_STAGE3##*/}"

	# File to indiciate successful verification
	local CURRENT_STAGE3_VERIFIED="${CURRENT_STAGE3_FILE}.verified"

	# Download file if not already downloaded
	if [[ -e $CURRENT_STAGE3_FILE && -e $CURRENT_STAGE3_VERIFIED ]]; then
		einfo "$STAGE3_BASENAME tarball already downloaded and verified"
	else
		einfo "Downloading latest $STAGE3_BASENAME tarball"
		download "$STAGE3_BASEURL/${CURRENT_STAGE3}" "${CURRENT_STAGE3_FILE}"
		download "$STAGE3_BASEURL/${CURRENT_STAGE3}.asc" "${CURRENT_STAGE3_FILE}.asc"
		download "$STAGE3_BASEURL/${CURRENT_STAGE3}.DIGESTS" "${CURRENT_STAGE3_FILE}.DIGESTS"

		# Import gentoo keys
		einfo "Importing gentoo gpg key"
		local GENTOO_GPG_KEY="$TMP_DIR/gentoo-keys.gpg"
        gpg --quiet --keyserver hkps://keys.gentoo.org --recv-keys 0xBB572E0E2D182910 \
			|| die "Could not import gentoo gpg key"

		# Verify asc signature
		einfo "Verifying tarball signature"
		gpg --quiet --verify "${CURRENT_STAGE3_FILE}.asc" \
			|| die "Signature of '${CURRENT_STAGE3_FILE}.asc' invalid!"

		# Verify DIGESTS signature
		einfo "Verifying tarball checksums signature"
		gpg --quiet --verify "${CURRENT_STAGE3_FILE}.DIGESTS" \
			|| die "Signature of '${CURRENT_STAGE3_FILE}.DIGESTS' invalid!"

		# Check hashes
		einfo "Verifying tarball integrity"
        sha512sum --check --ignore-missing "${CURRENT_STAGE3_FILE}.DIGESTS" \
			|| die "Checksums of '${CURRENT_STAGE3_FILE}' mismatch!"

		# Create verification file in case the script is restarted
		touch_or_die 0644 "$CURRENT_STAGE3_VERIFIED"
	fi

    # Print tarball path
    export STAGE3_FILE="$(realpath "$CURRENT_STAGE3_FILE")"
    echo "$STAGE3_FILE"
    einfo "Done."
}

download_stage3

