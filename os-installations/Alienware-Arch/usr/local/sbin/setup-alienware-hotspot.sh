#!/bin/env sh
# Create or update the WPA3 hotspot profile and its encrypted password.
# Activation is left to the NetworkManager dispatcher script (90-hotspot).

set -eu
umask 077

PROFILE='Alienware-hotspot'
SSID='Alienware-hotspot'
CREDENTIAL='/etc/credstore.encrypted/alienware-hotspot-passwd'

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

[ "$(id -u)" -eq 0 ] || fail 'Run this script as root.'

for tool in nmcli systemd-creds uuidgen chattr; do
    command -v "$tool" >/dev/null || fail "Missing command: $tool"
done

nmcli general status >/dev/null || fail 'NetworkManager is not running.'

if [ -L "$CREDENTIAL" ] || { [ -e "$CREDENTIAL" ] && [ ! -f "$CREDENTIAL" ]; }; then
    fail "Not a regular file: $CREDENTIAL"
fi

# Generate the password once and store it only encrypted. It is written to a
# temporary file and then moved into place, so an interrupted run never
# leaves a partial credential behind.
if [ ! -e "$CREDENTIAL" ]; then
    mkdir -p "${CREDENTIAL%/*}"
    tmp=$(mktemp "$CREDENTIAL.XXXXXXXX")
    trap 'rm -f "$tmp"' 0
    trap 'exit 1' 1 2 3 15

    password=$(uuidgen --random) || fail 'Could not generate a password.'
    # The credential name defaults to the output file name, so pass the final
    # name explicitly; decryption derives it from the file name.
    printf '802-11-wireless-security.psk:%s\n' "$password" |
        systemd-creds encrypt --name="${CREDENTIAL##*/}" - "$tmp" ||
        fail 'Could not encrypt the password.'
    unset password
    mv "$tmp" "$CREDENTIAL"
fi

systemd-creds decrypt "$CREDENTIAL" - >/dev/null ||
    fail "Could not decrypt $CREDENTIAL"

# Block changes and deletion, even by root, until "chattr -i" is run.
chattr +i "$CREDENTIAL" ||
    fail 'Could not make the credential immutable (unsupported filesystem?).'

# Set protocol and ciphers explicitly: when unset, wpa_supplicant also offers
# WPA1 and TKIP (TKIP even as the group cipher), which WPA3 forbids. With
# them, AP initialization failed (proto) and iPhones refused to join (TKIP).
# Band and channel stay unset so the driver picks a supported combination.
# The PSK is never stored (psk-flags 2); the dispatcher supplies it.
set -- \
    802-11-wireless.ssid "$SSID" \
    802-11-wireless.mode ap \
    802-11-wireless.band '' \
    802-11-wireless.channel '' \
    wifi-sec.key-mgmt sae \
    wifi-sec.proto rsn \
    wifi-sec.pairwise ccmp \
    wifi-sec.group ccmp \
    wifi-sec.pmf required \
    wifi-sec.psk '' \
    wifi-sec.psk-flags 2 \
    ipv4.method shared \
    ipv6.method disabled \
    connection.autoconnect no \
    connection.zone nm-shared

if nmcli -g connection.uuid connection show id "$PROFILE" >/dev/null 2>&1; then
    nmcli connection modify id "$PROFILE" "$@"
    printf 'Updated the hotspot profile.\n'
else
    nmcli connection add type wifi ifname '*' con-name "$PROFILE" "$@"
    printf 'Created the hotspot profile.\n'
fi

printf 'UUID: %s\n' "$(nmcli -g connection.uuid connection show id "$PROFILE")"
printf 'Credential: %s (immutable)\n' "$CREDENTIAL"
printf 'Not activated; the dispatcher handles activation.\n'
