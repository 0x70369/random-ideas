#!/bin/sh
#
# Run by 95-grub-update.hook, with the matched packages on stdin. When grub
# itself changed, reinstalls it in the boot drive's MBR and BIOS boot
# partition, so the core image matches the new modules. Always regenerates
# grub.cfg. The drive is the one holding the ESP mounted at /boot, so its
# /dev/sdX letter does not matter.

set -eu

command -v grub-install >/dev/null || exit 0
ls /boot >/dev/null   # triggers the ESP's automount, if there is one
esp="$(findmnt -n -o SOURCE -t vfat /boot | head -n 1)"
disk="$(lsblk -n -p -o PKNAME "${esp:-?}" 2>/dev/null)" || disk=""
if [ ! -b "${disk}" ]; then
    echo "grub-update: no ESP mounted at /boot; GRUB not updated." >&2
    exit 1
fi

if grep -qx grub; then
    grub-install --target=i386-pc --boot-directory=/boot "${disk}"
fi
grub-mkconfig -o /boot/grub/grub.cfg
