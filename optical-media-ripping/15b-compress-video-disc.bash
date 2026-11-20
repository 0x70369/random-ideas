#!/usr/bin/env bash
#
# 15b-compress-video-disc.bash <disc_dir> [destination_dir]
#
# Compresses a video disc already copied to disk (a VIDEO_TS folder, e.g.
# from 15a) into one .mkv per title, without touching the drive. The video
# becomes x265 (CRF 20, slow preset: close to transparent, much smaller
# than DVD MPEG-2). Every audio and subtitle track is copied as it is; a
# track HandBrake cannot pass through (DVD LPCM) becomes Opus at 256 kbit/s
# per channel (HandBrake caps -B there). Chapters become MKV chapters. No
# cropping: black-bar detection can cut real picture in dark scenes. The
# VIDEO_TS backup is never deleted.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

(( $# == 1 || $# == 2 )) || die "usage: $0 <disc_dir> [destination_dir]"
disc=$1
dest="${2:-/temp/video-final}"
need HandBrakeCLI
video_ts="$(find "${disc}" -maxdepth 1 -iname VIDEO_TS -type d -print -quit)"
[[ -n "${video_ts}" ]] || die "no VIDEO_TS folder in '${disc}'."
mkdir -pv -- "${dest}"

# Scans use plain -v: higher levels bury the track list.
HandBrakeCLI -v -i "${disc}" -t 0 --scan
read_titles "Title number(s) to encode (e.g. '1' or '1 2 3'): "

# ask_count PROMPT: prints a whole number read from the user (a typo would
# only fail inside HandBrake, much later).
ask_count() {
    local answer=""
    until [[ "${answer}" =~ ^[0-9]+$ ]]; do read -rp "$1" answer; done
    echo "${answer}"
}

for title in "${TITLES[@]}"; do
    echo
    echo "=== Title ${title}: look for its audio and subtitle tracks ==="
    HandBrakeCLI -v -i "${disc}" -t "${title}" --scan
    audio="$(ask_count "How many audio tracks? ")"
    subs="$(ask_count "How many subtitle tracks (0 if none)? ")"

    # Copy every track; Opus only for one that cannot be copied. -B is
    # ignored for copied tracks and capped at 256 kbit/s per channel.
    audio_args=(-a none)
    if (( audio > 0 )); then
        tracks="$(seq -s, "${audio}")"   # 1,2,3
        encoders=copy rates=6144
        for (( i = 1; i < audio; i++ )); do
            encoders+=,copy rates+=,6144
        done
        audio_args=(-a "${tracks}" -E "${encoders}" -B "${rates}"
            --audio-fallback opus)
    fi
    sub_args=()
    if (( subs > 0 )); then
        tracks="$(seq -s, "${subs}")"
        sub_args=(-s "${tracks}")
    fi

    read -rp "Output file (e.g. 'Movie (2020)', 'S01E01 - Title'): " name
    name="${name:-title-${title}}"
    [[ "${name}" != */* ]] || die "the file name cannot contain '/'."
    [[ "${name}" == *.mkv ]] || name+=.mkv
    [[ ! -e "${dest}/${name}" ]] || die "'${dest}/${name}' already exists."

    HandBrakeCLI --verbose=2 -i "${disc}" -t "${title}" -o "${dest}/${name}" \
        -e x265 --encoder-preset slow -q 20 --comb-detect --decomb \
        --crop 0:0:0:0 "${audio_args[@]}" "${sub_args[@]}" -m
done
echo "Done: ${dest}"
