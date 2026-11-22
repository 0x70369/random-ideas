#!/bin/sh
# Install or remove the Halo 4 Reflow Spartan Ops maps as symbolic links.
# Usage: InstallHalo4Reflow.sh [install | remove]; no argument shows status.
# Set H4 if MCC is in another Steam library.
set -eu

steam=${HOME}/.steam/root/steamapps/common
h4=${H4:-${steam}/Halo The Master Chief Collection/halo4}
mod=${h4}/mods/reflow/halo4/maps-spartanops
game=${h4}/maps

case ${1:-} in
    install | remove | '') ;;
    *) echo "Usage: ${0##*/} [install | remove]" >&2; exit 2 ;;
esac
[ -d "${game}" ] || { echo "Game folder not found: ${game}" >&2; exit 1; }

# $1 = mod map, $2 = game map. Back up the original, then link.
link() {
    if [ -L "$2" ]; then
        echo "Already linked: ${2##*/}"
        return
    fi
    if [ -e "$2" ] && [ ! -e "$2.bak" ]; then
        mv -v -- "$2" "$2.bak"
    fi
    if [ -e "$2" ]; then
        echo "Skipped, ${2##*/} and its backup both exist." >&2
        return
    fi
    ln -sv -- "$1" "$2"
}

# $1 = game map. Remove the link, then restore the original.
restore() {
    if [ -L "$1" ]; then
        rm -v -- "$1"
    fi
    if [ ! -e "$1.bak" ]; then
        return
    fi
    if [ -e "$1" ]; then
        echo "Kept ${1##*/}.bak: ${1##*/} is not a link." >&2
        return
    fi
    mv -v -- "$1.bak" "$1"
}

total=0 linked=0
for m in "${mod}"/*.map; do
    [ -e "${m}" ] || { echo "No .map files in ${mod}" >&2; exit 1; }
    f=${game}/${m##*/}
    case ${1:-} in
        install) link "${m}" "${f}" ;;
        remove) restore "${f}" ;;
        *) ;;
    esac
    total=$((total + 1))
    if [ -L "${f}" ]; then
        linked=$((linked + 1))
    fi
done
echo "Reflow maps linked: ${linked} of ${total}."
