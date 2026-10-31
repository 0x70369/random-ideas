#!/usr/bin/env bash
#
# 04-convert-to-opus.bash <flac_directory>
#
# Recursively converts every FLAC in a tree to Opus, in place, at the
# codec's actual technical ceiling (256 kbit/s per channel), preserving
# the metadata and cover art Picard already embedded. Deletes each FLAC
# as soon as its Opus counterpart is generated successfully.
#
# opusenc's full output for each file is captured and printed in one block
# when that file finishes, so 32 parallel encoders don't interleave their
# progress lines into an unreadable mess.

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
    echo "Usage: $0 <flac_directory>" >&2
    exit 1
fi
SOURCE="$1"

for cmd in metaflac opusenc; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "Error: '$cmd' not found." >&2; exit 1; }
done

[[ -d "$SOURCE" ]] || { echo "Error: directory '$SOURCE' does not exist." >&2; exit 1; }

total="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
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
        out="${f%.flac}.opus"
        logfile="$(mktemp -p /temp)"
        if [[ -z "$logfile" ]]; then
            echo "Failed: $f (mktemp itself returned nothing)" >&2
            exit 0
        fi
        if opusenc --bitrate "$bitrate" "$f" "$out" >"$logfile" 2>&1; then
            echo "=== OK: $f (channels=$channels bitrate=$bitrate) ==="
            cat "$logfile"
            rm -v -- "$f"
        else
            echo "=== Failed: $f (channels=$channels bitrate=$bitrate) ===" >&2
            cat "$logfile" >&2
        fi
        rm -fv "$logfile"
    ' _ {}

remaining="$(find "$SOURCE" -type f -iname '*.flac' | wc -l)"
if [[ "$remaining" -gt 0 ]]; then
    echo "Error: $remaining FLAC(s) were not converted (see errors above)." >&2
    exit 1
fi
echo "Done: all FLACs converted and removed."
