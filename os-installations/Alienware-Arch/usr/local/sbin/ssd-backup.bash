#!/usr/bin/env bash

# Backs up the subvolumes of the portable SSD's Btrfs file system before it is reformatted, and
# restores them onto the new file system afterwards.
#
# Usage: see usage() below, or run it with -h or --help.
#
# Backup
#   Every subvolume except @snapshots and Arch/ (and anything below them), which are recreated from
#   scratch. Each subvolume is first recompressed in place with zstd level 15 (Btrfs' maximum),
#   since they are archives. Then a read-only snapshot of it is sent with btrfs send, keeping the
#   already compressed extents (--compressed-data). The backup folder is --destination, by default
#   ~/Downloads/ssd-backup of the user who ran sudo.
#     - on Btrfs: the snapshots are received there as subvolumes (btrfs receive);
#     - on any other file system: the send streams are saved as files, with SHA-256 checksums.
#   Files and folders that aren't inside any subvolume (e.g. btrfs-full-snapshot.bash) go into
#   top-level-files.tar.zst.
#
# Restore
#   Receives each subvolume back at its original path, extracts the files outside the subvolumes,
#   puts the immutable and append-only flags back and recreates an empty @snapshots. Arch/ isn't
#   touched. The target must be a new file system: nothing at the original paths may exist yet.
#   If it is interrupted, running it again continues after the last subvolume that was finished.
#
# Immutable (chattr +i) and append-only (+a) files and folders can't receive the compression
# property or be rewritten, so the backup removes the flags and puts them back on the SSD at the
# end, even if the script fails. Neither btrfs send nor tar keeps these flags, nor the No_COW one
# (+C), so all three are listed in attributes.tsv, which the restore uses. Other chattr flags
# (noatime, nodump...) aren't carried over.
#
## https://btrfs.readthedocs.io/en/latest/Compression.html
## https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html (defragment)
## https://btrfs.readthedocs.io/en/latest/btrfs-send.html
## https://btrfs.readthedocs.io/en/latest/btrfs-receive.html

set -euo pipefail

# -----------------------------------------------------
# Settings
# -----------------------------------------------------

level=15                # ZSTD_BTRFS_MAX_LEVEL in fs/btrfs/zstd.c
excluded="@snapshots"   # recreated from scratch; its snapshots can be deleted before the backup
skipped="Arch"          # empty, recreated from scratch; neither backed up nor touched
ro_name=".ssd-backup-ro"        # on the SSD: read-only snapshots while the backup sends them
staging_name=".ssd-restore"     # on the SSD: subvolumes being received by the restore

# -----------------------------------------------------
# Common
# -----------------------------------------------------

die() { printf 'Error: %s\n' "$*" >&2; exit 1; }
msg() { printf '\n==> %s\n' "$*"; }
confirm() { local answer; read -r -p "$1 [y/N] " answer; [ "${answer,,}" = y ]; }

