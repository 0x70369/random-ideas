#!/usr/bin/env bash
#
# 10a-install-dependencies.bash
#
# Installs every package the scripts need with yay (official and AUR), in
# two commands: the tools, then, with --asdeps, the ones that are optional
# dependencies of another package. lib32- versions are included where they
# exist and build.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

need yay
yay -S --needed libcdio lib32-libcdio flac lib32-flac ffmpeg dvdbackup \
    lsdvd ogmtools vcdimager picard opus-tools handbrake-cli cyanrip \
    rsgain libdvd-audio
yay -S --needed --asdeps libdvdcss lib32-libdvdcss chromaprint
echo "Next, once per drive: ./10b-find-drive-offset.bash"
