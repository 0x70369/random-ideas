#!/usr/bin/env bash
#
# 02b-rip-dvd-video.bash [device] [destination_dir]
#
# Extracts audio from a live-show DVD-Video into FLAC, one file per
# chapter. If no device is given, auto-detects among common optical-drive
# paths (/dev/sr0, /dev/cdrom, etc.) -- passing a path explicitly always
# works too. Shows the lsdvd listing and lets you pick which title(s) to
# extract -- including more than one, e.g. when a disc has the full show
# plus a separate instrumental-only title.
#
# How it works, per chosen title:
#   1. dvdbackup -t copies ONLY that title's sectors into a temp folder in
#      /temp. Several titles often share one VTS_xx_*.VOB set; copying the
#      whole set would drag the other titles in, and the chapter times
#      would no longer line up (the last chapter would run into them).
#   2. ffprobe lists that copy's audio streams with their stream ids
#      (0xa0-0xa7 = LPCM, 0x80-0x87 = AC-3, 0x88-0x8f = DTS) and you pick
#      one BY ID -- the stream order ffmpeg sees is not guaranteed to match
#      lsdvd's numbering, the id is unambiguous.
#   3. ffmpeg extracts that stream to one FLAC; dvdxchap's chapter times
#      cut it into one FLAC per chapter.
#
# Why not ffmpeg -f dvdvideo: that demuxer failed to read even the first
# chapter on one of your discs; lsdvd/dvdxchap/dvdbackup read the same
# disc structure without that problem.

set -euo pipefail

# Resolved once at startup: if a script cd's elsewhere later, a relative $0
# would point to the wrong folder and the sounds would not be found.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }

WORK=""
# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    [[ -n "$WORK" && -d "$WORK" ]] && rm -rfv "$WORK"
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

for cmd in lsdvd dvdbackup dvdxchap ffprobe ffmpeg; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }

# Never mix two discs: output folders are always title-N/NN.flac.
if [[ -n "$(find "$DEST" \( -iname '*.wav' -o -iname '*.flac' \) -print -quit 2>/dev/null)" ]]; then
    echo "Error: '$DEST' still has audio files from another disc. Process/move them first, or pass another folder." >&2
    exit 1
fi

WORK="$(mktemp -d -p /temp)"

echo "=== lsdvd listing (titles, chapters, audio streams) ==="
lsdvd -a "$DEVICE"
echo "========================================================"
echo

read -rp "Which title number(s) do you want to extract? (space-separated, e.g. '1' or '1 3') " -a TITLES
[[ "${#TITLES[@]}" -gt 0 ]] || { echo "Error: no title chosen." >&2; exit 1; }
for TITLE in "${TITLES[@]}"; do
    [[ "$TITLE" =~ ^[0-9]+$ ]] || { echo "Error: '$TITLE' is not a title number." >&2; exit 1; }
done

# VOBs often announce streams late; probe deeper than ffmpeg's default.
PROBE=(-analyzeduration 100M -probesize 100M)

for TITLE in "${TITLES[@]}"; do
    echo
    echo "--- Title $TITLE ---"
    echo "Copying only title $TITLE from the disc (this can take a while)..."
    dvdbackup -v -i "$DEVICE" -t "$TITLE" -n "title-$TITLE" -o "$WORK"

    mapfile -t VOB_FILES < <(find "$WORK/title-$TITLE" -iname 'VTS_*_[1-9].VOB' | sort)
    [[ "${#VOB_FILES[@]}" -gt 0 ]] || { echo "Error: dvdbackup produced no VOB for title $TITLE." >&2; exit 1; }
    CONCAT_INPUT="$(printf '%s|' "${VOB_FILES[@]}")"
    CONCAT_INPUT="concat:${CONCAT_INPUT%|}"

    echo
    echo "=== Audio streams in title $TITLE (id: 0xa0-0xa7 LPCM, 0x80-0x87 AC-3, 0x88-0x8f DTS) ==="
    ffprobe -v error "${PROBE[@]}" -select_streams a \
        -show_entries stream=id,codec_name,channels,sample_rate,bit_rate -of compact=p=0 \
        "$CONCAT_INPUT"
    echo "========================================================================================="
    while :; do
        read -rp "Stream id to extract (e.g. 0xa0): " STREAM_ID
        [[ "$STREAM_ID" =~ ^0x[0-9a-fA-F]+$ ]] && break
        echo "Please type the id exactly as shown above (0x...)." >&2
    done

    OUT_DIR="$DEST/title-$TITLE"
    mkdir -pv "$OUT_DIR"
    WHOLE="$WORK/title-$TITLE.flac"

    echo "Extracting the whole title as one file..."
    ffmpeg -n -loglevel verbose "${PROBE[@]}" -i "$CONCAT_INPUT" -map "0:i:$STREAM_ID" -vn -c:a flac "$WHOLE"

    echo "Reading chapter timecodes with dvdxchap..."
    mapfile -t CHAPTER_STARTS < <(dvdxchap -t "$TITLE" "$DEVICE" | grep -oP '^CHAPTER[0-9]+=\K.*')
    [[ "${#CHAPTER_STARTS[@]}" -gt 0 ]] || { echo "Error: dvdxchap returned no chapters for title $TITLE." >&2; exit 1; }

    echo "Splitting into ${#CHAPTER_STARTS[@]} chapter(s)..."
    for i in "${!CHAPTER_STARTS[@]}"; do
        n=$((i + 1))
        start="${CHAPTER_STARTS[$i]}"
        if [[ $n -lt "${#CHAPTER_STARTS[@]}" ]]; then
            end_args=(-to "${CHAPTER_STARTS[$n]}")
        else
            end_args=()
        fi
        out="$OUT_DIR/$(printf '%02d' "$n").flac"
        echo "  chapter $n ($start) -> $out"
        ffmpeg -n -loglevel verbose -ss "$start" "${end_args[@]}" -i "$WHOLE" -c:a flac "$out"
    done

    # Free the tmpfs RAM before the next title.
    rm -rfv "$WORK/title-$TITLE" "$WHOLE"
done

echo
echo "Done. Files are in $DEST"
