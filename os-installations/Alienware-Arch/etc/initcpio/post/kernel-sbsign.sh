#!/bin/sh
# mkinitcpio post hook: sign the kernel with the MOK.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key
# $1 is the kernel image; KERNELDESTINATION is set when mkinitcpio copied it elsewhere.
kernel=${KERNELDESTINATION:-$1}
[ -f "$kernel" ] || exit 0
exec /usr/local/sbin/sbsign-mok.sh "$kernel"
