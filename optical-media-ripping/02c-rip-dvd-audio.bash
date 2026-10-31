#!/usr/bin/env bash
#
# 02c-rip-dvd-audio.bash [device] [destination_dir]
#
# Extracts audio from a DVD-Audio disc (AUDIO_TS) via libdvd-audio
# (dvda-debug-info + dvda2wav), then compresses it to FLAC. If no device
# is given, auto-detects among common optical-drive paths (/dev/sr0,
# /dev/cdrom, etc.) -- passing a path explicitly always works too. Asks
# for confirmation before extracting because this tool's MLP support is
# limited -- worth checking the listing before committing.

set -euo pipefail

# Resolved once at startup: this script cd's into the destination later,
# and a relative $0 would then point to the wrong folder.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }

MOUNTPOINT=""
MOUNTED=false
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    if $MOUNTED; then sudo umount -v "$MOUNTPOINT"; fi
    if [[ -n "$MOUNTPOINT" ]]; then rmdir -v "$MOUNTPOINT"; fi
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

for cmd in dvda-debug-info dvda2wav flac; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: '$cmd' not found. Install the AUR package 'libdvd-audio'." >&2
        exit 1
    }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }

# Never mix two discs in the same folder.
if [[ -n "$(find "$DEST" \( -iname '*.wav' -o -iname '*.flac' \) -print -quit 2>/dev/null)" ]]; then
    echo "Error: '$DEST' still has audio files from another disc. Process/move them first, or pass another folder." >&2
    exit 1
fi

mkdir -pv "$DEST"
# A fresh mount point each run: a fixed one stays busy if a previous run died.
MOUNTPOINT="$(mktemp -d -p /temp)"
sudo mount -v -o ro "$DEVICE" "$MOUNTPOINT"
MOUNTED=true

AUDIO_TS_DIR="$(find "$MOUNTPOINT" -maxdepth 1 -iname AUDIO_TS -type d | head -n1)"
[[ -n "$AUDIO_TS_DIR" ]] || { echo "Error: no AUDIO_TS folder (any case) found on the disc." >&2; exit 1; }

echo "Tracks found:"
dvda-debug-info -A "$AUDIO_TS_DIR"
echo

read -rp "Proceed with extracting all tracks listed above? [Y/n] " reply
reply=${reply:-Y}
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

cd "$DEST"
dvda2wav -A "$AUDIO_TS_DIR"

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 --verbose -P"$(nproc)" -I{} flac --best --verify --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"
