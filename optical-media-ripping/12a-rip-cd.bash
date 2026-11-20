#!/usr/bin/env bash
#
# 12a-rip-cd.bash [device] [destination_dir]
#
# Rips an audio CD to FLAC with cyanrip, extraction only (tagging is done in
# Picard). cyanrip corrects the drive's read offset (saved by 10b), verifies
# each track against AccurateRip, applies de-emphasis when the disc needs
# it and writes a rip log. This script then reads the log and gives the
# verdict: error status on read errors or AccurateRip mismatches (the files
# are kept). Only audio tracks are ripped; audio hidden before track 1
# (HTOA) becomes track 0.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

need cd-info cyanrip eject udevadm
use_device "${1:-}"
dest="${2:-/temp/rip}"
check_dest "${dest}"
set_drive_id
[[ -f "${OFFSET_FILE}" ]] ||
    die "no read offset for this drive; run ./10b-find-drive-offset.bash."
offset="$(<"${OFFSET_FILE}")"
[[ "${offset}" =~ ^-?[0-9]+$ ]] || die "'${OFFSET_FILE}' is not a number."

read_toc
(( ${#AUDIO_TRACKS[@]} > 0 )) || die "no audio tracks on the disc."

# -N no MusicBrainz lookup, -U no cover download, -K no ReplayGain tags
# (opusenc would turn them into a header gain; see 14).
args=(-d "${DEVICE}" -s "${offset}" -N -U -K)
if (( DATA_TRACKS > 0 )); then
    # Enhanced CD: list the audio tracks, so the data track is skipped.
    list="$(IFS=,; echo "${AUDIO_TRACKS[*]}")"
    echo "Enhanced CD: ripping only audio tracks ${list}."
    args+=(-l "${list}")
elif (( TRACK1_LSN >= 150 )); then
    # Track 1 starts 2 s or more into the disc: hidden audio (HTOA).
    echo "Saving the $(( TRACK1_LSN / 75 )) s before track 1 as track 0."
    args+=(-p "1=track")
fi

mkdir -pv -- "${dest}"
cd -- "${dest}"
status=0
cyanrip "${args[@]}" || status=$?
eject -v -- "${DEVICE}"

log="$(find . -iname '*.log' -print -quit)"
[[ -n "${log}" ]] || die "no rip log (cyanrip exit status ${status})."
echo "Rip log: ${dest}/${log#./}"
disc_id="$(sed -n 's/^[[:space:]]*DiscID:[[:space:]]*//p' "${log}" |
    head -n 1)"
[[ -z "${disc_id}" ]] ||
    echo "Releases with this disc: https://musicbrainz.org/cdtoc/${disc_id}"

# last_value REGEX: the last \1 match of REGEX (no '|' in it) in the log.
last_value() { sed -nE "s|$1|\\1|p" "${log}" | tail -n 1; }
ar="$(last_value '^AccurateRip:[[:space:]]*(.*)')"
accurate="$(last_value '^Tracks ripped accurately: ([0-9]+)/.*')"
errors="$(last_value '^Ripping errors: ([0-9]+).*')"
expected=${#AUDIO_TRACKS[@]}

echo
echo "=== Verdict ==="
failed=false
if (( status != 0 )); then
    echo "cyanrip exited with status ${status}."
    failed=true
fi
if [[ -z "${errors}" ]]; then
    echo "No error count in the log; check it yourself."
    failed=true
elif (( errors > 0 )); then
    echo "Read errors: ${errors} (unreadable audio became silence)."
    failed=true
fi
case "${ar}" in
    found)
        if (( ${accurate:-0} >= expected )); then
            echo "AccurateRip: all ${expected} track(s) match."
        else
            echo "AccurateRip: ${accurate:-0} of ${expected} track(s) match;"
            echo "  clean the disc and rip again."
            failed=true
        fi
        ;;
    "not found" | mismatch)
        echo "AccurateRip: pressing not in the database; not verified."
        ;;
    *)
        echo "AccurateRip: ${ar:-no result}; not verified."
        ;;
esac
if "${failed}"; then
    die "NOT a clean rip; the files are kept in ${dest}."
fi
if [[ "${ar}" == found ]]; then
    echo "Result: clean rip, verified by AccurateRip."
else
    echo "Result: no read errors, but not verified by AccurateRip."
fi
