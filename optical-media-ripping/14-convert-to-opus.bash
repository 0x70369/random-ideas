#!/usr/bin/env bash
#
# 14-convert-to-opus.bash <directory>
#
# Converts every FLAC in a tree to Opus in place, at 256 kbit/s per channel
# (the codec's ceiling), keeping the tags and cover Picard embedded, then
# writes the R128 loudness tags of RFC 7845 with rsgain. The audio itself is
# never normalized: players that read the tags even out the volume.
#   - HDCD: 16-bit stereo FLACs are checked for HDCD codes. For each album
#     that has them you choose whether to decode them (to 24-bit) first;
#     the choice is final, since the FLACs are deleted afterwards.
#   - Each FLAC is deleted only after its Opus decodes cleanly and lasts as
#     long (within 0.1 s).
#   - Small Ogg pages (--max-delay = 32000 / bitrate, at least 20 ms), so
#     VLC 3 finds the duration.
#   - Album gain per album: a "Disco N"/"Disc N"/"CD N" folder counts with
#     its sibling discs. Albums whose files all have both R128 tags are
#     skipped, so a rerun after adding a disc only tags the changed album.
#   - rsgain: -o s (R128 tags at -23 LUFS, header gain 0) and -c p
#     (clipping protection for positive gains).

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

