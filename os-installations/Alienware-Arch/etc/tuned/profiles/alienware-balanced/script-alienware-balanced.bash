#!/bin/env bash
#
# alienware-balanced: profile script.
# The shared code, and why it works this way, is in alienware-common/power-policy.bash.
#
. /usr/lib/tuned/functions
. "$(dirname "$(readlink -f "$0")")/../alienware-common/power-policy.bash"

start() {
    # Platform profile, then PL1, PL2 and PL4 in W, and the PL1 time window (Tau) in s.
    # Applied in the background, after the firmware delay.
    schedule_power_policy balanced 55 86 160 64
    return 0
}

stop() {
    restore_firmware_policy
    return 0
}

process "$@"
