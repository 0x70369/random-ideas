#!/bin/env bash
#
# alienware-balanced-battery: profile script.
# The shared code, and why it works this way, is in alienware-common/power-policy.bash.
#
# Also turns on Wi-Fi power saving.
# The limits sit between alienware-balanced (55/86/160 W) and alienware-battery. They are a
# starting point: compare the discharge rate in powertop with the other profiles and adjust.
#
. /usr/lib/tuned/functions
. "$(dirname "$(readlink -f "$0")")/../alienware-common/power-policy.bash"

start() {
    # Platform profile, then PL1, PL2 and PL4 in W, and the PL1 time window (Tau) in s.
    # Applied in the background, after the firmware delay.
    schedule_power_policy balanced 24 36 64 28
    wifi_powersave_on
    return 0
}

stop() {
    wifi_powersave_restore
    restore_firmware_policy
    return 0
}

process "$@"
