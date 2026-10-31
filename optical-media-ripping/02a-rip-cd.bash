#!/usr/bin/env bash
#
# 02a-rip-cd.bash [device] [destination_dir]
#
# Extracts a CD-DA to FLAC, one file per track. If no device is given,
# auto-detects among common optical-drive paths (/dev/sr0, /dev/cdrom,
# etc.) -- passing a path explicitly always works too.
#
# Only the audio tracks are ripped: on an "enhanced" CD (audio + a data
# track with videos/extras), cdparanoia aborts the whole run if the span
# includes the data track, so the span is computed from the TOC first.
#
# The extraction itself cannot be parallelized (the bottleneck is the
# drive spinning the disc), but the WAV->FLAC compression uses every core.

set -euo pipefail

# Resolved once at startup: this script cd's into the destination later,
# and a relative $0 would then point to the wrong folder.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
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
DEST="${2:-/temp/rip}"

for cmd in cd-info cdparanoia flac; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }

# Never mix two discs: cdparanoia always names files track01..., so a
# leftover rip would be overwritten or tagged as the wrong album.
if [[ -n "$(find "$DEST" \( -iname '*.wav' -o -iname '*.flac' \) -print -quit 2>/dev/null)" ]]; then
    echo "Error: '$DEST' still has audio files from another disc. Process/move them first, or pass another folder." >&2
    exit 1
fi

# Audio tracks from the TOC (rows like "  2: 05:22:40 024040 audio ...").
mapfile -t AUDIO_TRACKS < <(cd-info --no-header --no-device-info "$DEVICE" 2>/dev/null |
                            awk '$1 ~ /^[0-9]+:$/ && $4 == "audio" { sub(":", "", $1); print $1 }')
[[ "${#AUDIO_TRACKS[@]}" -gt 0 ]] || { echo "Error: no audio tracks found on the disc." >&2; exit 1; }
SPAN="${AUDIO_TRACKS[0]}-${AUDIO_TRACKS[-1]}"

mkdir -pv "$DEST"
cd "$DEST"

echo "Ripping audio tracks $SPAN from $DEVICE into $DEST ..."
cdparanoia -vBw -d "$DEVICE" -- "$SPAN"

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 --verbose -P"$(nproc)" -I{} flac --best --verify --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"
