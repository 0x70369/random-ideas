#!/bin/env bash

# To be used in this file
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Extracts any archive(s) (if unp isn't installed)
extract() {
    # Verify the proper commands for your system and edit this function accordingly

    for archive in "$@"; do
        if [ -f "$archive" ]; then
            case "$archive" in
            *.tar.* | *.tbz2 | *.tgz | *.tar) tar -xaf "$archive" ;; # -a enables autodetection for tar
            *.7z) 7z x "$archive" ;;
            *.bz2) bunzip2 -v "$archive" ;;
            *.exe) cabextract "$archive" ;;
            *.gz) gunzip -v "$archive" ;;
            *.rar) unar x "$archive" ;;
            *.xz) unxz -vv "$archive" ;;
            *.Z) uncompress -v "$archive" ;;
            *.zip) unzip -v "$archive" ;;
            *.zst) unzstd -v "$archive" ;;
            *) echo "don't know how to extract '$archive'..." ;;
            esac
        else
            echo "'$archive' is not a valid file!"
        fi
    done
}

# Searches for text in all files in the current folder
findtext() {
    # -i case-insensitive
    # -I ignore binary files
    # -H causes filename to be printed
    # -r recursive search
    # -n causes line number to be printed
    # optional: -F treat search term as a literal, not a regular expression
    # optional: -l only print filenames and not the matching lines ex. grep -irl "$1" *
    # optional: -E interprets PATTERNS as extended regular expressions
    grep -iIHrn --color=always "$1" . | less -r
}

# Copy and go to the directory
cpgo() {
    if [ -d "$2" ]; then
        cp "$1" "$2" && { cd "$2" || return; }
    else
        cp "$1" "$2"
    fi
}

# Move and go to the directory
mvgo() {
    if [ -d "$2" ]; then
        mv "$1" "$2" && { cd "$2" || return; }
    else
        mv "$1" "$2"
    fi
}

# Create and go to the directory
mkdirgo() {
    mkdir -p "$1" && { cd "$1" || return; }
}

# Goes up a specified number of directories  (i.e. up 4)
goup() {
    local d=""
    local limit=$1

    for ((i = 1; i <= limit; i++)); do
        d=$d/..
    done

    d=$(echo "$d" | sed 's/^\///')

    if [ -z "$d" ]; then
        d=..
    fi

    cd "$d" || return
}

# Automatically do an ls after each cd, z, or zoxide
cd() {
    if [ -n "$1" ]; then
        builtin cd "$@" && ls
    else
        builtin cd ~ && ls
    fi
}

# Returns the last 2 fields of the working directory
pwdtail() {
    pwd | awk -F/ '{nlast = NF -1;print $nlast"/"$NF}'
}

# IP address lookup
alias whatismyip="whatsmyip"
function whatsmyip() {
    # Internal IP Lookup.
    if command_exists ip; then
        echo -n "Internal IP: "
        ip route get 1.1.1.1 | awk '{print $7; exit}'
    else
        echo "ip command not found, cannot determine internal IP."
    fi

    # External IP Lookup
    echo -n "External IP: "
    curl -4 ifconfig.me
}

# Trim leading and trailing spaces (for scripts)
trim() {
    local var=$*
    var="${var#"${var%%[![:space:]]*}"}" # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}" # remove trailing whitespace characters
    echo -n "$var"
}

# GitHub Titus Additions
gcom() {
    git add . && git commit -m "$1"
}
lazyg() {
    git add . && git commit -m "$1" && git push
}

# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# Functions that you don't want to keep defined
# outside of this file's scope can be undefined
# like so: unset -f <function name>
# The same applies for variables: unset <variable>
