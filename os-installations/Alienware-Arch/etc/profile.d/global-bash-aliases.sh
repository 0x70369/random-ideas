#!/bin/env sh

# This script sources the global aliases file, if it exists.

# This is a cleaner way of sourcing it, 
# rather than inserting code in the global bash config file,
# as package updates may overwrite your changes.

file="/etc/bash.bash_aliases"

if [ -f "$file" ] && [ -r "$file" ] && [ -s "$file" ]; then
    # shellcheck source=/etc/bash.bash_aliases
    if ! . "$file"; then
        printf 'Failed to load: %s\n' "$file" >&2
        return
    fi
else
    printf 'Failed to load: %s\n' "$file" >&2
    return
fi
# -f checks if $file exists and it's a regular file;
# -r checks if $file is readable;
# -s checks if $file isn't empty;