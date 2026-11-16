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
#     results and the disc ID.
#
# At the end, this script reads that log and gives the verdict:
#   - every track matches AccurateRip, no read errors: success sound;
#   - read errors, or tracks that don't match the database: error sound
#     (clean the disc and rip again -- the files are kept);
#   - disc not in AccurateRip (CD-Rs, rare pressings): no verification is
#     possible, so it only reports that (success sound if no read errors).
# The HTOA track 0 is never in AccurateRip, so it is not counted.
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

# Shared setup -- logging to /temp/logs, sounds, Ctrl+C, drive helpers --
# lives in common.bash, next to the scripts. SCRIPT_DIR is resolved first:
# a relative $0 would break once the script cd's elsewhere.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1

DEVICE="${1:-$(detect_device)}"
DEST="${2:-/temp/rip}"

for cmd in cd-info cyanrip eject; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }
lock_device   # one script per drive at a time (common.bash)

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
# Not fatal here: the log is read below either way.
CYANRIP_RC=0
cyanrip "${CYANRIP_ARGS[@]}" || CYANRIP_RC=$?

echo "Done: $(find . -iname '*.flac' | wc -l) track(s) in $DEST"
eject -v "$DEVICE"

# --- Verdict from the rip log ---------------------------------------------
LOG_FILE="$(find . -iname '*.log' -print -quit)"
if [[ -z "$LOG_FILE" ]]; then
    echo "Error: no rip log found (cyanrip exit status $CYANRIP_RC)." >&2
    exit 1
fi
echo "Rip log: $DEST/${LOG_FILE#./} (Picard: Tools > Lookup CD > From CD ripper log file)"

# The disc ID cyanrip computed from the TOC (no lookup was made). Picard 3
# reads it from the log itself: Tools > Lookup CD > From CD ripper log file.
DISC_ID="$(sed -n 's/^[[:space:]]*DiscID:[[:space:]]*//p' "$LOG_FILE" | head -n1)"
if [[ -n "$DISC_ID" ]]; then
    echo "Disc ID: $DISC_ID -- releases with this exact disc: https://musicbrainz.org/cdtoc/$DISC_ID"
fi

# Lines written by cyanrip at the end of the log:
#   "AccurateRip:    found|not found|mismatch|error|disabled"
#   "Tracks ripped accurately: X/Y"   (only when the disc was found)
#   "Ripping errors: N"               (frames that could not be read)
AR_STATUS="$(sed -n 's/^AccurateRip:[[:space:]]*//p' "$LOG_FILE" | tail -n1)"
ACCURATE="$(sed -n 's/^Tracks ripped accurately: \([0-9]\+\)\/[0-9]\+.*/\1/p' "$LOG_FILE" | tail -n1)"
PARTIAL="$(sed -n 's/^Tracks ripped partially accurately: \([0-9]\+\)\/[0-9]\+.*/\1/p' "$LOG_FILE" | tail -n1)"
RIP_ERRORS="$(sed -n 's/^Ripping errors: \([0-9]\+\).*/\1/p' "$LOG_FILE" | tail -n1)"
EXPECTED="${#AUDIO_TRACKS[@]}"   # the disc's audio tracks, without a track 0

echo
echo "=== Verdict ==="
FAILED=false
if [[ "$CYANRIP_RC" -ne 0 ]]; then
    echo "cyanrip exited with status $CYANRIP_RC."
    FAILED=true
fi
if [[ -z "$RIP_ERRORS" ]]; then
    echo "Could not read the error count from the log -- check it yourself."
    FAILED=true
elif [[ "$RIP_ERRORS" -gt 0 ]]; then
    echo "Read errors: $RIP_ERRORS (unreadable audio was replaced by silence)."
    FAILED=true
else
    echo "Read errors: none."
fi
case "$AR_STATUS" in
    found)
        if [[ "${ACCURATE:-0}" -ge "$EXPECTED" ]]; then
            echo "AccurateRip: all $EXPECTED track(s) match the database."
        else
            echo "AccurateRip: only ${ACCURATE:-0} of $EXPECTED track(s) match the database${PARTIAL:+ ($PARTIAL more match partially)}."
            echo "  The others differ from every rip in the database: a damaged or dirty disc"
            echo "  (clean it and rip again), or, less often, a pressing not in the database."
            FAILED=true
        fi
        ;;
    "not found"|mismatch)
        echo "AccurateRip: this pressing is not in the database (normal for CD-Rs and rare"
        echo "  releases), so the rip cannot be verified -- rely on the read errors above."
        ;;
    *)
        echo "AccurateRip: ${AR_STATUS:-no result in the log} -- the rip was not verified."
        ;;
esac
if $FAILED; then
    echo "Result: NOT a clean rip. The files are kept in $DEST; see the log for the per-track details." >&2
    exit 1
fi
if [[ "$AR_STATUS" == found ]]; then
    echo "Result: clean rip, verified by AccurateRip."
else
    echo "Result: no read errors, but not verified by AccurateRip."
fi
