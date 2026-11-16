#!/usr/bin/env bash
#
# 12c-rip-dvd-audio.bash [device] [destination_dir]
#
# Extracts audio from a DVD-Audio disc (AUDIO_TS) via libdvd-audio
# (dvda-debug-info + dvda2wav), then compresses it to FLAC. If no device
# is given, auto-detects among common optical-drive paths (/dev/sr0,
# /dev/cdrom, etc.) -- passing a path explicitly always works too. Asks
# for confirmation before extracting because this tool's MLP support is
# limited -- worth checking the listing before committing.
#
# Commercial DVD-Audio discs are encrypted (CPPM): dvda2wav only decrypts
# when it is given the drive (-c), otherwise the "audio" is noise.
# dvda2wav and dvda-debug-info only read titleset 1 (ATS_01); if the disc
# has more titlesets, this script warns you before extracting.

set -euo pipefail

# Shared setup -- logging to /temp/logs, sounds, Ctrl+C, drive helpers --
# lives in common.bash, next to the scripts. SCRIPT_DIR is resolved first:
# a relative $0 would break once the script cd's elsewhere.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1

MOUNTPOINT=""
MOUNTED=false
# Runs on every exit, before the sound (see common.bash). `|| true`: a
# failing step must not skip the next one.
# shellcheck disable=SC2329
cleanup() {
    if $MOUNTED; then sudo umount -v "$MOUNTPOINT" || true; fi
    if [[ -n "$MOUNTPOINT" ]]; then rmdir -v "$MOUNTPOINT" || true; fi
}

DEVICE="${1:-$(detect_device)}"
DEST="${2:-/temp/rip}"

command -v eject >/dev/null 2>&1 || { echo "Error: 'eject' not found." >&2; exit 1; }
for cmd in dvda-debug-info dvda2wav flac; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "Error: '$cmd' not found. Install the AUR package 'libdvd-audio'." >&2
        exit 1
    }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }
lock_device   # one script per drive at a time (common.bash)

# Never mix two discs in the same folder.
if [[ -n "$(find "$DEST" \( -iname '*.wav' -o -iname '*.flac' \) -print -quit 2>/dev/null)" ]]; then
    echo "Error: '$DEST' still has audio files from another disc. Process/move them first, or pass another folder." >&2
    exit 1
fi

DISC_BYTES="$( { lsblk -bdno SIZE "$DEVICE" 2>/dev/null || true; } | head -n1)"
DISC_BYTES="${DISC_BYTES:-0}"
if [[ "$DISC_BYTES" -gt 0 ]]; then
    need_space $(( DISC_BYTES * 3 ))
else
    echo "Warning: could not read the disc size; skipping the space check."
fi

mkdir -pv "$DEST"
# A fresh mount point each run: a fixed one stays busy if a previous run died.
MOUNTPOINT="$(mktemp -d -p /temp)"
sudo mount -v -o ro "$DEVICE" "$MOUNTPOINT"
MOUNTED=true

AUDIO_TS_DIR="$(find "$MOUNTPOINT" -maxdepth 1 -iname AUDIO_TS -type d | head -n1)"
[[ -n "$AUDIO_TS_DIR" ]] || { echo "Error: no AUDIO_TS folder (any case) found on the disc." >&2; exit 1; }

echo "Tracks found (titleset 1):"
dvda-debug-info -A "$AUDIO_TS_DIR"
echo

TITLESETS="$(find "$AUDIO_TS_DIR" -maxdepth 1 -iname 'ATS_[0-9][0-9]_0.IFO' | wc -l)"
if [[ "$TITLESETS" -gt 1 ]]; then
    echo "Warning: this disc has $TITLESETS titlesets (ATS_01..), and dvda2wav can only"
    echo "extract titleset 1 -- the audio in the others will NOT be extracted."
fi

read -rp "Proceed with extracting all tracks listed above? [Y/n] " reply
reply=${reply:-Y}
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

cd "$DEST"
# -c: the drive, so dvda2wav can decrypt CPPM-protected discs.
dvda2wav -A "$AUDIO_TS_DIR" -c "$DEVICE"
# dvda2wav exits 0 even when it extracted nothing.
[[ -n "$(find . -maxdepth 1 -name '*.wav' -print -quit)" ]] || { echo "Error: dvda2wav produced no WAV file (see its messages above)." >&2; exit 1; }

echo "Encoding to FLAC (parallel, $(nproc) cores)..."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 --verbose -P"$(nproc)" -I{} flac --best --verify --delete-input-file {}

echo "Done: $(find . -maxdepth 1 -name '*.flac' | wc -l) track(s) in $DEST"
sudo umount -v "$MOUNTPOINT"
MOUNTED=false
eject -v "$DEVICE"
