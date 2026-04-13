#!/bin/env sh

memtest_binary="/boot/memtest86+/memtest.efi"
key="/root/secureboot/keys/MOK/MOK.key"
cert="/root/secureboot/keys/MOK/MOK.crt"

if ! sbverify --cert "$cert" "$memtest_binary" >/dev/null 2>&1; then
    sbsign "$memtest_binary" --key "$key" --cert "$cert" --output "$memtest_binary"
fi
