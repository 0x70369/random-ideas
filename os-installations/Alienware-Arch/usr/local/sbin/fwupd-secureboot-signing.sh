#!/bin/env sh

# Sign fwupd's EFI capsule loader with the MOK, so shim accepts it when Secure Boot is enabled.
# fwupd looks for "fwupdx64.efi.signed" whenever Secure Boot is on, and refuses UEFI capsule updates without it.
## https://wiki.archlinux.org/title/Fwupd#Secure_Boot

# Stop at the first error, so a failure shows up in pacman's output
set -eu

# Refuse to run without root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

efi_binary="/usr/lib/fwupd/efi/fwupdx64.efi"
signed_binary="$efi_binary.signed"

key="/root/secureboot/keys/MOK/MOK.key"
cert="/root/secureboot/keys/MOK/MOK.crt"

# Sign into a temporary file first, so an interrupted run never leaves a broken signed binary behind
tmp_binary="$signed_binary.tmp"
trap 'rm -vf "$tmp_binary"' EXIT

sbsign "$efi_binary" --key "$key" --cert "$cert" --output "$tmp_binary" 
sbverify "$tmp_binary" --cert "$cert"  >/dev/null
mv -vf "$tmp_binary" "$signed_binary"

echo "Signed $efi_binary as $signed_binary"