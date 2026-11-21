#!/bin/sh
#
# sbsign-mok.sh INPUT [OUTPUT]
#
# Signs an EFI binary with the MOK, so shim accepts it with Secure Boot on.
# Without OUTPUT, INPUT is signed in place, unless it already has a valid
# MOK signature. Used by the pacman hooks of fwupd and memtest86+, the
# mkinitcpio post hooks and systemd-boot-setup-shim.sh.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key

set -eu   # a failure shows up in pacman's output or the service status

key=/root/secureboot/keys/MOK/MOK.key
cert=/root/secureboot/keys/MOK/MOK.crt

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 INPUT [OUTPUT]" >&2
    exit 2
fi
input=$1
output=${2:-$1}

if [ "${output}" = "${input}" ] &&
    sbverify "${input}" --cert "${cert}" >/dev/null 2>&1; then
    echo "${input} is already signed"
    exit 0
fi

# Signed into a temporary file first: an interrupted run never leaves a
# broken binary behind.
tmp="${output}.tmp"
trap 'rm -f "${tmp}"' EXIT
sbsign "${input}" --key "${key}" --cert "${cert}" --output "${tmp}"
sbverify --cert "${cert}" "${tmp}" >/dev/null
mv -vf "${tmp}" "${output}"
echo "Signed ${input} as ${output}"
