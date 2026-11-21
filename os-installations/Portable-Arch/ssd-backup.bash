#!/bin/bash
#
# sudo ./ssd-backup.bash backup|restore <SSD> [backup folder]
#
# Backs up the subvolumes of the portable SSD's Btrfs file system before it
# is reformatted, and restores them onto the new file system afterwards.
# <SSD> is the mount point of its top-level subvolume (subvolid=5), e.g.
# /run/media/$USER/Oazideia. The backup folder must be on Btrfs, outside the
# SSD; by default, ~/Downloads/ssd-backup of the user who ran sudo.
#
# Backup: every subvolume except @snapshots and Arch/ (and anything below
# them), which are recreated from scratch. Each one is first recompressed in
# place with zstd level 15 (Btrfs' maximum), since they are archives, then a
# read-only snapshot of it is sent with --compressed-data (the compressed
# extents are kept) and received in the backup folder. Files outside the
# subvolumes go into top-level-files.tar.zst.
#
# Restore: receives each subvolume back at its original path, extracts the
# files outside the subvolumes, puts the flags back and creates an empty
# @snapshots. Arch/ is not touched. Nothing may exist at the original paths
# yet. An interrupted restore continues after the last finished subvolume.
#
# Flags: immutable (+i) and append-only (+a) files cannot take the
# compression property or be rewritten, so the backup removes those flags
# and puts them back at the end, even if it fails. Neither btrfs send nor
# tar keeps them, nor No_COW (+C), so all three are listed in
# attributes.tsv for the restore. Other chattr flags are not carried over.
#
# Needs btrfs-progs 6.14+ and Linux 6.15+ (compression level in defragment).
## https://btrfs.readthedocs.io/en/latest/Compression.html
## https://btrfs.readthedocs.io/en/latest/btrfs-filesystem.html
## https://btrfs.readthedocs.io/en/latest/btrfs-send.html
## https://btrfs.readthedocs.io/en/latest/btrfs-receive.html

set -euo pipefail
shopt -s inherit_errexit

level=15                    # ZSTD_BTRFS_MAX_LEVEL in fs/btrfs/zstd.c
excluded=@snapshots         # deleted (optional) and recreated empty
skipped=Arch                # empty, recreated from scratch; never touched
ro_name=.ssd-backup-ro      # on the SSD: snapshots being sent
staging_name=.ssd-restore   # on the SSD: subvolumes being received

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}
msg() { printf '\n==> %s\n' "$*"; }

# confirm PROMPT: goes on only on y; anything else, or Ctrl+D, exits.
confirm() {
    local answer
    read -rp "$1 [y/N] " answer || answer=n
    [[ "${answer,,}" == y ]] || exit 0
}

usage="usage: sudo $0 backup|restore <SSD mount point> [backup folder]"
(( $# == 2 || $# == 3 )) || die "${usage}"
mode=$1
[[ "${mode}" == backup || "${mode}" == restore ]] || die "${usage}"
(( EUID == 0 )) || die "run with sudo."
for cmd in setfattr zstd chattr lsattr; do
    command -v "${cmd}" >/dev/null || die "'${cmd}' not found."
done

# The backup's files belong to the user who ran sudo, if there is one.
owner="" group=""
if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != root ]]; then
    owner=${SUDO_USER}
    group="$(id -gn "${owner}")"
fi
own() { [[ -z "${owner}" ]] || chown "$1" "${owner}:${group}" "${@:2}"; }

backup_arg=${3:-}
if [[ -z "${backup_arg}" ]]; then
    [[ -n "${owner}" ]] ||
        die "without sudo from your user, give the backup folder."
    home="$(getent passwd "${owner}" | cut -d: -f6)"
    backup_arg="${home}/Downloads/ssd-backup"
fi

[[ -d "$2" ]] || die "'$2' is not a folder."
ssd="$(realpath -- "$2")"
backup="$(realpath -m -- "${backup_arg}")"
manifest="${backup}/manifest.tsv"
attributes="${backup}/attributes.tsv"
snapshots_meta="${backup}/snapshots.meta"
top_level_tar="${backup}/top-level-files.tar.zst"

# The SSD must be given by the root of the mounted device: a mount point on
# Btrfs showing the top-level subvolume (ID 5) from its root (inode 256).
fs="$(stat -f -c %T "${ssd}")"
[[ "${fs}" == btrfs ]] || die "${ssd} is not on Btrfs."
mountpoint -q "${ssd}" ||
    die "${ssd} is not a mount point; give the folder the SSD is mounted on."
