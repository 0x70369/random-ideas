#!/bin/sh

# libvirt hook: load the kvmfr module (Looking Glass's shared memory) while
# the VMs below run, and unload it afterwards.
## https://libvirt.org/hooks.html
## https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#KVMFR_module

OBJECT="$1"
OPERATION="$2"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never
# writes to a closed pipe.
cat > /dev/null

case "${OBJECT}" in
    "Bosta11-bare-metal" | "Bosta10") ;;
    *) exit 0 ;;
esac

# -s logs errors to syslog, where the hook's output would be lost
case "${OPERATION}" in
    prepare) modprobe -s kvmfr ;;
    release) modprobe -sr kvmfr ;;
    *) ;;
esac
