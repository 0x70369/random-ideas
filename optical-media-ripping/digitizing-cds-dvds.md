# Digitizing CDs/DVDs (music, albums, live shows, movies) — Arch Linux

Full procedure: identify the media → extract to FLAC → tag and organize with MusicBrainz Picard → convert to Opus. Video discs (movies, TV series) have their own branch: bit-exact backup and, optionally, a compressed MKV.

**Environment:** Arch Linux, USB optical drive at `/dev/sr0`, working area on a tmpfs mounted at `/temp`.

**Recordable media (CD-R / DVD±R / RW):** the tools classify a disc by its *content*, not by whether it was pressed or burned. An audio CD-R behaves like any audio CD; a DVD-R/+R/RW reports `DVD-R`/`DVD+R`/`DVD-RW` instead of `DVD-ROM` and is handled the same way. The one practical difference: burned discs may have `VIDEO_TS`/`AUDIO_TS` folders and `.VOB` files in lowercase, depending on the burning software. The scripts search case-insensitively; when typing commands by hand, use `find -iname` if `ls` finds nothing.

**Final file tree:**
```
Artist(s)/Album - Year/[Disco N/]NN - Title.opus
```
- `Various Artists` replaces the artist when an album has several; the individual artists stay in each track's metadata.
- The `Disco N` level only exists for multi-disc albums.
- Year = official release year, when available.

---

## Scripts

Each step exists as an independent Bash script (Unix philosophy: one script per step). This document explains *why* each command is used; the scripts add the edge cases and the interactive decision points.

| Script | Step | Interaction |
|---|---|---|
| `10a-install-dependencies.bash` | Check packages (`pacman -T`), install the missing ones | Confirms before installing; AUR packages are only reported |
| `10b-find-drive-offset.bash [device]` | Find and save the drive's read offset (once per drive) | You type the offset cyanrip found |
| `11-identify-media.bash [device]` | Identify the disc | None. Prints one token to stdout (`CD-DA`, `DVD-VIDEO`, `DVD-AUDIO`, `VCD`, `UNKNOWN`) and the next step to stderr |
| `12a-rip-cd.bash [device] [dest]` | Audio CD → FLAC (cyanrip), extraction only | None |
| `12b-rip-dvd-video.bash [device] [dest]` | Live-show DVD → FLAC per chapter | You pick the title(s) and the audio stream |
| `12c-rip-dvd-audio.bash [device] [dest]` | DVD-Audio → FLAC | Confirms after showing the track list |
| *(Picard)* | Tags and file tree | Graphical tool, by design |
| `14-convert-to-opus.bash <dir>` | FLAC → Opus in place, then R128 normalization tags (rsgain) | None |
| `15a-backup-video-disc.bash [device] [dest]` | Bit-exact backup of a DVD-Video or VCD/SVCD | Asks the folder name |
| `15b-compress-video-disc.bash <disc_dir> [dest]` | DVD backup → MKV (x265) | You pick the title(s) and track counts, and name each file |

Common behavior:
- With no device argument, the scripts try `/dev/sr0`, `/dev/sr1`, `/dev/cdrom`, `/dev/dvd`, `/dev/dvdrw`, `/dev/cdrw`, in that order. With two drives connected, pass the device explicitly.
- Verbose flags are used wherever the tool offers one (`mkdir -v`, `mount -v`, `dvdbackup -v`, `ffmpeg -loglevel verbose`, ...).
- On exit, `outcome-success.oga` plays on success and `dialog-error.oga` on failure. Both files must sit next to the scripts.
- **Ctrl+C** (or `kill`) stops the script with an error status, so `dialog-error.oga` plays. Without this, a program that catches Ctrl+C and exits 0 would make bash simply carry on with the next command.
- The rip scripts refuse to run if the destination still holds audio files from another disc, so two discs never get mixed.
- Temporary files and mount points are created inside `/temp`.
- **Logs:** when run from a terminal (both input and output; with piped input, e.g. `echo y | ...`, the script runs directly), each script re-runs itself under `script` (util-linux), which records everything shown — including prompts and your answers — to `/temp/logs/<script>-<date>.log`. Progress bars keep working because the script still runs in a (pseudo-)terminal. When the output is captured instead (`type=$(./11-identify-media.bash)`), nothing is logged, so the captured token stays clean.
- **Free space:** `/temp` is RAM. The DVD scripts compare the disc size with the free space first and stop before copying if it would not fit (`12b`, `15a`: disc + 10%; `12c`: 3× the disc, because decoded MLP can be about twice the disc size).
- **Eject:** after a successful rip, the disc is ejected (`eject -v`) — a visual "next disc" signal. On failure it stays in, so you can retry.

