#!/usr/bin/env bash
#
# 12a-rip-cd.bash [device] [destination_dir]
#
# Rips an audio CD to FLAC with cyanrip (AUR) -- extraction only, no
# metadata lookup (tagging is done by hand in Picard). On top of plain
# cd-paranoia ripping, cyanrip:
#   - corrects the drive's read offset (saved by 10b-find-drive-offset.bash)
#     and verifies every track against the AccurateRip database (checksums
#     of the audio, not metadata);
#   - detects pre-emphasis (TOC and subcode) and applies de-emphasis
#     automatically -- otherwise mid-80s/early-90s CDs come out harsh;
#   - writes a rip log with the paranoia error counts, the AccurateRip
#     results and the disc ID -- read it to know whether the disc ripped
#     cleanly.
#
# Disabled on purpose: MusicBrainz lookup (-N), cover art download (-U) and
# ReplayGain tags (-K). Without metadata, cyanrip names the folder
# "Unknown disc (XXXX) [FLAC]" and the files "<track> - Unknown track.flac";
# Picard renames everything when you save.
#
# Only audio tracks are ripped (an "enhanced" CD's data track is skipped),
# and audio hidden before track 1 (HTOA) is saved as track 0.
#
# If no device is given, auto-detects among common optical-drive paths
# (/dev/sr0, /dev/cdrom, etc.) -- passing a path explicitly always works.

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
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
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

# Identifies the physical drive, so each drive gets its own offset file:
# udev's ID_SERIAL (vendor_model_serial), or vendor + model from sysfs.
drive_id() {
    local id sysdev
    # `|| true`: with pipefail, a failing udevadm/cat would otherwise end
    # the script right here, silently, before the fallback or the error.
    id="$( { udevadm info --query=property --name="$DEVICE" 2>/dev/null || true; } | sed -n 's/^ID_SERIAL=//p')"
    if [[ -z "$id" ]]; then
        sysdev="/sys/class/block/$(basename "$(readlink -f "$DEVICE")")/device"
        id="$( { cat "$sysdev/vendor" "$sysdev/model" 2>/dev/null || true; } | xargs)"
    fi
    # Safe file name: anything but letters, digits, '.', '_' and '-' becomes '_'.
    id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_' | tr -s '_')"
    id="${id#_}"
    echo "${id%_}"
}

DEVICE="${1:-$(detect_device)}"
DEST="${2:-/temp/rip}"

for cmd in cd-info cyanrip eject; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }

# Never mix two discs in the same folder.
if [[ -n "$(find "$DEST" \( -iname '*.wav' -o -iname '*.flac' \) -print -quit 2>/dev/null)" ]]; then
    echo "Error: '$DEST' still has audio files from another disc. Process/move them first, or pass another folder." >&2
    exit 1
fi

# --- Drive offset (one-time setup per drive) ------------------------------
DRIVE_ID="$(drive_id)"
[[ -n "$DRIVE_ID" ]] || { echo "Error: could not identify the drive behind '$DEVICE' (no udev serial, no vendor/model)." >&2; exit 1; }
OFFSET_FILE="$SCRIPT_DIR/drive-offsets/drive-offset.$DRIVE_ID"
echo "Drive: $DRIVE_ID"
if [[ ! -f "$OFFSET_FILE" ]]; then
    echo "Error: no read offset saved for this drive yet. Run once, with a popular commercial CD inserted:" >&2
    echo "  $SCRIPT_DIR/10b-find-drive-offset.bash $DEVICE" >&2
    exit 1
fi
OFFSET="$(tr -d '[:space:]' < "$OFFSET_FILE")"
[[ "$OFFSET" =~ ^-?[0-9]+$ ]] || { echo "Error: '$OFFSET_FILE' does not hold a number. Run 10b-find-drive-offset.bash again." >&2; exit 1; }

# --- Tracks from the TOC (rows like "  2: 05:22:40 024040 audio ...") -------
TOC="$(cd-info --no-header --no-device-info "$DEVICE" 2>/dev/null || true)"
mapfile -t AUDIO_TRACKS < <(awk '$1 ~ /^[0-9]+:$/ && $4 == "audio" { sub(":", "", $1); print $1 }' <<<"$TOC")
DATA_TRACKS="$(awk '$1 ~ /^[0-9]+:$/ && $4 != "audio" && $4 != "leadout"' <<<"$TOC" | wc -l)"
[[ "${#AUDIO_TRACKS[@]}" -gt 0 ]] || { echo "Error: no audio tracks found on the disc." >&2; exit 1; }

# -N: no MusicBrainz lookup  -U: no cover art download  -K: no ReplayGain
# tags (opusenc would turn them into an Opus header gain, changing the
# playback volume everywhere -- see 14-convert-to-opus.bash).
CYANRIP_ARGS=(-d "$DEVICE" -s "$OFFSET" -N -U -K)

if [[ "$DATA_TRACKS" -gt 0 ]]; then
    # Enhanced CD: name the audio tracks explicitly, so the data track is
    # not ripped as a .bin file.
    LIST="$(IFS=,; echo "${AUDIO_TRACKS[*]}")"
    echo "Enhanced CD: ripping only audio tracks $LIST (skipping $DATA_TRACKS data track(s))."
    CYANRIP_ARGS+=(-l "$LIST")
else
    # Hidden track before track 1 (HTOA): track 1 then starts later than
    # the usual LSN 0. Ignore tiny pregaps (< 2 s) -- they hold no music.
    TRACK1_LSN="$(awk '$1 == "1:" && $4 == "audio" { print $3 + 0 }' <<<"$TOC")"
    if [[ "${TRACK1_LSN:-0}" -ge 150 ]]; then
        echo "Track 1 starts $((TRACK1_LSN / 75)) s into the disc: saving that hidden audio as track 0."
        CYANRIP_ARGS+=(-p "1=track")
    fi
fi

mkdir -pv "$DEST"
cd "$DEST"

echo "Ripping into $DEST (offset $OFFSET samples)..."
cyanrip "${CYANRIP_ARGS[@]}"

echo "Done: $(find . -iname '*.flac' | wc -l) track(s) in $DEST"
echo "Check the rip log next to the files: it shows the AccurateRip result per track."
# The disc ID cyanrip computed from the TOC (no lookup was made): handy to
# find the exact release on MusicBrainz without the disc in the drive.
DISC_ID="$(find . -iname '*.log' -exec sed -n 's/^[[:space:]]*DiscID:[[:space:]]*//p' {} + | head -n1)"
if [[ -n "$DISC_ID" ]]; then
    echo "Disc ID: $DISC_ID -- releases with this exact disc: https://musicbrainz.org/cdtoc/$DISC_ID"
fi
eject -v "$DEVICE"
