#!/usr/bin/env bash
#
# 04-convert-to-opus.bash <flac_directory>
#
# Recursively converts every FLAC in a tree to Opus, in place, at the
# codec's actual technical ceiling (256 kbit/s per channel), preserving
# the metadata and cover art Picard already embedded. Deletes each FLAC
# as soon as its Opus counterpart is generated successfully.

set -euo pipefail

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <flac_directory>" >&2
    completion_sound
    exit 1
fi
SOURCE="$1"

for cmd in metaflac opusenc; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; completion_sound; exit 1; }
done

[[ -d "$SOURCE" ]] || { echo "Error: directory '$SOURCE' does not exist." >&2; completion_sound; exit 1; }

total="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
echo "Converting $total FLAC file(s) in $SOURCE (parallel, $(nproc) cores)..."

find "$SOURCE" -type f -iname '*.flac' -print0 |
    xargs -0 -P"$(nproc)" -I{} bash -c '
        f="$1"
        channels="$(metaflac --show-channels "$f" 2>/dev/null | tail -n1 | tr -cd "0-9")"
        if ! [[ "$channels" =~ ^[0-9]+$ ]] || [[ "$channels" -lt 1 ]]; then
            echo "Failed: $f (metaflac did not return a clean channel count: [$channels])" >&2
            exit 0
        fi
        bitrate=$(( channels * 256 ))
        out="${f%.flac}.opus"
        errfile="$(mktemp)"
        if [[ -z "$errfile" ]]; then
            echo "Failed: $f (mktemp itself returned nothing)" >&2
            exit 0
        fi
        if opusenc --bitrate "$bitrate" --vbr "$f" "$out" >"$errfile" 2>&1; then
            rm -- "$f"
        else
            echo "Failed: $f (channels=$channels bitrate=$bitrate) -- full output below:" >&2
            cat "$errfile" >&2
        fi
        rm -f "$errfile"
    ' _ {}

remaining="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
if [[ "$remaining" -gt 0 ]]; then
    echo "Warning: $remaining FLAC(s) were not converted (see errors above)." >&2
else
    echo "Done: all FLACs converted and removed."
fi

completion_sound
