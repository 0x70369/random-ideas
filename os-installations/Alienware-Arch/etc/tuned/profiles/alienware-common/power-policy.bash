#!/bin/env bash
#
# Shared code of the alienware-* profiles: Dell platform profile, package power limits (RAPL) and
# Wi-Fi power saving. Sourced by each profile's script, and also run by itself as a transient
# systemd unit (alienware-power-policy.service) that applies the platform profile and the limits.
#
# Thermal/fan policy: platform_profile, identical to selecting a profile in AWCC on Windows.
## cat /sys/firmware/acpi/platform_profile_choices
# https://docs.kernel.org/userspace-api/sysfs-platform_profile.html
#
# The Alienware firmware applies platform_profile asynchronously. A 16 s delay is required before
# the RAPL writes; without it the firmware can overwrite the MMIO PL1/PL2. That wait runs in the
# transient unit, so TuneD isn't blocked for 16 s on every profile switch (and at boot).
#
# Fast profile switches: every run gets a unit with a unique name (alienware-power-policy-<id>),
# because reusing one name can fail right after stopping it ("Unit ... was already loaded"),
# while systemd hasn't unloaded the stopped unit yet. A switch stops every pending run, and also
# records the id of the run it starts; a run checks that id before each step and exits as soon
# as a newer switch replaced it, so even a run that survived the stop never writes stale values.
# Being stopped between two writes is harmless: each single write keeps PL1 <= PL2 <= PL4.
#
# Package power limits, written to both the MMIO and the MSR interfaces:
#   constraint_0  long_term  (PL1) -- the sustained limit, what thermals settle at; its time window
#                                     (Tau) is how long the average may exceed it;
#   constraint_1  short_term (PL2) -- burst, held for the constraint_1 time window;
#   constraint_2  peak_power (PL4) -- instantaneous clamp, no time window. It bounds current spikes
#                                     rather than average draw.
# The invariant PL1 <= PL2 <= PL4 must hold after every single write. So the limits that go up are
# written from the top down (PL4, PL2, PL1), and then the ones that go down from the bottom up
# (PL1, PL2, PL4). This works for any switch, raising, lowering or mixed.
#
# The EC on Alienware hardware can rewrite RAPL (a platform_profile change is one trigger), and if
# the BIOS set the PKG_POWER_LIMIT lock bit the writes fail. So the values are read back 10, 20
# and 30 s after being written; every time the effective limits (the lower of MMIO and MSR, which
# is what the CPU applies) changed, they are written again. Everything is logged to the journal of
# the transient unit.
## journalctl -t alienware-power-policy
## grep . /sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw
## grep . /sys/class/powercap/intel-rapl-mmio:0/constraint_*_power_limit_uw
# https://docs.kernel.org/power/powercap/powercap.html
#
# Wi-Fi power saving (802.11 power save) has no sysfs path, so it is set with iw. The state found
# before the change is saved and restored afterwards, instead of forcing power saving off.
## iw dev wlp0s20f3 get power_save
# https://wiki.archlinux.org/title/Power_management#Network_interfaces
#
# NVIDIA dGPU (used by alienware-battery). Normally it powers off by itself when idle (RTD3,
# NVreg_DynamicPowerManagement=0x02), so some time after the profile starts this code checks
# whether it did. If it didn't, it logs what keeps it awake and, when it is safe, removes it from
# the PCI bus: the kernel then cuts its power, like supergfxctl's "Integrated" mode. Leaving the
# profile brings it back (PCI rescan) and restarts nvidia-persistenced and nvidia-undervolt,
# since the driver starts the GPU from scratch and the clock settings are lost.
# The removal is refused (and the reason logged) when:
#   - the dGPU isn't bound to the nvidia driver (e.g. vfio-pci, passed through to a VM);
#   - a display is connected to one of its outputs;
#   - a process other than nvidia-persistenced has /dev/nvidia* or its render node open
#     (games, CUDA, a browser or a compositor rendering on it).
# Processes that only hold its card node (/dev/dri/cardN) don't block the removal: compositors
# keep every GPU's card node open to watch for displays, and handle the GPU going away. They are
# logged, since a compositor reacting badly to the removal would be the first suspect.
## cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status
## journalctl -t alienware-dgpu
# https://download.nvidia.com/XFree86/Linux-x86_64/latest/README/dynamicpowermanagement.html
# https://docs.kernel.org/PCI/sysfs-pci.html

