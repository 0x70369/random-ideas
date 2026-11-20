#!/usr/bin/env bash
#
# vlc-ogg-length-report.bash [-r DIR] FILE.opus...
# vlc-ogg-length-report.bash [-r DIR] --generate DIR
#
# Collects the data for a VLC bug: VLC 3 reports no duration (00:00 / --:--,
# no seeking; "live" on iOS) for valid Ogg Opus files whose last Ogg page is
# larger than 8500 bytes (OGGSEEK_BYTES_TO_READ in modules/demux/oggseek.c).
#
# For each file it prints:
#   - oggz-validate and oggz-info (framing validity, duration, page sizes);
#   - the last 6 Ogg pages (offset, size, bytes before EOF, granule, flags);
#   - the length VLC itself reports (rc interface, get_length);
#   - the SHA-256 of the decoded PCM (to show two files hold the same audio).
# and a summary table at the end.
#
# -r DIR also copies every file whose last page is larger than 8500 bytes
# into DIR and repaginates the copy losslessly with 17-fix-opus-pages.bash
# (~4 KB pages, same packets, headers and granules; it must sit next to
# this script, with common.bash), then reports on it right after its
# original. An A/B/C comparison:
#   vlc-ogg-length-report.bash -r DIR BAD.opus GOOD.opus
# gives A = a file VLC fails on, C = its repaginated copy, B = a file from
# the same encoder that VLC reads fine.
#
# --generate DIR creates a reproducer from scratch (no copyrighted audio):
# 253.913 s of pink noise encoded twice at 512 kbit/s, with opusenc's
# default paging (up to 1 s per page, ~56 KB) and with --max-delay 62
# (~3.6 KB pages), then reports on both. The decoded audio is identical
# (same SHA-256): only the paging differs.
#
# Needs: vlc, ffmpeg, python3; oggz-validate/oggz-info (liboggz) and
# opusenc (opus-tools) are optional (only their steps are skipped).
# VLC refuses to run as root, so run this as a normal user.

set -euo pipefail
shopt -s inherit_errexit

die() {
    echo "Error: $*" >&2
    exit 1
}

for cmd in vlc ffmpeg python3; do
    command -v "${cmd}" >/dev/null || die "'${cmd}' not found."
done
if [[ ${EUID} -eq 0 ]]; then
    die "VLC does not run as root; run this as a normal user."
fi

# Prints the last Ogg pages of a file; the last line is a summary for the
# table: "SUMMARY <last page bytes> <largest page bytes>".
last_pages() {
    python3 -I - "$1" <<'EOF'
import sys

d = open(sys.argv[1], "rb").read()
pages, i = [], 0
while i < len(d):
    if d[i:i + 4] != b"OggS":
        sys.exit("not an Ogg page at byte %d" % i)
    n = d[i + 26]
    s = 27 + n + sum(d[i + 27:i + 27 + n])
    g = int.from_bytes(d[i + 6:i + 14], "little", signed=True)
    pages.append((i, s, g, d[i + 5]))
    i += s
print(f"{len(d)} bytes, {len(pages)} pages, "
      f"largest {max(p[1] for p in pages)} bytes")
print("offset      size  bytes-before-EOF   granule  flags")
for off, size, gran, flags in pages[-6:]:
    print(f"{off:<10} {size:>6} {len(d) - off:>17} {gran:>9}  0x{flags:02x}")
print("last page within the last 8500 bytes:",
      "yes" if len(d) - pages[-1][0] <= 8500 else "NO")
print("SUMMARY", pages[-1][1], max(p[1] for p in pages))
EOF
}

# The length VLC reports, in seconds, through its rc interface. It is
# asked once a second for 10 s and the largest answer kept, so a slow start
# (VLC answers 0 until it knows the length) is not taken for the bug. The
# rc interface ends its lines with \r, hence the tr.
vlc_length() {
    local i
    {
        for (( i = 0; i < 10; i++ )); do
            sleep 1
            echo get_length
        done
        echo quit
    } | vlc -I rc --aout=dummy --no-video "$1" 2>/dev/null |
        tr -d '\r' | sed -n 's/^> \([0-9][0-9]*\)$/\1/p' | sort -n |
        tail -n 1
}