Chaining identification and ripping in your shell:
```bash
case "$(./11-identify-media.bash)" in
  CD-DA)     ./12a-rip-cd.bash ;;
  DVD-VIDEO) ./12b-rip-dvd-video.bash ;;   # or ./15a-backup-video-disc.bash for a movie/series
  DVD-AUDIO) ./12c-rip-dvd-audio.bash ;;
  VCD)       ./15a-backup-video-disc.bash ;;
  *)         echo "Unrecognized disc." ;;
esac
```

---

## 0. Required packages (install once)

`10a-install-dependencies.bash` checks each package below with `pacman -T` (deptest) and installs only the missing official ones with `pacman -S --needed`; missing AUR packages are listed with the `paru` command to install them. `-T` is used instead of `-Q` because it accepts any installed package that *provides* the name: with `handbrake-cli-git` or `cyanrip-git` installed, `handbrake-cli`/`cyanrip` count as present instead of being flagged and replaced.

By hand:
```bash
sudo pacman -S --needed libcdio flac ffmpeg libdvdcss dvdbackup \
                        lsdvd ogmtools vcdimager \
                        picard chromaprint opus-tools handbrake-cli
```

From the AUR (e.g. with `paru`):
```bash
paru -S cyanrip         # required: audio CD ripping
paru -S libdvd-audio    # only for DVD-Audio discs
paru -S rsgain          # required: R128 normalization tags in step 4
```
If `libdvd-audio` fails (its MLP support is weak and the project has been inactive since 2017), the proprietary, paid alternative is `dvdae-bin` (AUR).

`script`, `eject` and `lsblk` come from `util-linux`, part of every Arch install.

### 0b. Drive read offset (once per drive)

Every CD drive reads audio a few samples early or late. Without correcting this "read offset", a rip is not bit-identical to the reference rips in the AccurateRip database, so it cannot be verified against them. With a popular commercial audio CD in the drive (it must be in AccurateRip):
```bash
cyanrip -d /dev/sr0 -f
udevadm info --query=property --name=/dev/sr0 | grep '^ID_SERIAL='
# e.g. ID_SERIAL=PIONEER_BD-ROM_BDC-207D_PROLIFICMP000000002-0:0
mkdir -pv drive-offsets
echo 667 > drive-offsets/drive-offset.PIONEER_BD-ROM_BDC-207D_PROLIFICMP000000002-0_0
```
Each drive gets its own file, `drive-offsets/drive-offset.<drive id>`, in a `drive-offsets` folder next to the scripts. The id is the drive's udev `ID_SERIAL` (vendor, model and serial number); characters that are unsafe in file names become `_`. If udev reports no serial, the vendor and model from `/sys/class/block/srN/device/` are used instead.

