#!/usr/bin/env bash
#
# 12b-rip-dvd-video.bash [device] [destination_dir]
#
# Extracts the audio of a live-show DVD-Video to FLAC, one file per chapter,
# for the title(s) you pick from the lsdvd listing. Per title:
#   1. dvdbackup -t copies only that title's sectors to /temp (titles often
#      share one VOB set; copying it whole would shift the chapter times);
#   2. you pick the audio stream BY ID (0xa0-0xa7 LPCM, 0x80-0x87 AC-3,
#      0x88-0x8f DTS): ffmpeg's stream order may not match lsdvd's;
#   3. ffmpeg extracts it to one FLAC, cut at dvdxchap's chapter times.
# ffmpeg's dvdvideo demuxer is not used: it failed on one of the discs.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

work=""
cleanup() { [[ -z "${work}" ]] || rm -rf -- "${work}"; }

need lsdvd dvdbackup dvdxchap ffprobe ffmpeg eject
use_device "${1:-}"
dest="${2:-/temp/rip}"
check_dest "${dest}"
need_disc_space 110
work="$(mktemp -d -p /temp)"

lsdvd -a "${DEVICE}"
echo
read_titles "Title number(s) to extract (e.g. '1' or '1 3'): "

# VOBs often announce their streams late: probe deeper than the default.
probe=(-analyzeduration 100M -probesize 100M)

for title in "${TITLES[@]}"; do
    echo
    echo "=== Title ${title}: copying it from the disc ==="
    dvdbackup -v -i "${DEVICE}" -t "${title}" -n "title-${title}" \
        -o "${work}"
    vobs="$(find "${work}/title-${title}" -iname 'VTS_*_[1-9].VOB' | sort)"
    [[ -n "${vobs}" ]] || die "dvdbackup copied no VOB for title ${title}."
    input="concat:$(paste -sd '|' <<<"${vobs}")"

    ffprobe -v error "${probe[@]}" -select_streams a -of compact=p=0 \
        -show_entries stream=id,codec_name,channels,sample_rate,bit_rate \
        "${input}"
    id=""
    until [[ "${id}" =~ ^0x[0-9a-fA-F]+$ ]]; do
        read -rp "Stream id to extract (e.g. 0xa0): " id
    done

    whole="${work}/title-${title}.flac"
    ffmpeg -n -loglevel verbose "${probe[@]}" -i "${input}" \
        -map "0:i:${id}" -vn -c:a flac "${whole}"

    chapters="$(dvdxchap -t "${title}" "${DEVICE}" |
        sed -n 's/^CHAPTER[0-9]*=//p')"
    [[ -n "${chapters}" ]] || die "dvdxchap found no chapters in ${title}."
    mapfile -t starts <<<"${chapters}"

    out_dir="${dest}/title-${title}"
    mkdir -pv -- "${out_dir}"
    for i in "${!starts[@]}"; do
        n=$(( i + 1 ))
        end=()
        (( n == ${#starts[@]} )) || end=(-to "${starts[n]}")
        out="${out_dir}/$(printf '%02d' "${n}").flac"
        # -ss/-to before -i: sample-exact cuts, so the chapters join back
        # without a gap or an overlap.
        ffmpeg -n -loglevel verbose -ss "${starts[i]}" "${end[@]}" \
            -i "${whole}" -c:a flac -compression_level 8 "${out}"
    done
    rm -rfv -- "${work}/title-${title}" "${whole}"   # free the RAM
done

eject -v -- "${DEVICE}"
echo "Done: ${dest}"
