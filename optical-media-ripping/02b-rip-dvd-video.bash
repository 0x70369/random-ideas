#!/usr/bin/env bash
#
# 02b-rip-dvd-video.bash [/dev/srX] [destination_dir]
#
# Extracts audio from a live-show DVD-Video into FLAC, one file per
# chapter. Backs up the VIDEO_TS structure with dvdbackup, shows the full
# lsdvd listing (titles, chapter counts, audio streams) and lets you pick
# which title(s) to extract -- including more than one, e.g. when a disc
# has the full show plus a separate instrumental-only title.
#
# WHY NOT ffmpeg -f dvdvideo: that demuxer (libdvdnav/libdvdread-based
# chapter navigation) turned out to be unreliable against a plain
# VIDEO_TS folder -- it can fail to read even the first chapter on some
# discs. lsdvd and dvdxchap use the same libdvdread just for *reading*
# metadata and work fine, so this script uses them for information, and
# extracts the actual audio by concatenating the title's own .VOB files
# directly (plain MPEG-PS, no DVD navigation library involved), then cuts
# chapters out of that stream using dvdxchap's timecodes.

set -euo pipefail

DEVICE="${1:-/dev/sr0}"
DEST="${2:-/temp/rip}"
BACKUP_DIR="/temp"

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

for cmd in dvdbackup lsdvd dvdxchap ffmpeg; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; completion_sound; exit 1; }
done

echo "Copying the VIDEO_TS structure from $DEVICE into $BACKUP_DIR (this can take a while)..."
sudo dvdbackup -i "$DEVICE" -M -o "$BACKUP_DIR"

echo
echo "DVD folders found in $BACKUP_DIR:"
find "$BACKUP_DIR" -mindepth 2 -maxdepth 2 -iname VIDEO_TS -type d -printf '%h\n'
echo
read -rp "Which one is the disc you just copied? (full path) " DISC_DIR
VIDEO_TS_DIR="$(find "$DISC_DIR" -maxdepth 1 -iname VIDEO_TS -type d | head -n1)"
[[ -n "$VIDEO_TS_DIR" ]] || { echo "Error: no VIDEO_TS folder (any case) found under '$DISC_DIR'." >&2; completion_sound; exit 1; }

echo
echo "=== lsdvd listing (titles, chapters, audio streams) ==="
lsdvd -a "$DISC_DIR"
echo "========================================================"
echo
echo "=== VOB files in VIDEO_TS (to match a title to its VTS number) ==="
find "$VIDEO_TS_DIR" -maxdepth 1 -iname 'VTS_*.VOB' -exec ls -lh {} + 2>/dev/null || echo "(none found)"
echo "===================================================================="
echo

read -rp "Which title number(s) do you want to extract? (space-separated, e.g. '1' or '1 3') " -a TITLES

for TITLE in "${TITLES[@]}"; do
    echo
    echo "--- Title $TITLE ---"
    read -rp "Audio stream index for ffmpeg's -map (0 = lsdvd's 'Audio: 01', 1 = 'Audio: 02', ...): " AUDIO_IDX
    read -rp "VTS number backing this title (see the VOB listing above; usually the same number as the title): " VTS

    VTS_PADDED="$(printf '%02d' "$VTS")"
    mapfile -t VOB_FILES < <(find "$VIDEO_TS_DIR" -maxdepth 1 -iname "VTS_${VTS_PADDED}_[1-9].VOB" | sort)
    [[ "${#VOB_FILES[@]}" -gt 0 ]] || { echo "Error: no VTS_${VTS_PADDED}_*.VOB files found (any case) under '$VIDEO_TS_DIR'." >&2; completion_sound; exit 1; }
    echo "Using VOB files: ${VOB_FILES[*]}"

    CONCAT_INPUT="$(printf '%s|' "${VOB_FILES[@]}")"
    CONCAT_INPUT="${CONCAT_INPUT%|}"

    OUT_DIR="$DEST/title-$TITLE"
    mkdir -vp "$OUT_DIR"
    WHOLE="$OUT_DIR/whole-title.flac"

    echo "Extracting the whole title as one file (this can take a while)..."
    ffmpeg -loglevel error -i "concat:$CONCAT_INPUT" -map "0:a:$AUDIO_IDX" -vn -c:a flac "$WHOLE"

    echo "Reading chapter timecodes with dvdxchap..."
    mapfile -t CHAPTER_STARTS < <(dvdxchap -t "$TITLE" "$DISC_DIR" | grep -oP '^CHAPTER[0-9]+=\K.*')
    [[ "${#CHAPTER_STARTS[@]}" -gt 0 ]] || { echo "Error: dvdxchap returned no chapters for title $TITLE." >&2; exit 1; }

    echo "Splitting into ${#CHAPTER_STARTS[@]} chapter(s)..."
    for i in "${!CHAPTER_STARTS[@]}"; do
        n=$((i + 1))
        start="${CHAPTER_STARTS[$i]}"
        if [[ $((i + 1)) -lt "${#CHAPTER_STARTS[@]}" ]]; then
            end_args=(-to "${CHAPTER_STARTS[$((i + 1))]}")
        else
            end_args=()
        fi
        out="$OUT_DIR/$(printf '%02d' "$n").flac"
        echo "  chapter $n ($start) -> $out"
        ffmpeg -loglevel error -ss "$start" "${end_args[@]}" -i "$WHOLE" -c:a flac "$out"
    done

    rm -f "$WHOLE"
done

echo
echo "Done."

completion_sound
