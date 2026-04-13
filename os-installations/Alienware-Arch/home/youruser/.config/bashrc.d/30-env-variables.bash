#!/bin/env bash

# -----------------------------------------------------
# Notes
# -----------------------------------------------------
# Some environment variables are defined in ~/.bash_profile


# -----------------------------------------------------
# Bash
# -----------------------------------------------------
# Don't include consecutive duplicate commands or commands starting with a space in ~/.bash_history
## https://unix.stackexchange.com/questions/48713/how-can-i-remove-duplicates-in-my-bash-history-preserving-order
export HISTCONTROL=ignorespace:ignoredups:erasedups

# Expand the history size
export HISTFILESIZE=6969
export HISTSIZE=2666
export HISTTIMEFORMAT="%A, %d/%m/%Y %T: " # add timestamp to history (this format is for the command, not the file)


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
# User
# -----------------------------------------------------
# Defining XDG directories according to: https://specifications.freedesktop.org/basedir-spec/latest/#variables
export XDG_CACHE_HOME="$HOME/.cache"

add_config_dirs() {
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        case ":$XDG_CONFIG_DIRS:" in
            *:"$dir":*)
                ;;
            *)
                XDG_CONFIG_DIRS=${XDG_CONFIG_DIRS:+$XDG_CONFIG_DIRS:}$dir
                ;;
        esac
    done
}
add_config_dirs "/etc/xdg"

export XDG_CONFIG_HOME="$HOME/.config"

add_data_dirs() {
    for dir in "$@"; do
        [ -d "$dir" ] || continue
        case ":$XDG_DATA_DIRS:" in
            *:"$dir":*)
                ;;
            *)
                XDG_DATA_DIRS=${XDG_DATA_DIRS:+$XDG_DATA_DIRS:}$dir
                ;;
        esac
    done
}
#add_data_dirs "/whatever/you/want"

export XDG_DATA_HOME="$HOME/.local/share"

if [ -z "$XDG_RUNTIME_DIR" ]; then
    export XDG_RUNTIME_DIR="/run/user/$(id -u)"
fi

export XDG_STATE_HOME="$HOME/.local/state"


# -----------------------------------------------------
# Applications
# -----------------------------------------------------
# Defining the default manual viewer
# Suggestion by Mental Outlaw: https://www.youtube.com/watch?v=Dg2Lek-xN70&t=135s
# Falls back to less with colors if neovim is not installed
if command -v nvim >/dev/null 2>&1; then
    export MANPAGER="nvim +Man!"
fi

# Color for manpages in less makes manpages a little easier to read.
# Used when another manpager isn't selected already.
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;31m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'


# Display a stack trace when a Rust program encounters an error
export RUST_BACKTRACE=full


# -----------------------------------------------------
# Wayland
# -----------------------------------------------------
# Setting the default path where cursors are stored (https://wiki.archlinux.org/title/Cursor_themes#Qt)
if [ -z "$XCURSOR_PATH" ]; then
    export XCURSOR_PATH="$HOME/.local/share/icons"
fi

# Define the mouse cursor theme used in Wayland; the cursor theme must be saved inside ~/.local/share/icons
if [ "$XDG_SESSION_TYPE" == "wayland" ]; then
    export XCURSOR_THEME=Bibata-Modern-Ice
    export XCURSOR_SIZE=32
fi

# Uncomment this if your cursor doesn't appear on your screen when using Wayland. Note: not a guaranteed fix
## https://wiki.archlinux.org/title/Sway#No_visible_cursor
#export WLR_NO_HARDWARE_CURSORS=1


# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
# Users can define their own functions in the dedicated configuration file (60-functions.bash).
unset -f add_paths add_config_dirs add_data_dirs