**If `cyanrip -f` finds no offset** (the disc is not in AccurateRip, or no reference rip matched):
1. Try 2 or 3 other mainstream commercial CDs — big-label pressings, not CD-Rs or rare releases. Only one disc AccurateRip knows is needed, and nothing is ripped.
2. Or look up your drive model in the [AccurateRip drive offset list](http://www.accuraterip.com/driveoffsets.htm) or at [daefeatures.co.uk](https://www.daefeatures.co.uk/), and type the value. Search the drive's own vendor/model, which `10b` prints from `/sys/class/block/srN/device/{vendor,model}`: in a USB enclosure, udev's serial may name the USB bridge instead of the drive.
3. As a last resort, save `0`: the rips sound exactly the same, AccurateRip just can't confirm them. Rerun `10b` later to replace it.

`10b-find-drive-offset.bash` does all of this: it asks whether to detect the offset or type it, keeps going when detection fails, accepts `+667`-style values as the databases print them, and validates the number. `12a` identifies the drive in use and refuses to run until that drive's offset is saved, telling you the exact `10b` command to run. Plugging in a second drive just means running `10b` once more with it.

Only CD audio has a read offset. DVDs are read as plain data, sector by sector, so the DVD scripts don't need one.

---

## 1. Identify the media

With the disc in the drive:
```bash
cd-info --dvd --no-header --no-device-info /dev/sr0
```

Two parts of the output matter:
- `Disc mode is listed as:` — `CD-DA`, `DVD-ROM`, `DVD-R`, etc.
- The track list, one row per track, e.g. `  2: 05:22:40 024040 audio false no 2 no`. The fourth column says whether a track is `audio` or data.

Counting audio vs. data rows is more reliable than the mode string alone:

| What you see | Disc | Next step |
|---|---|---|
| Only `audio` tracks | Audio CD (pressed or CD-R) | Case A |
| `audio` tracks **and** a data track | "Enhanced" CD (album + videos/extras) | Case A — only the audio tracks are ripped |
| No audio tracks, a `DVD-*` mode | DVD | mount it, see below |
| No audio tracks, a CD mode | Data CD — maybe a Video CD | mount it, see below |

If `cd-info` fails (e.g. the drive is busy because of an automount):
```bash
udevadm info --query=property --name=/dev/sr0 | grep ID_CDROM_MEDIA
```
(`ID_CDROM_MEDIA_TRACK_COUNT_AUDIO` / `_DATA` give the same track counts.)

To see a DVD's or data CD's folder structure:
```bash
mnt="$(mktemp -d -p /temp)" && sudo mount -v -o ro /dev/sr0 "$mnt"
ls "$mnt"
sudo umount -v "$mnt" && rmdir -v "$mnt"
```
- `AUDIO_TS` with files → **Case C** (DVD-Audio, rare). If `VIDEO_TS` also has files (hybrid disc), still use `AUDIO_TS`: it is lossless.
- `VIDEO_TS` with files → **Case B** for a live show (audio only) or **step 5** for a movie/series (keep the video).
- `MPEGAV` (Video CD) or `MPEG2` (Super Video CD) → **step 5**.
- A DVD that refuses to mount is almost always a DVD-Video without a standard ISO 9660 file system: treat it as `VIDEO_TS`.

---

## 2. Extract to FLAC

### Case A — Audio CD (`12a-rip-cd.bash`)

CDs are ripped with **cyanrip**, which uses cd-paranoia underneath and adds what plain `cdparanoia` lacks:

| Problem | What cyanrip does |
|---|---|
| Drive read offset | Corrects it with `-s <offset>` (saved in step 0b) |
| No way to know whether a scratched disc ripped cleanly | Verifies every track against AccurateRip (v1/v2) and writes a rip log with the paranoia error counts |
| **Pre-emphasis**: some mid-80s to early-90s CDs were mastered with a treble boost and a flag telling the player to undo it (up to about −9.5 dB at 20 kHz). Rippers that ignore the flag produce harsh, bright files | Detects the flag (TOC and subcode) and applies de-emphasis automatically |
| Hidden track before track 1 (HTOA) | `-p 1=track` saves it as track 0 |
| Enhanced CD data track | `-l 1,2,...` rips only the listed audio tracks |
| Metadata | **Nothing is looked up**: `-N` (no MusicBrainz), `-U` (no cover download), `-K` (no ReplayGain tags — see section 4). Tagging is done by hand in Picard. AccurateRip stays on: it compares audio checksums, it is not metadata |

```bash
mkdir -pv /temp/rip && cd /temp/rip
cyanrip -d /dev/sr0 -s 6 -N -U -K              # 6 = your saved offset
eject -v /dev/sr0
```
Optional arguments, added by `12a` when they apply:
- `-l 1,2,3` — only these tracks (enhanced CD: the audio tracks, read from `cd-info`).
- `-p 1=track` — track 1 starts 2 s or more into the disc (its LSN in `cd-info` is ≥ 150): there is hidden audio before it.

Without metadata, cyanrip creates `/temp/rip/Unknown disc (XXXX) [FLAC]/` (XXXX = start of the barcode, MCN or disc ID) with `<track> - Unknown track.flac` files (maximum compression), a CUE sheet and the **rip log**. Picard renames everything on save. At the end, `12a` prints the disc ID (from the log) and its MusicBrainz page, `https://musicbrainz.org/cdtoc/<disc ID>`. Read the log after each disc: it says per track whether the rip matched AccurateRip. A track that is not in the database is not an error — the log then just cannot confirm it.

**About gaps:** cyanrip handles pregaps like EAC: each track's pregap (the silence between tracks) is attached to the **end of the previous track**. Cutting it is destructive: it removes reverb tails and applause on live or gapless discs. If you still want to remove only the trailing silence:
```bash
for f in *.flac; do
  ffmpeg -i "$f" -af "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse" "cut-$f"
done
```
Try it on one disc before applying it to the whole collection.

### Case B — DVD-Video live show, audio only (`12b-rip-dvd-video.bash`)

List titles, chapter counts and audio streams:
```bash
lsdvd -a /dev/sr0
```
Pick the title(s): the show is usually the longest; extra titles may be alternative versions (e.g. an instrumental mix) — compare durations and audio streams.

For each chosen title (`N` below):

**1. Copy only that title** to a temporary folder:
```bash
work="$(mktemp -d -p /temp)"
dvdbackup -v -i /dev/sr0 -t N -n "title-N" -o "$work"
```
Why not just concatenate the `VTS_xx_*.VOB` set of the title: several titles often share one VTS. Concatenating the whole set drags the other titles in, so chapter times no longer line up and the last chapter runs into the next title. `dvdbackup -t` copies only the sectors of that title.

**2. List its audio streams with their stream ids:**
```bash
vobs="concat:$(find "$work/title-N" -iname 'VTS_*_[1-9].VOB' | sort | paste -sd'|')"
ffprobe -v error -analyzeduration 100M -probesize 100M -select_streams a \
  -show_entries stream=id,codec_name,channels,sample_rate,bit_rate -of compact=p=0 "$vobs"
```
Ids on DVD-Video: `0xa0`–`0xa7` = LPCM (lossless), `0x80`–`0x87` = AC-3, `0x88`–`0x8f` = DTS (both lossy). Choose by quality: LPCM first, then the higher bitrate/channel count.

Select the stream **by id**, not by index: the order in which ffmpeg lists streams is not guaranteed to match `lsdvd`'s numbering. The larger `-analyzeduration`/`-probesize` help because VOBs often announce some streams late.

**3. Extract the whole title as one FLAC:**
```bash
ffmpeg -n -loglevel verbose -analyzeduration 100M -probesize 100M \
  -i "$vobs" -map 0:i:0xa0 -vn -c:a flac "$work/title-N.flac"
```
If the id does not exist, ffmpeg stops with an error instead of picking another stream.

**4. Read the chapter times:**
```bash
dvdxchap -t N /dev/sr0
# CHAPTER01=00:00:00.000
# CHAPTER02=00:04:12.240
# ...
```

**5. Cut one FLAC per chapter:**
```bash
mkdir -pv /temp/rip/title-N
ffmpeg -n -ss 00:00:00.000 -to 00:04:12.240 -i "$work/title-N.flac" -c:a flac -compression_level 8 /temp/rip/title-N/01.flac
ffmpeg -n -ss 00:04:12.240                  -i "$work/title-N.flac" -c:a flac -compression_level 8 /temp/rip/title-N/02.flac
# (no -to on the last chapter, so it runs to the end of the title)
rm -rfv "$work"
```
`-n` never overwrites an existing file. With `-ss`/`-to` before `-i`, the cuts are sample-exact on the title's timeline: decoded and joined back, the chapters are identical to the whole title (tested), with no gap or overlap. `-compression_level 8` matches `flac --best`.

**Why not `ffmpeg -f dvdvideo`:** that demuxer (built on `libdvdnav`/`libdvdread`) failed to read even the first chapter of one of the discs in this collection. `lsdvd`, `dvdxchap` and `dvdbackup` read the same disc structure without that problem.

**Note:** if a title only has AC-3/DTS audio, the source is already lossy. FLAC stores the decoded audio without adding loss, but it cannot recover what the disc's encoder discarded.

### Case C — DVD-Audio (`12c-rip-dvd-audio.bash`)

```bash
mnt="$(mktemp -d -p /temp)" && sudo mount -v -o ro /dev/sr0 "$mnt"
dvda-debug-info -A "$mnt/AUDIO_TS"      # lists titles and tracks (titleset 1)
ls "$mnt/AUDIO_TS"/ATS_*_0.IFO          # more than one = more than one titleset
mkdir -pv /temp/rip && cd /temp/rip
dvda2wav -A "$mnt/AUDIO_TS" -c /dev/sr0   # -c: decrypt CPPM
find . -maxdepth 1 -name '*.wav' -print0 |
  xargs -0 --verbose -P"$(nproc)" -I{} flac --best --verify --delete-input-file {}
sudo umount -v "$mnt" && rmdir -v "$mnt"
```
On burned discs the folder may be lowercase: find it with `find "$mnt" -maxdepth 1 -iname AUDIO_TS`.

- **`-c /dev/sr0` is required for commercial discs:** they are encrypted with CPPM, and `dvda2wav` only decrypts when it is given the drive. Without it the output is noise.
- **Only titleset 1:** `dvda2wav` and `dvda-debug-info` have the titleset fixed at 1 (`ATS_01_*`). If the disc has `ATS_02_0.IFO` or more, `12c` warns you: that audio is not extracted.
- `dvda2wav` exits 0 even when it extracts nothing, so `12c` checks that WAV files were produced.

---

## 3. Tags and organization (MusicBrainz Picard)

### 3.1 Configure once (Options)

**Options ▸ File Naming ▸ Edit file naming script** — paste:
```
$if($eq(%albumartist%,Various Artists),Various Artists,%albumartist%)/%album% - $if2($left(%originaldate%,4),$left(%date%,4))/$if($gt(%totaldiscs%,1),Disco %discnumber%/,)$num(%tracknumber%,2) - %title%
```
(`Disco` is the folder name you chose for multi-disc albums; change it to `Disc` in the script if you prefer.)

**File Naming:**
- ✅ Rename files when saving
- ✅ Move files when saving → Destination directory: `/temp/final`
- ✅ Delete empty directories
- ✅ Move additional files → `*.log *.cue` (the cyanrip rip log and CUE sheet travel with the album, and the emptied rip folder can be deleted)
- ❌ Replace non-ASCII characters (leave unchecked to keep accents)

**Cover Art:**
- ✅ Embed cover images into tags
- ✅ Embed only a single front image

Click **Make It So**.

### 3.2 Workflow, one album at a time

1. **File ▸ Add Folder** → `/temp/rip` (or `/temp/rip/title-N`) — one album at a time.
2. Identify the release — the first method that applies:
   - **CDs:** put the disc back in the drive and use **Tools ▸ Lookup CD**. Picard computes the disc ID from the disc's table of contents and lists the releases with exactly that track layout; pick one and drag the files onto it. If none matches, the same dialog lets you submit the disc ID to MusicBrainz, attaching it to the right release. Alternatives: Picard 3.0+ can instead read the disc ID from the cyanrip rip log: Tools ▸ Lookup CD ▸ from a log file. Picard 2.x does not read cyanrip logs. Without the disc: open the `cdtoc` link `12a` printed, copy the URL of the right release and paste it into Picard's search box — Picard loads that release.
   - **DVD shows and anything else:** click **Cluster**, then **Scan** (AcoustID fingerprint), which works well for commercial studio releases. If nothing is found (common for live shows and bootlegs), search by artist/title in the right pane and drag the cluster onto the right release.
3. Compare the release's track list (right) with the files (left) — this is where you check that the DVD chapter order matches the official track numbering.
4. Check the cover in the **Cover Art** tab.
5. `Ctrl+S` — Picard moves and renames the files (and the log/CUE) into `/temp/final/...`. With "Delete empty directories" on, `/temp/rip` is left empty, ready for the next disc.

---

## 4. Convert to Opus (`14-convert-to-opus.bash /temp/final`)

```bash
find /temp/final -type f -iname '*.flac' -print0 |
  xargs -0 -P"$(nproc)" -I{} bash -c '
    f="$1"
    channels="$(metaflac --show-channels "$f" 2>/dev/null | tail -n1 | tr -cd "0-9")"
    if ! [[ "$channels" =~ ^[0-9]+$ ]] || [[ "$channels" -lt 1 ]]; then
        echo "Failed: $f (metaflac did not return a clean channel count: [$channels])" >&2
        exit 0
    fi
    bitrate=$(( channels * 256 ))
    out="${f%.*}.opus"
    logfile="$(mktemp -p /temp)"
    trap '\''rm -f -- "$out" "$logfile"; exit 130'\'' INT TERM
    if opusenc --bitrate "$bitrate" "$f" "$out" >"$logfile" 2>&1; then
        trap - INT TERM
        echo "=== OK: $f (channels=$channels bitrate=$bitrate) ==="
        cat "$logfile"
        rm -v -- "$f"
    else
        echo "=== Failed: $f (channels=$channels bitrate=$bitrate) ===" >&2
        cat "$logfile" >&2
        rm -fv -- "$out"
    fi
    rm -fv "$logfile"
  ' _ {}
```

**Why:**
- `bitrate=$(( channels * 256 ))`: `opusenc`'s help gives 256 kbit/s **per channel** as the ceiling, but `--bitrate` takes the **total** — hence the multiplication (stereo → 512, 5.1 → 1536). Tested: asking for more (mono 510, stereo 1020, 5.1 3060) gives exactly the same average bitrate (about 244, 451 and 1276 kbit/s on full-band noise), because libopus caps the rate internally, so this already is the real ceiling. This is a deliberate choice: above roughly 128–160 kbit/s stereo, Xiph already considers Opus transparent; the extra bitrate buys no proven audible gain.
- VBR is the default mode and complexity (`--comp`) already defaults to 10 (maximum), so neither is passed. Note `--vbr` is a plain switch: `--vbr on` is rejected and makes `opusenc` print its help screen.
- No `--discard-comments`/`--discard-pictures`: by default `opusenc` copies the Vorbis comments and the embedded cover from the FLAC — exactly what Picard wrote.
- **ReplayGain:** `opusenc` converts `REPLAYGAIN_*` tags into the Opus header *output gain*, which every player applies, always (album gain −10 dB → header gain −15 dB, normalized to −23 LUFS). The files would then play at another volume than the CD everywhere. `12a` does not write these tags (`-K`); if any FLAC still has them (e.g. from a Picard plugin), `14` removes them with `metaflac --remove-tag` before converting. Normalization is done afterwards, the Opus way (4b). Check an existing file with `opusinfo file.opus | grep 'Playback gain'`.
- The channel count is validated: an empty or non-numeric value would become an invalid `--bitrate`.
- Ctrl+C during an encode removes the half-written `.opus` and its log; the FLAC stays (tested). The cleanup is disarmed once the Opus is complete, before the FLAC is deleted.
- One log file per process (`mktemp`): a fixed file name shared by parallel processes gets overwritten by the others. Each file's output is printed in one block when it finishes, so parallel encoders don't interleave their progress lines.
- The FLAC is deleted only if the conversion succeeded. If any FLAC is left at the end, the script exits with an error.
- `-P"$(nproc)"`: one process per core — this is where the CPU, not the drive, is the bottleneck.

At the end `/temp/final` holds only `.opus` files in the `Artist(s)/Album - Year/[Disco N/]NN - Title.opus` tree, ready to be moved off the tmpfs.

### 4b. Normalization tags (done by `14` after the conversion)

ReplayGain-style normalization measures each track's and album's loudness and stores, as tags, how much a player should turn the volume up or down so everything plays at a similar loudness. The audio is never changed: players that read the tags adjust the volume, the others play the file as the CD sounds. **Album gain** keeps the loudness differences between the tracks of an album; **track gain** evens every track out (shuffle).

`14` uses only the Opus standard (RFC 7845): `R128_TRACK_GAIN`/`R128_ALBUM_GAIN` tags referenced to −23 LUFS, with the header output gain at 0 dB. It is done on the final Opus files, not by cyanrip, because `opusenc` would turn FLAC ReplayGain tags into that header gain, which every player applies.

```bash
# per album: all its .opus files at once (Disco N folders count as one album)
rsgain custom -a -s i -c p -o s "/temp/final/Artist/Album - Year"/*.opus
```
- `-a` album gain; `-s i` write the tags (rsgain's default only scans); `-c p` clipping protection when a gain is positive — rsgain's recommended settings.
- `-o s` — R128 tags at −23 LUFS, header gain set to 0 (which also restores the CD's volume on any Opus file that got a header gain earlier). Some players (foobar2000, among others) add +5 dB to Opus files to match ReplayGain's −18 LUFS; that is the player's choice, the tags stay standard.
- `14` groups the files per album from the tree (a `Disco N`/`Disc N`/`CD N` folder belongs to the album above it), runs one `rsgain` per album in parallel, prints each album's result in one block and exits with an error if any album failed. It only runs once every FLAC was converted, so no album is measured incomplete.
- **Already-tagged albums are skipped:** before calling `rsgain`, `14` reads each file's tags with `ffprobe`; an album whose files all have both `R128_TRACK_GAIN` and `R128_ALBUM_GAIN` is skipped. So running `14` on `/temp/final` after ripping another CD only measures the new album — plus any album an earlier run failed to tag. The check is per album, not per file: a new file in an album (e.g. a later `Disco N`) changes the album gain of every file in it, so that whole album is measured again. With no FLAC left, `14` only does this check.

---

## 5. Video discs: movies and TV series

### 5a. Bit-exact backup (`15a-backup-video-disc.bash`)

The script mounts the disc, looks at its folders and asks for a folder name (default: the volume label). Always choosing the name matters: many discs share generic labels like `DVD_VIDEO`, and two of them would be merged into one folder.

**DVD-Video (`VIDEO_TS`)** — the whole structure, every title, audio track, subtitle, chapter and menu, exactly as authored:
```bash
dvdbackup -v -i /dev/sr0 -M -n "Movie Name" -o /temp/video-backup
```

**Video CD / Super Video CD (`MPEGAV` / `MPEG2`)** — every MPEG track as a `.mpg`, plus `videocd.xml` describing the disc structure (menus, entry points, playback control); `vcdxbuild` can rebuild the disc from both:
```bash
mkdir -pv "/temp/video-backup/Movie Name" && cd "/temp/video-backup/Movie Name"
vcdxrip --verbose --progress --cdrom-device=/dev/sr0
```
Do not just copy the `.DAT` files from a mounted VCD: they use Mode 2 Form 2 sectors, which a normal file copy reads incorrectly.

**No `sudo` for `dvdbackup`/`vcdxrip`:** your user already reads the drive (CD ripping works without it). Running them as root leaves root-owned files in `/temp` that you then need `sudo rm -r` to delete. Only `mount`/`umount` need `sudo`.

### 5b. Compressed MKV (`15b-compress-video-disc.bash`)

Works from a DVD backup made in 5a, never from the drive, so a slow or scratched disc is read only once:
```bash
HandBrakeCLI -v -i "/temp/video-backup/Movie Name" -t 0 --scan    # list titles
HandBrakeCLI -v -i "/temp/video-backup/Movie Name" -t N --scan    # tracks of title N
HandBrakeCLI --verbose=2 -i "/temp/video-backup/Movie Name" -t N \
  -o "/temp/video-final/Movie Name (2020).mkv" \
  -e x265 --encoder-preset slow -q 20 --comb-detect --decomb \
  --crop 0:0:0:0 \
  -a 1,2,3 -E copy,copy,copy --audio-fallback flac24 \
  -s 1,2 -m
```
- **Video:** x265 at CRF 20, `slow` preset — a large size reduction from the DVD's MPEG-2 at close to transparent quality.
- **Audio and subtitles:** copied untouched (`-E copy`). They are small; re-encoding would only risk quality. If a track cannot be passed through, the fallback is FLAC 24-bit, which is lossless.
- **Chapters:** kept as MKV chapter markers (`-m`).
- **No cropping** (`--crop 0:0:0:0`): HandBrake crops black bars automatically by default, and that detection can cut real picture in dark scenes. Bars cost almost nothing to encode.
- One `.mkv` per title: for a TV season, each episode is usually its own title.
- Nothing deletes the backup: whether to keep it is your decision.
- VCD `.mpg` files are not handled by 5b.

---

## Appendix A — Lossless vs. lossy (CD/DVD audio)

**Lossless:**
| Format | Where it appears |
|---|---|
| PCM / LPCM | CD-DA, DVD-Video, DVD-Audio |
| MLP | DVD-Audio |
| FLAC | produced by us, not native to discs |

**Lossy:**
| Format | Where it appears |
|---|---|
| DTS (core, DTS-ES, DTS 96/24) | DVD-Video, DVD-Audio |
| Dolby Digital / AC-3 | DVD-Video |
| MPEG-1/2 Audio Layer II | DVD-Video (common on European discs), Video CD |

(DTS-HD Master Audio, Dolby TrueHD and DTS-HD High Resolution only exist on Blu-ray/HD DVD — they do not apply to a CD/DVD drive.)

## Appendix B — Where multithreading helps

| Step | Parallel? | Why |
|---|---|---|
| `cyanrip` | No (one drive) | The drive spinning the disc is the bottleneck; it already writes FLAC directly |
| `dvdbackup`, `vcdxrip` | No | Drive I/O is the bottleneck |
| DVD title extraction and chapter cuts | Not worth it | Each cut depends on the single file extracted before |
| `dvda2wav` | No | Single-threaded tool |
| `flac` (WAV→FLAC, DVD-Audio) | Yes, per file | Each track is independent |
| Picard (Scan) | Already parallel internally | — |
| `opusenc` (FLAC→Opus) | Yes, per file | The largest real CPU load of the whole pipeline |
| `rsgain` (R128 tags) | Yes, per album | Album gain needs all of an album's files in one run |
| HandBrake (x265) | Already multithreaded | x265 uses all cores on its own |

## Appendix C — References

- ArchWiki — Rip Audio CDs: https://wiki.archlinux.org/title/Rip_Audio_CDs
- ArchWiki — Optical disc drive: https://wiki.archlinux.org/title/Optical_disc_drive
- ArchWiki — Dvdbackup: https://wiki.archlinux.org/title/Dvdbackup
- cd-info man page: https://man.archlinux.org/man/extra/libcdio/cd-info.1.en
- cyanrip (README: options, offset, AccurateRip, de-emphasis, pregap actions, naming): https://github.com/cyanreg/cyanrip
- cyanrip (AUR): https://aur.archlinux.org/packages/cyanrip
- cyanrip offset sources (FreeBSD port message): https://cgit.freebsd.org/ports/tree/audio/cyanrip/pkg-message
- AccurateRip drive offset list: http://www.accuraterip.com/driveoffsets.htm
- Bash manual — signals and traps: https://www.gnu.org/software/bash/manual/html_node/Signals.html
- CD pre-emphasis explained (Archimago): https://archimago.blogspot.com/2020/09/how-to-cd-pre-emphasis-and-dealing-with.html
- cdparanoia man page: https://manpages.org/cdparanoia
- cdparanoia source (aborts on spans with data tracks): https://stuff.mit.edu/people/nocturne/athena/sipbcopy/project/cdparanoia-netbsd/cdparanoia/main.c
- MusicBrainz Picard — Lookup CD: https://picard-docs.musicbrainz.org/en/usage/retrieve_lookup_cd.html
- Picard source (cyanrip log support, PICARD-3346, 3.0): https://github.com/metabrainz/picard/blob/master/picard/disc/cyanriplog.py
- cyanrip source (defaults without metadata: "Unknown disc", "Unknown track"): https://github.com/cyanreg/cyanrip/blob/master/src/cyanrip_main.c
- opus-tools source (ReplayGain → header gain): https://github.com/xiph/opus-tools/blob/master/src/flac.c
- rsgain (README: Opus modes, Easy Mode defaults): https://github.com/complexlogic/rsgain
- RFC 7845 (Ogg Opus: output gain, R128 tags): https://datatracker.ietf.org/doc/html/rfc7845
- rsgain man page: https://www.mankier.com/1/rsgain
- ReplayGain (Hydrogenaudio Wiki): https://wiki.hydrogenaudio.org/index.php/ReplayGain
- script(1) — util-linux: https://www.man7.org/linux/man-pages/man1/script.1.html
- eject(1) — util-linux: https://www.man7.org/linux/man-pages/man1/eject.1.html
- dvdbackup man page: https://man.archlinux.org/man/dvdbackup.1.en
- lsdvd man page: https://man.archlinux.org/man/lsdvd.1.en.raw
- FFmpeg formats (`dvdvideo` demuxer): https://ffmpeg.org/ffmpeg-formats.html
- FFmpeg stream specifiers (`i:stream_id`): https://huggingface.co/spaces/Pranjal12345/Whisper_with_FastApi/blob/71f4c16f9b95f944d8859ad5b51a31c953c2c690/bin/ffmpeg/doc/fftools-common-opts.texi
- opusenc man page: https://man.archlinux.org/man/opusenc.1
- Opus recommended settings (Xiph): https://wiki.xiph.org/Opus_Recommended_Settings
- MusicBrainz Picard — naming scripts: https://picard-docs.musicbrainz.org/en/latest/tutorials/naming_script.html
- MusicBrainz Picard — file naming options: https://picard-docs.musicbrainz.org/en/v3.0/config/options_filerenaming.html
- MusicBrainz Picard — cover art options: https://picard-docs.musicbrainz.org/en/v3.0/config/options_cover.html
- vcdxrip man page: https://man.archlinux.org/man/vcdxrip.1.en
- vcdimager (Arch package): https://archlinux.org/packages/extra/x86_64/vcdimager/
- HandBrakeCLI command-line reference: https://handbrake.fr/docs/en/latest/cli/command-line-reference.html
- libdvd-audio (AUR): https://aur.archlinux.org/packages/libdvd-audio
- Gap handling (EAC): https://exactaudiocopy.de/gap-technology/
