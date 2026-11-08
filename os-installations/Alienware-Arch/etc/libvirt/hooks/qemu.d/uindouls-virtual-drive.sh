#!/bin/env sh

# libvirt hook: build a virtual disk for a VM out of the Windows partitions of a drive that is shared with
# the host (e.g. a single drive with Arch and Windows), so the VM never sees the host's partitions.
#
# Layout of the virtual disk (a device-mapper device), with a fresh GPT describing it:
#   [GPT header] [VM-only ESP] [Windows partitions, in on-disk order] [backup GPT]
# The Windows partitions are found by their GPT type every time the VM starts, so partitions created,
# removed or resized by Windows (on bare metal) are picked up automatically. Their GUIDs, names and
# attributes are copied, so Windows keeps the same drive letters in the VM and on bare metal.
#
## https://libvirt.org/hooks.html
## https://docs.kernel.org/admin-guide/device-mapper/index.html
## https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/configure-uefigpt-based-hard-drive-partitions
#
# Requires: device-mapper (dmsetup), gptfdisk (sgdisk), dosfstools (mkfs.fat), util-linux, cryptsetup.

set -eu

# ------------------------------------------------------------------
# Configuration
# ------------------------------------------------------------------
# Name of the VM in libvirt
target_vm="CHANGE_ME"

# Drive holding the Windows partitions. Use the drive itself, not a partition, from /dev/disk/by-id/
windows_disk="/dev/disk/by-id/nvme-CHANGE_ME"

# The VM's disk will be /dev/mapper/$mapper_name. Use this path as <source dev="..."/> in the VM's XML.
mapper_name="windows-VM"

# ESP used only by the VM, so the host's ESP (mounted at /boot) is never exposed to it
esp_image="/var/lib/libvirt/images/$mapper_name-esp.img"
esp_size_mib=260

# GPT types of the partitions given to the VM. ESPs and Linux partitions are never included.
type_basic_data="ebd0a0a2-b9e5-4433-87c0-68b6b72699c7"
type_microsoft_reserved="e3c9e316-0b5c-4db8-817d-f92df00215ae"
type_windows_recovery="de94bba4-06d1-4d40-a16a-bfd50179d6ac"
windows_types="$type_basic_data $type_microsoft_reserved $type_windows_recovery"

# Temporary files for the GPT header and backup (recreated at every start)
state_dir="/run/libvirt-virtual-disk/$mapper_name"

# ------------------------------------------------------------------

OBJECT="${1:-}"
OPERATION="${2:-}"
SUBOPERATION="${3:-}"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
cat > /dev/null

case "$OBJECT" in
    "$target_vm") ;;
    *) exit 0 ;;
esac

mib=2048    # 1 MiB in 512-byte sectors, the unit used by lsblk's START and by device-mapper
nl='
'           # Newline, to add lines to the device-mapper table without breaking the indentation

die() {
    echo "$mapper_name: $*" >&2
    exit 1
}

# Detach every loop device backed by a file
detach_loops() {
    for loop in $(losetup --noheadings --output NAME --associated "$1" 2>/dev/null); do
        losetup --detach "$loop"
    done
}

teardown() {
    if dmsetup info "$mapper_name" >/dev/null 2>&1; then
        dmsetup remove "$mapper_name"
    fi
    for file in "$state_dir/header.img" "$state_dir/footer.img" "$esp_image"; do
        detach_loops "$file"
    done
}

# Round a number of 512-byte sectors up to the next MiB
align() {
    echo $(( ($1 + mib - 1) / mib * mib ))
}

# Windows partitions of the drive, sorted by their position on it, one path per line
windows_partitions() {
    lsblk --list --noheadings --paths --output NAME,TYPE,START,PARTTYPE -- "$windows_disk" |
    while read -r name type start parttype; do
        case "$type" in part) ;; *) continue ;; esac
        case " $windows_types " in
            *" $parttype "*) echo "$start $name" ;;
        esac
    done | sort -n | cut -d ' ' -f 2
}

# Make sure the host doesn't use a Windows partition before giving it to the VM.
# A partition can be in use without being mounted: unlocking BitLocker (cryptsetup, udisks, a file
# manager) creates a device-mapper device on top of it, which stays open after unmounting. That device
# would keep the partition busy (device-mapper can't claim it for the virtual disk) and holds decrypted
# data cached on the host. Such a device is closed here if nothing uses it anymore.
# True if the directory has at least one entry
has_entries() {
    for entry in "$1"/*; do
        [ -e "$entry" ] && return 0
    done
    return 1
}

release_partition() {
    part="$1"
    dev=$(basename "$(readlink -f -- "$part")")

    # Without --nodeps, lsblk also lists the devices on top of the partition (e.g. the unlocked volume)
    case "$(lsblk --noheadings --output MOUNTPOINTS -- "$part")" in
        *[![:space:]]*) die "$part (or its unlocked volume) is mounted on the host. Unmount it before starting $OBJECT." ;;
    esac

    for holder_path in "/sys/class/block/$dev/holders"/*; do
        [ -e "$holder_path" ] || continue
        holder="${holder_path##*/}"
        name=$(cat "/sys/class/block/$holder/dm/name" 2>/dev/null) ||
            die "$part is in use by $holder on the host. Release it before starting $OBJECT."
        uuid=$(cat "/sys/class/block/$holder/dm/uuid" 2>/dev/null || :)

        # Only encrypted volumes (BitLocker, LUKS) are closed; anything else is left to the user
        case "$uuid" in
            CRYPT-*) ;;
            *) die "$part is in use by /dev/mapper/$name on the host. Remove it before starting $OBJECT." ;;
        esac

        open=$(dmsetup info --noheadings --columns --options open "$name" | tr -d '[:space:]')
        if has_entries "/sys/class/block/$holder/holders" || [ "$open" != 0 ]; then
            die "$part is unlocked on the host as /dev/mapper/$name and still in use. Close it before starting $OBJECT."
        fi

        cryptsetup close "$name" || die "could not close /dev/mapper/$name ($part)."
        echo "$mapper_name: closed /dev/mapper/$name, which was left unlocked on the host ($part)." >&2
    done
}

