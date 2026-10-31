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

# Log the whole run to /temp/logs, but only when input and output are a
# terminal (piped input, e.g. `echo y | ...`, goes straight to the
# script): `script` re-runs this script inside a pseudo-terminal, so
# progress bars and prompts keep working and everything is also saved.
if [[ -t 0 && -t 1 && -z "${DIGITIZE_LOG:-}" ]]; then
    mkdir -pv /temp/logs >&2
    DIGITIZE_LOG="/temp/logs/$(basename "$0" .bash)-$(date +%Y%m%d-%H%M%S).log"
    export DIGITIZE_LOG
    echo "Logging to $DIGITIZE_LOG" >&2
    SHELL=/bin/bash exec script -qef -c "$(printf '%q ' bash "$0" "$@")" "$DIGITIZE_LOG"
fi

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
    # `|| true`: a failing cleanup step must not skip the sound.
    if $MOUNTED; then sudo umount -v "$MOUNTPOINT" || true; fi
    if [[ -n "$MOUNTPOINT" ]]; then rmdir -v "$MOUNTPOINT" || true; fi
    if [[ $rc -eq 0 ]]; then success_sound; else error_sound; fi
}
trap on_exit EXIT
# Ctrl+C / kill: stop with an error status, so the error sound plays --
# even when the program running at that moment catches the signal and
# exits 0 (bash would otherwise just carry on with the next command).
trap 'exit 130' INT
trap 'exit 143' TERM

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

command -v eject >/dev/null 2>&1 || { echo "Error: 'eject' not found." >&2; exit 1; }
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

# /temp is a tmpfs (RAM): check the free space up front instead of
# failing halfway through a multi-GB copy.
need_space() {
    local need=$1 avail
    avail="$(df -B1 --output=avail /temp | tail -n1 | tr -d ' ')"
    echo "Space check: about $(numfmt --to=iec "$need") needed, $(numfmt --to=iec "$avail") free in /temp."
    if (( avail < need )); then
        echo "Error: not enough free space in /temp -- free some (old backups?) and try again." >&2
        exit 1
    fi
}
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
