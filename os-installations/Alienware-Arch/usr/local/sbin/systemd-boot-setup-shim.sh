#!/bin/env sh

# Inspired by https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key

systemd_binary="/boot/EFI/systemd/systemd-bootx64.efi"
key="/root/secureboot/keys/MOK/MOK.key"
cert="/root/secureboot/keys/MOK/MOK.crt"

bootloader_binary="/boot/EFI/BOOT/grubx64.efi"

if ! sbverify --cert "$cert" "$bootloader_binary" >/dev/null 2>&1; then
    sbsign "$systemd_binary" --key "$key" --cert "$cert" --output "$bootloader_binary"
fi
