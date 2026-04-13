#!/bin/env bash

#
# ~/.bash_profile
#

# DON'T CHANGE THIS FILE
# You can define your custom configuration by adding/editing files in ~/.config/bashprofile.d

# Login shells: load POSIX profile first (env for all shells)
# shellcheck source=/dev/null
if [ -f "$HOME/.profile" ]; then
    . "$HOME/.profile"
fi

if [ -d "$HOME"/.config/bashprofile.d ]; then
    for file in "$HOME"/.config/bashprofile.d/*.bash; do
        [ -f "$file" ] && [ -r "$file" ] && [ -s "$file" ] || continue

        if ! . "$file"; then
            printf 'Failed to load: %s\n' "$file" >&2
        fi
    done

    unset file
else
    mkdir -p "$HOME/.config/bashprofile.d" >/dev/null >&2
    echo "The '~/.config/bashprofile.d' directory was created. You can customize your session by editing files there."
fi

####################################################################

[ -f "$HOME"/.bashrc ] && [ -r "$HOME"/.bashrc ] && [ -s "$HOME"/.bashrc ] && . "$HOME"/.bashrc

# -f checks if $file exists and it's a regular file;
# -r checks if $file is readable;
# -s checks if $file isn't empty;
