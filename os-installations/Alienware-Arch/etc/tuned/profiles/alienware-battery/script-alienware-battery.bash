#!/bin/env bash
#
# alienware-battery: profile script.
# The shared code, and why it works this way, is in alienware-common/power-policy.bash.
#
# Also turns on Wi-Fi power saving and makes sure the dGPU is powered off (removed from the PCI bus
# if RTD3 didn't do it; see the dGPU part of power-policy.bash). USB autosuspend lives in the [usb]
# plugin in tuned.conf.
# The limits are the lowest of the profiles (they were 16/32/86 W, Tau 32 s); with turbo off
# they mostly cap bursts. If the system stutters on light tasks, raise PL1 first.
#
. /usr/lib/tuned/functions
. "$(dirname "$(readlink -f "$0")")/../alienware-common/power-policy.bash"

start() {
    # Platform profile, then PL1, PL2 and PL4 in W, and the PL1 time window (Tau) in s.
    # Applied in the background, after the firmware delay.
    schedule_power_policy quiet 12 24 42 16
    wifi_powersave_on
    schedule_dgpu_off
    return 0
}

stop() {
    dgpu_restore
    wifi_powersave_restore
    restore_firmware_policy
    return 0
}

process "$@"
