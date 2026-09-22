#!/bin/env sh

if [ "$#" -ne 3 ]; then
    printf 'Usage: %s DIRECTORY OLD_STRING NEW_STRING\n' "$0" >&2
    exit 1
fi

dir=$1
old=$2
new=$3

if [ -z "$old" ]; then
    printf 'Error: the old string cannot be empty.\n' >&2
    exit 1
fi

if [ ! -d "$dir" ]; then
    printf 'Error: directory does not exist: %s\n' "$dir" >&2
    exit 1
fi

# Prevent relative paths beginning with "-" from being interpreted
# as options by mv.
case $dir in
    /*|./*|../*)
        ;;
    *)
        dir="./$dir"
        ;;
esac

# Remove the trailing "/" except when the directory is "/".
case $dir in
    /)
        ;;
    */)
        dir=${dir%/}
        ;;
esac

# Include regular files and hidden files.
for path in "$dir"/* "$dir"/.[!.]* "$dir"/..?*
do
    [ -f "$path" ] || continue

    name=${path##*/}

    new_name=$(
        awk '
        BEGIN {
            old  = ARGV[1]
            repl = ARGV[2]
            text = ARGV[3]

            result = ""

            while ((pos = index(text, old)) != 0) {
                result = result substr(text, 1, pos - 1) repl
                text = substr(text, pos + length(old))
            }

            printf "%s%s", result, text
            exit
        }
        ' "$old" "$new" "$name"
    )

    [ "$name" = "$new_name" ] && continue

    new_path="$dir/$new_name"

    if [ -e "$new_path" ] || [ -L "$new_path" ]; then
        printf 'Skipping: destination already exists: %s\n' "$new_path" >&2
        continue
    fi

    printf '%s -> %s\n' "$name" "$new_name"
    mv "$path" "$new_path"
done
