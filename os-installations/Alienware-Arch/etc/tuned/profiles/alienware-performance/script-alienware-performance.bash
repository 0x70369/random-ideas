#!/bin/env bash
#
# alienware-performance: profile script.
# The shared code, and why it works this way, is in alienware-common/power-policy.bash.
#
# Platform profile "performance" == AWCC Overdrive: fans pinned at max. 
# Not worth the ears, so this profile uses "balanced-performance".
#
. /usr/lib/tuned/functions
. "$(dirname "$(readlink -f "$0")")/../alienware-common/power-policy.bash"

start() {
    # Platform profile, then PL1, PL2 and PL4 in W, and the PL1 time window (Tau) in s.
    # Applied in the background, after the firmware delay.
    schedule_power_policy balanced-performance 157 157 330 0
    return 0
}

stop() {
    restore_firmware_policy
    return 0
}

process "$@"
