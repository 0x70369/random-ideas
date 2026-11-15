#!/bin/env sh

# Called by /etc/pacman.d/hooks/95-grub.hook with the matched packages on stdin.
#   - grub installed or upgraded: reinstalls GRUB into the drive's MBR and BIOS boot partition, so
#     the core image matches the new modules, then regenerates grub.cfg;
#   - a kernel or memtest86+ installed or removed: only regenerates grub.cfg.
# The drive is found from the ESP mounted at /boot, so it doesn't depend on its /dev/sdX letter.

set -eu

die() {
    printf 'grub-update: %s; GRUB not updated.\n' "$1" >&2
    exit 1
}

command -v grub-install > /dev/null || exit 0

ls /boot > /dev/null   # triggers an automount of the ESP, if there is one

esp=$(findmnt -n -o SOURCE -t vfat /boot | head -n 1)
[ -n "$esp" ] || die "the ESP isn't mounted at /boot"

disk=$(lsblk -n -p -o PKNAME "$esp")
[ -b "$disk" ] || die "couldn't find the disk of $esp"

if grep -qx grub; then
    grub-install --target=i386-pc --boot-directory=/boot "$disk"
fi
grub-mkconfig -o /boot/grub/grub.cfg