(( $# == 1 )) || die "usage: $0 <directory>"
src=$1
[[ -d "${src}" ]] || die "'${src}' is not a folder."
need metaflac opusenc ffmpeg ffprobe rsgain

# album_of DIR: the album folder of DIR (a disc folder belongs to its
# parent).
album_of() {
    local dir=$1
    [[ ! "${dir##*/}" =~ ^(Disco|Disc|CD)[[:space:]_-]*[0-9]+$ ]] ||
        dir="${dir%/*}"
    printf '%s\n' "${dir}"
}

# hdcd_check FILE: prints FILE if it holds HDCD codes. Only CD audio
# (16-bit stereo) can; ffmpeg's hdcd filter accepts nothing else.
hdcd_check() {
    local format report
    format="$(metaflac --show-bps --show-channels "$1" | paste -sd ' ')"
    [[ "${format}" == "16 2" ]] || return 0
    report="$(ffmpeg -nostdin -hide_banner -nostats -i "$1" -af hdcd \
        -c:a pcm_s32le -f null - 2>&1)"
    [[ "${report}" != *"HDCD detected: yes"* ]] || printf '%s\n' "$1"
}

# hdcd_decode FILE: decodes HDCD to 24-bit in place, tags and cover kept.
# The result is written next to FILE, under a name that is not *.flac (a
# leftover is never taken for a track), then renamed over it.
hdcd_decode() {
    tmp="$(mktemp -p "${1%/*}" --suffix=.hdcdtmp .XXXXXX)"
    trap 'rm -f -- "${tmp}"' EXIT
    ffmpeg -nostdin -v error -y -i "$1" -map 0 -c:v copy -af hdcd \
        -c:a flac -compression_level 8 -sample_fmt s32 \
        -bits_per_raw_sample 24 -fflags +bitexact -flags:a +bitexact \
        -f flac "${tmp}"
    chmod --reference="$1" -- "${tmp}"
    mv -f -- "${tmp}" "$1"
    echo "HDCD decoded: $1"
}

# to_opus FILE: encodes FILE to Opus next to it, checks the Opus, then
# deletes FILE. Prints its output in one block, so parallel jobs do not
# interleave.
to_opus() {
    local f=$1 channels rate delay log errors samples hz opus_s problem=""
    out="${f%.*}.opus"   # removed by the trap if the job dies
    trap 'rm -f -- "${out}"' EXIT
    channels="$(metaflac --show-channels "${f}")"
    rate=$(( channels * 256 ))
    delay=$(( 32000 / rate ))
    (( delay >= 20 )) || delay=20
    log="$(opusenc --bitrate "${rate}" --max-delay "${delay}" "${f}" \
        "${out}" 2>&1)" || problem="opusenc failed"
    if [[ -z "${problem}" ]]; then
        errors="$(ffmpeg -nostdin -v error -i "${out}" -f null - 2>&1)" ||
            errors+=" (ffmpeg failed)"
        [[ -z "${errors}" ]] || problem="decode errors: ${errors}"
    fi
    if [[ -z "${problem}" ]]; then
        samples="$(metaflac --show-total-samples "${f}")"
        hz="$(metaflac --show-sample-rate "${f}")"
        opus_s="$(ffprobe -v error -show_entries format=duration \
            -of csv=p=0 "${out}")"
        if (( samples > 0 )) && ! awk -v n="${samples}" -v r="${hz}" \
                -v o="${opus_s}" \
                'BEGIN { d = n / r - o; exit !(d <= 0.1 && d >= -0.1) }'
        then
            problem="FLAC and Opus durations differ (Opus: ${opus_s} s)"
        fi
    fi
    if [[ -n "${problem}" ]]; then
        printf '=== Failed: %s ===\n%s\n%s\n' "${f}" "${log}" "${problem}" >&2
        exit 1
    fi
    trap - EXIT   # the Opus is checked: keep it from here on
    printf '=== OK: %s (%s kbit/s, pages <= %s ms) ===\n%s\n' "${f}" \
        "${rate}" "${delay}" "${log}"
    rm -v -- "${f}"
}

# album_tags ALBUM: writes the R128 tags of every Opus in ALBUM as one
# album, unless all of them already have both tags.
album_tags() {
    local list files f tags untagged=0 log
    local r128=R128_TRACK_GAIN,R128_ALBUM_GAIN
    list="$(find "$1" -type f -iname '*.opus' | sort)"
    mapfile -t files <<<"${list}"
    for f in "${files[@]}"; do
        tags="$(ffprobe -v error -of default=nw=1 -show_entries \
            "stream_tags=${r128}:format_tags=${r128}" "${f}")"
        [[ "${tags^^}" == *TAG:R128_TRACK_GAIN=* &&
            "${tags^^}" == *TAG:R128_ALBUM_GAIN=* ]] ||
            untagged=$(( untagged + 1 ))
    done
    if (( untagged == 0 )); then
        echo "=== Skipped: $1 (already tagged) ==="
        return 0
    fi
    if ! log="$(rsgain custom -a -s i -c p -o s "${files[@]}" 2>&1)"; then
        printf '=== Failed: %s ===\n%s\n' "$1" "${log}" >&2
        exit 1
    fi
    printf '=== OK: %s (%s of %s file(s) were untagged) ===\n%s\n' "$1" \
        "${untagged}" "${#files[@]}" "${log}"
}

total="$(find "${src}" -type f -iname '*.flac' | wc -l)"
opus="$(find "${src}" -type f -iname '*.opus' -print -quit)"
(( total > 0 )) || [[ -n "${opus}" ]] || die "no FLAC or Opus in '${src}'."

if (( total > 0 )); then
    echo "Checking ${total} FLAC file(s) for HDCD..."
    hdcd="$(find "${src}" -type f -iname '*.flac' -print0 | each hdcd_check |
        sort)"
    decode=()
    if [[ -n "${hdcd}" ]]; then
        mapfile -t hdcd_files <<<"${hdcd}"
        declare -A count=()
        for f in "${hdcd_files[@]}"; do
            album="$(album_of "${f%/*}")"
            count["${album}"]=$(( ${count["${album}"]:-0} + 1 ))
        done
        for album in "${!count[@]}"; do
            echo
            echo "HDCD in ${count["${album}"]} track(s) of: ${album}"
            echo "  Decoding restores the dynamic range it was mastered with,"
            echo "  but sounds different from a plain CD player (peak"
            echo "  extension can expand the top 3 dB into 9 dB)."
            reply=""
            until [[ "${reply}" =~ ^[YyNn]$ ]]; do
                read -rp "  Decode HDCD for this album? [y/n] " reply ||
                    die "no answer; nothing was converted."
            done
            [[ "${reply}" =~ ^[Yy]$ ]] || continue
            for f in "${hdcd_files[@]}"; do
                a="$(album_of "${f%/*}")"
                [[ "${a}" != "${album}" ]] || decode+=("${f}")
            done
        done
    fi
    if (( ${#decode[@]} > 0 )); then
        printf '%s\0' "${decode[@]}" | each hdcd_decode
    fi

    echo "Converting ${total} FLAC file(s)..."
    find "${src}" -type f -iname '*.flac' -print0 | each to_opus
fi

dirs="$(find "${src}" -type f -iname '*.opus' -printf '%h\n' | sort -u)"
albums="$(while IFS= read -r dir; do album_of "${dir}"; done <<<"${dirs}" |
    sort -u)"
echo "Checking the R128 tags of every album..."
tr '\n' '\0' <<<"${albums}" | each album_tags
echo "Done: every album has R128 tags (header gain 0 dB)."
