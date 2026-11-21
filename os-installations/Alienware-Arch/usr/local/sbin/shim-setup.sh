#!/bin/sh
#
# shim-setup.sh install|remove
#
# Copies shim and MokManager next to systemd-boot in the ESP (/EFI/systemd),
# or removes them. shim loads "grubx64.efi" from its own folder, which is
# where systemd-boot-setup-shim.sh puts the MOK-signed systemd-boot.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim

set -eu   # a failure shows up in pacman's output

src=/usr/share/shim-signed
dest=/boot/EFI/systemd

# copy FILE: copies FILE from src to dest through a temporary file, so an
# interrupted run never leaves a broken binary in the ESP.
copy() {
    cp -f "${src}/$1" "${dest}/$1.tmp"
    mv -f "${dest}/$1.tmp" "${dest}/$1"
    echo "Copied ${src}/$1 to ${dest}/$1"
}

case "${1:-}" in
    install)
        mkdir -vp "${dest}"
        copy shimx64.efi
        copy mmx64.efi
        # shim is useless without the signed systemd-boot next to it
        /usr/local/sbin/systemd-boot-setup-shim.sh
        ;;
    remove)
        rm -vf "${dest}/shimx64.efi" "${dest}/mmx64.efi"
        ;;
    *)
        echo "Usage: $0 install|remove" >&2
        exit 2
        ;;
esac
sync