PLATFORM_PROFILE=/sys/firmware/acpi/platform_profile
RAPL_DOMAINS="/sys/class/powercap/intel-rapl-mmio:0 /sys/class/powercap/intel-rapl:0"
UNIT=alienware-power-policy        # unit name prefix and journal identifier
FIRMWARE_DELAY=16    # seconds between the platform_profile change and the RAPL writes
VERIFY_TIMES="10 20 30"    # seconds after the RAPL writes when they are read back
WIFI_STATE_DIR=/run/tuned/alienware-wifi
DGPU=0000:01:00.0          # the dGPU's PCI address (lspci -D)
DGPU_FUNCTIONS="0000:01:00.1 $DGPU"    # all its functions; the HDMI audio first
DGPU_UNIT=alienware-dgpu
RUN_DIR=/run/tuned/alienware       # ids of the latest runs
DGPU_DELAY=30              # seconds to wait for RTD3 before checking
DGPU_STATE=/run/tuned/alienware-dgpu-removed
PCI_DEVICES=/sys/bus/pci/devices
PCI_RESCAN=/sys/bus/pci/rescan
SELF=$(readlink -f "${BASH_SOURCE[0]}")

# ------------------------------------------------------------------------------------------------
# Called from the profile scripts (inside TuneD)
# ------------------------------------------------------------------------------------------------

# Start a transient unit named PREFIX-<id> running this file with ACTION, and record the id as the
# latest one for PREFIX. usage: start_run PREFIX DESCRIPTION ACTION [ARGS...]
start_run() {
    prefix=$1 description=$2 action=$3
    shift 3
    id=$(date +%s%N)
    mkdir -p "$RUN_DIR"
    echo "$id" > "$RUN_DIR/$prefix"
    systemd-run --quiet --collect --unit="$prefix-$id" --description="$description" \
        --property=SyslogIdentifier="$prefix" \
        /usr/bin/bash "$SELF" "$action" "$id" "$@"
}

# Stop every pending run of PREFIX and invalidate the recorded id
stop_runs() {
    echo none > "$RUN_DIR/$1" 2>/dev/null
    systemctl stop "$1-*.service" 2>/dev/null
    systemctl reset-failed "$1-*.service" 2>/dev/null
    return 0
}

# usage: schedule_power_policy PLATFORM_PROFILE PL1_W PL2_W PL4_W PL1_TAU_S
schedule_power_policy() {
    cancel_power_policy
    start_run "$UNIT" "Alienware platform profile and package power limits" apply "$@"
}

# Stop a pending application (e.g. the previous profile's, still waiting for the firmware)
cancel_power_policy() {
    stop_runs "$UNIT"
}

# Hand the thermal policy back to the firmware's balanced mode, for when TuneD stops or switches
# to a profile that is not an alienware-* one
restore_firmware_policy() {
    cancel_power_policy
    echo balanced > "$PLATFORM_PROFILE" 2>/dev/null
    return 0
}

# Check the dGPU in the background, DGPU_DELAY seconds from now (see the header)
schedule_dgpu_off() {
    cancel_dgpu_off
    start_run "$DGPU_UNIT" "Alienware dGPU power check" dgpu-off
}

cancel_dgpu_off() {
    stop_runs "$DGPU_UNIT"
}

# Bring the dGPU back if dgpu_off removed it
dgpu_restore() {
    cancel_dgpu_off
    [ -e "$DGPU_STATE" ] || return 0
    echo 1 > "$PCI_RESCAN"
    # Services that were in use before the removal, saved in the state file. Restart, not start:
    # nvidia-undervolt is a oneshot that may still count as active from its first run.
    while read -r service; do
        [ -n "$service" ] && systemctl restart --no-block "$service"
    done < "$DGPU_STATE"
    rm -f "$DGPU_STATE"
    return 0
}

wifi_powersave_on() {
    mkdir -p "$WIFI_STATE_DIR"
    for wireless in /sys/class/net/*/wireless; do
        [ -e "$wireless" ] || continue
        iface=${wireless%/wireless}
        iface=${iface##*/}
        state=$(iw dev "$iface" get power_save 2>/dev/null | awk '{ print $NF }')
        # Keep the state saved by an earlier call, so it is the one from before this profile
        if [ -n "$state" ] && [ ! -e "$WIFI_STATE_DIR/$iface" ]; then
            echo "$state" > "$WIFI_STATE_DIR/$iface"
        fi
        iw dev "$iface" set power_save on 2>/dev/null
    done
    return 0
}

wifi_powersave_restore() {
    for file in "$WIFI_STATE_DIR"/*; do
        [ -e "$file" ] || continue
        iw dev "${file##*/}" set power_save "$(cat "$file")" 2>/dev/null
        rm -f "$file"
    done
    return 0
}

# ------------------------------------------------------------------------------------------------
# Run by the transient unit. Output goes to its journal; a "<N>" prefix sets the log level
# (3 error, 4 warning, 6 info).
# ------------------------------------------------------------------------------------------------

