#!/usr/bin/env bash
#
# 02a-rip-cd.bash [device] [destination_dir]
#
# Extracts a CD-DA to FLAC, one file per track. If no device is given,
# auto-detects among common optical-drive paths (/dev/sr0, /dev/cdrom,
# etc.) -- passing a path explicitly always works too. The extraction
# itself cannot be parallelized (the bottleneck is the drive spinning the
# disc), but the WAV->FLAC compression uses every available core.

set -euo pipefail

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

# Common paths for an optical drive across distros/setups: /dev/sr0 is the
# usual raw SCSI/USB name, the rest are symlinks some systems create.
detect_device() {
    local candidate
    for candidate in /dev/sr0 /dev/sr1 /dev/cdrom /dev/dvd /dev/dvdrw /dev/cdrw; do
        [[ -b "$candidate" ]] && { echo "$candidate"; return; }
    done
    echo "/dev/sr0"  # nothing found; fall back to the old default so the
                      # error message below stays familiar
}

DEVICE="${1:-$(detect_device)}"
DEST="${2:-/temp/rip}"

for cmd in cdparanoia flac; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; completion_sound; exit 1; }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; completion_sound; exit 1; }

mkdir -p "$DEST"
cd "$DEST"

echo "Ripping tracks from $DEVICE into $DEST ..."
cdparanoia -wBv -d "$DEVICE"

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 -P"$(nproc)" -I{} flac --best --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"

completion_sound
