#!/usr/bin/env bash
#
# 14-convert-to-opus.bash <flac_directory>
#
# Recursively converts every FLAC in a tree to Opus, in place, at the
# codec's actual technical ceiling (256 kbit/s per channel), preserving
# the metadata and cover art Picard already embedded. Deletes each FLAC
# as soon as its Opus counterpart is generated successfully. Then writes
# the loudness-normalization tags of the Opus standard (RFC 7845) with
# rsgain (AUR).
#
# opusenc's full output for each file is captured and printed in one block
# when that file finishes, so 32 parallel encoders don't interleave their
# progress lines into an unreadable mess.
#
# Before converting:
#   - HDCD: CD audio (16-bit FLACs) is checked for HDCD codes, which hide
#     about 20 bits of dynamic range in the 16-bit stream. Only if an album
#     has them, you are asked whether to decode them (ffmpeg's hdcd filter,
#     to 24-bit) before the Opus encode. Decoding restores the extended
#     range but changes the sound against a plain CD player (peak extension
#     can expand the top 3 dB into 9 dB), and the FLACs are deleted later,
#     so the choice is final -- hence the question. Tags and cover are kept.
# Before deleting each FLAC:
#   - the Opus is decoded completely and its duration compared with the
#     FLAC's (at most 0.1 s apart); if either check fails, the FLAC stays.
#
# Normalization, the Opus way only (RFC 7845): R128_TRACK_GAIN and
# R128_ALBUM_GAIN tags, referenced to -23 LUFS, and the header "output
# gain" at 0 dB. Players that read the tags even out the volume; the others
# play the files exactly as the CD sounds. The audio is never touched.
#   - Album gain is computed per album, following the final tree
#     "Artist/Album - Year/[Disco N/]NN - Title.opus": a "Disco N" folder
#     counts as one album together with its sibling discs.
#   - Albums whose files ALL have both R128 tags already are skipped, so
#     rerunning on /temp/final after ripping another CD only tags the new
#     album (and any album an earlier run failed to tag). With no FLAC
#     left to convert, the script only does this check. The check is per album, not per file: a new file (e.g. the
#     second disc of an album) changes the album gain of every file in that
#     album, so the whole album is measured again.
#   - Any REPLAYGAIN_* tags in the FLACs are removed first: opusenc would
#     turn them into the header output gain, which every player applies
#     unconditionally (the files would play quieter everywhere).
#   - rsgain settings: its recommended ones (ReplayGain 2.0 measurement,
#     clipping protection for positive gains), with Opus mode "s" -- R128
#     tags at -23 LUFS, header gain 0.

set -euo pipefail

# Shared setup -- logging to /temp/logs, sounds, Ctrl+C, drive helpers --
# lives in common.bash, next to the scripts. SCRIPT_DIR is resolved first:
# a relative $0 would break once the script cd's elsewhere.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <flac_directory>" >&2
    exit 1
fi
SOURCE="$1"

for cmd in metaflac opusenc ffmpeg ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done
command -v rsgain >/dev/null 2>&1 || { echo "Error: 'rsgain' not found. Install it from the AUR: yay -S --needed rsgain" >&2; exit 1; }

[[ -d "$SOURCE" ]] || { echo "Error: directory '$SOURCE' does not exist." >&2; exit 1; }

total="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
if [[ "$total" -eq 0 ]] && [[ -z "$(find "$SOURCE" -type f -iname '*.opus' -print -quit)" ]]; then
    echo "Error: no FLAC or Opus files found in '$SOURCE'." >&2
    exit 1
fi

# --- Remove ReplayGain tags from the FLACs ---------------------------------
RG_TAGS=(REPLAYGAIN_ALBUM_GAIN REPLAYGAIN_ALBUM_PEAK REPLAYGAIN_TRACK_GAIN
         REPLAYGAIN_TRACK_PEAK REPLAYGAIN_REFERENCE_LOUDNESS)
RG_SHOW=() RG_REMOVE=()
for tag in "${RG_TAGS[@]}"; do RG_SHOW+=("--show-tag=$tag"); RG_REMOVE+=("--remove-tag=$tag"); done
while IFS= read -r -d '' f; do
    if [[ -n "$(metaflac "${RG_SHOW[@]}" "$f" 2>/dev/null)" ]]; then
        echo "Removing ReplayGain tags (they would become a header gain): $f"
        metaflac "${RG_REMOVE[@]}" "$f"
    fi
done < <(find "$SOURCE" -type f -iname '*.flac' -print0)

# Album folder of a file's folder: a "Disco N" / "Disc N" / "CD N" folder
# belongs to the album folder above it.
album_of() {
    local dir="$1"
    if [[ "$(basename "$dir")" =~ ^(Disco|Disc|CD)[[:space:]_-]*[0-9]+$ ]]; then
        dir="$(dirname "$dir")"
    fi
    printf '%s' "$dir"
}

