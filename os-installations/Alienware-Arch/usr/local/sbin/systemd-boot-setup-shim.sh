#!/bin/env sh

# Sign systemd-boot with the MOK as grubx64.efi, the file shim loads from its own directory.
# Run after every systemd-boot update (ExecStartPost of systemd-boot-update.service) and by
# shim-setup.sh.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key

# Stop at the first error, so a failure shows up in the service status
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

systemd_binary="/boot/EFI/systemd/systemd-bootx64.efi"
bootloader_binary="/boot/EFI/systemd/grubx64.efi"
cert="/root/secureboot/keys/MOK/MOK.crt"

# Hash of the systemd-boot binary that was last signed.
# Used to detect systemd-boot updates, since the old signed copy stays valid after an update.
state_file="/var/lib/systemd-boot-shim/source.sha256"

current_hash=$(sha256sum "$systemd_binary" | cut -d ' ' -f 1)
saved_hash=$(cat "$state_file" 2>/dev/null || true)

# Nothing to do if the signed copy matches the current systemd-boot and its signature is valid
# (the check catches a new MOK too)
if [ "$current_hash" = "$saved_hash" ] && sbverify "$bootloader_binary" --cert "$cert" >/dev/null 2>&1; then
    exit 0
fi

/usr/local/sbin/sbsign-mok.sh "$systemd_binary" "$bootloader_binary"
sync

mkdir -vp "$(dirname "$state_file")"
printf '%s\n' "$current_hash" > "$state_file"
