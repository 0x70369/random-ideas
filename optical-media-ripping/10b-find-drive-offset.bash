#!/usr/bin/env bash
#
# 10b-find-drive-offset.bash [device]
#
# Finds the drive's read offset with `cyanrip -f` and saves it where
# 12a-rip-cd.bash reads it. Insert a popular commercial audio CD first:
# cyanrip needs a disc that is in the AccurateRip database.

# shellcheck source=common.bash
source -- "$(dirname -- "${BASH_SOURCE[0]}")/common.bash"

need cyanrip udevadm
use_device "${1:-}"
set_drive_id

# Last line on success: "Drive offset of +6 found (confidence: 13)!"
output="$(cyanrip -d "${DEVICE}" -f 2>&1 | tee /dev/stderr)" || true
offset="$(sed -nE 's/^Drive offset of ([+-]?[0-9]+) found.*/\1/p' \
    <<<"${output}" | tail -n 1)"

if [[ -z "${offset}" ]]; then
    # The drive's own vendor/model: in a USB enclosure, udev's serial may
    # name the USB bridge instead.
    dev="$(realpath -- "${DEVICE}")"
    sysdev="/sys/class/block/${dev##*/}/device"
    model="$(cat "${sysdev}/vendor" "${sysdev}/model" | xargs)"
    cat >&2 <<EOF
No offset found. Try another mainstream commercial CD, or look up
"${model}" in http://www.accuraterip.com/driveoffsets.htm and save it:
  echo OFFSET > '${OFFSET_FILE}'
EOF
    exit 1
fi

mkdir -pv -- "${OFFSET_FILE%/*}"
printf '%s\n' "${offset#+}" >"${OFFSET_FILE}"
echo "Saved: ${offset#+} samples -> ${OFFSET_FILE}"
