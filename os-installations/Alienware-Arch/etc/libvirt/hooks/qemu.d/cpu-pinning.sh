#!/bin/env sh

# libvirt hook: keep the host off the CPUs reserved for the VMs below while they run.
## https://libvirt.org/hooks.html
## https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Dynamically_isolating_CPUs

OBJECT="$1"
OPERATION="$2"

# libvirt passes the domain XML on stdin. Read all of it, so libvirt never writes to a closed pipe.
cat > /dev/null

# CPUs left to the host while the VM runs:
# 8-15 (P-cores 4-7) go to the vCPUs, 16-19 (one E-core cluster) to the emulator and the iothread
host_cpus_vm_running="0-7,20-31"
host_cpus_all="0-31"

set_host_cpus() {
    for unit in system.slice user.slice init.scope; do
        systemctl set-property --runtime -- "$unit" AllowedCPUs="$1"
    done
}

case "$OBJECT" in
    "Bosta11-bare-metal"|"Bosta10")
        case "$OPERATION" in
            prepare) set_host_cpus "$host_cpus_vm_running" ;;
            release) set_host_cpus "$host_cpus_all" ;;
            *) exit 0 ;;
        esac
        ;;

    *) exit 0 ;;
esac
