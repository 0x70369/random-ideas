#!/usr/bin/env bash
#
# 11-identify-media.bash [device]
#
# Identifies the disc in the drive and prints one token to stdout:
#   CD-DA      audio CD, "enhanced" CDs (audio + data track) included
#   DVD-VIDEO  DVD-Video (live show, movie or TV series)
#   DVD-AUDIO  DVD-Audio (AUDIO_TS), hybrids with VIDEO_TS included
#   VCD        Video CD / Super Video CD (MPEGAV or MPEG2 folder)
#   UNKNOWN    could not tell (exit status 1)
# Everything else, including the next step, goes to stderr, so
# type=$(./11-identify-media.bash) captures only the token.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

# finish TOKEN [HINT...]: prints the hints to stderr and TOKEN to stdout.
finish() {
    local token=$1 hint
    shift
    for hint in "$@"; do echo "Next step: ${hint}" >&2; done
    echo "${token}"
    exit 0
}

unknown() {
    echo "$1 Inspect the disc by hand." >&2
    echo UNKNOWN
    exit 1
}

dvd_video() {
    finish DVD-VIDEO \
        "./12b-rip-dvd-video.bash ${DEVICE}   (live show: audio only)" \
        "./15a-backup-video-disc.bash ${DEVICE}   (movie/series: video)"
}

need cd-info
use_device "${1:-}"
read_toc
audio=${#AUDIO_TRACKS[@]}
echo "Disc mode: ${DISC_MODE:-unknown} | audio tracks: ${audio}" \
    "| other tracks: ${DATA_TRACKS}" >&2
[[ -n "${DISC_MODE}" ]] || unknown "Could not read the disc."

# A pure audio CD has nothing to mount.
if [[ "${DISC_MODE}" != DVD* ]] && (( audio > 0 && DATA_TRACKS == 0 )); then
    finish CD-DA "./12a-rip-cd.bash ${DEVICE}"
fi

mount_disc
if [[ -z "${MOUNTPOINT}" ]]; then
    [[ "${DISC_MODE}" != DVD* ]] || dvd_video
    (( audio == 0 )) || finish CD-DA "./12a-rip-cd.bash ${DEVICE}"
    unknown "Could not mount the disc."
fi

# filled NAME: prints something if the folder NAME at the disc root holds
# anything.
filled() {
    local dir
    dir="$(disc_dir "$1")"
    [[ -z "${dir}" ]] || find "${dir}" -mindepth 1 -print -quit
}

audio_ts="$(filled AUDIO_TS)"
video_ts="$(filled VIDEO_TS)"
mpegav="$(disc_dir MPEGAV)"
mpeg2="$(disc_dir MPEG2)"

if [[ -n "${audio_ts}" ]]; then
    [[ -z "${video_ts}" ]] ||
        echo "Hybrid disc: using AUDIO_TS (lossless)." >&2
    finish DVD-AUDIO "./12c-rip-dvd-audio.bash ${DEVICE}"
fi
[[ -z "${video_ts}" ]] || dvd_video
[[ -z "${mpegav}${mpeg2}" ]] ||
    finish VCD "./15a-backup-video-disc.bash ${DEVICE}"
if (( audio > 0 )); then
    echo "Enhanced CD: only the audio tracks will be ripped." >&2
    finish CD-DA "./12a-rip-cd.bash ${DEVICE}"
fi
unknown "No audio tracks and no AUDIO_TS, VIDEO_TS, MPEGAV or MPEG2."