repag_dir=""
if [[ "${1:-}" == -r ]]; then
    [[ -n "${2:-}" ]] || die "usage: $0 -r DIR FILE.opus..."
    repag_dir="$2"
    shift 2
    fix_script="$(dirname -- "$0")/17-fix-opus-pages.bash"
    [[ -f "${fix_script}" ]] ||
        die "'${fix_script}' not found (keep it next to this script)."
    mkdir -pv -- "${repag_dir}"
fi

if [[ "${1:-}" == --generate ]]; then
    [[ -n "${2:-}" ]] || die "usage: $0 --generate DIR"
    command -v opusenc >/dev/null || die "'opusenc' not found."
    mkdir -pv -- "$2"
    src="$2/noise.flac"
    ffmpeg -nostdin -v error -y -f lavfi \
        -i "anoisesrc=d=253.913:c=pink:a=0.5" \
        -ac 2 -ar 44100 -sample_fmt s16 "${src}"
    opusenc --quiet --bitrate 512 "${src}" "$2/big-pages.opus"
    opusenc --quiet --bitrate 512 --max-delay 62 "${src}" \
        "$2/small-pages.opus"
    rm -f -- "${src}"
    set -- "$2/big-pages.opus" "$2/small-pages.opus"
fi

(( $# > 0 )) ||
    die "usage: $0 [-r DIR] FILE.opus... | [-r DIR] --generate DIR"
for f in "$@"; do
    [[ -f "${f}" ]] || die "'${f}' is not a file."
done

# With -r: each file, followed by a repaginated copy if its last page is
# larger than 8500 bytes (the files VLC gets no length for). The copies are
# made first, then 17-fix-opus-pages.bash repaginates them all in DIR.
files=()
copies=0
for f in "$@"; do
    files+=("${f}")
    [[ -n "${repag_dir}" ]] || continue
    line="$(last_pages "${f}" | grep '^SUMMARY ')"
    read -r _ last _ <<<"${line}"
    (( last > 8500 )) || continue
    copy="${repag_dir}/repaginated-$(basename -- "${f}")"
    cp -v -- "${f}" "${copy}"
    files+=("${copy}")
    copies=$((copies + 1))
done
if (( copies > 0 )); then
    bash "${fix_script}" "${repag_dir}" </dev/null
fi

echo "=== Environment"
if [[ -r /etc/os-release ]]; then
    sed -n 's/^PRETTY_NAME=//p' /etc/os-release | tr -d '"'
fi
uname -srm
vlc --version 2>/dev/null | head -n 1
ffmpeg -version | head -n 1
if command -v opusenc >/dev/null; then opusenc --version | head -n 1; fi
if command -v pacman >/dev/null; then
    pacman -Q vlc libogg opus opus-tools liboggz 2>/dev/null || true
fi

summary=()
for f in "${files[@]}"; do
    echo
    echo "=== ${f}"
    if command -v oggz-validate >/dev/null; then
        echo "--- oggz-validate (no output = no framing errors)"
        oggz-validate "${f}" || true
    fi
    if command -v oggz-info >/dev/null; then
        echo "--- oggz-info -l -g"
        oggz-info -l -g "${f}" || true
    fi
    echo "--- last Ogg pages"
    pages="$(last_pages "${f}")"
    grep -v '^SUMMARY ' <<<"${pages}"
    line="$(grep '^SUMMARY ' <<<"${pages}")"
    read -r _ last largest <<<"${line}"
    echo "--- VLC length (rc get_length, seconds)"
    length="$(vlc_length "${f}")"
    echo "${length:-no answer}"
    echo "--- decoded PCM, sha256"
    sha="$(ffmpeg -nostdin -v error -i "${f}" -f s16le - | sha256sum)"
    echo "${sha%% *}"
    summary+=("$(printf '%-12s %-14s %-10s %s' "${length:-?}" \
        "${last}" "${largest}" "$(basename -- "${f}")")")
done

echo
echo "=== Summary"
printf '%-12s %-14s %-10s %s\n' "VLC length" "last page (B)" \
    "max (B)" "file"
printf '%s\n' "${summary[@]}"