build() {
    [ -b "$windows_disk" ] || die "$windows_disk not found."

    partitions=$(windows_partitions)
    [ -n "$partitions" ] || die "no Windows partitions found on $windows_disk."

    # Start from a clean state, in case a previous run was interrupted. This comes first, so a
    # leftover virtual disk isn't mistaken for a host device using the partitions.
    teardown

    # Never hand a filesystem that the host is using to the VM
    for part in $partitions; do
        release_partition "$part"
    done

    sector_size=$(blockdev --getss "$windows_disk")
    ratio=$(( sector_size / 512 ))
    disk_guid=$(lsblk --noheadings --nodeps --output PTUUID -- "$windows_disk")

    # VM-only ESP, created and formatted on the first start
    if [ ! -f "$esp_image" ]; then
        mkdir -vp "$(dirname "$esp_image")"
        truncate --size "${esp_size_mib}M" "$esp_image"
        mkfs.fat -F 32 -S "$sector_size" -n "ESP-WINVM" "$esp_image" -v >/dev/null
        cat /proc/sys/kernel/random/uuid > "$esp_image.guid"
    fi
    esp_guid=$(cat "$esp_image.guid")
    esp_sectors=$(( $(stat --format %s "$esp_image") / 512 ))

    mkdir -vp "$state_dir"
    for file in header footer; do
        rm -vf "$state_dir/$file.img"
        truncate --size 1M "$state_dir/$file.img"
    done

    header_loop=$(losetup --find --show --sector-size "$sector_size" "$state_dir/header.img")
    esp_loop=$(losetup --find --show --sector-size "$sector_size" "$esp_image")
    footer_loop=$(losetup --find --show --sector-size "$sector_size" "$state_dir/footer.img")

    # Device-mapper table ("start length target args", in 512-byte sectors) and the matching sgdisk
    # arguments, built side by side. The sgdisk arguments go into "$@", so names with spaces stay intact.
    table="0 $mib linear $header_loop 0"
    table="$table${nl}$mib $esp_sectors linear $esp_loop 0"
    set -- --clear --set-alignment=1 --disk-guid="$disk_guid" \
        --new="1:$(( mib / ratio )):$(( (mib + esp_sectors) / ratio - 1 ))" \
        --typecode=1:c12a7328-f81f-11d2-ba4b-00a0c93ec93b \
        --partition-guid="1:$esp_guid" \
        --change-name="1:EFI system partition"

    position=$(( mib + esp_sectors ))
    number=1

    for part in $partitions; do
        number=$(( number + 1 ))
        size=$(( $(lsblk --noheadings --nodeps --bytes --output SIZE -- "$part") / 512 ))

        # Unused space between partitions reads as zeros
        start=$(align "$position")
        if [ "$start" -gt "$position" ]; then
            table="$table${nl}$position $(( start - position )) zero"
        fi

        table="$table${nl}$start $size linear $part 0"

        set -- "$@" \
            --new="$number:$(( start / ratio )):$(( (start + size) / ratio - 1 ))" \
            --typecode="$number:$(lsblk --noheadings --nodeps --output PARTTYPE -- "$part")" \
            --partition-guid="$number:$(lsblk --noheadings --nodeps --output PARTUUID -- "$part")" \
            --change-name="$number:$(lsblk --noheadings --nodeps --output PARTLABEL -- "$part")"

        # Attributes such as "hidden" or "no drive letter" (used by the recovery partition), if any is set
        flags=$(lsblk --noheadings --nodeps --output PARTFLAGS -- "$part")
        flags="${flags#0x}"
        case "$flags" in
            *[!0]*) set -- "$@" --attributes="$number:=:$flags" ;;
        esac

        position=$(( start + size ))
    done

    # Room for the backup GPT
    start=$(align "$position")
    if [ "$start" -gt "$position" ]; then
        table="$table${nl}$position $(( start - position )) zero"
    fi

    table="$table${nl}$start $mib linear $footer_loop 0"

    printf '%s\n' "$table" | dmsetup create "$mapper_name"
    udevadm settle

    # The GPT is written only to the header and footer loop devices, never to the Windows partitions
    sgdisk "$@" "/dev/mapper/$mapper_name" >/dev/null

    echo "$mapper_name: virtual disk ready with $(( number - 1 )) Windows partition(s) from $windows_disk."
}

case "$OPERATION/$SUBOPERATION" in
    prepare/begin)
        # If anything fails, undo the partial setup, and libvirt aborts the start
        trap 'teardown' EXIT
        build
        trap - EXIT
        ;;

    release/end)
        teardown
        ;;
esac

exit 0