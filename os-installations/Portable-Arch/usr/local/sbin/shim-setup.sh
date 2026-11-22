#!/bin/sh
#
# shim-setup.sh install|remove
#
# Portable system: puts shim at the default boot path (/EFI/BOOT/BOOTX64.EFI),
# with MokManager next to it, so no computer needs a boot entry in its NVRAM.
# shim loads "grubx64.efi" from its own folder, which is where
# systemd-boot-setup-shim.sh puts the MOK-signed systemd-boot. bootctl update
# then skips BOOTX64.EFI, since it's owned by another boot loader.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim

set -eu   # a failure shows up in pacman's output

src=/usr/share/shim-signed
dest=/boot/EFI/BOOT

# copy FROM TO: copies src/FROM to dest/TO through a temporary file, so an
# interrupted run never leaves a broken binary in the ESP.
copy() {
    cp -fv "$1" "${dest}/$2.tmp"
    mv -fv "${dest}/$2.tmp" "${dest}/$2"
}

case "${1:-}" in
    install)
        mkdir -vp "${dest}"
        copy "${src}/shimx64.efi" BOOTX64.EFI
        copy "${src}/mmx64.efi" mmx64.efi
        # shim is useless without the signed systemd-boot next to it
        /usr/local/sbin/systemd-boot-setup-shim.sh
        ;;
    remove)
        # Hand the default boot path back to systemd-boot
        copy /boot/EFI/systemd/systemd-bootx64.efi BOOTX64.EFI
        rm -fv "${dest}/mmx64.efi"
        ;;
    *)
        echo "Usage: $0 install|remove" >&2
        exit 2
        ;;
esac
sync
