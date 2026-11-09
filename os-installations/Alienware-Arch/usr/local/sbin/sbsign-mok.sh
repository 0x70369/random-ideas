#!/bin/env sh

# Sign an EFI binary with the MOK, so shim accepts it when Secure Boot is enabled.
# Used by the pacman hooks of fwupd and memtest86+, and by systemd-boot-setup-shim.sh.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key
#
# Usage: sbsign-mok.sh INPUT [OUTPUT]
# Without OUTPUT, INPUT is signed in place (skipped if it already has a valid MOK signature).

# Stop at the first error, so a failure shows up in pacman's output or in the service status
set -eu

key="/root/secureboot/keys/MOK/MOK.key"
cert="/root/secureboot/keys/MOK/MOK.crt"

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    echo "Usage: $0 INPUT [OUTPUT]" >&2
    exit 2
fi

input=$1
output=${2:-$1}

if [ "$output" = "$input" ] && sbverify "$input" --cert "$cert" >/dev/null 2>&1; then
    echo "$input is already signed"
    exit 0
fi

# Sign into a temporary file first, so an interrupted run never leaves a broken binary behind
tmp="$output.tmp"
trap 'rm -vf "$tmp"' EXIT

sbsign "$input" --key "$key" --cert "$cert" --output "$tmp"
sbverify --cert "$cert" "$tmp" >/dev/null
mv -vf "$tmp" "$output"

echo "Signed $input as $output"
