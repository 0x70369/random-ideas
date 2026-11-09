#!/bin/env bash

# -----------------------------------------------------
# Notes
# -----------------------------------------------------
# Some environment variables are defined in ~/.bash_profile

# -----------------------------------------------------
# PATH
# -----------------------------------------------------
# Function to add directories to the PATH variable, if they exist - Adapted from the function in /etc/profile in Arch Linux
# Original idea sourced from: https://wiki.archlinux.org/title/Environment_variables#Using_shell_initialization_files
add_paths() {
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        case ":$PATH:" in
        *:"$dir":*)
            ;;
        *)
            PATH=${PATH:+$PATH:}$dir
            ;;
        esac
    done
}

# Call the function with the directories one wishes to add to $PATH
add_paths "$HOME/.local/bin" "/var/lib/flatpak/exports/bin" "$HOME/.local/share/flatpak/exports/bin"

# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
# Users can define their own functions in the dedicated configuration file (60-functions.bash).
unset -f add_paths
