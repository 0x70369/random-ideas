#!/usr/bin/env bash
#
# 10b-find-drive-offset.bash [device]
#
# One-time setup. Every CD drive reads audio a few samples early or late
# (its "read offset"); without correcting it, a rip is not bit-identical to
# the reference rips in the AccurateRip database and cannot be verified
# against them. This script finds your drive's offset with `cyanrip -f`
# and saves it as "drive-offsets/drive-offset.<drive id>" next to the
# scripts, where <drive id> is the drive's udev serial (vendor_model_serial)
# -- one file per drive. 12a-rip-cd.bash reads the file of whichever drive
# it uses.
#
# Insert a popular commercial audio CD first: `cyanrip -f` needs a disc
# that is in the AccurateRip database. If detection finds nothing, you can
# type the offset from the AccurateRip drive offset list instead. Run it
# once for each drive.

set -euo pipefail

# Shared setup -- logging to /temp/logs, sounds, Ctrl+C, drive helpers --
# lives in common.bash, next to the scripts. SCRIPT_DIR is resolved first:
# a relative $0 would break once the script cd's elsewhere.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1

DEVICE="${1:-$(detect_device)}"

command -v cyanrip >/dev/null 2>&1 || { echo "Error: 'cyanrip' not found. Install it from the AUR: yay -S --needed cyanrip" >&2; exit 1; }
[[ -b "$DEVICE" ]] || { echo "Error: '$DEVICE' is not a block device." >&2; exit 1; }
lock_device   # one script per drive at a time (common.bash)

DRIVE_ID="$(drive_id)"
[[ -n "$DRIVE_ID" ]] || { echo "Error: could not identify the drive behind '$DEVICE' (no udev serial, no vendor/model)." >&2; exit 1; }
OFFSET_DIR="$SCRIPT_DIR/drive-offsets"
OFFSET_FILE="$OFFSET_DIR/drive-offset.$DRIVE_ID"
echo "Drive: $DRIVE_ID"

if [[ -f "$OFFSET_FILE" ]]; then
    echo "Already saved for this drive: $(cat "$OFFSET_FILE") samples ($OFFSET_FILE) -- it will be replaced."
fi

# The drive's own vendor/model (SCSI inquiry), which is what the offset
# databases list. In a USB enclosure, udev's serial may name the USB
# bridge instead, so this is the better string to search for.
SYSDEV="/sys/class/block/$(basename "$(readlink -f "$DEVICE")")/device"
MODEL_STR="$( { cat "$SYSDEV/vendor" "$SYSDEV/model" 2>/dev/null || true; } | xargs)"
echo "Drive model (search this in the offset databases): ${MODEL_STR:-unknown}"
echo

echo "How do you want to get the offset?"
echo "  Enter = detect it with cyanrip -f (needs a mainstream commercial CD that AccurateRip knows)"
echo "  m     = type it yourself (e.g. from the AccurateRip drive offset list)"
read -rp "> " MODE
FOUND=""
if [[ ! "$MODE" =~ ^[Mm]$ ]]; then
    echo "Searching the read offset of $DEVICE..."
    # Output is shown live and kept, to read the result from its last line:
    #   "Drive offset of +6 found (confidence: 13)!"
    # Not fatal: when the disc is not in AccurateRip, -f finds nothing,
    # and you still get the other options below.
    CYANRIP_OUT="$(mktemp -p /temp)"
    cyanrip -d "$DEVICE" -f 2>&1 | tee "$CYANRIP_OUT" || echo "cyanrip -f exited with an error (see above)."
    FOUND="$(sed -n 's/^Drive offset of \([+-]\?[0-9]\+\) found.*/\1/p' "$CYANRIP_OUT" | tail -n1)"
    rm -fv "$CYANRIP_OUT"
fi

if [[ -n "$FOUND" ]]; then
    echo
    read -rp "Save the detected offset ${FOUND} for this drive? [Y/n] " reply
    reply=${reply:-Y}
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        OFFSET="${FOUND#+}"
        mkdir -pv "$OFFSET_DIR"
        printf '%s\n' "$OFFSET" > "$OFFSET_FILE"
        echo "Saved: $OFFSET samples -> $OFFSET_FILE"
        exit 0
    fi
fi

cat <<EOF

Other ways to get the offset:
  - Try 2 or 3 other mainstream commercial CDs (big-label pressings, not
    CD-Rs or rare releases). cyanrip only needs one disc AccurateRip knows,
    and nothing is ripped. Ctrl+C now, swap the disc, run this again.
  - Or look up your drive model (${MODEL_STR:-see above}) in:
      http://www.accuraterip.com/driveoffsets.htm
      https://www.daefeatures.co.uk/
  - 0 also works: the rips sound exactly the same, AccurateRip just can't
    confirm them. You can rerun this script later to replace it.
EOF
echo
while :; do
    read -rp "Offset to save, in samples (e.g. 6 or -1164; empty = cancel): " OFFSET
    [[ -n "$OFFSET" ]] || { echo "Cancelled -- nothing saved." >&2; exit 1; }
    [[ "$OFFSET" =~ ^[+-]?[0-9]+$ ]] && break
    echo "Please type a whole number (it can be negative)." >&2
done
OFFSET="${OFFSET#+}"   # the databases write positive offsets as "+667"

mkdir -pv "$OFFSET_DIR"
printf '%s\n' "$OFFSET" > "$OFFSET_FILE"
echo "Saved: $OFFSET samples -> $OFFSET_FILE"
