#!/usr/bin/env bash
#
# 10a-install-dependencies.bash
#
# Checks every package the pipeline needs with `pacman -T` (deptest) and
# installs only the missing official ones with `pacman -S --needed`, in
# two commands: the tools themselves, then -- with --asdeps -- the ones
# that are optional dependencies of another package (libdvdcss of
# libdvdread, chromaprint of picard), so they count as dependencies.
#
# The 32-bit (lib32-) versions are included where they exist: lib32-flac
# from [multilib] (skipped with a note if [multilib] is not enabled), and
# lib32-libcdio / lib32-libdvdcss from the AUR. None of the scripts runs
# 32-bit code. lib32-ffmpeg and lib32-chromaprint are left out: a large,
# often-failing AUR build, and an abandoned package that fails to build.
#
# The AUR packages are checked the same way, but only reported -- installing
# them is left to yay, which this script does not run (it builds as your
# user and asks its own questions):
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

# Shared setup -- logging to /temp/logs, sounds, Ctrl+C, drive helpers --
# lives in common.bash, next to the scripts. SCRIPT_DIR is resolved first:
# a relative $0 would break once the script cd's elsewhere.
SCRIPT_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
# shellcheck source=common.bash
source "$SCRIPT_DIR/common.bash" || exit 1

OFFICIAL=(libcdio flac lib32-flac ffmpeg dvdbackup lsdvd ogmtools
          vcdimager picard opus-tools handbrake-cli)
OFFICIAL_DEPS=(libdvdcss chromaprint)   # installed with --asdeps
AUR=(cyanrip libdvd-audio rsgain lib32-libcdio)
AUR_DEPS=(lib32-libdvdcss)              # installed with --asdeps

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
echo "Official packages (optional dependencies, --asdeps):"
mapfile -t MISSING_DEPS < <(missing_of "${OFFICIAL_DEPS[@]}")
echo "AUR packages:"
mapfile -t MISSING_AUR < <(missing_of "${AUR[@]}")
echo "AUR packages (--asdeps):"
mapfile -t MISSING_AUR_DEPS < <(missing_of "${AUR_DEPS[@]}")
echo

# lib32- packages come from [multilib]: if it is not enabled, pacman would
# fail the whole command over them, so leave them out with a note.
AVAILABLE=()
for pkg in "${MISSING[@]}"; do
    if [[ "$pkg" == lib32-* ]] && ! pacman -Si "$pkg" >/dev/null 2>&1; then
        echo "Note: $pkg is not in your enabled repositories ([multilib] off?) -- skipped."
    else
        AVAILABLE+=("$pkg")
    fi
done
MISSING=("${AVAILABLE[@]}")

if [[ "${#MISSING[@]}" -eq 0 && "${#MISSING_DEPS[@]}" -eq 0 ]]; then
    echo "All official packages are already installed."
else
    echo "Missing official packages: ${MISSING[*]:-none}"
    echo "Missing optional dependencies (--asdeps): ${MISSING_DEPS[*]:-none}"
    read -rp "Install them now with pacman? [Y/n] " reply
    reply=${reply:-Y}
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        if [[ "${#MISSING[@]}" -gt 0 ]]; then
            sudo pacman -S --needed --verbose "${MISSING[@]}"
        fi
        if [[ "${#MISSING_DEPS[@]}" -gt 0 ]]; then
            sudo pacman -S --needed --asdeps --verbose "${MISSING_DEPS[@]}"
        fi
    else
        echo "Skipped."
    fi
fi

if [[ "${#MISSING_AUR[@]}" -gt 0 || "${#MISSING_AUR_DEPS[@]}" -gt 0 ]]; then
    echo
    echo "Missing AUR packages: ${MISSING_AUR[*]:-none}; --asdeps: ${MISSING_AUR_DEPS[*]:-none}"
    echo "Install them with yay:"
    echo
    [[ "${#MISSING_AUR[@]}" -eq 0 ]] || echo "  yay -S --needed ${MISSING_AUR[*]}"
    [[ "${#MISSING_AUR_DEPS[@]}" -eq 0 ]] || echo "  yay -S --needed --asdeps ${MISSING_AUR_DEPS[*]}"
    echo
    echo "(cyanrip is required for audio CDs and rsgain for 14-convert-to-opus.bash;"
    echo "libdvd-audio only for DVD-Audio discs.)"
fi

if ! pacman -T cyanrip >/dev/null 2>&1 || [[ ! -d "$SCRIPT_DIR/drive-offsets" ]]; then
    cat <<'EOF'

Once cyanrip is installed, run 10b-find-drive-offset.bash once per drive,
with a popular commercial audio CD inserted, so CD rips are
offset-corrected and AccurateRip-verified.
EOF
fi
