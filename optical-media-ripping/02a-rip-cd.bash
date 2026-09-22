#!/usr/bin/env bash
#
# 02a-rip-cd.bash [/dev/srX] [destination_dir]
#
# Extracts a CD-DA to FLAC, one file per track. The extraction itself
# cannot be parallelized (the bottleneck is the drive spinning the disc),
# but the WAV->FLAC compression uses every available core.

set -euo pipefail

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

DEVICE="${1:-/dev/sr0}"
DEST="${2:-/temp/rip}"

for cmd in cdparanoia flac; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

mkdir -vp "$DEST"
cd "$DEST"

echo "Ripping tracks from $DEVICE into $DEST ..."
cdparanoia -B -d "$DEVICE"

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 -P"$(nproc)" -I{} flac --best --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"

completion_sound
