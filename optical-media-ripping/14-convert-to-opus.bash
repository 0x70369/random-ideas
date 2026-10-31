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
# Ctrl+C / kill: stop with an error status, so the error sound plays --
# even when the program running at that moment catches the signal and
# exits 0 (bash would otherwise just carry on with the next command).
trap 'exit 130' INT
trap 'exit 143' TERM

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <flac_directory>" >&2
    exit 1
fi
SOURCE="$1"

for cmd in metaflac opusenc ffprobe; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done
command -v rsgain >/dev/null 2>&1 || { echo "Error: 'rsgain' not found. Install it from the AUR: paru -S rsgain" >&2; exit 1; }

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
            if opusenc --bitrate "$bitrate" "$f" "$out" >"$logfile" 2>&1; then
                # The Opus is complete: from here on, never delete it.
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
# Every album in the tree (the skip check below makes this cheap). One
# album per folder holding .opus files; a "Disco N" / "Disc N" / "CD N"
# folder belongs to the album folder above it.
mapfile -d '' -t ALBUMS < <(
    find "$SOURCE" -type f -iname '*.opus' -printf '%h\0' |
        while IFS= read -r -d '' dir; do
            if [[ "$(basename "$dir")" =~ ^(Disco|Disc|CD)[[:space:]_-]*[0-9]+$ ]]; then
                dir="$(dirname "$dir")"
            fi
            printf '%s\0' "$dir"
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
