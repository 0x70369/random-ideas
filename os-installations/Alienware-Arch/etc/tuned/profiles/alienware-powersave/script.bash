#!/bin/env bash
#
# alienware-powersave: profile script.
#
# Wi-Fi power saving only. USB autosuspend moved to the [usb] plugin in tuned.conf,
# where it used to sit behind an undefined $USB_AUTOSUSPEND and never ran.
# 802.11 power save has no sysfs path, so it cannot move into the profile.
#
## https://wiki.archlinux.org/title/Power_management#Network_interfaces

. /usr/lib/tuned/functions

start() {
    enable_wifi_powersave
    return 0
}

stop() {
    disable_wifi_powersave
    return 0
}

process $@