usage() {
    local me=${0##*/} user=${SUDO_USER:-${USER:-you}}
    cat << EOF
Usage: sudo ./$me backup  -s <SSD mount point> [-d <backup folder>]
       sudo ./$me restore -d <SSD mount point> [-s <backup folder>]
       ./$me -h|--help

Backs up the Btrfs subvolumes of the portable SSD before it is reformatted, and puts them back
on the new file system afterwards.

  backup       Recompress every subvolume on the SSD with zstd level $level, then copy them, the
               files outside the subvolumes and their immutable, append-only and No_COW flags.
               $excluded and $skipped/ aren't backed up. The backup folder must be empty.
  restore      Put everything back on a newly formatted SSD and create an empty $excluded.
               If it is interrupted, running it again continues where it stopped.
  (neither)    Show a menu to choose between the two.

  -s, --source <path>        Where the data comes from: the SSD for backup, the backup folder
                             for restore.
  -d, --destination <path>   Where the data goes: the backup folder for backup, the SSD for
                             restore.
  -h, --help                 Show this help.

The SSD is always required, and it must be given by the mount point of its top-level subvolume
(subvolid=5), for example /run/media/$user/Oazideia. The backup folder is optional: without it,
~/Downloads/ssd-backup of the user who ran sudo is used. It can't be inside the SSD.

Examples:
  sudo ./$me backup -s /run/media/$user/Oazideia
  sudo ./$me backup --source /run/media/$user/Oazideia --destination /mnt/disk/ssd-backup
  sudo ./$me restore -d /run/media/$user/Oazideia
  sudo ./$me restore --source /mnt/disk/ssd-backup --destination /run/media/$user/Oazideia

Needs: btrfs-progs 6.14+ and kernel 6.15+ (backup), attr, e2fsprogs, zstd; compsize is optional.
EOF
}

bad_usage() { usage >&2; die "$@"; }

mode="" source_arg="" destination_arg=""
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) usage; exit 0 ;;
        backup|restore)
            [ -z "$mode" ] || bad_usage "choose only one of backup and restore."
            mode=$1 ;;
        -s|--source)
            [ $# -ge 2 ] && [ -n "$2" ] || bad_usage "$1 needs a path."
            source_arg=$2; shift ;;
        --source=?*) source_arg=${1#*=} ;;
        -d|--destination)
            [ $# -ge 2 ] && [ -n "$2" ] || bad_usage "$1 needs a path."
            destination_arg=$2; shift ;;
        --destination=?*) destination_arg=${1#*=} ;;
        *) bad_usage "unknown argument: $1" ;;
    esac
    shift
done

[ "$(id -u)" -eq 0 ] || die "run with sudo."

if [ -z "$mode" ]; then
    PS3="What do you want to do? "
    select _ in "Back up the SSD (--source) to the backup folder (--destination)" \
                "Restore the backup folder (--source) to the SSD (--destination)" "Quit"; do
        case "$REPLY" in
            1) mode=backup; break ;;
            2) mode=restore; break ;;
            3) exit 0 ;;
        esac
    done
    [ -n "$mode" ] || exit 0
fi

# The SSD is the source of a backup and the destination of a restore
if [ "$mode" = backup ]; then
    ssd_arg=$source_arg ssd_option=--source backup_arg=$destination_arg
else
    ssd_arg=$destination_arg ssd_option=--destination backup_arg=$source_arg
fi
[ -n "$ssd_arg" ] || bad_usage "$mode needs $ssd_option <mount point of the SSD's top-level subvolume>."

# The backup's files are given to the user who ran sudo, if there is one
owner="" owner_group=""
if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != root ]; then
    owner=$SUDO_USER
    owner_group=$(id -gn "$owner")
fi
own() { [ -z "$owner" ] || chown "$1" "$owner:$owner_group" "${@:2}"; }

if [ -z "$backup_arg" ]; then
    [ -n "$owner" ] || die "without sudo from your user there is no ~/Downloads to default to: give the backup folder too."
    backup_arg="$(getent passwd "$owner" | cut -d: -f6)/Downloads/ssd-backup"
fi

[ -d "$ssd_arg" ] || die "$ssd_arg ($ssd_option) isn't a folder."
ssd=$(realpath "$ssd_arg")
backup=$(realpath -m "$backup_arg")
manifest="$backup/manifest.tsv"
attributes="$backup/attributes.tsv"
snapshots_meta="$backup/snapshots.meta"
top_level_tar="$backup/top-level-files.tar.zst"

# The SSD must be given by the root of the mounted device: a mount point, on Btrfs, showing the
# top-level subvolume (ID 5) from its own root (inode 256), not one of its folders or subvolumes.
[ "$(stat -f -c %T "$ssd")" = btrfs ] || die "$ssd ($ssd_option) isn't on Btrfs."
mountpoint -q "$ssd" \
    || die "$ssd ($ssd_option) isn't a mount point. Give the folder where the SSD is mounted, not one inside it."
