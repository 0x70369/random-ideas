#!/usr/bin/env bash
#
# 17-fix-opus-pages.bash <opus_directory>
#
# Repairs Opus files that VLC 3 shows without a duration (--:--, no seeking;
# "live" on iOS): opusenc's default puts up to 1 s of audio in each Ogg
# page, and VLC never sees a whole last page in the final 8500 bytes it
# reads. 14 now writes small pages; this fixes files made before that.
#
# Lossless: the Opus packets are copied byte for byte into pages of about
# 4 KB; the header pages (OpusHead, OpusTags with tags and cover) are kept
# as they are; the granule positions are recomputed and checked against the
# original pages, end trimming included. Before replacing a file: same
# packets, same final granule, valid CRCs, same ffprobe duration, clean
# ffmpeg decode. The new file is written next to the original (not as
# *.opus) and renamed over it, keeping permissions and date. Files with
# small pages already are skipped; anything unusual (chained streams, data
# after the last page, timing that does not match) is reported and left
# alone.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

(( $# == 1 )) || die "usage: $0 <opus_directory>"
src=$1
[[ -d "${src}" ]] || die "'${src}' is not a folder."
need python3 ffmpeg ffprobe

# The repagination itself, in Python (byte handling and the Ogg CRC are not
# practical in Bash). Arguments: input, output. Exit status: 0 = written,
# 3 = pages already small (nothing written), other = error (on stderr).
FIX_PY="$(cat <<'PY'
import sys

MAX_PAGE = 8500        # VLC reads the last 8500 bytes first
TARGET = 4000          # bytes of packet data per new page


def crc_table():
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) if r & 0x80000000 else r << 1
        table.append(r & 0xFFFFFFFF)
    return table


TABLE = crc_table()


def ogg_crc(data):
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ TABLE[(crc >> 24) ^ b]
    return crc


def parse_pages(data):
    pages, pos = [], 0
    while pos < len(data):
        if data[pos:pos + 4] != b"OggS":
            raise ValueError("data that is not an Ogg page at byte %d" % pos)
        if data[pos + 4] != 0:
            raise ValueError("unknown Ogg version at byte %d" % pos)
        nseg = data[pos + 26]
        lacing = data[pos + 27:pos + 27 + nseg]
        size = 27 + nseg + sum(lacing)
        raw = data[pos:pos + size]
        if len(raw) < size:
            raise ValueError("truncated last page")
        check = bytearray(raw)
        check[22:26] = b"\0\0\0\0"
        if ogg_crc(check) != int.from_bytes(raw[22:26], "little"):
            raise ValueError("bad CRC in the page at byte %d" % pos)
        pages.append({
            "raw": raw,
            "flags": raw[5],
            "granule": int.from_bytes(raw[6:14], "little", signed=True),
            "serial": int.from_bytes(raw[14:18], "little"),
            "lacing": lacing,
            "body": raw[27 + nseg:],
        })
        pos += size
    return pages


def split_packets(pages):
    """Packets, and for each page the number of packets completed on it."""
    packets, done_per_page, cur = [], [], b""
    for p in pages:
        done, off = 0, 0
        for lace in p["lacing"]:
            cur += p["body"][off:off + lace]
            off += lace
            if lace < 255:
                packets.append(cur)
                cur, done = b"", done + 1
        done_per_page.append(done)
    if cur:
        raise ValueError("the last packet is unfinished")
    return packets, done_per_page


def opus_samples(packet):
    """Duration of an Opus packet in 48 kHz samples (RFC 6716, 3.1)."""
    toc = packet[0]
    config = toc >> 3
    if config < 12:
        frame = (480, 960, 1920, 2880)[config & 3]
    elif config < 16:
        frame = (480, 960)[config & 1]
    else:
        frame = (120, 240, 480, 960)[config & 3]
    code = toc & 3
    count = 1 if code == 0 else 2 if code < 3 else packet[1] & 0x3F
    return frame * count


def build_page(flags, granule, serial, seq, packets):
    lacing = bytearray()
    for pkt in packets:
        lacing += b"\xff" * (len(pkt) // 255) + bytes([len(pkt) % 255])
    head = bytearray(b"OggS\0")
    head.append(flags)
    head += granule.to_bytes(8, "little", signed=True)
    head += serial.to_bytes(4, "little")
    head += seq.to_bytes(4, "little")
    head += b"\0\0\0\0"
    head.append(len(lacing))
    page = head + lacing + b"".join(packets)
    page[22:26] = ogg_crc(page).to_bytes(4, "little")
    return bytes(page)


def segments(pkt):
    return len(pkt) // 255 + 1


def main(src, dst):
    data = open(src, "rb").read()
    pages = parse_pages(data)
    if not pages:
        raise ValueError("empty file")
    if len({p["serial"] for p in pages}) != 1:
        raise ValueError("more than one logical stream (chained/multiplexed)")
    if not pages[0]["flags"] & 2 or not pages[-1]["flags"] & 4:
        raise ValueError("first page is not BOS or last page is not EOS")
    packets, done = split_packets(pages)
    if len(packets) < 3 or not packets[0].startswith(b"OpusHead") \
            or not packets[1].startswith(b"OpusTags"):
        raise ValueError("not an Ogg Opus stream")

    # Header pages: up to the page that completes OpusTags, which must not
    # carry any audio data (RFC 7845: audio starts on a new page).
    total, header_pages = 0, 0
    for i, n in enumerate(done):
        total += n
        if total >= 2:
            header_pages = i + 1
            break
    if total != 2 or pages[header_pages - 1]["lacing"][-1] == 255:
        raise ValueError("audio data shares a page with the headers")
    audio = packets[2:]
    serial = pages[0]["serial"]
    # Only the audio pages matter: the header pages (a large cover can make
    # OpusTags span big pages) are copied as they are anyway, and checking
    # them would make already fixed files look unfixed on every run.
    if max(len(p["raw"]) for p in pages[header_pages:]) <= MAX_PAGE:
        return 3

    # Check the timing: every audio page granule must equal the samples of
    # the packets completed so far plus one constant offset (0 for opusenc);
    # only the last page may be lower (end trimming).
    cum, idx, offset = 0, 0, None
    audio_pages = pages[header_pages:]
    for j, p in enumerate(audio_pages):
        n = done[header_pages + j]
        cum += sum(opus_samples(pkt) for pkt in audio[idx:idx + n])
        idx += n
        if p["granule"] == -1:
            continue
        if offset is None:
            offset = p["granule"] - cum
        expected = cum + offset
        last = j == len(audio_pages) - 1
        if p["granule"] != expected and not (last and p["granule"] < expected):
            raise ValueError("granule %d where %d was expected"
                             % (p["granule"], expected))
    if offset is None:
        raise ValueError("no audio page with a granule position")
    final_granule = audio_pages[-1]["granule"]

    # New pages: whole packets only, about TARGET bytes each.
    groups, cur, cur_bytes, cur_segs = [], [], 0, 0
    for pkt in audio:
        if segments(pkt) > 255:
            raise ValueError("packet too large for one page")
        if cur and (cur_bytes + len(pkt) > TARGET
                    or cur_segs + segments(pkt) > 255):
            groups.append(cur)
            cur, cur_bytes, cur_segs = [], 0, 0
        cur.append(pkt)
        cur_bytes += len(pkt)
        cur_segs += segments(pkt)
    groups.append(cur)
    granules, cum = [], 0
    for g in groups:
        cum += sum(opus_samples(pkt) for pkt in g)
        granules.append(cum + offset)
    granules[-1] = final_granule
    if min(granules) < 0:
        raise ValueError("start trimming larger than the first new page")
    # The trimmed end must not go below the previous page: merge if needed.
    while len(groups) > 1 and granules[-2] > final_granule:
        merged = groups[-2] + groups[-1]
        if sum(segments(pkt) for pkt in merged) > 255:
            raise ValueError("end trimming longer than one page")
        groups[-2:] = [merged]
        granules[-2:] = [final_granule]

    out = bytearray()
    for p in pages[:header_pages]:
        out += p["raw"]
    seq = int.from_bytes(pages[header_pages - 1]["raw"][18:22], "little") + 1
    for k, (g, gran) in enumerate(zip(groups, granules)):
        flags = 4 if k == len(groups) - 1 else 0
        out += build_page(flags, gran, serial, seq + k, g)

    # Verify before handing it over.
    new_pages = parse_pages(bytes(out))
    new_packets, _ = split_packets(new_pages)
    if new_packets != packets:
        raise ValueError("verification failed: packets differ")
    if new_pages[-1]["granule"] != final_granule:
        raise ValueError("verification failed: final granule differs")
    if max(len(p["raw"]) for p in new_pages[header_pages:]) > MAX_PAGE:
        raise ValueError("verification failed: a page is still too large")
    open(dst, "wb").write(out)
    print("pages: %d -> %d, largest audio page: %d -> %d bytes"
          % (len(pages), len(new_pages),
             max(len(p["raw"]) for p in audio_pages),
             max(len(p["raw"]) for p in new_pages[header_pages:])))
    return 0


try:
    sys.exit(main(sys.argv[1], sys.argv[2]))
except (ValueError, IndexError, OSError) as err:
    print("error: %s" % err, file=sys.stderr)
    sys.exit(1)
PY
)"
export FIX_PY

# fix_file FILE: repaginates FILE in place. Prints its output in one block.
fix_file() {
    local f=$1 report status=0 before after errors
    tmp="$(mktemp -p /temp --suffix=.opus)"
    place="${f%/*}/.${f##*/}.fixtmp"
    trap 'rm -f -- "${tmp}" "${place}"' EXIT
    report="$(python3 -I -c "${FIX_PY}" "${f}" "${tmp}" 2>&1)" || status=$?
    if (( status == 3 )); then
        echo "=== Already fine: ${f} ==="
        return 0
    fi
    if (( status == 0 )); then
        before="$(ffprobe -v error -show_entries format=duration \
            -of csv=p=0 "${f}")"
        after="$(ffprobe -v error -show_entries format=duration \
            -of csv=p=0 "${tmp}")"
        [[ -n "${after}" && "${before}" == "${after}" ]] ||
            report="duration changed: ${before} -> ${after}" status=1
    fi
    if (( status == 0 )); then
        errors="$(ffmpeg -nostdin -v error -i "${tmp}" -f null - 2>&1)" ||
            errors+=" (ffmpeg failed)"
        [[ -z "${errors}" ]] || report="decode errors: ${errors}" status=1
    fi
    if (( status != 0 )); then
        printf '=== Failed (unchanged): %s ===\n%s\n' "${f}" "${report}" >&2
        exit 1
    fi
    # Same file system as the original, so the rename is atomic.
    cp -- "${tmp}" "${place}"
    chmod --reference="${f}" -- "${place}"
    touch -r "${f}" -- "${place}"
    mv -f -- "${place}" "${f}"
    printf '=== Fixed: %s ===\n%s, duration %s s\n' "${f}" "${report}" \
        "${after}"
}

opus="$(find "${src}" -type f -iname '*.opus' -print -quit)"
[[ -n "${opus}" ]] || die "no Opus files in '${src}'."
find "${src}" -type f -iname '*.opus' -print0 | each fix_file
echo "Done: every Opus file in ${src} has small Ogg pages."
