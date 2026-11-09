#!/bin/env sh
# Create or update the wired profile for the IMT Nord Europe network.
# The network has a captive portal: after connecting, open any plain IP
# address in a browser (e.g. http://1.1.1.1), wait for the redirect to the
# portal and log in with the IMT credentials.
#
# Usage (as root): setup-imt-wired.sh [PROFILE_NAME]

set -eu

PROFILE=${1:-'Conexão com fio IMT NE'}

# Quad9, added to the DNS servers that the network announces
QUAD9_DNS4='9.9.9.9#dns.quad9.net,149.112.112.112#dns.quad9.net'
QUAD9_DNS6='2620:fe::fe#dns.quad9.net,2620:fe::9#dns.quad9.net'

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'Run this script as root.'
command -v nmcli >/dev/null || fail 'Missing command: nmcli'
nmcli general status >/dev/null || fail 'NetworkManager is not running.'

# Link: with auto-negotiate=yes, NetworkManager forces autonegotiation through
# ethtool on every activation and reapply. On the ASIX AX88179 USB adapter
# that restarts the negotiation and the link drops for about 3 s. Proton VPN
# reapplies the profile when it connects (it adds a route to the VPN server),
# so its 4 s reachability check always failed. With auto-negotiate=no and no
# speed/duplex, NetworkManager leaves the link alone and the adapter still
# negotiates by itself (1000 Mb/s full duplex here).
#
# MAC: captive portals usually tie the login to the MAC address, so always
# use the adapter's own address instead of a random one.
#
# DNS: the servers announced by the network (DHCP and router advertisements)
# are kept, since the portal is only reachable through them, and Quad9 is
# added. NetworkManager always puts manually set servers before the announced
# ones, so Quad9 comes first in the list. systemd-resolved starts with the
# first server and moves to the next one when it stops answering; on IMT's
# network Quad9 doesn't answer, so it ends up on IMT's servers (opening the
# portal can take a little longer while the queries to Quad9 time out).
# DNS over TLS is not forced (forcing it is what broke captive portals
# before). With the VPN up, its own DNS is used.
#
# Autoconnect is off: the profile is chosen by hand when at IMT.
set -- \
    802-3-ethernet.auto-negotiate no \
    802-3-ethernet.speed 0 \
    802-3-ethernet.duplex '' \
    802-3-ethernet.cloned-mac-address permanent \
    ipv4.method auto \
    ipv4.ignore-auto-dns no \
    ipv4.dns "$QUAD9_DNS4" \
    ipv4.dns-priority 0 \
    ipv6.method auto \
    ipv6.ignore-auto-dns no \
    ipv6.dns "$QUAD9_DNS6" \
    ipv6.dns-priority 0 \
    connection.dns-over-tls default \
    connection.dnssec default \
    connection.autoconnect no \
    connection.zone work

if nmcli -g connection.uuid connection show id "$PROFILE" >/dev/null 2>&1; then
    nmcli connection modify id "$PROFILE" "$@"
    printf 'Updated the profile "%s".\n' "$PROFILE"
else
    nmcli connection add type ethernet ifname '*' con-name "$PROFILE" "$@"
    printf 'Created the profile "%s".\n' "$PROFILE"
fi

printf 'UUID: %s\n' "$(nmcli -g connection.uuid connection show id "$PROFILE")"
printf 'Add this UUID to UPSTREAM_UUIDS in 90-hotspot to share this network.\n'
printf 'If the profile is active, reconnect it to apply the changes.\n'