[ "$(btrfs inspect-internal rootid "$ssd")" = 5 ] && [ "$(stat -c %i "$ssd")" = 256 ] \
    || die "$ssd ($ssd_option) is mounted, but not from the top-level subvolume (subvolid=5). Mount the SSD with -o subvolid=5."

[[ $backup/ != "$ssd"/* ]] || die "the backup folder ($backup) can't be inside the SSD ($ssd)."

command -v setfattr > /dev/null || die "setfattr not found: pacman -S --needed attr"
command -v zstd > /dev/null || die "zstd not found: pacman -S --needed zstd"
command -v chattr > /dev/null || die "chattr not found: pacman -S --needed e2fsprogs"

# Subvolume paths relative to the top level, parents before children
list_subvolumes() {
    btrfs subvolume list -a "$ssd" | sed -E 's/^ID [0-9]+ gen [0-9]+ top level [0-9]+ path (<FS_TREE>\/)?//' \
        | { grep -Ev "^(${ro_name//./\\.}|${staging_name//./\\.})/" || true; } | LC_ALL=C sort
}

# Deletes the subvolumes an interrupted run left in a work folder on the SSD
remove_leftovers() {
    [ -d "$1" ] || return 0
    local item
    for item in "$1"/* "$1"/.[!.]*; do
        [ -d "$item" ] && [ "$(stat -c %i "$item")" = 256 ] && btrfs -v subvolume delete "$item"
    done
    return 0
}

# Compression property on every folder and file of a subvolume. -xdev stops at nested subvolumes,
# which are handled on their own.
set_compression_property() {
    find "$1" -xdev \( -type d -o -type f \) -print0 \
        | xargs -0 -r -t -n 1000 setfattr -n btrfs.compression -v zstd \
        || echo "    (some files refused the property, e.g. No_COW files, which Btrfs never compresses; see the errors above)"
}

# chattr rewrites every flag of the file, including the compression one ("c"), and on Btrfs that
# resets the compression property to the algorithm of the compress= mount option, or to zlib when
# there is none (btrfs_fileattr_set in fs/btrfs/ioctl.c). So, while the script runs, the SSD is
# remounted with compress=zstd:15. That also applies the level to anything written meanwhile.
original_compress=$(findmnt -no OPTIONS --target "$ssd" | grep -oE 'compress(-force)?=[^,]+' || echo compress=no)
remount_zstd() {
    msg "Remounting $ssd with compress=zstd:$level (was: $original_compress)"
    mount -v -o "remount,compress=zstd:$level" "$ssd"
}
remount_original() {
    msg "Remounting $ssd with $original_compress again"
    mount -v -o "remount,$original_compress" "$ssd" || true
}

# Calls "$@ <flags> <path>" for each line of attributes.tsv. The paths are relative to the SSD's top
# level. The lines are split by hand because read would drop spaces and tabs at the end of a name.
each_flagged() {
    local line
    tail -n +2 "$attributes" | while IFS= read -r line; do
        "$@" "${line%%$'\t'*}" "${line#*$'\t'}"
    done
}

# Immutable and append-only: removed by the backup, put back by both modes. No_COW (C) is never
# removed, so it isn't handled here.
unlock_one() {
    local flags=${1//C/}
    [ -z "$flags" ] || chattr -V -i -a -- "$ssd/$2" || echo "    (couldn't remove the flags of $2; it stays as it is)"
}
lock_one() {
    local flags=${1//C/}
    [ -z "$flags" ] || chattr -V "+$flags" -- "$ssd/$2" || true
}

# No_COW again, for the restore. A folder or an empty file just takes the flag. A file with data
# can't: it is copied into a new No_COW file, which replaces it. Compression and No_COW exclude each
# other, so the compression property goes first.
nocow_one() {
    [[ $1 == *C* ]] || return 0
    local target="$ssd/$2" dir dir_mtime tmp="" current
    current=$(lsattr -d -- "$target" 2>/dev/null || true)
    [[ ${current%% *} == *C* ]] && return 0
    setfattr -x btrfs.compression -- "$target" 2>/dev/null || true
    if [ -d "$target" ] || [ ! -s "$target" ]; then
        chattr -V +C -- "$target" || echo "    (couldn't set No_COW on $2)"
        return 0
    fi
    dir=$(dirname "$target")
    dir_mtime=$(stat -c %y "$dir")
    if tmp=$(mktemp -p "$dir" .nocow.XXXXXX) && chattr +C -- "$tmp" \
        && cp -v -a --reflink=never --sparse=always -- "$target" "$tmp" && mv -v -f -- "$tmp" "$target"; then
        :
    else
        [ -z "$tmp" ] || rm -f -- "$tmp"
        echo "    (couldn't make $2 No_COW again; it stays a normal file)"
    fi
    touch -m -d "$dir_mtime" -- "$dir" || true
}

# -----------------------------------------------------
# Backup
# -----------------------------------------------------

do_backup() {
    # Compression levels in defragment: kernel 6.15+ and btrfs-progs 6.14+
    local defrag_help
    defrag_help=$(btrfs filesystem defragment --help 2>&1 || true)
    [[ $defrag_help == *--level* ]] \
        || die "this btrfs-progs can't set the compression level in defragment (needs 6.14 or newer)."
    [ "$(printf '%s\n' 6.15 "$(uname -r)" | sort -V | head -n 1)" = 6.15 ] \
        || die "kernel $(uname -r) can't set the compression level in defragment (needs 6.15 or newer)."

    [ ! -e "$backup" ] || [ -d "$backup" ] || die "$backup exists and isn't a folder."
    mkdir -vp "$backup"
    [ -z "$(ls -A "$backup")" ] || die "$backup isn't empty. Move or delete its contents first (what is in subvolumes/ needs: btrfs subvolume delete $backup/subvolumes/*)."
    own -v "$backup"
    local backup_is_btrfs=false
    [ "$(stat -f -c %T "$backup")" = btrfs ] && backup_is_btrfs=true

    local subvolumes
    mapfile -t subvolumes < <(list_subvolumes | grep -Ev "^(${excluded}|${skipped})(/|$)")
    [ ${#subvolumes[@]} -gt 0 ] || die "no subvolumes found in $ssd."

    # A read-only subvolume can't receive the property or be recompressed
    local sv snapshots_stat=""
    for sv in "${subvolumes[@]}"; do
        [ "$(btrfs property get -ts "$ssd/$sv" ro)" = "ro=false" ] \
            || die "$sv is read-only. Make it writable first: btrfs property set -ts '$ssd/$sv' ro false"
    done

    remove_leftovers "$ssd/$ro_name"

    msg "Subvolumes to back up (zstd level $level):"
    printf '    %s\n' "${subvolumes[@]}"
    printf '    (skipped: %s, %s/ and everything below them)\n' "$excluded" "$skipped"
    printf '\nBackup folder: %s (%s)\n' "$backup" "$($backup_is_btrfs && echo 'Btrfs: btrfs receive' || echo 'not Btrfs: stream files')"

    # ---- Optional: delete @snapshots first ----

    if [ -d "$ssd/$excluded" ]; then
        # Its permissions and owner, so the restore can recreate it empty, the same way
        snapshots_stat=$(stat -c '%a %u %g' "$ssd/$excluded")

        # Recompressing rewrites every extent. Snapshots in @snapshots keep the old extents, so
        # while they exist the recompressed data takes extra space instead of replacing the old data.
        printf '\n%s will be recreated from scratch after the reformat. Deleting it now frees the space\n' "$excluded"
        printf 'its snapshots share with the other subvolumes, which recompression would otherwise duplicate.\n'
        if confirm "Delete $excluded and every snapshot inside it now?"; then
            # Children before parents
            list_subvolumes \
                | { grep -E "^${excluded}/" || true; } \
                | LC_ALL=C sort -r \
                | while IFS= read -r child; do btrfs -v subvolume delete "$ssd/$child"; done
            btrfs -v subvolume delete "$ssd/$excluded"
            btrfs -v subvolume sync "$ssd"
        fi
    fi

    btrfs filesystem usage -h "$ssd" | grep -E 'Used:|Free \(estimated\)'
    df -h --output=avail "$backup" | sed "1s/.*/Free in the backup folder:/"
    confirm $'\nStart? Recompressing at level 15 can take hours.' || exit 0
    [ -z "$snapshots_stat" ] || printf '%s\n' "$snapshots_stat" > "$snapshots_meta"

    # ---- 1. Immutable and append-only flags ----

    # Lists the i, a and C flags of every folder and file being backed up: those in the subvolumes
    # and those outside them (except in the skipped @snapshots and Arch/). Then removes i and a.
    printf 'flags\tpath\n' > "$attributes"

    list_flags() {
        find "$@" \( -type d -o -type f \) -print0 \
            | xargs -0 -r lsattr -d -- 2>/dev/null \
            | while IFS= read -r line; do
                  flags=${line%% *}; path=${line#* }
                  kept=${flags//[!iaC]/}
                  if [ -n "$kept" ]; then printf '%s\t%s\n' "$kept" "${path#"$ssd"/}"; fi
              done || true   # lsattr fails on some special files; they can't carry these flags anyway
    }

    msg "Looking for immutable, append-only and No_COW files"
    {
        for sv in "${subvolumes[@]}"; do list_flags "$ssd/$sv" -xdev; done
        list_flags "$ssd" -mindepth 1 -xdev \( -path "$ssd/$excluded" -o -path "$ssd/$skipped" \) -prune -o
    } | awk '!seen[$0]++' >> "$attributes"
    flagged=$(tail -n +2 "$attributes" | awk -F'\t' '$1 ~ /[ia]/' | wc -l)
    echo "    $(($(wc -l < "$attributes") - 1)) found, $flagged of them immutable or append-only (list: $attributes)"

    remount_zstd

    # Puts the flags and the mount option back. Runs at the end, and also if the script stops halfway.
    cleanup_backup() {
        if [ "$flagged" -gt 0 ]; then
            msg "Putting the immutable and append-only flags back on the SSD"
            each_flagged lock_one
        fi
        remount_original
    }
    trap cleanup_backup EXIT

    if [ "$flagged" -gt 0 ]; then each_flagged unlock_one; fi

    # ---- 2. Compression property and recompression ----

    # The compression property only stores the algorithm, not the level (fs/btrfs/props.c): new
    # writes use the level of the compress= mount option. The level is applied to the existing data
    # by defragment, and those extents keep it from then on, including through send --compressed-data.
    for sv in "${subvolumes[@]}"; do
        msg "$sv: compression property on every existing folder and file"
        set_compression_property "$ssd/$sv"

        msg "$sv: recompressing the existing data with zstd:$level"
        # A file that fails (e.g. in use) only stays less compressed, so don't stop the backup for it
        btrfs -v filesystem defragment -r -v -czstd -L "$level" "$ssd/$sv" \
            || echo "    (defragment reported errors for some files; they stay as they were)"
    done
    sync

    if command -v compsize > /dev/null; then
        msg "Compression result"
        for sv in "${subvolumes[@]}"; do printf '%s\n' "$sv"; { compsize -x "$ssd/$sv" 2>&1 || true; } | sed 's/^/    /'; done
    fi

    # ---- 3. Read-only snapshots and send ----

    # btrfs send only accepts read-only subvolumes. The received subvolume takes the snapshot's
    # name, so the name encodes the original path ("/" becomes "%").
    local ro_dir="$ssd/$ro_name"
    mkdir -vp "$ro_dir"
    printf 'name\toriginal path\n' > "$manifest"

    if $backup_is_btrfs; then mkdir -vp "$backup/subvolumes"; else mkdir -vp "$backup/streams"; fi

    local name snap
    for sv in "${subvolumes[@]}"; do
        name=${sv//\//%}
        snap="$ro_dir/$name"
        msg "$sv: sending"
        btrfs -v subvolume snapshot -r "$ssd/$sv" "$snap"
        printf '%s\t%s\n' "$name" "$sv" >> "$manifest"

        if $backup_is_btrfs; then
            btrfs -v send --proto 2 --compressed-data "$snap" | btrfs -v receive "$backup/subvolumes"
        else
            btrfs -v send --proto 2 --compressed-data -f "$backup/streams/$name.btrfs" "$snap"
            # Parses the whole stream and checks each command's CRC32C. The dump lists every
            # operation in the stream (millions of lines), so only its result is shown.
            btrfs -v receive --dump -f "$backup/streams/$name.btrfs" > /dev/null \
                || die "the stream of $sv failed verification: $backup/streams/$name.btrfs"
            echo "    stream OK: $name.btrfs"
            (cd "$backup/streams" && sha256sum "$name.btrfs" | tee -a SHA256SUMS)
        fi

        btrfs -v subvolume delete "$snap"
    done
    rmdir -v "$ro_dir"

    # ---- 4. Files outside the subvolumes ----

    # --one-file-system skips subvolumes (each one has its own device number)
    msg "Files and folders outside the subvolumes"
    tar --one-file-system --acls --xattrs --numeric-owner --zstd \
        --exclude="./$excluded" --exclude="./$skipped" -cvf "$top_level_tar" -C "$ssd" .
    zstd -tv "$top_level_tar" || die "$top_level_tar failed verification."

    # A copy of this script goes with the backup, for the restore
    install -v -m 755 "$(realpath "$0")" "$backup/ssd-backup.sh"
    own -Rv "$manifest" "$attributes" "$top_level_tar" "$backup/ssd-backup.sh"
    [ -f "$snapshots_meta" ] && own -v "$snapshots_meta"
    $backup_is_btrfs || own -Rv "$backup/streams"

    cleanup_backup
    trap - EXIT

    msg "Backup done: $backup"
    du -sh "$backup"   # du has no verbose mode; this is the total size
    echo "To restore after reformatting: sudo $0 restore --source $backup --destination <mount point of the new file system>"
    if $backup_is_btrfs; then
        echo "To delete the backup later: sudo btrfs subvolume delete $backup/subvolumes/* && rm -r $backup"
    fi
}

# -----------------------------------------------------
# Restore
# -----------------------------------------------------

do_restore() {
    [ -d "$backup" ] || die "the backup folder $backup doesn't exist."
    [ -f "$manifest" ] && [ -f "$attributes" ] && [ -f "$top_level_tar" ] \
        || die "no complete backup in $backup (manifest.tsv, attributes.tsv and top-level-files.tar.zst are needed)."

    local format
    if [ -d "$backup/subvolumes" ]; then format=subvolumes
    elif [ -d "$backup/streams" ]; then format=streams
    else die "$backup has neither subvolumes/ nor streams/."
    fi

    # name<TAB>original path, parents before children
    local entries
    mapfile -t entries < <(tail -n +2 "$manifest")
    [ ${#entries[@]} -gt 0 ] || die "manifest.tsv lists no subvolumes."

    # Subvolumes an interrupted restore already finished are listed in the staging folder and
    # skipped. Each one is only moved to its path after it was received completely.
    staging="$ssd/$staging_name"
    local done_list="$staging/restored.list"
    is_restored() { [ -f "$done_list" ] && grep -Fxq -- "$1" "$done_list"; }

    # Nothing else may exist at the original paths yet. An empty folder is accepted: that is where
    # a nested subvolume was when its parent was snapshotted.
    local entry name path
    msg "Subvolumes to restore from $backup to $ssd:"
    for entry in "${entries[@]}"; do
        IFS=$'\t' read -r name path <<< "$entry"
        if is_restored "$name"; then
            printf '    %s (already restored by an earlier run)\n' "$path"
        elif [ -e "$ssd/$path" ] && ! { [ -d "$ssd/$path" ] && [ -z "$(ls -A "$ssd/$path")" ]; }; then
            die "$ssd/$path already exists. The restore only writes to a new file system."
        else
            printf '    %s\n' "$path"
        fi
    done
    printf '    + files outside the subvolumes, flags (attributes.tsv) and an empty %s\n' "$excluded"

    du -sh "$backup" | sed 's/\t.*/ in the backup/'
    df -h --output=avail "$ssd" | sed "1s/.*/Free on the SSD:/"
    confirm $'\nStart the restore?' || exit 0

    if [ "$format" = streams ]; then
        msg "Checking the stream files"
        (cd "$backup/streams" && sha256sum -c SHA256SUMS)
    fi

    remount_zstd

    # Received subvolumes arrive in the staging folder first, read-only, and are then moved to
    # their original path. A subvolume left there by an interrupted run is incomplete.
    trap remount_original EXIT
    remove_leftovers "$staging"
    mkdir -vp "$staging"

    # ---- 1. Subvolumes ----

    local target
    for entry in "${entries[@]}"; do
        IFS=$'\t' read -r name path <<< "$entry"
        target="$ssd/$path"
        if is_restored "$name"; then
            msg "$path: already restored, skipping"
            continue
        fi
        msg "$path: receiving"
        if [ "$format" = subvolumes ]; then
            btrfs -v send --proto 2 --compressed-data "$backup/subvolumes/$name" | btrfs -v receive "$staging"
        else
            btrfs -v receive -f "$backup/streams/$name.btrfs" "$staging"
        fi

        # Writable again (received subvolumes are read-only)
        btrfs -v property set -f "$staging/$name" ro false

        msg "$path: compression property on every folder and file"
        set_compression_property "$staging/$name"

        # Only now to its original path: what is there is always complete
        mkdir -vp "$(dirname "$target")"
        [ -d "$target" ] && rmdir -v "$target"
        mv -v "$staging/$name" "$target"
        printf '%s\n' "$name" >> "$done_list"
    done

    # ---- 2. Files outside the subvolumes ----

    if [ -f "$staging/tar.done" ]; then
        msg "Files and folders outside the subvolumes: already restored, skipping"
    else
        msg "Files and folders outside the subvolumes"
        tar --acls --xattrs --numeric-owner -xvf "$top_level_tar" -C "$ssd"
        touch "$staging/tar.done"
    fi

    # ---- 3. No_COW, immutable and append-only flags ----

    # Last, because an immutable folder can't receive anything else
    if [ "$(tail -n +2 "$attributes" | wc -l)" -gt 0 ]; then
        msg "Putting the No_COW flags back"
        each_flagged nocow_one
        msg "Putting the immutable and append-only flags back"
        each_flagged lock_one
    fi

    # ---- 4. Empty @snapshots ----

    if [ ! -e "$ssd/$excluded" ]; then
        msg "Creating an empty $excluded"
        local perms=1750 uid=0 gid=0   # as on the old SSD (drwxr-x--T root), if the backup didn't record it
        [ -f "$snapshots_meta" ] && read -r perms uid gid < "$snapshots_meta"
        btrfs -v subvolume create "$ssd/$excluded"
        chown -v "$uid:$gid" "$ssd/$excluded"
        chmod -v "$perms" "$ssd/$excluded"
    fi

    rm -v "$done_list" "$staging/tar.done"
    rmdir -v "$staging"
    remount_original
    trap - EXIT

    msg "Restore done: $ssd"
    btrfs subvolume list "$ssd"
}

case "$mode" in
    backup)  do_backup ;;
    restore) do_restore ;;
esac
