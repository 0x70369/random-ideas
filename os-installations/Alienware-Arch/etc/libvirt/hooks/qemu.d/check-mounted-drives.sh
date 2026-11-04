#!/bin/env sh

# libvirt hook for the uindouls 11 VM:
# - refuses to start a VM that uses a physical drive while any of its partitions is mounted on the host;
## https://libvirt.org/hooks.html
## https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Dynamically_isolating_CPUs

OBJECT="$1"
OPERATION="$2"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
cat > /dev/null

# Physical drive used by the VM. Use the same path as the <source dev="..."/> in the VM's XML.
UINDOULS_DRIVE="/dev/disk/by-id/CHANGE_ME"

# Abort the VM's start if the drive or any of its partitions is mounted on the host,
# since both systems writing to the same filesystem would corrupt it
refuse_if_disk_mounted() {
    mountpoints=$(lsblk --noheadings --raw --output MOUNTPOINTS -- "$UINDOULS_DRIVE" 2>/dev/null)

    case "$mountpoints" in
        *[![:space:]]*)
            echo "$UINDOULS_DRIVE is mounted on the host (at: $(echo "$mountpoints" | tr '\n' ' ')). Unmount it before starting $OBJECT." >&2
            exit 1
            ;;
    esac
}

case "$OBJECT" in
    "Bosta11-bare-metal")
        case "$OPERATION" in
            prepare) refuse_if_disk_mounted ;;

            *) exit 0 ;;
        esac
        ;;

    *) exit 0 ;;
esac