# True while this run (id in $run_id) is still the latest one for its prefix
still_current() {
    [ "$(cat "$RUN_DIR/$run_prefix" 2>/dev/null)" = "$run_id" ]
}

# Exit quietly if a newer profile switch replaced this run
exit_if_replaced() {
    if ! still_current; then
        echo "<6>Replaced by a newer profile switch; stopping"
        exit 0
    fi
}

write_value() {
    if ! echo "$2" > "$1" 2>/dev/null; then
        echo "<3>Could not write $2 to $1 (locked by the firmware?)"
    fi
}

# Write PL1/PL2/PL4 (in µW, indexed like the constraints) and the PL1 time window to one domain
write_limits() {
    domain=$1
    if [ ! -d "$domain" ]; then
        echo "<4>$domain not found, skipped"
        return
    fi
    # Raise from the top down, then lower from the bottom up
    for i in 2 1 0; do
        file="$domain/constraint_${i}_power_limit_uw"
        [ -e "$file" ] && [ "${limits[i]}" -gt "$(cat "$file")" ] && write_value "$file" "${limits[i]}"
    done
    for i in 0 1 2; do
        file="$domain/constraint_${i}_power_limit_uw"
        [ -e "$file" ] && [ "${limits[i]}" -lt "$(cat "$file")" ] && write_value "$file" "${limits[i]}"
    done
    write_value "$domain/constraint_0_time_window_us" "$tau"
}

# True if the effective limits are the requested ones. The CPU applies the lower of the MMIO and
# MSR values, so one interface being set higher by someone else (on this laptop, the MMIO PL1
# goes back to 50 W in the "quiet" platform profile) doesn't matter while the other holds the
# requested value; that is only logged, once per run. A limit that ended up lower than requested
# does matter, and makes this return false.
limits_hold() {
    ok=0
    for i in 0 1 2; do
        effective=""
        for domain in $RAPL_DOMAINS; do
            file="$domain/constraint_${i}_power_limit_uw"
            [ -e "$file" ] || continue
            current=$(cat "$file")
            if [ -z "$effective" ] || [ "$current" -lt "$effective" ]; then
                effective=$current
            fi
            if [ "$current" != "${limits[i]}" ]; then
                case " $noted " in
                    *" $file=$current "*) ;;
                    *)
                        echo "<6>$file is $current, expected ${limits[i]}"
                        noted="$noted $file=$current"
                        ;;
                esac
            fi
        done
        [ -n "$effective" ] || continue
        if [ "$effective" != "${limits[i]}" ]; then
            echo "<4>The effective constraint_$i limit is $effective, expected ${limits[i]}"
            ok=1
        fi
    done
    return "$ok"
}

apply_policy() {
    profile=$1
    limits=( $(( $2 * 1000000 )) $(( $3 * 1000000 )) $(( $4 * 1000000 )) )
    tau=$(( $5 * 1000000 ))

    exit_if_replaced
    write_value "$PLATFORM_PROFILE" "$profile"
    sleep "$FIRMWARE_DELAY"

    exit_if_replaced
    for domain in $RAPL_DOMAINS; do
        write_limits "$domain"
    done

    # Read the limits back at each of VERIFY_TIMES, counted from the first write
    noted=""
    elapsed=0
    rewrites=0
    for at in $VERIFY_TIMES; do
        sleep $(( at - elapsed ))
        elapsed=$at
        exit_if_replaced
        if ! limits_hold; then
            echo "<4>The limits changed ${at} s after being written (EC?); writing them again"
            for domain in $RAPL_DOMAINS; do
                write_limits "$domain"
            done
            rewrites=$(( rewrites + 1 ))
        fi
    done

    if [ "$rewrites" -eq 0 ]; then
        echo "<6>Applied platform profile $profile, PL1 $2 W (Tau $5 s), PL2 $3 W, PL4 $4 W"
    else
        echo "<4>Applied platform profile $profile, PL1 $2 W (Tau $5 s), PL2 $3 W, PL4 $4 W, after rewriting the limits $rewrites time(s)"
    fi
}

