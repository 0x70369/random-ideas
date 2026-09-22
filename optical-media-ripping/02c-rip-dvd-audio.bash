#!/usr/bin/env bash
#
# 02c-rip-dvd-audio.bash [/dev/srX] [destination_dir]
#
# Extracts audio from a DVD-Audio disc (AUDIO_TS) via libdvd-audio
# (dvda-debug-info + dvda2wav), then compresses it to FLAC. Asks for
# confirmation before extracting because this tool's MLP support is
# limited -- worth checking the listing before committing.

set -euo pipefail

DEVICE="${1:-/dev/sr0}"
DEST="${2:-/temp/rip}"
MOUNTPOINT="/temp/disc"

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

for cmd in dvda-debug-info dvda2wav flac; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: '$cmd' not found. Install the AUR package 'libdvd-audio'." >&2
        completion_sound
        exit 1
    }
done

mkdir -vp "$MOUNTPOINT" "$DEST"
sudo mount -vo ro "$DEVICE" "$MOUNTPOINT"
trap 'sudo umount "$MOUNTPOINT" 2>/dev/null' EXIT

AUDIO_TS_DIR="$(find "$MOUNTPOINT" -maxdepth 1 -iname AUDIO_TS -type d | head -n1)"
[[ -n "$AUDIO_TS_DIR" ]] || { echo "Error: no AUDIO_TS folder (any case) found on the disc." >&2; completion_sound; exit 1; }

echo "Tracks found:"
dvda-debug-info -A "$AUDIO_TS_DIR"
echo

read -rp "Proceed with extracting all tracks listed above? [Y/n] " reply
reply=${reply:-Y}
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; completion_sound; exit 0; }

cd "$DEST"
dvda2wav -A "$AUDIO_TS_DIR"

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 -P"$(nproc)" -I{} flac --best --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"

completion_sound
