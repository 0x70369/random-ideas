#!/usr/bin/env bash
#
# 10a-install-dependencies.bash
#
# Checks every package the pipeline needs with `pacman -T` (deptest) and
# installs only the missing official ones with `pacman -S --needed`. The
# AUR packages are checked the same way, but only reported -- installing
# them needs an AUR helper you might not have set up:
#   cyanrip       audio CD ripper (12a-rip-cd.bash) -- required
#   libdvd-audio  DVD-Audio extraction (12c-rip-dvd-audio.bash) -- only
#                 if you have DVD-Audio discs
#   rsgain        R128 normalization tags on the Opus files
#                 (14-convert-to-opus.bash) -- required
#
# Why -T and not -Q: `pacman -Q name` only finds a package installed under
# that exact name. `pacman -T` checks whether the name is satisfied by any
# installed package, so a variant that provides it (e.g. handbrake-cli-git
# for handbrake-cli, cyanrip-git for cyanrip) counts as installed instead
# of being flagged as missing and replaced.
#
# util-linux (script, eject, lsblk) is part of every Arch install.

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

OFFICIAL=(libcdio flac ffmpeg libdvdcss dvdbackup lsdvd ogmtools
          vcdimager picard chromaprint opus-tools handbrake-cli)
AUR=(cyanrip libdvd-audio rsgain)

# Prints the packages from the arguments that no installed package
# satisfies, and shows the status of each one on stderr. `pacman -T`
# prints the unsatisfied ones and exits with 127 when there are any --
# that is an answer, not a failure, hence the `|| true`.
missing_of() {
    local pkg missing
    missing="$(pacman -T "$@" || true)"
    for pkg in "$@"; do
        if grep -qxF -- "$pkg" <<<"$missing"; then
            echo "  [missing] $pkg" >&2
            echo "$pkg"
        else
            echo "  [ok]      $pkg" >&2
        fi
    done
}

echo "Official packages:"
mapfile -t MISSING < <(missing_of "${OFFICIAL[@]}")
echo "AUR packages:"
mapfile -t MISSING_AUR < <(missing_of "${AUR[@]}")
echo

if [[ "${#MISSING[@]}" -eq 0 ]]; then
    echo "All official packages are already installed."
else
    echo "Missing official packages: ${MISSING[*]}"
    read -rp "Install them now with pacman? [Y/n] " reply
    reply=${reply:-Y}
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        sudo pacman -S --needed --verbose "${MISSING[@]}"
    else
        echo "Skipped."
    fi
fi

if [[ "${#MISSING_AUR[@]}" -gt 0 ]]; then
    cat <<EOF

Missing AUR packages: ${MISSING_AUR[*]}
Install them with your AUR helper, e.g.:

  paru -S ${MISSING_AUR[*]}

(cyanrip is required for audio CDs and rsgain for 14-convert-to-opus.bash;
libdvd-audio only for DVD-Audio discs.)
EOF
fi

if ! pacman -T cyanrip >/dev/null 2>&1 || [[ ! -d "$SCRIPT_DIR/drive-offsets" ]]; then
    cat <<'EOF'

Once cyanrip is installed, run 10b-find-drive-offset.bash once per drive,
with a popular commercial audio CD inserted, so CD rips are
offset-corrected and AccurateRip-verified.
EOF
fi
