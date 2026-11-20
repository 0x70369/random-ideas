#!/usr/bin/env bash
#
# 15b-compress-video-disc.bash <disc_dir> [destination_dir]
#
# Compresses a video disc already copied to disk (a VIDEO_TS folder, e.g.
# from 15a-backup-video-disc.bash) into one .mkv per title. It never reads
# the drive, so a flaky disc or a slow drive only costs you once.
#
# The VIDEO is re-encoded to x265 (CRF 20, slow preset: a large size
# reduction from DVD MPEG-2 at close to transparent quality). Every AUDIO
# and SUBTITLE track is copied as it is -- they are small, and re-encoding
# a lossy track (AC-3, DTS, MP2) only loses more. An audio track HandBrake
# cannot pass through (DVD LPCM) becomes Opus at 256 kbit/s per channel,
# all its channels kept -- the same ceiling as 14-convert-to-opus.bash
# (HandBrake caps -B there). Chapters become MKV chapters. No cropping
# (--crop 0:0:0:0): automatic black-bar detection can cut real picture in
# dark scenes, and bars cost almost nothing.
#
# Several titles can be picked in one run (e.g. a TV season with one
# title per episode). The VIDEO_TS backup is never deleted.

set -euo pipefail

SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1   # shared setup and helpers

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $0 <disc_dir> [destination_dir]" >&2
    exit 1
fi
DISC_DIR="$1"
DEST="${2:-/temp/video-final}"
need HandBrakeCLI
[[ -n "$(find "$DISC_DIR" -maxdepth 1 -iname VIDEO_TS -type d \
    -print -quit)" ]] || die "no VIDEO_TS folder (any case) in '$DISC_DIR'."
mkdir -pv "$DEST"

# Scans use plain -v: higher levels bury the track list. The encode uses 2.
echo "=== All titles in $DISC_DIR ==="
HandBrakeCLI -v -i "$DISC_DIR" -t 0 --scan
echo
read_titles "Title number(s) to encode (e.g. '1' or '1 2 3'): "

# ask_count PROMPT: a whole number (a typo would only fail inside
# HandBrake, much later).
ask_count() {
    local answer
    until [[ "${answer:-}" =~ ^[0-9]+$ ]]; do read -rp "$1" answer; done
    echo "$answer"
}

for TITLE in "${TITLES[@]}"; do
    echo
    echo "=== Title $TITLE (look for its audio and subtitle tracks) ==="
    HandBrakeCLI -v -i "$DISC_DIR" -t "$TITLE" --scan
    echo
    AUDIO="$(ask_count "How many audio tracks does it have? ")"
    SUBS="$(ask_count "How many subtitle tracks (0 if none)? ")"

    # Every track copied as it is; Opus only for one that cannot be.
    # -B is ignored for copied tracks, and capped by HandBrake at 256
    # kbit/s per channel for Opus; its default would be 96 per pair.
    AUDIO_ARGS=(-a none)
    if (( AUDIO > 0 )); then
        ENCODERS=copy RATES=6144
        for (( i = 1; i < AUDIO; i++ )); do
            ENCODERS+=,copy RATES+=,6144
        done
        AUDIO_ARGS=(-a "$(seq -s, 1 "$AUDIO")" -E "$ENCODERS" -B "$RATES"
                    --audio-fallback opus)
    fi
    SUB_ARGS=()
    (( SUBS == 0 )) || SUB_ARGS=(-s "$(seq -s, 1 "$SUBS")")

    read -rp "Output file (e.g. 'Movie (2020).mkv', 'S01E01 - Title'): " NAME
    NAME="${NAME:-title-$TITLE}"
    [[ "$NAME" != */* ]] || die "the file name cannot contain '/'."
    [[ "$NAME" == *.mkv ]] || NAME+=.mkv
    [[ ! -e "$DEST/$NAME" ]] || die "'$DEST/$NAME' already exists."

    echo "Encoding title $TITLE -> $DEST/$NAME ..."
    HandBrakeCLI --verbose=2 -i "$DISC_DIR" -t "$TITLE" -o "$DEST/$NAME" \
        -e x265 --encoder-preset slow -q 20 --comb-detect --decomb \
        --crop 0:0:0:0 "${AUDIO_ARGS[@]}" "${SUB_ARGS[@]}" -m
done

echo
echo "Done. Files are in $DEST"
