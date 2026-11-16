# common.bash -- shared setup for the 1x scripts. Not run on its own: every
# script sources it right after `set` and SCRIPT_DIR, so a fix made here
# applies to all of them:
#
#   SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
#   source "$SCRIPT_DIR/common.bash" || exit 1
#
# Provides:
#   - logging of the whole run to /temp/logs (when run from a terminal);
#   - success_sound / error_sound, played on exit by status;
#   - Ctrl+C / kill handling (exit with an error, so the error sound plays);
#   - an optional cleanup hook: define `cleanup()` in the script and it runs
#     on every exit, before the sound (its failure never skips the sound);
#   - detect_device, drive_id, need_space, lock_device.
#
# SCRIPT_DIR must be set by the caller: the sounds live next to the scripts.

# shellcheck shell=bash

# Log the whole run to /temp/logs, but only when input and output are a
# terminal (piped input, e.g. `echo y | ...`, goes straight to the
# script): `script` re-runs the calling script inside a pseudo-terminal,
# so progress bars and prompts keep working and everything is also saved.
# Sourced without arguments, "$@" here is the calling script's arguments.
if [[ -t 0 && -t 1 && -z "${DIGITIZE_LOG:-}" ]]; then
    mkdir -pv /temp/logs >&2
    DIGITIZE_LOG="/temp/logs/$(basename "$0" .bash)-$(date +%Y%m%d-%H%M%S).log"
    export DIGITIZE_LOG
    echo "Logging to $DIGITIZE_LOG" >&2
    SHELL=/bin/bash exec script -qef -c "$(printf '%q ' bash "$0" "$@")" "$DIGITIZE_LOG"
fi

success_sound() { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/outcome-success.oga" >/dev/null 2>&1 || true; }
error_sound()   { ffplay -nodisp -autoexit -loglevel quiet "$SCRIPT_DIR/dialog-error.oga"    >/dev/null 2>&1 || true; }

# shellcheck disable=SC2329  # called by the trap
on_exit() {
    local rc=$?
    if declare -F cleanup >/dev/null; then cleanup || true; fi
    if [[ $rc -eq 0 ]]; then success_sound; else error_sound; fi
}
trap on_exit EXIT
# Ctrl+C / kill: stop with an error status, so the error sound plays --
# even when the program running at that moment catches the signal and
# exits 0 (bash would otherwise just carry on with the next command).
trap 'exit 130' INT
trap 'exit 143' TERM

# Common paths for an optical drive across distros/setups: /dev/sr0 is the
# usual raw SCSI/USB name, the rest are symlinks some systems create.
# shellcheck disable=SC2329  # not every script uses every helper
detect_device() {
    local candidate
    for candidate in /dev/sr0 /dev/sr1 /dev/cdrom /dev/dvd /dev/dvdrw /dev/cdrw; do
        [[ -b "$candidate" ]] && { echo "$candidate"; return; }
    done
    echo "/dev/sr0"
}

# Identifies the physical drive behind $DEVICE, so each drive gets its own
# offset file: udev's ID_SERIAL (vendor_model_serial), or vendor + model
# from sysfs.
# shellcheck disable=SC2329
drive_id() {
    local id sysdev
    # `|| true`: with pipefail, a failing udevadm/cat would otherwise end
    # the script right here, silently, before the fallback or the error.
    id="$( { udevadm info --query=property --name="$DEVICE" 2>/dev/null || true; } | sed -n 's/^ID_SERIAL=//p')"
    if [[ -z "$id" ]]; then
        sysdev="/sys/class/block/$(basename "$(readlink -f "$DEVICE")")/device"
        id="$( { cat "$sysdev/vendor" "$sysdev/model" 2>/dev/null || true; } | xargs)"
    fi
    # Safe file name: anything but letters, digits, '.', '_' and '-' becomes '_'.
    id="$(printf '%s' "$id" | tr -c 'A-Za-z0-9._-' '_' | tr -s '_')"
    id="${id#_}"
    echo "${id%_}"
}

# /temp is a tmpfs (RAM): check the free space up front instead of
# failing halfway through a multi-GB copy. Argument: bytes needed.
# shellcheck disable=SC2329
need_space() {
    local need=$1 avail
    avail="$( { df -B1 --output=avail /temp 2>/dev/null || true; } | tail -n1 | tr -d ' ')"
    [[ "$avail" =~ ^[0-9]+$ ]] || { echo "Error: could not read the free space of /temp." >&2; exit 1; }
    echo "Space check: about $(numfmt --to=iec "$need") needed, $(numfmt --to=iec "$avail") free in /temp."
    if (( avail < need )); then
        echo "Error: not enough free space in /temp -- free some (old backups?) and try again." >&2
        exit 1
    fi
}

# One script per drive at a time: two programs reading the same drive at
# once (e.g. 11 while 12a rips) slow each other down or break the rip.
# Takes an exclusive lock for $DEVICE, held until the script exits (fd 9
# stays open; the child programs inherit it, which is harmless). The lock
# file lives in /temp/locks and is named after the real device (sr0).
# shellcheck disable=SC2329
lock_device() {
    local lock
    mkdir -p /temp/locks
    lock="/temp/locks/$(basename "$(readlink -f "$DEVICE")").lock"
    exec 9>"$lock"
    if ! flock -n 9; then
        echo "Error: another script is using $DEVICE right now -- wait for it to finish." >&2
        exit 1
    fi
}
