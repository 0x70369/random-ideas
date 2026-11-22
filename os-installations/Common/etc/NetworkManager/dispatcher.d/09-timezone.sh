#!/bin/sh
# Set the time zone from the public IP address when a connection comes up.

[ "$2" = up ] && [ "$1" != lo ] || exit 0

# Skip the hotspot (shared), tunnels (through a VPN, the IP is the server's,
# not where the laptop is) and virtual links (bridges and veth for VMs and
# containers, loopback). nmcli prints the method, then the type.
info=$(nmcli -g ipv4.method,connection.type connection show \
    uuid "${CONNECTION_UUID:-}" 2>/dev/null) || exit 0
case ${info} in
    shared* | *wireguard | *vpn | *tun | *dummy | *bridge | *veth | *loopback)
        exit 0 ;;
    *) ;;
esac

# shellcheck disable=SC2016  # ${tz} is expanded by the inner sh
systemd-run --quiet --no-block --collect --unit=nm-timezone sh -c \
    'tz=$(curl -sS --fail --max-time 60 https://ipapi.co/timezone) &&
    timedatectl set-timezone "${tz}"' 2>/dev/null || :
