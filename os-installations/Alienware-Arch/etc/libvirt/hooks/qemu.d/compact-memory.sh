#!/bin/sh

# libvirt hook: reserve the hugepages of a VM backed by hugepages before it starts, and give them
# back when it stops.
#
# Dynamic hugepages (vm.nr_overcommit_hugepages) are only created when QEMU maps the guest RAM, and
# that fails with "unable to map backing store for guest RAM: Cannot allocate memory" when the host
# does not have enough free, contiguous 2 MiB blocks at that moment. Compacting alone is not enough:
# it only rearranges free memory, while most of the memory is usually in the page cache or in use by
# programs. So, before the VM starts, this hook:
#   1. drops the clean page cache and the dentry/inode caches (no data is lost; later reads just
#      come from the disk again);
#   2. if free memory is still short of the VM's RAM plus a margin, asks the kernel to reclaim the
#      difference from the user session (memory.reclaim of user.slice): idle program memory goes to
#      swap (zswap, so it comes back quickly), at the cost of a short stall when it is used again;
#   3. compacts the memory;
#   4. adds the VM's pages to the persistent pool (vm.nr_hugepages) and checks that all of them were
#      allocated. If not, it gives them back and aborts the start with a clear message.
# vm.compaction_proactiveness (sysctl.d/kvm.conf) also keeps memory compacted in the background.
# When the VM stops, the same number of pages is removed from the pool.
#
# Changes take effect only after restarting libvirtd (or virtqemud): libvirt looks for hook scripts
# when the daemon starts.
## https://libvirt.org/hooks.html
## https://docs.kernel.org/admin-guide/mm/hugetlbpage.html
## https://docs.kernel.org/admin-guide/sysctl/vm.html#compact-memory
## https://docs.kernel.org/admin-guide/cgroup-v2.html#memory-interface-files (memory.reclaim)

OBJECT="$1"
OPERATION="$2"
SUBOPERATION="$3"

POOL=/proc/sys/vm/nr_hugepages
STATE_DIR=/run/libvirt-hugepages
USER_SLICE=/sys/fs/cgroup/user.slice
RECLAIM_MARGIN_KIB=$(( 1024 * 1024 ))    # keep 1 GiB free besides the VM's RAM
STATE="$STATE_DIR/$OBJECT"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
DOMAIN_XML=$(cat)

log() {
    logger -t libvirt-hook "$OBJECT: $*"
}

# Message shown by libvirt (and virt-manager) when the start is aborted.
abort() {
    log "$*"
    printf '%s\n' "$*" >&2
    exit 1
}

pool_size() {
    cat "$POOL"
}

# Guest RAM in KiB, from <memory unit="...">N</memory> (libvirt's default unit is KiB).
guest_kib() {
    line=$(printf '%s\n' "$DOMAIN_XML" | grep -m1 '<memory[ >]') || return 1
    value=$(printf '%s\n' "$line" | sed -n 's/.*>[[:space:]]*\([0-9][0-9]*\)[[:space:]]*<\/memory>.*/\1/p')
    unit=$(printf '%s\n' "$line" | sed -n "s/.*unit=[\"']\([A-Za-z]*\)[\"'].*/\1/p")
    [ -n "$value" ] || return 1
    case "$unit" in
        ''|k|KiB) echo "$value" ;;
        b|bytes) echo $(( value / 1024 )) ;;
        KB) echo $(( value * 1000 / 1024 )) ;;
        M|MiB) echo $(( value * 1024 )) ;;
        MB) echo $(( value * 1000000 / 1024 )) ;;
        G|GiB) echo $(( value * 1024 * 1024 )) ;;
        GB) echo $(( value * 1000000000 / 1024 )) ;;
        *) return 1 ;;
    esac
}

case "$OPERATION/$SUBOPERATION" in
    prepare/begin|release/end) ;;
    *) exit 0 ;;
esac

# Only act on VMs that use hugepages
case "$DOMAIN_XML" in
    *"<hugepages"*) ;;
    *) exit 0 ;;
esac

# Hook runs for different VMs may overlap: serialize the changes to the pool
mkdir -vp "$STATE_DIR"
exec 9> "$STATE_DIR/.lock"
flock 9

if [ "$OPERATION" = release ]; then
    [ -f "$STATE" ] || exit 0
    added=$(cat "$STATE")
    rm -vf "$STATE"
    target=$(( $(pool_size) - added ))
    [ "$target" -ge 0 ] || target=0
    echo "$target" > "$POOL" || log 'Could not shrink the hugepage pool'
    log "Released $added hugepages (pool: $(pool_size))"
    exit 0
fi

# prepare/begin. A VM that is already being prepared (e.g. a retried start) keeps its pages.
[ -f "$STATE" ] && exit 0

page_kib=$(awk '/^Hugepagesize:/ { print $2 }' /proc/meminfo)
if ! kib=$(guest_kib) || [ -z "$page_kib" ]; then
    # Unknown memory layout: fall back to compacting only and let QEMU try
    echo 1 > /proc/sys/vm/compact_memory
    log 'Could not read the guest RAM size; only compacted the memory'
    exit 0
fi
needed=$(( (kib + page_kib - 1) / page_kib ))

sync
echo 3 > /proc/sys/vm/drop_caches

# Reclaim from the user session whatever free memory still lacks for the VM plus a margin. The
# kernel may reclaim less than asked (the write then fails); the pool check below has the last word.
free_kib=$(awk '/^MemFree:/ { print $2 }' /proc/meminfo)
deficit_kib=$(( needed * page_kib + RECLAIM_MARGIN_KIB - free_kib ))
if [ "$deficit_kib" -gt 0 ] && [ -w "$USER_SLICE/memory.reclaim" ]; then
    echo "$(( deficit_kib * 1024 ))" > "$USER_SLICE/memory.reclaim" 2>/dev/null ||
        log "Reclaimed less than the $(( deficit_kib / 1024 )) MiB asked from the user session"
fi

echo 1 > /proc/sys/vm/compact_memory

before=$(pool_size)
echo $(( before + needed )) > "$POOL"
added=$(( $(pool_size) - before ))

if [ "$added" -lt "$needed" ]; then
    echo "$before" > "$POOL"
    abort "Not enough contiguous memory for the hugepages: got $added of $needed pages of $page_kib KiB. Close some programs and try again."
fi

echo "$added" > "$STATE"
log "Reserved $added hugepages (pool: $(pool_size))"
exit 0