# --- HDCD -------------------------------------------------------------------
# Detection, in parallel: only 16-bit FLACs (CD audio) can carry HDCD. The
# filter decodes the whole file to null and reports "HDCD detected: yes/no".
if [[ "$total" -gt 0 ]]; then
    echo "Checking $total FLAC file(s) for HDCD (parallel, $(nproc) cores)..."
    # shellcheck disable=SC2016  # single quotes on purpose: expanded by the inner bash
    mapfile -d '' -t HDCD_FILES < <(
        find "$SOURCE" -type f -iname '*.flac' -print0 |
            xargs -0 -n 1 -P"$(nproc)" bash -c '
                [[ "$(metaflac --show-bps "$1" 2>/dev/null)" == 16 ]] || exit 0
                if ffmpeg -nostdin -hide_banner -nostats -i "$1" -af hdcd -c:a pcm_s32le -f null - 2>&1 |
                        grep -q "HDCD detected: yes"; then
                    printf "%s\0" "$1"
                fi
            ' _ | sort -z
    )
    if [[ "${#HDCD_FILES[@]}" -eq 0 ]]; then
        echo "No HDCD found."
    else
        # One question per album, so all its tracks are treated the same.
        declare -A HDCD_COUNT=()
        for f in "${HDCD_FILES[@]}"; do
            album="$(album_of "$(dirname "$f")")"
            HDCD_COUNT["$album"]=$(( ${HDCD_COUNT["$album"]:-0} + 1 ))
        done
        DECODE=()
        for album in "${!HDCD_COUNT[@]}"; do
            echo
            echo "HDCD found in ${HDCD_COUNT[$album]} track(s) of: $album"
            echo "  Decoding restores the extended dynamic range the disc was mastered"
            echo "  with, but sounds different from a plain CD player (peak extension"
            echo "  can expand the top 3 dB into 9 dB). The FLACs are deleted after the"
            echo "  conversion, so this choice is final."
            while :; do
                read -rp "  Decode HDCD for this album? [y/n] " reply ||
                    { echo "Error: no answer (no terminal?) -- nothing was converted." >&2; exit 1; }
                [[ "$reply" =~ ^[YyNn]$ ]] && break
            done
            if [[ "$reply" =~ ^[Yy]$ ]]; then
                for f in "${HDCD_FILES[@]}"; do
                    [[ "$(album_of "$(dirname "$f")")" == "$album" ]] && DECODE+=("$f")
                done
            fi
        done
        if [[ "${#DECODE[@]}" -gt 0 ]]; then
            echo "Decoding HDCD in ${#DECODE[@]} file(s) to 24-bit FLAC (tags and cover kept)..."
            # Each file is decoded to a temporary FLAC in /temp and then moved
            # over the original, which no longer has HDCD codes afterwards --
            # so a rerun does not ask again. -map 0 -c:v copy keeps the cover.
            # shellcheck disable=SC2016  # single quotes on purpose: expanded by the inner bash
            if ! printf '%s\0' "${DECODE[@]}" |
                xargs -0 -n 1 -P"$(nproc)" bash -c '
                    f="$1"
                    tmp="$(mktemp -p /temp --suffix=.flac)"
                    trap '\''rm -f -- "$tmp"; exit 130'\'' INT TERM
                    if ffmpeg -nostdin -v error -y -i "$f" -map 0 -c:v copy -af hdcd \
                            -c:a flac -compression_level 8 -sample_fmt s32 -bits_per_raw_sample 24 \
                            -fflags +bitexact -flags:a +bitexact "$tmp" &&
                            mv -f -- "$tmp" "$f"; then
                        echo "HDCD decoded: $f"
                    else
                        rm -f -- "$tmp"
                        echo "Failed to decode HDCD: $f" >&2
                        exit 1
                    fi
                ' _; then
                echo "Error: HDCD decoding failed for some file(s) -- nothing was converted." >&2
                exit 1
            fi
        fi
    fi
fi

# --- FLAC -> Opus -----------------------------------------------------------
if [[ "$total" -eq 0 ]]; then
    echo "No FLAC to convert in $SOURCE -- only checking the normalization tags."
