#!/usr/bin/env bash
#
# 00-install-dependencies.bash
#
# Installs the official packages needed for the whole pipeline. The AUR
# package (libdvd-audio, needed only for DVD-Audio) is left out -- it
# requires an AUR helper you might not have set up.

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

PACKAGES=(libcdio cdparanoia flac ffmpeg libdvdcss dvdbackup lsdvd ogmtools
          vcdimager picard chromaprint opus-tools handbrake-cli)

echo "Required official packages:"
printf '  %s\n' "${PACKAGES[@]}"
echo

read -rp "Install now with pacman? [Y/n] " reply
reply=${reply:-Y}
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

sudo pacman -S --needed --verbose "${PACKAGES[@]}"

cat <<'EOF'

For DVD-Audio (AUDIO_TS) you will also need the AUR package 'libdvd-audio'.
If you have an AUR helper (paru, yay...), run it manually:

  paru -S libdvd-audio

EOF
