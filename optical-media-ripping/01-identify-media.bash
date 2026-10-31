#!/usr/bin/env bash
#
# 01-identify-media.bash [device]
#
# Identifies the type of optical media in the drive. If no device is given,
# auto-detects among common optical-drive paths (/dev/sr0, /dev/cdrom,
# etc.) -- passing a path explicitly always works too.
#
# Prints exactly one of these tokens to stdout (for use by other scripts
# or by yourself, e.g.: type=$(./01-identify-media.bash)):
#
#   CD-DA       audio CD -- including "enhanced" CDs (audio + data track)
#   DVD-VIDEO   DVD-Video (live show, movie or TV series)
#   DVD-AUDIO   DVD-Audio (AUDIO_TS) -- includes hybrids with VIDEO_TS
#   VCD         Video CD / Super Video CD (MPEGAV or MPEG2 folder)
#   UNKNOWN     could not determine (see stderr messages)
#
# Everything else -- diagnostics and the "Next step: ..." hint -- goes to
# stderr, so "type=$(...)" still captures only the token.

set -uo pipefail

# Resolved once at startup: if a script cd's elsewhere later, a relative $0
# would point to the wrong folder and the sounds would not be found.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck disable=SC2329  # used inside the trap handler
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
# shellcheck disable=SC2329
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }

MOUNTPOINT=""
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    if [[ -n "$MOUNTPOINT" ]]; then
        sudo umount -v "$MOUNTPOINT" >&2
        rmdir -v "$MOUNTPOINT" >&2
    fi
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

log() { echo "$*" >&2; }

# Token to stdout, hint(s) to stderr.
finish() {
    local token="$1" hint
    shift
    for hint in "$@"; do log "Next step: $hint"; done
    echo "$token"
    exit 0
}

unknown() {
    log "$*"
    log "No next script for an unrecognized disc -- inspect it manually."
    echo "UNKNOWN"
    exit 1
}

[[ -b "$DEVICE" ]] || { log "Error: '$DEVICE' is not a block device."; exit 1; }

# --- What the TOC says ---------------------------------------------------
# cd-info prints the disc mode plus one row per track, e.g.
#   "  2: 05:22:40 024040 audio false no 2 no"
# Counting audio vs. other rows is more reliable than the mode string,
# which varies (CD-DA, mixed, XA...).
mode="" audio_tracks=0 other_tracks=0
if command -v cd-info >/dev/null 2>&1; then
    output="$(cd-info --dvd --no-header --no-device-info "$DEVICE" 2>/dev/null)"
    mode="$(grep -m1 'Disc mode is listed as:' <<<"$output" | sed 's/.*listed as: *//')" || true
    audio_tracks="$(awk '$1 ~ /^[0-9]+:$/ && $4 == "audio"' <<<"$output" | wc -l)"
    other_tracks="$(awk '$1 ~ /^[0-9]+:$/ && $4 != "audio" && $4 != "leadout"' <<<"$output" | wc -l)"
fi

if [[ -z "$mode" ]]; then
    log "cd-info gave no useful result; trying udevadm..."
    properties="$(udevadm info --query=property --name="$DEVICE" 2>/dev/null)"
    audio_tracks="$(sed -n 's/^ID_CDROM_MEDIA_TRACK_COUNT_AUDIO=//p' <<<"$properties")"
    other_tracks="$(sed -n 's/^ID_CDROM_MEDIA_TRACK_COUNT_DATA=//p' <<<"$properties")"
    audio_tracks="${audio_tracks:-0}" other_tracks="${other_tracks:-0}"
    if grep -q '^ID_CDROM_MEDIA_DVD=1' <<<"$properties"; then
        mode="DVD"
    elif grep -q '^ID_CDROM_MEDIA_CD=1' <<<"$properties"; then
        mode="CD"
    fi
fi

log "Disc mode: ${mode:-<unknown>} | audio tracks: $audio_tracks | other tracks: $other_tracks"
[[ -z "$mode" ]] && unknown "Could not read the disc."

# Pure audio CD: nothing to mount.
if [[ "$mode" != DVD* && "$audio_tracks" -gt 0 && "$other_tracks" -eq 0 ]]; then
    finish "CD-DA" "./02a-rip-cd.bash $DEVICE"
fi

# --- What the file system says --------------------------------------------
MOUNTPOINT="$(mktemp -d -p /temp)"
log "Mounting $DEVICE at $MOUNTPOINT to inspect its structure..."
if ! sudo mount -v -o ro "$DEVICE" "$MOUNTPOINT" >&2; then
    rmdir -v "$MOUNTPOINT" >&2
    MOUNTPOINT=""
    if [[ "$mode" == DVD* ]]; then
        log "Could not mount (common for DVD-Video without a standard ISO9660 fs). Assuming DVD-VIDEO."
        finish "DVD-VIDEO" "./02b-rip-dvd-video.bash $DEVICE   (live show: audio only)" \
                           "./05a-backup-video-disc.bash $DEVICE   (movie/series: keep the video)"
    fi
    [[ "$audio_tracks" -gt 0 ]] && finish "CD-DA" "./02a-rip-cd.bash $DEVICE"
    unknown "Could not mount the disc."
fi

find_dir()    { find "$MOUNTPOINT" -maxdepth 1 -iname "$1" -type d 2>/dev/null | head -n1; }
has_dir()     { [[ -n "$(find_dir "$1")" ]]; }
has_content() { local d; d="$(find_dir "$1")"; [[ -n "$d" && -n "$(ls -A "$d" 2>/dev/null)" ]]; }

if has_content AUDIO_TS; then
    has_content VIDEO_TS && log "Hybrid disc (AUDIO_TS + VIDEO_TS) -- using AUDIO_TS (lossless)."
    finish "DVD-AUDIO" "./02c-rip-dvd-audio.bash $DEVICE"
elif has_content VIDEO_TS; then
    finish "DVD-VIDEO" "./02b-rip-dvd-video.bash $DEVICE   (live show: audio only)" \
                       "./05a-backup-video-disc.bash $DEVICE   (movie/series: keep the video)"
elif has_dir MPEGAV || has_dir MPEG2; then
    finish "VCD" "./05a-backup-video-disc.bash $DEVICE"
elif [[ "$audio_tracks" -gt 0 ]]; then
    log "Enhanced CD (audio + data track) -- only the audio tracks will be ripped."
    finish "CD-DA" "./02a-rip-cd.bash $DEVICE"
else
    unknown "No audio tracks and no AUDIO_TS, VIDEO_TS, MPEGAV or MPEG2 folder found (mode: $mode)."
fi
