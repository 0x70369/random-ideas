#!/bin/env sh

shim_binary="/usr/share/shim-signed/shimx64.efi"
mm_binary="/usr/share/shim-signed/mmx64.efi"

OPERATION="$1"

boot_shim_binary="/boot/EFI/BOOT/BOOTX64.EFI"
boot_mm_binary="/boot/EFI/BOOT/mmx64.efi"

case "$OPERATION" in
    install)
        mkdir -p /boot/EFI/BOOT
        cp "$shim_binary" "$boot_shim_binary" -vf
        cp "$mm_binary" "$boot_mm_binary" -vf
        ;;
        
    remove)
        rm "$boot_shim_binary" -vf
        rm "$boot_mm_binary" -vf
        ;;
        
    *) exit 0 ;;
        
esac
