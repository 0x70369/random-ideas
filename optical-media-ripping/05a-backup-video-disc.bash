#!/usr/bin/env bash
#
# 05a-backup-video-disc.bash [device] [destination_dir]
#
# Pure, bit-exact backup of a video disc (movie, TV series), nothing
# re-encoded. Detects the disc format by its folder structure:
#
#   DVD-Video (VIDEO_TS)  -> dvdbackup -M: the whole VIDEO_TS structure,
#                            every title, audio track, subtitle, chapter
#                            and menu, exactly as authored.
#   VCD / SVCD (MPEGAV or -> vcdxrip (vcdimager): every MPEG track as a
#   MPEG2 folder)            .mpg, plus videocd.xml describing the disc
#                            structure (menus, entry points, playback
#                            control) -- vcdxbuild can rebuild the disc
#                            from these two.
#
# Why not just copy the VCD's .DAT files: they are stored in a special
# sector format (Mode 2 Form 2) that a normal file copy reads incorrectly;
# vcdxrip reads the raw sectors and writes clean MPEG files.
#
# The folder name is always asked (default: the disc's volume label):
# many discs share generic labels like "DVD_VIDEO", and two of them would
# otherwise be merged into the same folder.
#
# Use 05b-compress-video-disc.bash afterwards on a DVD backup if you want
# a much smaller file. (05b only takes VIDEO_TS; VCD .mpg files are not
# covered there.)

set -euo pipefail

# Resolved once at startup: this script may cd into the destination later,
# and a relative $0 would then point to the wrong folder.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }

MOUNTPOINT=""
unmount_disc() {
    [[ -n "$MOUNTPOINT" ]] || return 0
    sudo umount -v "$MOUNTPOINT"
    rmdir -v "$MOUNTPOINT"
    MOUNTPOINT=""
}
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    unmount_disc || true
    if [[ $rc -eq 0 ]]; then success_sound; else error_sound; fi
}
trap on_exit EXIT

# Common paths for an optical drive across distros/setups: /dev/sr0 is the
# usual raw SCSI/USB name, the rest are symlinks some systems create.
detect_device() {
    local candidate
    for candidate in /dev/sr0 /dev/sr1 /dev/cdrom /dev/dvd /dev/dvdrw /dev/cdrw; do
        [[ -b "$candidate" ]] && { echo "$candidate"; return; }
    done
    echo "/dev/sr0"
}

DEVICE="${1:-$(detect_device)}"
DEST="${2:-/temp/video-backup}"

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }

# --- Detect the format --------------------------------------------------
FORMAT=""
MOUNTPOINT="$(mktemp -d -p /temp)"
echo "Mounting $DEVICE at $MOUNTPOINT to inspect its structure..."
if sudo mount -v -o ro "$DEVICE" "$MOUNTPOINT"; then
    find_dir() { find "$MOUNTPOINT" -maxdepth 1 -iname "$1" -type d 2>/dev/null | head -n1; }
    if [[ -n "$(find_dir VIDEO_TS)" ]]; then
        FORMAT="DVD"
    elif [[ -n "$(find_dir MPEGAV)" || -n "$(find_dir MPEG2)" ]]; then
        FORMAT="VCD"
    fi
    unmount_disc
else
    rmdir -v "$MOUNTPOINT"
    MOUNTPOINT=""
    echo "Could not mount (common for DVD-Video without a standard ISO9660 fs). Assuming DVD."
    FORMAT="DVD"
fi

[[ -n "$FORMAT" ]] || { echo "Error: no VIDEO_TS, MPEGAV or MPEG2 folder found -- not a video disc this script knows." >&2; exit 1; }
echo "Detected format: $FORMAT"

if [[ "$FORMAT" == "DVD" ]]; then
    command -v dvdbackup >/dev/null 2>&1 || { echo "Error: 'dvdbackup' not found." >&2; exit 1; }
else
    command -v vcdxrip >/dev/null 2>&1 || { echo "Error: 'vcdxrip' not found (package 'vcdimager')." >&2; exit 1; }
fi

# --- Folder name ---------------------------------------------------------
LABEL="$(lsblk -no LABEL "$DEVICE" 2>/dev/null | head -n1)"
read -rp "Folder name for this disc [${LABEL:-$FORMAT}]: " NAME
NAME="${NAME:-${LABEL:-$FORMAT}}"
[[ "$NAME" != */* ]] || { echo "Error: the name cannot contain '/'." >&2; exit 1; }
OUT_DIR="$DEST/$NAME"
if [[ -e "$OUT_DIR" ]]; then
    echo "Error: '$OUT_DIR' already exists -- pick another name." >&2
    exit 1
fi
mkdir -pv "$DEST"

# --- DVD-Video -----------------------------------------------------------
# No sudo: your user already reads the drive (cdparanoia works without it),
# and a root-run dvdbackup leaves root-owned files you can't delete later.
if [[ "$FORMAT" == "DVD" ]]; then
    echo "Backing up the whole disc from $DEVICE into $OUT_DIR (this can take a while)..."
    dvdbackup -v -i "$DEVICE" -M -n "$NAME" -o "$DEST"
    echo
    echo "Done. The VIDEO_TS folder is in $OUT_DIR"
    echo "Pass '$OUT_DIR' to 05b-compress-video-disc.bash if you want a smaller file too."
    exit 0
fi

# --- VCD / SVCD ----------------------------------------------------------
mkdir -pv "$OUT_DIR"
cd "$OUT_DIR"
echo "Ripping the Video CD from $DEVICE into $OUT_DIR (this can take a while)..."
vcdxrip --verbose --progress --cdrom-device="$DEVICE"

echo
echo "Done. MPEG tracks and videocd.xml are in $OUT_DIR"
