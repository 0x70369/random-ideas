#!/bin/env bash

# Environment for the whole session: the graphical session is started by a login shell, which
# sources ~/.bash_profile (and so this file), so programs launched from Plasma see it too.
## https://wiki.archlinux.org/title/Environment_variables#Using_shell_initialization_files

# -----------------------------------------------------
# PATH
# -----------------------------------------------------
# Add directories to PATH if they exist and aren't there yet - adapted from /etc/profile in Arch Linux
add_paths() {
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        case ":$PATH:" in
            *:"$dir":*) ;;
            *) PATH=${PATH:+$PATH:}$dir ;;
        esac
    done
    export PATH
}

add_paths "$HOME/.local/bin" "/var/lib/flatpak/exports/bin" "$HOME/.local/share/flatpak/exports/bin"

unset -f add_paths
unset dir
