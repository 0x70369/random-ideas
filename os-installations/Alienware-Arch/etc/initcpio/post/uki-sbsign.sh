#!/bin/sh
# mkinitcpio post hook: sign the UKI with the MOK.
## https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot#shim_with_key
# $3 is the UKI; it is empty when the preset builds a plain initramfs.
[ -n "$3" ] || exit 0
exec /usr/local/sbin/sbsign-mok.sh "$3"
