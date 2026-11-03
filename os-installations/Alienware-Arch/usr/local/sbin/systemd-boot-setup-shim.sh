#!/bin/env sh
 
# Inspired by https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key
 
# Stop at the first error, so a failure shows up in the service status
set -eu

# Refuse to run without root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi
 
systemd_binary="/boot/EFI/systemd/systemd-bootx64.efi"
bootloader_binary="/boot/EFI/systemd/grubx64.efi"
 
key="/root/secureboot/keys/MOK/MOK.key"
cert="/root/secureboot/keys/MOK/MOK.crt"
 
# Hash of the systemd-boot binary that was last signed.
# Used to detect systemd-boot updates, since the old signed copy stays valid after an update.
state_file="/var/lib/systemd-boot-shim/source.sha256"
 
current_hash=$(sha256sum "$systemd_binary" | cut -d ' ' -f 1)
saved_hash=$(cat "$state_file" 2>/dev/null || true)
 
# Nothing to do if the signed copy matches the current systemd-boot and its signature is valid
if [ "$current_hash" = "$saved_hash" ] && sbverify "$bootloader_binary" --cert "$cert"  >/dev/null 2>&1; then
    exit 0
fi
 
# Sign into a temporary file first, so an interrupted run never leaves a broken bootloader in the ESP
tmp_binary="$bootloader_binary.tmp"
trap 'rm -vf "$tmp_binary"' EXIT
 
sbsign "$systemd_binary" --key "$key" --cert "$cert" --output "$tmp_binary" 
sbverify "$tmp_binary" --cert "$cert"  >/dev/null
mv -vf "$tmp_binary" "$bootloader_binary"
sync
 
mkdir -vp "$(dirname "$state_file")"
printf '%s\n' "$current_hash" > "$state_file"
 
echo "Signed $systemd_binary as $bootloader_binary"
