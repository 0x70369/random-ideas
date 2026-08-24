#!/bin/env bash
#
# alienware-performance: profile script.
#
# Thermal/fan policy. Identical to selecting a profile in AWCC on windows
# "performance" == AWCC Overdrive: fans pinned at max. Not worth the ears.
# https://docs.kernel.org/userspace-api/sysfs-platform_profile.html
## cat /sys/firmware/acpi/platform_profile_choices
#
# The Alienware firmware applies platform_profile asynchronously. A 200 ms delay
# is required before RAPL writes; without it the firmware can overwrite MMIO PL1/PL2.
#
# Package power cap.
# All values in microwatts (µW). 
#
#   constraint_0  long_term  (PL1) -- the sustained limit, what thermals settle at;
#   constraint_1  short_term (PL2) -- burst, held for the constraint_1 time window;
#   constraint_2  peak_power (PL4) -- instantaneous clamp, no time window. It bounds
#                                     current spikes rather than average draw.
#
# Written highest to lowest so that raising the caps on a profile switch never leaves
# an already-raised PL1 sitting above a not-yet-raised PL4 -- the invariant is
# PL1 <= PL2 <= PL4. MMIO is written first for completeness; MSR is written last.
#
# Read the values back after a few minutes: the EC on Alienware hardware can rewrite
# RAPL (a platform_profile change is one trigger, and this script makes one), and if
# the BIOS set the PKG_POWER_LIMIT lock bit the write fails outright and only shows
# up in the tuned log.
## grep . /sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw
## grep . /sys/class/powercap/intel-rapl-mmio:0/constraint_*_power_limit_uw
## journalctl -u tuned -n 30
# https://docs.kernel.org/power/powercap/powercap.html

. /usr/lib/tuned/functions

PLATFORM_PROFILE=/sys/firmware/acpi/platform_profile
RAPL_MMIO=/sys/class/powercap/intel-rapl-mmio:0
RAPL_MSR=/sys/class/powercap/intel-rapl:0

apply_power_policy() {
    echo balanced-performance > "$PLATFORM_PROFILE"
    sleep 0.3

    ## MMIO
    echo 330000000 > "$RAPL_MMIO/constraint_2_power_limit_uw"
    echo 157000000 > "$RAPL_MMIO/constraint_1_power_limit_uw"
    echo 117000000 > "$RAPL_MMIO/constraint_0_power_limit_uw"
    echo 128000000 > "$RAPL_MMIO/constraint_0_time_window_us"

    ## MSR
    echo 330000000 > "$RAPL_MSR/constraint_2_power_limit_uw"
    echo 157000000 > "$RAPL_MSR/constraint_1_power_limit_uw"
    echo 117000000 > "$RAPL_MSR/constraint_0_power_limit_uw"
    echo 128000000 > "$RAPL_MSR/constraint_0_time_window_us"
}

start() {
    apply_power_policy
    return 0
}

stop() {
    return 0
}

process "$@"
