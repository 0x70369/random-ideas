#!/usr/bin/env bash
#
# 12c-rip-dvd-audio.bash [device] [destination_dir]
#
# Extracts a DVD-Audio disc (AUDIO_TS) with libdvd-audio and compresses it
# to FLAC. dvda2wav decrypts CPPM only when given the drive (-c), and it
# reads only titleset 1 (ATS_01); the script warns if there are more. It
# asks before extracting, since libdvd-audio's MLP support is limited.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

need eject dvda-debug-info dvda2wav flac
use_device "${1:-}"
dest="${2:-/temp/rip}"
check_dest "${dest}"
need_disc_space 300   # decoded MLP can be about twice the disc size

mount_disc
[[ -n "${MOUNTPOINT}" ]] || die "could not mount the disc."
audio_ts="$(disc_dir AUDIO_TS)"
[[ -n "${audio_ts}" ]] || die "no AUDIO_TS folder on the disc."

dvda-debug-info -A "${audio_ts}"
titlesets="$(find "${audio_ts}" -maxdepth 1 -iname 'ATS_[0-9][0-9]_0.IFO' |
    wc -l)"
if (( titlesets > 1 )); then
    echo "Warning: ${titlesets} titlesets; only the first is extracted."
fi
confirm "Extract the tracks listed above?"

mkdir -pv -- "${dest}"
cd -- "${dest}"
dvda2wav -A "${audio_ts}" -c "${DEVICE}"
# dvda2wav exits 0 even when it extracted nothing.
wav="$(find . -maxdepth 1 -name '*.wav' -print -quit)"
[[ -n "${wav}" ]] || die "dvda2wav produced no WAV file."
find . -maxdepth 1 -name '*.wav' -print0 |
    xargs -0 -r -n 1 -P "${CORES}" flac --best --verify --delete-input-file

unmount_disc
eject -v -- "${DEVICE}"
echo "Done: ${dest}"