root_id="$(btrfs inspect-internal rootid "${ssd}")"
inode="$(stat -c %i "${ssd}")"
[[ "${root_id}" == 5 && "${inode}" == 256 ]] ||
    die "${ssd} is not the top-level subvolume; mount it with -o subvolid=5."
[[ "${backup}/" != "${ssd}"/* ]] ||
    die "the backup folder (${backup}) cannot be inside the SSD."

# Subvolume paths relative to the top level, parents before children,
# without the script's own work folders.
list_subvolumes() {
    local prefix='^ID [0-9]+ gen [0-9]+ top level [0-9]+ path (<FS_TREE>/)?'
    btrfs subvolume list -a "${ssd}" | sed -E "s|${prefix}||" |
        awk -v a="${ro_name}/" -v b="${staging_name}/" \
            'index($0, a) != 1 && index($0, b) != 1' |
        LC_ALL=C sort
}

# remove_leftovers DIR: deletes the subvolumes an interrupted run left in a
# work folder on the SSD.
remove_leftovers() {
    local item inode
    [[ -d "$1" ]] || return 0
    for item in "$1"/* "$1"/.[!.]*; do
        [[ -d "${item}" ]] || continue
        inode="$(stat -c %i "${item}")"
        [[ "${inode}" != 256 ]] || btrfs -v subvolume delete "${item}"
    done
}

# set_compression_property SUBVOLUME: on every folder and file; -xdev stops
# at nested subvolumes, which are handled on their own.
set_compression_property() {
    find "$1" -xdev \( -type d -o -type f \) -print0 |
        xargs -0 -r -t -n 1000 setfattr -n btrfs.compression -v zstd ||
        echo "    (some files refused the property, e.g. No_COW ones," \
            "which Btrfs never compresses; see the errors above)"
}

# chattr rewrites every flag of a file, the compression one too, and on
# Btrfs that resets the compression property to the algorithm of the
# compress= mount option, or zlib without one (btrfs_fileattr_set in
# fs/btrfs/ioctl.c). So, while the script runs, the SSD is mounted with
# compress=zstd:15, which also applies to anything written meanwhile.
options="$(findmnt -no OPTIONS --target "${ssd}")"
original_compress="$(grep -oE 'compress(-force)?=[^,]+' <<<"${options}")" ||
    original_compress=compress=no
remount_zstd() {
    msg "Remounting ${ssd} with compress=zstd:${level}" \
        "(was: ${original_compress})"
    mount -v -o "remount,compress=zstd:${level}" "${ssd}"
}
remount_original() {
    msg "Remounting ${ssd} with ${original_compress} again"
    mount -v -o "remount,${original_compress}" "${ssd}" || true
}

# each_flagged COMMAND...: runs "COMMAND... FLAGS PATH" for every line of
# attributes.tsv (paths relative to the SSD's top level). The lines are
# split by hand: read would drop spaces and tabs at the end of a name.
each_flagged() {
    local line
    tail -n +2 "${attributes}" | while IFS= read -r line; do
        "$@" "${line%%$'\t'*}" "${line#*$'\t'}"
    done
}

# Immutable and append-only: removed by the backup, put back by both modes.
# No_COW is never removed, so these ignore it.
unlock_one() {
    [[ -z "${1//C/}" ]] || chattr -V -i -a -- "${ssd}/$2" ||
        echo "    (could not remove the flags of $2; it stays as it is)"
}
lock_one() {
    [[ -z "${1//C/}" ]] || chattr -V "+${1//C/}" -- "${ssd}/$2" || true
}

# nocow_one FLAGS PATH: No_COW again, for the restore. A folder or an empty
# file just takes the flag; a file with data cannot, so it is copied into a
# new No_COW file that replaces it. Compression and No_COW exclude each
# other, so the compression property goes first.
nocow_one() {
    local target="${ssd}/$2" current dir mtime tmp
    [[ "$1" == *C* ]] || return 0
    current="$(lsattr -d -- "${target}" 2>/dev/null)" || current=""
    [[ "${current%% *}" != *C* ]] || return 0
    setfattr -x btrfs.compression -- "${target}" 2>/dev/null || true
    if [[ -d "${target}" || ! -s "${target}" ]]; then
        chattr -V +C -- "${target}" || echo "    (could not set No_COW on $2)"
        return 0
    fi
    dir="$(dirname -- "${target}")"
    mtime="$(stat -c %y "${dir}")"
    tmp="$(mktemp -p "${dir}" .nocow.XXXXXX)"
    # The new file inherits the folder's compression property: drop it.
    setfattr -x btrfs.compression -- "${tmp}" 2>/dev/null || true
    if chattr +C -- "${tmp}" &&
        cp -v -a --reflink=never --sparse=always -- "${target}" "${tmp}" &&
        mv -v -f -- "${tmp}" "${target}"; then
        touch -m -d "${mtime}" -- "${dir}"
    else
        rm -f -- "${tmp}"
        echo "    (could not make $2 No_COW again; it stays a normal file)"
    fi
}

do_backup() {
    local subvolumes sv list found fs ro answer free self snapshots_stat=""
    [[ ! -e "${backup}" || -d "${backup}" ]] ||
        die "${backup} exists and is not a folder."
    mkdir -vp "${backup}"
    found="$(find "${backup}" -mindepth 1 -print -quit)"
    [[ -z "${found}" ]] || die "${backup} is not empty; empty it first."
    fs="$(stat -f -c %T "${backup}")"
    [[ "${fs}" == btrfs ]] || die "the backup folder must be on Btrfs."
    own -v "${backup}"

    list="$(list_subvolumes)"
    list="$(grep -Ev "^(${excluded}|${skipped})(/|$)" <<<"${list}")" ||
        die "no subvolumes found in ${ssd}."
    mapfile -t subvolumes <<<"${list}"

    # A read-only subvolume cannot take the property or be recompressed.
    for sv in "${subvolumes[@]}"; do
        ro="$(btrfs property get -ts "${ssd}/${sv}" ro)"
        [[ "${ro}" == ro=false ]] ||
            die "${sv} is read-only; make it writable first:" \
                "btrfs property set -ts '${ssd}/${sv}' ro false"
    done
    remove_leftovers "${ssd}/${ro_name}"

    msg "Subvolumes to back up to ${backup} (zstd level ${level}):"
    printf '    %s\n' "${subvolumes[@]}"
    echo "    (skipped: ${excluded}, ${skipped}/ and everything below them)"

    if [[ -d "${ssd}/${excluded}" ]]; then
        # Kept so the restore recreates it with the same mode and owner.
        snapshots_stat="$(stat -c '%a %u %g' "${ssd}/${excluded}")"
        # Recompression rewrites every extent; snapshots keep the old ones,
        # so while they exist the new data takes extra space.
        echo
        echo "${excluded} is recreated from scratch after the reformat." \
            "Deleting it now frees"
        echo "the space its snapshots share with the other subvolumes."
        read -rp "Delete ${excluded} and its snapshots now? [y/N] " answer ||
            answer=n
        if [[ "${answer,,}" == y ]]; then
            list="$(list_subvolumes)"
            list="$(grep -E "^${excluded}/" <<<"${list}" | LC_ALL=C sort -r)" ||
                list=""
            while IFS= read -r sv; do
                [[ -z "${sv}" ]] || btrfs -v subvolume delete "${ssd}/${sv}"
            done <<<"${list}"
            btrfs -v subvolume delete "${ssd}/${excluded}"
            btrfs -v subvolume sync "${ssd}"
        fi
    fi

    btrfs filesystem usage -h "${ssd}" | grep -E 'Used:|Free \(estimated\)'
    free="$(df -h --output=avail "${backup}" | tail -n 1)"
    echo "Free in the backup folder: ${free}"
    echo
    confirm "Start? Recompressing at level ${level} can take hours."
    [[ -z "${snapshots_stat}" ]] ||
        printf '%s\n' "${snapshots_stat}" >"${snapshots_meta}"

    # ---- 1. Flags (inside the subvolumes and outside them) ----
    list_flags() {
        local line flags kept
        find "$@" \( -type d -o -type f \) -print0 |
            xargs -0 -r lsattr -d -- 2>/dev/null |
            while IFS= read -r line; do
                flags=${line%% *}
                kept=${flags//[!iaC]/}
                [[ -z "${kept}" ]] ||
                    printf '%s\t%s\n' "${kept}" "${line#* "${ssd}"/}"
            done || true   # lsattr fails on special files, which have none
    }
    msg "Looking for immutable, append-only and No_COW files"
    printf 'flags\tpath\n' >"${attributes}"
    {
        for sv in "${subvolumes[@]}"; do list_flags "${ssd}/${sv}" -xdev; done
        list_flags "${ssd}" -mindepth 1 -xdev \( -path "${ssd}/${excluded}" \
            -o -path "${ssd}/${skipped}" \) -prune -o
    } | awk '!seen[$0]++' >>"${attributes}"
    flagged="$(tail -n +2 "${attributes}" | awk -F'\t' '$1 ~ /[ia]/' |
        wc -l)"
    total="$(tail -n +2 "${attributes}" | wc -l)"
    echo "    ${total} found, ${flagged} immutable or append-only" \
        "(${attributes})"

    remount_zstd
    # Puts the flags and the mount option back, also if the script stops.
    cleanup_backup() {
        if (( flagged > 0 )); then
            msg "Putting the immutable and append-only flags back"
            each_flagged lock_one
        fi
        remount_original
    }
    trap cleanup_backup EXIT
    (( flagged == 0 )) || each_flagged unlock_one

    # ---- 2. Compression property and recompression ----
    # The property only stores the algorithm (fs/btrfs/props.c); defragment
    # applies the level to the existing data, and those extents keep it,
    # through send --compressed-data too.
    for sv in "${subvolumes[@]}"; do
        msg "${sv}: compression property on every folder and file"
        set_compression_property "${ssd}/${sv}"
        msg "${sv}: recompressing with zstd:${level}"
        # A file that fails (e.g. in use) only stays less compressed.
        btrfs -v filesystem defragment -r -v -czstd -L "${level}" \
            "${ssd}/${sv}" ||
            echo "    (defragment failed on some files; they stay as they were)"
    done
    sync
    if command -v compsize >/dev/null; then
        msg "Compression result"
        for sv in "${subvolumes[@]}"; do
            echo "${sv}"
            compsize -x "${ssd}/${sv}" 2>&1 | sed 's/^/    /' || true
        done
    fi

    # ---- 3. Read-only snapshots, sent to the backup folder ----
    # btrfs send needs read-only subvolumes. The received subvolume takes
    # the snapshot's name, which encodes the original path ("/" -> "%").
    local ro_dir="${ssd}/${ro_name}" name
    mkdir -vp "${ro_dir}" "${backup}/subvolumes"
    printf 'name\toriginal path\n' >"${manifest}"
    for sv in "${subvolumes[@]}"; do
        name=${sv//\//%}
        msg "${sv}: sending"
        btrfs -v subvolume snapshot -r "${ssd}/${sv}" "${ro_dir}/${name}"
        printf '%s\t%s\n' "${name}" "${sv}" >>"${manifest}"
        btrfs -v send --proto 2 --compressed-data "${ro_dir}/${name}" |
            btrfs -v receive "${backup}/subvolumes"
        btrfs -v subvolume delete "${ro_dir}/${name}"
    done
    rmdir -v "${ro_dir}"

    # ---- 4. Files outside the subvolumes ----
    # --one-file-system skips subvolumes (each has its own device number).
    msg "Files and folders outside the subvolumes"
    tar --one-file-system --acls --xattrs --numeric-owner --zstd \
        --exclude="./${excluded}" --exclude="./${skipped}" \
        -cvf "${top_level_tar}" -C "${ssd}" .
    zstd -tv "${top_level_tar}"

    # A copy of this script goes with the backup, for the restore.
    self="$(realpath -- "$0")"
    install -v -m 755 "${self}" "${backup}/ssd-backup.bash"
    own -v "${manifest}" "${attributes}" "${top_level_tar}" \
        "${backup}/ssd-backup.bash"
    [[ ! -f "${snapshots_meta}" ]] || own -v "${snapshots_meta}"

    cleanup_backup
    trap - EXIT
    msg "Backup done: ${backup}"
    du -sh "${backup}"
    echo "To restore after reformatting:" \
        "sudo $0 restore <mount point of the new file system> ${backup}"
    echo "To delete the backup later:" \
        "sudo btrfs subvolume delete ${backup}/subvolumes/* && rm -r ${backup}"
}

do_restore() {
    local list entries entry name path target found size free
    local staging="${ssd}/${staging_name}"
    local done_list="${staging}/restored.list"
    [[ -f "${manifest}" && -f "${attributes}" && -f "${top_level_tar}" &&
        -d "${backup}/subvolumes" ]] ||
        die "no complete backup in ${backup}."
    list="$(tail -n +2 "${manifest}")"
    [[ -n "${list}" ]] || die "manifest.tsv lists no subvolumes."
    mapfile -t entries <<<"${list}"

    # Subvolumes an interrupted restore finished are in done_list; each one
    # is moved to its path only after it was received completely.
    touch -a "${done_list}" 2>/dev/null || true
    msg "Subvolumes to restore from ${backup} to ${ssd}:"
    for entry in "${entries[@]}"; do
        IFS=$'\t' read -r name path <<<"${entry}"
        if grep -Fxq -- "${name}" "${done_list}" 2>/dev/null; then
            echo "    ${path} (already restored by an earlier run)"
            continue
        fi
        # An empty folder is accepted: a nested subvolume's place in the
        # snapshot of its parent.
        found=""
        [[ ! -e "${ssd}/${path}" ]] ||
            found="$(find "${ssd}/${path}" -maxdepth 0 ! -empty)"
        [[ -z "${found}" ]] ||
            die "${ssd}/${path} already exists; restore only to a new file" \
                "system."
        echo "    ${path}"
    done
    echo "    + files outside the subvolumes, flags and an empty ${excluded}"
    size="$(du -sh "${backup}" | cut -f 1)"
    free="$(df -h --output=avail "${ssd}" | tail -n 1)"
    echo "Backup: ${size}; free on the SSD: ${free}"
    echo
    confirm "Start the restore?"

    remount_zstd
    trap remount_original EXIT
    # A subvolume left in staging by an interrupted run is incomplete.
    remove_leftovers "${staging}"
    mkdir -vp "${staging}"

    # ---- 1. Subvolumes ----
    for entry in "${entries[@]}"; do
        IFS=$'\t' read -r name path <<<"${entry}"
        target="${ssd}/${path}"
        if grep -Fxq -- "${name}" "${done_list}" 2>/dev/null; then
            msg "${path}: already restored, skipping"
            continue
        fi
        msg "${path}: receiving"
        btrfs -v send --proto 2 --compressed-data \
            "${backup}/subvolumes/${name}" | btrfs -v receive "${staging}"
        btrfs -v property set -f "${staging}/${name}" ro false
        msg "${path}: compression property on every folder and file"
        set_compression_property "${staging}/${name}"
        # Only now to its path, so what is there is always complete.
        mkdir -vp "$(dirname -- "${target}")"
        [[ ! -d "${target}" ]] || rmdir -v -- "${target}"
        mv -v -- "${staging}/${name}" "${target}"
        printf '%s\n' "${name}" >>"${done_list}"
    done

    # ---- 2. Files outside the subvolumes ----
    if [[ -f "${staging}/tar.done" ]]; then
        msg "Files outside the subvolumes: already restored, skipping"
    else
        msg "Files and folders outside the subvolumes"
        tar --acls --xattrs --numeric-owner -xvf "${top_level_tar}" \
            -C "${ssd}"
        touch "${staging}/tar.done"
    fi

    # ---- 3. Flags: last, since an immutable folder takes nothing else ----
    msg "Putting the No_COW, immutable and append-only flags back"
    each_flagged nocow_one
    each_flagged lock_one

    # ---- 4. Empty @snapshots ----
    if [[ ! -e "${ssd}/${excluded}" ]]; then
        msg "Creating an empty ${excluded}"
        # As on the old SSD (drwxr-x--T root) if the backup has no record.
        local perms=1750 uid=0 gid=0
        [[ ! -f "${snapshots_meta}" ]] ||
            read -r perms uid gid <"${snapshots_meta}"
        btrfs -v subvolume create "${ssd}/${excluded}"
        chown -v "${uid}:${gid}" "${ssd}/${excluded}"
        chmod -v "${perms}" "${ssd}/${excluded}"
    fi

    rm -v "${done_list}" "${staging}/tar.done"
    rmdir -v "${staging}"
    remount_original
    trap - EXIT
    msg "Restore done: ${ssd}"
    btrfs subvolume list "${ssd}"
}

"do_${mode}"
