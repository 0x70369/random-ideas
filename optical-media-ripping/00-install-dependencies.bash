#!/usr/bin/env bash
#
# 00-install-dependencies.bash
#
# Installs the official packages needed for the whole pipeline. The AUR
# package (libdvd-audio, needed only for DVD-Audio) is left out -- it
# requires an AUR helper you might not have set up.

set -euo pipefail

completion_sound() { ffplay -nodisp -autoexit -loglevel quiet "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/outcome-success.oga" >/dev/null 2>&1; }

PACKAGES=(libcdio cdparanoia flac ffmpeg libdvdcss dvdbackup lsdvd ogmtools picard chromaprint opus-tools)

echo "Required official packages:"
printf '  %s\n' "${PACKAGES[@]}"
echo

read -rp "Install now with pacman? [Y/n] " reply
reply=${reply:-Y}
[[ "$reply" =~ ^[Yy]$ ]] || { echo "Cancelled."; exit 0; }

sudo pacman -S --needed "${PACKAGES[@]}"

cat <<'EOF'

For DVD-Audio (AUDIO_TS) you will also need the AUR package 'libdvd-audio'.
If you have an AUR helper (paru, yay...), run it manually:

  paru -S libdvd-audio

EOF

completion_sound
