# Ogg: duration not found (shows --:--, no seeking) when the last Ogg page is larger than 8500 bytes

## Summary

For Ogg Opus files whose last page is larger than `OGGSEEK_BYTES_TO_READ`
(8500 bytes), VLC fails to determine the duration: the length shows as
00:00 / `--:--` and seeking is disabled. VLC for iOS (VLCKit) then reports
the item as a live stream, so iOS shows "LIVE" and a stop button instead of
pause on the lock screen and in Control Center.

Such pages are common and valid: opusenc's default `--max-delay` is
1000 ms, i.e. up to ~1 s of audio per page, which is ~56 KB per page at
512 kbit/s. FFmpeg's Ogg muxer also defaults to 1 s pages (`page_duration`
= 1000000 µs), so files written by FFmpeg are affected too at higher
bitrates. ffprobe and opusinfo read these files correctly.

## Environment

- VLC 3.0.20 (Ubuntu 24.04 package): reproduced.
- VLC 3.0.24 Vetinari (Arch Linux package): reproduced. The rc interface
  reports `get_length` = 0 for the affected file and 253 for the same
  audio repaginated into small pages.
- VLC for iOS 3.7.4: same files show as "live" with a stop button.
- The same code is in `master` (checked on 2026-11-20:
  `modules/demux/oggseek.c`, `Oggseek_ProbeEnd`, lines 210-310) and in
  `3.0.x` since 6183d1e1.

## Steps to reproduce

```
ffmpeg -f lavfi -i "anoisesrc=d=253.913:c=pink:a=0.5" -ac 2 -ar 44100 -sample_fmt s16 noise.flac
opusenc --bitrate 512 noise.flac big-pages.opus
opusenc --bitrate 512 --max-delay 62 noise.flac small-pages.opus
vlc big-pages.opus
vlc small-pages.opus
```

- `big-pages.opus`: largest page ~56 KB, last page ~51 KB -> no duration.
- `small-pages.opus`: largest page ~3.6 KB -> correct duration (4:13).

The audio packets are identical in both files; only the paging differs.
`opusinfo` and `ffprobe` report the correct duration for both.

I tested 7 durations between 250 and 260 s with opusenc's defaults at
512 kbit/s: all 7 had no duration in VLC. Re-encoded with `--max-delay 62`
or `--max-delay 90` (pages of ~3.6 KB and ~4.7 KB), every tested file had
the correct duration.

## Data from real files (VLC 3.0.24, Arch Linux)

Two tracks from the same CD, encoded the same way by `opusenc` 0.2
(opus 1.6.1) at 512 kbit/s with default paging, plus a copy of A
repaginated into ~3.5 KB pages without touching the packets:

| | A: original | C: A repaginated | B: other track |
|---|---|---|---|
| `oggz-validate` | no errors | no errors | no errors |
| `oggz-info` duration | 00:04:13.906 | 00:04:13.906 | 00:03:40.506 |
| Pages | 316 | 4286 | 285 |
| Largest page | 62384 bytes | 8219 bytes (header) | 62987 bytes |
| Last page | **29039 bytes** | **3635 bytes** | **4722 bytes** |
| Decoded PCM (sha256) | `4f74a8d2...` | `4f74a8d2...` (same) | `c9f50c96...` |
| VLC rc `get_length` | **0** | **253** | **220** |

B is the control: its pages are as large as A's (largest 62987 bytes),
but its last page happens to be short, and VLC finds its length. So the
trigger is the size of the last page, not large pages in general.

Last pages of the original (offset, size, bytes before EOF, granule):

```
15784900  59344  326129  11972160
15844244  59933  266785  12020160
15904177  58224  206852  12068160
15962401  60518  148628  12116160
16022919  59071   88110  12164160
16081990  29039   29039  12187832  (EOS)
```

The audio of A and C is bit-identical; only the paging differs, and only
the file whose last page is larger than 8500 bytes gets no length. A
also logs `ogg demux warning: Consider increasing access caching variable
from 1000 to >1900`, which C does not.

The full report (environment, `oggz-info`, last pages, VLC length and PCM
hash for each file) was produced by `vlc-ogg-length-report.bash` in
https://github.com/0x70369/random-ideas/tree/main/optical-media-ripping,
which also generates synthetic test files.

## Expected

The duration is shown and seeking works, as for files with small pages.

## Analysis

`Oggseek_ProbeEnd()` reads the end of the file in windows, starting with
the last `OGGSEEK_BYTES_TO_READ` (8500) bytes. If no complete page with a
granule is found, the next window starts earlier, but its upper bound is
moved down to the previous window's start + `MIN_PAGE_SIZE`
(`i_upperbound = i_next_upperbound`). So:

1. The last page ends at EOF. If it is larger than 8500 bytes, it is never
   complete in the first window, and no later window reaches EOF again.
2. The later windows are about 8.5, 25.5, 42.5, 23 and 23 KB long (plus
   up to 8500 bytes of read-ahead each), and the search stops at
   `i_lowerbound` (EOF - 2 x `MAX_PAGE_SIZE` per logical stream). With
   ~56 KB pages, no complete page fits in any of them, so
   `p_sys->i_length` stays unset.
3. `oy` (the `ogg_sync_state`) is not reset between windows, so the
   leftover bytes from one window are followed by bytes from an earlier
   file offset.

The 2022 fix "demux: ogg: fix last page probing" (efcb930b on master,
6183d1e1 on 3.0.x, refs #27610) is present in the tested version and does
not cover this case.

A possible fix: a window that ends at EOF and is at least `MAX_PAGE_SIZE`
(65307) bytes long always contains the whole last page, since no page can
be larger. Growing the window while keeping the upper bound at EOF (and
resetting `oy` before each window) would find it.

## Workaround

Encode with small pages (`opusenc --max-delay`, or FFmpeg's
`-page_duration`), or repaginate existing files (lossless: same packets,
smaller pages).

## Related

- #27610 / VLCKit#658 (short WhatsApp Ogg/Opus files): fixed by
  efcb930b / 6183d1e1, the change discussed above; this is a different
  case.
- vlc-android#3198: Opus files made by FFmpeg (libopus, ~318 kbit/s) show
  0:00 and cannot be seeked. Page sizes are not given there, but FFmpeg's
  default 1 s pages at that bitrate are ~40 KB, so it is probably the same
  bug.
