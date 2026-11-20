# shellcheck shell=bash disable=SC2034  # globals read by the scripts
#
# Shared setup and helpers for the optical-media scripts. Sourced, never run:
#   source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"
#
# On every exit: unmounts a disc mounted by mount_disc, runs cleanup() if the
# script defines one, then plays outcome-success.oga or dialog-error.oga.
# Ctrl+C or kill ends the script with an error status.

set -euo pipefail
shopt -s inherit_errexit

SCRIPT_DIR="$(realpath -- "$(dirname -- "${BASH_SOURCE[0]}")")"
CORES="$(nproc)"
DEVICE=""
MOUNTPOINT=""
TITLES=()
AUDIO_TRACKS=()
DATA_TRACKS=0
TRACK1_LSN=0
DISC_MODE=""
DRIVE_ID=""
OFFSET_FILE=""

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

# need COMMAND...: stops if a program is missing.
need() {
    local cmd
    for cmd in "$@"; do
        command -v "${cmd}" >/dev/null ||
            die "'${cmd}' not found; see 10a-install-dependencies.bash."
    done
}

# confirm PROMPT: Enter or y goes on; anything else, or Ctrl+D, exits.
confirm() {
    local answer
    read -rp "$1 [Y/n] " answer || answer=n   # read clears it at EOF
    [[ "${answer}" =~ ^[Yy]?$ ]] || { echo "Cancelled."; exit 0; }
}

# use_device [DEVICE]: sets DEVICE (default /dev/sr0) and checks it.
use_device() {
    DEVICE="${1:-/dev/sr0}"
    [[ -b "${DEVICE}" ]] || die "'${DEVICE}' is not a block device."
}

# set_drive_id: DRIVE_ID from udev's ID_SERIAL, made safe as a file name,
# and OFFSET_FILE, where 10b saves the drive's read offset for 12a.
set_drive_id() {
    local props id
    props="$(udevadm info --query=property --name="${DEVICE}")"
    id="$(sed -n 's/^ID_SERIAL=//p' <<<"${props}")"
    [[ -n "${id}" ]] || die "udev reports no serial for ${DEVICE}."
    id="$(printf '%s' "${id}" | tr -c 'A-Za-z0-9._-' '_' | tr -s '_')"
    id="${id#_}"
    DRIVE_ID="${id%_}"
    OFFSET_FILE="${SCRIPT_DIR}/drive-offsets/drive-offset.${DRIVE_ID}"
    echo "Drive: ${DRIVE_ID}"
}

# read_toc: DISC_MODE, AUDIO_TRACKS, DATA_TRACKS and TRACK1_LSN from the
# disc's TOC. cd-info prints one row per track, e.g.
#   "  2: 05:22:40 024040 audio false no 2 no"  (number, MSF, LSN, type)
read_toc() {
    local toc audio
    toc="$(cd-info --dvd --no-header --no-device-info "${DEVICE}" \
        2>/dev/null)" || true
    DISC_MODE="$(sed -n 's/.*Disc mode is listed as: *//p' <<<"${toc}")"
    audio="$(awk '$1 ~ /^[0-9]+:$/ && $4 == "audio" {
        sub(":", "", $1); printf "%s ", $1 }' <<<"${toc}")"
    read -ra AUDIO_TRACKS <<<"${audio}"
    DATA_TRACKS="$(awk '$1 ~ /^[0-9]+:$/ && $4 != "audio" &&
        $4 != "leadout"' <<<"${toc}" | wc -l)"
    TRACK1_LSN="$(awk '$1 == "1:" { print $3 + 0 }' <<<"${toc}")"
    TRACK1_LSN="${TRACK1_LSN:-0}"
}

# check_dest DIR: refuses a folder that holds another disc's audio.
check_dest() {
    local found
    found="$(find "$1" \( -iname '*.wav' -o -iname '*.flac' \) -print \
        -quit 2>/dev/null)" || true
    [[ -z "${found}" ]] ||
        die "'$1' holds audio from another disc; move it or pick a folder."
}

# need_disc_space PERCENT: stops unless /temp (RAM) has PERCENT % of the
# disc size free.
need_disc_space() {
    local size avail need_bytes need_h avail_h
    size="$(lsblk -bdno SIZE "${DEVICE}")" ||
        die "could not read the size of the disc in ${DEVICE}."
    avail="$(df -B1 --output=avail /temp | tail -n 1)"
    need_bytes=$(( size * $1 / 100 ))
    need_h="$(numfmt --to=iec "${need_bytes}")"
    avail_h="$(numfmt --to=iec "${avail}")"
    echo "Space: ${need_h} needed, ${avail_h} free in /temp."
    (( avail >= need_bytes )) || die "not enough free space in /temp."
}

# mount_disc: mounts the disc read-only at a new MOUNTPOINT in /temp;
# MOUNTPOINT stays empty if the disc cannot be mounted.
mount_disc() {
    MOUNTPOINT="$(mktemp -d -p /temp)"
    if ! sudo mount -v -o ro -- "${DEVICE}" "${MOUNTPOINT}" >&2; then
        rmdir -v -- "${MOUNTPOINT}" >&2
        MOUNTPOINT=""
    fi
}

unmount_disc() {
    [[ -n "${MOUNTPOINT}" ]] || return 0
    if sudo umount -v -- "${MOUNTPOINT}" >&2; then
        rmdir -v -- "${MOUNTPOINT}" >&2
    fi
    MOUNTPOINT=""
}

# disc_dir NAME: prints the folder NAME (any case) at the disc's root.
disc_dir() {
    find "${MOUNTPOINT}" -maxdepth 1 -iname "$1" -type d -print -quit
}

# read_titles PROMPT: reads the DVD title numbers into TITLES.
read_titles() {
    local title
    read -rp "$1" -a TITLES
    (( ${#TITLES[@]} > 0 )) || die "no title chosen."
    for title in "${TITLES[@]}"; do
        [[ "${title}" =~ ^[0-9]+$ ]] || die "'${title}' is not a title."
    done
}

# each FUNCTION: runs FUNCTION once per NUL-separated item on stdin, one
# process per core. Exits with 123 (failing the script) if any run failed.
each() {
    export -f "${1?}"
    # shellcheck disable=SC2016  # expanded by the child shell
    xargs -0 -r -n 1 -P "${CORES}" bash -c \
        'set -euo pipefail; shopt -s inherit_errexit; "$0" "$1"' "$1"
}

on_exit() {
    local status=$? sound=dialog-error
    unmount_disc
    if declare -F cleanup >/dev/null; then cleanup; fi
    (( status != 0 )) || sound=outcome-success
    ffplay -nodisp -autoexit -loglevel quiet "${SCRIPT_DIR}/${sound}.oga" \
        >/dev/null 2>&1 || true
}
trap on_exit EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