# Processes ("PID name") with any of the given paths open, other than nvidia-persistenced.
# find matches the fd links' targets itself (-lname), so no command runs per open file.
dgpu_users() {
    tests=()
    for path in "$@"; do
        tests+=(-o -lname "$path")
    done
    # "${tests[@]:1}" drops the leading -o
    find /proc/[0-9]*/fd -maxdepth 1 -type l \( "${tests[@]:1}" \) -printf '%h\n' 2>/dev/null |
    while read -r fd_dir; do
        pid=${fd_dir#/proc/}
        pid=${pid%%/*}
        name=$(cat "/proc/$pid/comm" 2>/dev/null)
        [ "$name" = nvidia-persistenced ] || echo "$pid $name"
    done | sort -u
}

dgpu_off() {
    dev=$PCI_DEVICES/$DGPU
    if [ ! -e "$dev" ]; then
        echo "<6>The dGPU ($DGPU) is not on the PCI bus; nothing to do"
        return
    fi

    sleep "$DGPU_DELAY"
    exit_if_replaced

    status=$(cat "$dev/power/runtime_status")
    if [ "$status" = suspended ]; then
        echo "<6>The dGPU is powered off by RTD3; nothing to do"
        return
    fi
    echo "<4>The dGPU is still $status after $DGPU_DELAY s"
    for function in $DGPU_FUNCTIONS; do
        [ -e "$PCI_DEVICES/$function" ] || continue
        echo "<6>  $function: runtime_status $(cat "$PCI_DEVICES/$function/power/runtime_status"), control $(cat "$PCI_DEVICES/$function/power/control")"
    done

    driver=$(basename "$(readlink "$dev/driver" 2>/dev/null)")
    if [ "$driver" != nvidia ]; then
        echo "<4>Not removing it: bound to ${driver:-no driver}, not nvidia"
        return
    fi

    # Its DRM nodes (/dev/dri/cardN, /dev/dri/renderDN) and connected outputs
    render_nodes=""
    card_nodes=""
    for node in "$dev"/drm/*; do
        [ -e "$node" ] || continue
        case "${node##*/}" in
            renderD*) render_nodes="$render_nodes /dev/dri/${node##*/}" ;;
            card*) card_nodes="$card_nodes /dev/dri/${node##*/}" ;;
        esac
        for output in "$node"/"${node##*/}"-*; do
            [ -e "$output/status" ] || continue
            if [ "$(cat "$output/status")" = connected ]; then
                echo "<4>Not removing it: a display is connected to ${output##*/}"
                return
            fi
        done
    done

    # shellcheck disable=SC2086  # the node lists are paths without spaces
    users=$(dgpu_users /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm /dev/nvidia[0-9]* $render_nodes)
    if [ -n "$users" ]; then
        echo "<4>Not removing it: in use by these processes (PID name):"
        printf '%s\n' "$users" | sed 's/^/<4>  /'
        return
    fi
    if [ -n "$card_nodes" ]; then
        # shellcheck disable=SC2086
        watchers=$(dgpu_users $card_nodes)
        if [ -n "$watchers" ]; then
            echo "<6>Its card node is open (not blocking) in these processes (PID name):"
            printf '%s\n' "$watchers" | sed 's/^/<6>  /'
        fi
    fi

    # The PCI bridge above it, whose power state shows whether the dGPU is really off afterwards
    bridge=$(basename "$(dirname "$(readlink -f "$dev")")")

    # Last check before changing anything
    exit_if_replaced

    # Remember which services to start again when the dGPU comes back
    : > "$DGPU_STATE"
    for service in nvidia-persistenced.service nvidia-undervolt.service; do
        if systemctl is-active --quiet "$service" || systemctl is-enabled --quiet "$service" 2>/dev/null; then
            echo "$service" >> "$DGPU_STATE"
        fi
    done
    systemctl stop nvidia-persistenced.service 2>/dev/null

    for function in $DGPU_FUNCTIONS; do
        [ -e "$PCI_DEVICES/$function/remove" ] && echo 1 > "$PCI_DEVICES/$function/remove"
    done

    if [ -e "$dev" ]; then
        echo "<3>The dGPU is still on the PCI bus after the removal; starting its services again"
        while read -r service; do
            [ -n "$service" ] && systemctl restart --no-block "$service"
        done < "$DGPU_STATE"
        rm -f "$DGPU_STATE"
        return
    fi
    echo "<6>Removed the dGPU from the PCI bus; it comes back when leaving the profile"
    sleep 5
    if [ -e "$PCI_DEVICES/$bridge/power/runtime_status" ]; then
        echo "<6>PCI bridge $bridge: runtime_status $(cat "$PCI_DEVICES/$bridge/power/runtime_status")"
    fi
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    case "${1:-}" in
        apply)
            [ "$#" -eq 7 ] || { echo "usage: $0 apply ID PLATFORM_PROFILE PL1_W PL2_W PL4_W PL1_TAU_S" >&2; exit 2; }
            run_prefix=$UNIT run_id=$2
            shift 2
            apply_policy "$@"
            ;;
        dgpu-off)
            [ "$#" -eq 2 ] || { echo "usage: $0 dgpu-off ID" >&2; exit 2; }
            run_prefix=$DGPU_UNIT run_id=$2
            dgpu_off
            ;;
        *)
            echo "usage: $0 apply ID PLATFORM_PROFILE PL1_W PL2_W PL4_W PL1_TAU_S | dgpu-off ID" >&2
            exit 2
            ;;
    esac
fi
