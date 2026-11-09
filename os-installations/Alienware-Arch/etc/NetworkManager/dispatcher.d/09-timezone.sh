#!/bin/sh
# Set the time zone from the public IP address when a connection comes up.

[ "$2" = up ] && [ "$1" != lo ] || exit 0

# Skip the hotspot (shared) and tunnels: through a VPN, the IP is the server's, not where the laptop is
[ "$(nmcli -g ipv4.method connection show uuid "$CONNECTION_UUID" 2>/dev/null)" != shared ] || exit 0
case "$(nmcli -g connection.type connection show uuid "$CONNECTION_UUID" 2>/dev/null)" in
    wireguard | vpn | tun | dummy) exit 0 ;;
esac

systemd-run --quiet --no-block --collect --unit=nm-timezone sh -c \
    'tz=$(curl -sS --fail --max-time 60 https://ipapi.co/timezone) && timedatectl set-timezone "$tz"' \
    2>/dev/null || :
