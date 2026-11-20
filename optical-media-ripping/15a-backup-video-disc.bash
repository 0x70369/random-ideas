#!/usr/bin/env bash
#
# 15a-backup-video-disc.bash [device] [destination_dir]
#
# Bit-exact backup of a video disc, nothing re-encoded:
#   DVD-Video (VIDEO_TS)        dvdbackup -M: the whole disc, menus included
#   VCD/SVCD (MPEGAV or MPEG2)  vcdxrip: every track as .mpg, plus
#                               videocd.xml, from which vcdxbuild rebuilds
#                               the disc. A plain copy of the .DAT files
#                               would read their Mode 2 Form 2 sectors wrong.
# The folder name is always asked (default: the volume label), since many
# discs share labels like "DVD_VIDEO". No sudo: a root-run dvdbackup leaves
# files your user cannot delete.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

need eject
use_device "${1:-}"
dest="${2:-/temp/video-backup}"

format=DVD
mount_disc
if [[ -n "${MOUNTPOINT}" ]]; then
    video_ts="$(disc_dir VIDEO_TS)"
    mpegav="$(disc_dir MPEGAV)"
    mpeg2="$(disc_dir MPEG2)"
    if [[ -z "${video_ts}" ]]; then
        [[ -n "${mpegav}${mpeg2}" ]] ||
            die "no VIDEO_TS, MPEGAV or MPEG2 folder: not a video disc."
        format=VCD
    fi
    unmount_disc
else
    echo "Could not mount the disc; assuming DVD-Video."
fi
echo "Format: ${format}"
if [[ "${format}" == DVD ]]; then need dvdbackup; else need vcdxrip; fi

label="$(lsblk -no LABEL "${DEVICE}")" || label=""
read -rp "Folder name for this disc [${label:-${format}}]: " name
name="${name:-${label:-${format}}}"
[[ "${name}" != */* ]] || die "the name cannot contain '/'."
out="${dest}/${name}"
[[ ! -e "${out}" ]] || die "'${out}' already exists."
need_disc_space 110
mkdir -pv -- "${dest}"

if [[ "${format}" == DVD ]]; then
    dvdbackup -v -i "${DEVICE}" -M -n "${name}" -o "${dest}"
    echo "For a smaller copy: ./15b-compress-video-disc.bash '${out}'"
else
    mkdir -pv -- "${out}"
    cd -- "${out}"
    vcdxrip --verbose --progress --cdrom-device="${DEVICE}"
fi
eject -v -- "${DEVICE}"
echo "Done: ${out}"
