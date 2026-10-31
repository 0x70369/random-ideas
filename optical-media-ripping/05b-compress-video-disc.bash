#!/usr/bin/env bash
#
# 05b-compress-video-disc.bash <disc_dir> [destination_dir]
#
# Compresses a video disc (movie, TV series) into one .mkv per title,
# starting from a VIDEO_TS folder already copied to disk (by
# 05a-backup-video-disc.bash, or any other means) -- never reads the
# optical drive itself, so a flaky disc or a slow drive only costs you
# once.
#
# Re-encodes the VIDEO to x265 (CRF 20, slow preset -- a widely used
# setting for this kind of archival: a large size reduction from raw DVD
# MPEG-2 at close to visually transparent quality). Every AUDIO track and
# every SUBTITLE track is copied byte-for-byte, never re-encoded -- they
# are already small, so there is nothing to gain and real quality to
# lose by touching them. Chapters are kept as proper MKV chapter markers.
#
# Handles multi-title discs (e.g. a TV season where each episode is its
# own title) by letting you pick more than one title in one run, one
# output file per title.
#
# Nothing here deletes the VIDEO_TS backup -- that decision (keep both,
# or free the space) is yours to make afterwards.

set -euo pipefail

# Resolved once at startup: if a script cd's elsewhere later, a relative $0
# would point to the wrong folder and the sounds would not be found.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    if [[ $rc -eq 0 ]]; then success_sound; else error_sound; fi
}
trap on_exit EXIT

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <disc_dir> [destination_dir]" >&2
    exit 1
fi
DISC_DIR="$1"
DEST="${2:-/temp/video-final}"

command -v HandBrakeCLI >/dev/null 2>&1 || { echo "Error: 'HandBrakeCLI' not found." >&2; exit 1; }

VIDEO_TS_DIR="$(find "$DISC_DIR" -maxdepth 1 -iname VIDEO_TS -type d | head -n1)"
[[ -n "$VIDEO_TS_DIR" ]] || { echo "Error: no VIDEO_TS folder (any case) found under '$DISC_DIR'." >&2; exit 1; }

mkdir -pv "$DEST"

# Scans use plain -v (log level 1): higher levels bury the track list you
# need to read. The encode itself uses level 2.
echo "=== Scanning all titles in $DISC_DIR ==="
HandBrakeCLI -v -i "$DISC_DIR" -t 0 --scan
echo "=========================================="
echo

# Asks until the answer is a whole number (a typo would otherwise only
# blow up later, inside HandBrake).
ask_int() {
    local answer
    while :; do
        read -rp "$1" answer
        [[ "$answer" =~ ^[0-9]+$ ]] && { echo "$answer"; return; }
        echo "Please type a number." >&2
    done
}

read -rp "Which title number(s) do you want to encode? (space-separated, e.g. '1' or '1 2 3') " -a TITLES
[[ "${#TITLES[@]}" -gt 0 ]] || { echo "Error: no title chosen." >&2; exit 1; }
for TITLE in "${TITLES[@]}"; do
    [[ "$TITLE" =~ ^[0-9]+$ ]] || { echo "Error: '$TITLE' is not a title number." >&2; exit 1; }
done

for TITLE in "${TITLES[@]}"; do
    echo
    echo "--- Title $TITLE ---"
    echo "=== Scanning title $TITLE (look for its audio and subtitle tracks below) ==="
    HandBrakeCLI -v -i "$DISC_DIR" -t "$TITLE" --scan
    echo "================================================================================"
    echo

    NUM_AUDIO="$(ask_int "How many audio tracks does this title have (see above)? ")"
    NUM_SUB="$(ask_int "How many subtitle tracks does this title have (see above, 0 if none)? ")"

    # Every track is copied untouched. The fallback only kicks in for a
    # track HandBrake cannot pass through -- FLAC keeps it lossless.
    if [[ "$NUM_AUDIO" -gt 0 ]]; then
        AENC_LIST="$(printf 'copy,%.0s' $(seq 1 "$NUM_AUDIO"))"
        AUDIO_ARGS=(-a "$(seq -s, 1 "$NUM_AUDIO")" -E "${AENC_LIST%,}" --audio-fallback flac24)
    else
        AUDIO_ARGS=(-a none)
    fi

    SUB_ARGS=()
    if [[ "$NUM_SUB" -gt 0 ]]; then
        SUB_ARGS=(-s "$(seq -s, 1 "$NUM_SUB")")
    fi

    read -rp "Output filename for this title (e.g. 'Movie Name (2020).mkv' or 'S01E01 - Title.mkv'): " OUT_NAME
    [[ -n "$OUT_NAME" ]] || OUT_NAME="title-$TITLE"
    [[ "$OUT_NAME" == *.mkv ]] || OUT_NAME="$OUT_NAME.mkv"
    if [[ -e "$DEST/$OUT_NAME" ]]; then
        echo "Error: '$DEST/$OUT_NAME' already exists -- not overwriting it." >&2
        exit 1
    fi

    echo "Encoding title $TITLE -> $DEST/$OUT_NAME ..."
    HandBrakeCLI \
        --verbose=2 \
        -i "$DISC_DIR" \
        -t "$TITLE" \
        -o "$DEST/$OUT_NAME" \
        -e x265 --encoder-preset slow -q 20 \
        --comb-detect --decomb \
        "${AUDIO_ARGS[@]}" \
        "${SUB_ARGS[@]}" \
        -m
done

echo
echo "Done. Files are in $DEST"
