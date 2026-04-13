#!/bin/env bash

#
# ~/.bashrc
#

# DON'T CHANGE THIS FILE
# You can define your custom configuration by adding/editing files in ~/.config/bashrc.d

# Source user's custom configuration
if [ -d "$HOME"/.config/bashrc.d ]; then
    for file in "$HOME"/.config/bashrc.d/*.bash; do
        [ -f "$file" ] && [ -r "$file" ] && [ -s "$file" ] || continue

        if ! . "$file"; then
            printf 'Failed to load: %s\n' "$file" >&2
        fi
    done

    unset file
else
    mkdir -p "$HOME/.config/bashrc.d" >/dev/null >&2
    echo "The '~/.config/bashrc.d' directory was created. You can customize your shell by editing files there."
fi

# -f checks if $file exists and it's a regular file;
# -r checks if $file is readable;
# -s checks if $file isn't empty;
