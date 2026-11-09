#!/bin/env sh

# Copy shim and MokManager next to systemd-boot in the ESP (/EFI/systemd), and remove them again.
# shim loads "grubx64.efi" from its own directory, which is where systemd-boot-setup-shim.sh
# puts the MOK-signed systemd-boot.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim
#
# Usage: shim-setup.sh install|remove

# Stop at the first error, so a failure shows up in pacman's output
set -eu

if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root." >&2
    exit 1
fi

shim_binary="/usr/share/shim-signed/shimx64.efi"
mm_binary="/usr/share/shim-signed/mmx64.efi"

boot_dir="/boot/EFI/systemd"
boot_shim_binary="$boot_dir/shimx64.efi"
boot_mm_binary="$boot_dir/mmx64.efi"

# Disabled: fwupd has no option to set the shim path and, depending on its version, looks in
# /EFI/systemd or in /EFI/<os-release ID>. Uncomment the "##" lines if UEFI capsule updates
# can't find shim.
##fwupd_shim_binary="/boot/EFI/arch/shimx64.efi"

# Copy a file through a temporary one, so an interrupted run never leaves a broken binary in the ESP
safe_copy() {
    cp -f "$1" "$2.tmp" || { rm -f "$2.tmp"; return 1; }
    mv -f "$2.tmp" "$2"
    echo "Copied $1 to $2"
}

case "${1:-}" in
    install)
        mkdir -vp "$boot_dir"
        safe_copy "$shim_binary" "$boot_shim_binary"
        safe_copy "$mm_binary" "$boot_mm_binary"
        ##mkdir -p "$(dirname "$fwupd_shim_binary")"
        ##safe_copy "$shim_binary" "$fwupd_shim_binary"

        # shim is useless without the signed systemd-boot next to it
        /usr/local/sbin/systemd-boot-setup-shim.sh
        sync
        ;;

    remove)
        rm -vf "$boot_shim_binary" "$boot_mm_binary"
        ##rm -vf "$fwupd_shim_binary"
        ##rmdir "$(dirname "$fwupd_shim_binary")" 2>/dev/null || true
        sync
        ;;

    *)
        echo "Usage: $0 install|remove" >&2
        exit 2
        ;;
esac
