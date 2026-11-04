#!/bin/sh

# libvirt hook: refuse to start any VM that uses a physical drive (or partition) from the host
# while that drive, or any of its partitions, is mounted on the host.
# Both systems writing to the same filesystem would corrupt it.
## https://libvirt.org/hooks.html
## https://libvirt.org/formatdomain.html#hard-drives-floppy-disks-cdroms

OBJECT="$1"
OPERATION="$2"
SUBOPERATION="$3"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
DOMAIN_XML=$(cat)

# Only act right before the VM starts
case "$OPERATION/$SUBOPERATION" in
    prepare/begin) ;;
    *) exit 0 ;;
esac

# xmllint comes with libxml2, a dependency of libvirt. Without it, the drives can't be checked,
# so refuse to start instead of risking the filesystems.
if ! command -v xmllint >/dev/null 2>&1; then
    echo "xmllint not found, can't check $OBJECT's drives. Install libxml2." >&2
    exit 1
fi

# Host block devices used as disks by the VM, one per line: <disk type="block"> with device "disk" or "lun".
# CD-ROMs and image files are skipped, since they can't hold a filesystem mounted on the host.
drives=$(printf '%s\n' "$DOMAIN_XML" \
    | xmllint --xpath '//devices/disk[@type="block"][@device="disk" or @device="lun"]/source/@dev' - 2>/dev/null \
    | tr ' ' '\n' \
    | sed -n 's/^dev="\(.*\)"$/\1/p')

# No physical drives: nothing to check
case "$drives" in
    "") exit 0 ;;
esac

# Check every drive, so the message lists all the mounted ones at once
mounted_drives=""
set -f          # The paths come from the XML: never expand them as globs
old_ifs="$IFS"
IFS='
'
for drive in $drives; do
    mountpoints=$(lsblk --noheadings --raw --output MOUNTPOINTS -- "$drive" 2>/dev/null | tr '\n' ' ')

    case "$mountpoints" in
        *[![:space:]]*)
            mounted_drives="$mounted_drives
    $drive (at: $mountpoints)"
            ;;
    esac
done
IFS="$old_ifs"
set +f

case "$mounted_drives" in
    "") exit 0 ;;
    *)
        echo "These drives are mounted on the host. Unmount them before starting $OBJECT:$mounted_drives" >&2
        exit 1
        ;;
esac
