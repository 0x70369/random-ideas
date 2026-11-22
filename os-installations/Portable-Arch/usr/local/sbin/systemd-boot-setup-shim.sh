#!/bin/sh
#
# Signs systemd-boot with the MOK as grubx64.efi, the file shim loads from
# its own folder (/EFI/BOOT on the portable system). Run by shim-setup.sh
# and after every systemd-boot update, as ExecStartPost of
# systemd-boot-update.service (a drop-in created by hand, not in this
# repository).
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key

set -eu   # a failure shows up in the service status

src=/boot/EFI/systemd/systemd-bootx64.efi
dest=/boot/EFI/BOOT/grubx64.efi
cert=/root/secureboot/keys/MOK/MOK.crt

# Hash of the systemd-boot last signed. An update does not invalidate the
# old signed copy, so the hash is what detects it.
state=/var/lib/systemd-boot-shim/source.sha256

hash="$(sha256sum "${src}")"
hash=${hash%% *}
saved="$(cat "${state}" 2>/dev/null)" || saved=""

# Nothing to do if the signed copy is of the current systemd-boot and its
# signature is valid (which also catches a new MOK).
if [ "${hash}" = "${saved}" ] &&
    sbverify "${dest}" --cert "${cert}" >/dev/null 2>&1; then
    exit 0
fi

/usr/local/sbin/sbsign-mok.sh "${src}" "${dest}"
sync
mkdir -vp "${state%/*}"
printf '%s\n' "${hash}" >"${state}"
