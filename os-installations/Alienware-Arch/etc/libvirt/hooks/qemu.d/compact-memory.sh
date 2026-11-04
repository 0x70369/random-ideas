#!/bin/env sh

# libvirt hook: compact the memory before a VM backed by hugepages starts, so the kernel can find
# enough contiguous 2 MiB blocks even when the host has been running for a long time.
## https://libvirt.org/hooks.html
## https://docs.kernel.org/admin-guide/sysctl/vm.html#compact-memory

OBJECT="$1"
OPERATION="$2"
SUBOPERATION="$3"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
DOMAIN_XML=$(cat)

# Only act right before the VM's resources are allocated
case "$OPERATION/$SUBOPERATION" in
    prepare/begin) ;;
    *) exit 0 ;;
esac

# Only act on VMs that use hugepages
case "$DOMAIN_XML" in
    *"<hugepages"*) ;;
    *) exit 0 ;;
esac

# A failure here must not block the VM from starting: a non-zero exit in "prepare" aborts the start
echo 1 > /proc/sys/vm/compact_memory

# The exit status checked here is the one of the echo above (i.e. of the write), on purpose
# shellcheck disable=SC2320
case $? in
    0) logger -t libvirt-hook "Compacted memory before starting $OBJECT" ;;
    *) logger -t libvirt-hook "Failed to compact memory before starting $OBJECT" ;;
esac

exit 0