else
    echo "Converting $total FLAC file(s) in $SOURCE (parallel, $(nproc) cores)..."

    # shellcheck disable=SC2016  # single quotes on purpose: expanded by the inner bash
    find "$SOURCE" -type f -iname '*.flac' -print0 |
        xargs -0 -P"$(nproc)" -I{} bash -c '
            f="$1"
            channels="$(metaflac --show-channels "$f" 2>/dev/null | tail -n1 | tr -cd "0-9")"
            if ! [[ "$channels" =~ ^[0-9]+$ ]] || [[ "$channels" -lt 1 ]]; then
                echo "Failed: $f (metaflac did not return a clean channel count: [$channels])" >&2
                exit 0
            fi
            bitrate=$(( channels * 256 ))
            out="${f%.*}.opus"   # also strips an upper-case .FLAC
            logfile="$(mktemp -p /temp)"
            if [[ -z "$logfile" ]]; then
                echo "Failed: $f (mktemp itself returned nothing)" >&2
                exit 0
            fi
            # Ctrl+C / kill mid-encode: no half-written Opus or stray log left.
            trap '\''rm -f -- "$out" "$logfile"; exit 130'\'' INT TERM
            # Deleting the FLAC cannot be undone: before that, the Opus must
            # decode completely, and last as long as the FLAC (<= 0.1 s apart).
            verify() {
                local samples rate flac_s opus_s errors
                errors="$(ffmpeg -nostdin -v error -i "$out" -f null - 2>&1)" || { echo "decode failed: $errors"; return 1; }
                [[ -z "$errors" ]] || { echo "decode errors: $errors"; return 1; }
                samples="$(metaflac --show-total-samples "$f")"
                rate="$(metaflac --show-sample-rate "$f")"
                opus_s="$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$out")"
                if [[ "$samples" =~ ^[1-9][0-9]*$ && "$rate" =~ ^[1-9][0-9]*$ ]]; then
                    flac_s="$(awk -v n="$samples" -v r="$rate" "BEGIN { printf \"%.3f\", n / r }")"
                    awk -v a="$flac_s" -v b="$opus_s" "BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= 0.1) }" ||
                        { echo "duration mismatch: FLAC ${flac_s}s, Opus ${opus_s}s"; return 1; }
                    echo "verified: decodes cleanly, ${opus_s}s (FLAC ${flac_s}s)"
                else
                    echo "FLAC length unknown: only the decode was checked"
                fi
            }
            if opusenc --bitrate "$bitrate" "$f" "$out" >"$logfile" 2>&1 &&
                    verify >>"$logfile" 2>&1; then
                # The Opus is complete and checked: from here on, never delete it.
                trap - INT TERM
                echo "=== OK: $f (channels=$channels bitrate=$bitrate) ==="
                cat "$logfile"
                rm -v -- "$f"
            else
                echo "=== Failed: $f (channels=$channels bitrate=$bitrate) ===" >&2
                cat "$logfile" >&2
                rm -fv -- "$out"   # no half-written Opus left behind
            fi
            rm -fv "$logfile"
        ' _ {}

    remaining="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
    if [[ "$remaining" -gt 0 ]]; then
        echo "Error: $remaining FLAC(s) were not converted (see errors above)." >&2
        exit 1
    fi
    echo "All FLACs converted and removed."
fi

# --- Normalization tags (RFC 7845) -----------------------------------------
# Every album in the tree (the skip check below makes this cheap), grouped
# with album_of.
mapfile -d '' -t ALBUMS < <(
    find "$SOURCE" -type f -iname '*.opus' -printf '%h\0' |
        while IFS= read -r -d '' dir; do
            printf '%s\0' "$(album_of "$dir")"
        done | sort -zu
)
echo "Checking R128 normalization tags of ${#ALBUMS[@]} album(s) (parallel, $(nproc) cores)..."

# One rsgain run per album: custom mode treats the files it gets as one
# album. -a album gain, -s i write the tags (rsgain's default only scans),
# -c p clipping protection for positive gains, -o s R128 tags at -23 LUFS
# with the header gain at 0. Output is captured per album and printed in
# one block, so parallel runs don't interleave.
# shellcheck disable=SC2016  # single quotes on purpose: expanded by the inner bash
if ! printf '%s\0' "${ALBUMS[@]}" |
    xargs -0 -n 1 -P"$(nproc)" bash -c '
        album="$1"
        mapfile -d "" -t files < <(find "$album" -type f -iname "*.opus" -print0 | sort -z)
        # Already done when every file has both tags (from an earlier run).
        untagged=0
        for f in "${files[@]}"; do
            tags="$(ffprobe -v error -show_entries stream_tags=R128_TRACK_GAIN,R128_ALBUM_GAIN:format_tags=R128_TRACK_GAIN,R128_ALBUM_GAIN -of default=nw=1 "$f" 2>/dev/null)"
            if ! grep -qi "^TAG:R128_TRACK_GAIN=" <<<"$tags" || ! grep -qi "^TAG:R128_ALBUM_GAIN=" <<<"$tags"; then
                untagged=$((untagged + 1))
            fi
        done
        if [[ "$untagged" -eq 0 ]]; then
            echo "=== Skipped: $album (all ${#files[@]} file(s) already tagged) ==="
            exit 0
        fi
        logfile="$(mktemp -p /temp)"
        trap '\''rm -f -- "$logfile"; exit 130'\'' INT TERM
        if rsgain custom -a -s i -c p -o s "${files[@]}" >"$logfile" 2>&1; then
            echo "=== OK: $album (${#files[@]} file(s), $untagged of them were untagged) ==="
            cat "$logfile"
            rm -f -- "$logfile"
        else
            echo "=== Failed: $album ===" >&2
            cat "$logfile" >&2
            rm -f -- "$logfile"
            exit 1
        fi
    ' _; then
    echo "Error: the normalization tags failed for some album(s) (see the 'Failed' blocks above)." >&2
    exit 1
fi
echo "Done: every album has R128 normalization tags (header gain 0 dB)."
