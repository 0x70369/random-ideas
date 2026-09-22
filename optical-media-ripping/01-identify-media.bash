#!/usr/bin/env bash
#
# 01-identify-media.bash [/dev/srX]
#
# Identifies the type of optical media in the drive.
# Prints exactly one of these tokens to stdout (for use by other scripts
# or by yourself, e.g.: type=$(./01-identify-media.bash)):
#
#   CD-DA       audio CD
#   DVD-VIDEO   DVD-Video (a video-based show)
#   DVD-AUDIO   DVD-Audio (AUDIO_TS) -- includes hybrids with VIDEO_TS
#   UNKNOWN     could not determine (see stderr messages)
#
# Diagnostic messages -- including a "Next step: ./<script> <device>" hint
# for whichever rip script matches the detected type -- go to stderr, so
# "type=$(...)" still captures only the token, even though everything else
# shows up on screen for a human running this interactively.

set -uo pipefail

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

DEVICE="${1:-/dev/sr0}"

log() { echo "$*" >&2; }

# Prints the token to stdout (the only thing meant to be captured by
# "type=$(...)") and, on stderr, a copy-pasteable hint for the next script
# -- so a human running this interactively sees it, without it ever
# ending up inside a captured variable.
finish() {
    local token="$1" next="$2"
    [[ -n "$next" ]] && log "Next step: ./$next $DEVICE"
    echo "$token"
    completion_sound
    exit 0
}

if [[ ! -b "$DEVICE" ]]; then
    log "Error: '$DEVICE' is not a block device."
    exit 1
fi

mode=""

if command -v cd-info >/dev/null 2>&1; then
    output="$(cd-info --dvd --no-header --no-device-info --no-cddb "$DEVICE" 2>/dev/null)"
    mode="$(grep -m1 'Disc mode is listed as:' <<<"$output" | sed 's/.*: *//')" || true
fi

if [[ -z "$mode" ]]; then
    log "cd-info gave no useful result; trying udevadm..."
    properties="$(udevadm info --query=property --name="$DEVICE" 2>/dev/null)"
    if grep -q '^ID_CDROM_MEDIA_DVD=1' <<<"$properties"; then
        mode="DVD-ROM"
    elif grep -q '^ID_CDROM_MEDIA_CD=1' <<<"$properties"; then
        mode="CD-DA"
    fi
fi

log "Raw mode detected: ${mode:-<empty>}"

case "$mode" in
    CD-DA)
        finish "CD-DA" "02a-rip-cd.bash"
        ;;
    "")
        log "No next script for an unrecognized disc -- inspect it manually."
        echo "UNKNOWN"
        completion_sound
        exit 1
        ;;
    DVD*)
        ;;
    *)
        log "Unrecognized mode: $mode"
        echo "UNKNOWN"
        completion_sound
        exit 1
        ;;
esac

# It's a DVD -- need to check whether it has VIDEO_TS, AUDIO_TS, or both.
MOUNTPOINT="$(mktemp -d)"
trap 'sudo umount "$MOUNTPOINT" 2>/dev/null; rmdir "$MOUNTPOINT" 2>/dev/null' EXIT

log "Mounting $DEVICE at $MOUNTPOINT to inspect its structure..."
if ! sudo mount -vo ro "$DEVICE" "$MOUNTPOINT" 2>/dev/null; then
    log "Could not mount (common for DVD-Video without a standard ISO9660 fs). Assuming DVD-VIDEO."
    finish "DVD-VIDEO" "02b-rip-dvd-video.bash"
fi

has_video=false
has_audio=false
video_ts_dir="$(find "$MOUNTPOINT" -maxdepth 1 -iname VIDEO_TS -type d 2>/dev/null | head -n1)"
audio_ts_dir="$(find "$MOUNTPOINT" -maxdepth 1 -iname AUDIO_TS -type d 2>/dev/null | head -n1)"
[[ -n "$video_ts_dir" ]] && [[ -n "$(ls -A "$video_ts_dir" 2>/dev/null)" ]] && has_video=true
[[ -n "$audio_ts_dir" ]] && [[ -n "$(ls -A "$audio_ts_dir" 2>/dev/null)" ]] && has_audio=true

if $has_audio; then
    $has_video && log "Hybrid disc (AUDIO_TS + VIDEO_TS) -- using AUDIO_TS (lossless)."
    finish "DVD-AUDIO" "02c-rip-dvd-audio.bash"
elif $has_video; then
    finish "DVD-VIDEO" "02b-rip-dvd-video.bash"
else
    log "Neither AUDIO_TS nor VIDEO_TS with content was found."
    log "No next script for an unrecognized disc -- inspect it manually."
    echo "UNKNOWN"
    completion_sound
    exit 1
fi
