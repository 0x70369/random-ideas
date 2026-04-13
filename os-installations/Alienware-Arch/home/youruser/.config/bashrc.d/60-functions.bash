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

# Show the current distribution
distribution() {
    local dtype="unknown" # Default to unknown

    # Use /etc/os-release for modern distro identification
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
        fedora | rhel | centos) dtype="redhat" ;;
        sles | opensuse*) dtype="suse" ;;
        ubuntu | debian) dtype="debian" ;;
        gentoo) dtype="gentoo" ;;
        arch | manjaro) dtype="arch" ;;
        slackware) dtype="slackware" ;;
        *)
            # Check ID_LIKE only if dtype is still unknown
            if [ -n "$ID_LIKE" ]; then
                case "$ID_LIKE" in
                *fedora* | *rhel* | *centos*) dtype="redhat" ;;
                *sles* | *opensuse*) dtype="suse" ;;
                *ubuntu* | *debian*) dtype="debian" ;;
                *gentoo*) dtype="gentoo" ;;
                *arch*) dtype="arch" ;;
                *slackware*) dtype="slackware" ;;
                esac
            fi

            # If ID or ID_LIKE is not recognized, keep dtype as unknown
            ;;
        esac
    fi

    echo "$dtype"
}

# Show the current version of the operating system
os_version() {
    local dtype
    dtype=$(distribution)

    case "$dtype" in
    redhat)
        if [ -s /etc/redhat-release ]; then
            cat /etc/redhat-release
        else
            cat /etc/issue
        fi
        uname -a
        ;;
    suse) cat /etc/SuSE-release ;;
    debian) lsb_release -a ;;
    gentoo) cat /etc/gentoo-release ;;
    arch) cat /etc/os-release ;;
    slackware) cat /etc/slackware-version ;;
    *)
        if [ -s /etc/issue ]; then
            cat /etc/issue
        else
            echo "Error: Unknown distribution"
            return 1
        fi
        ;;
    esac
}

get_aur_helper() {
    if [ "$(id -u)" -eq 0 ]; then
        echo "This function should not be run as root."
        return 1
    fi

    local dtype aur_helper
    dtype=$(distribution)

    case "$dtype" in
    "arch")
        # First check if an AUR helper is already installed
        # The command_exists function is defined earlier in this file
        for helper in yay paru; do
            if command_exists "$helper"; then
                aur_helper="$helper"
                break
            fi
        done

        if [ -z "$aur_helper" ]; then
            # If none are found, prompt the user to choose one
            echo "No AUR helpers were found."
            echo "Do you want to install one now?"
            while :; do
                read -rp "Choose 'Y' for yay, 'P' for paru or 'E' to exit: " choice

                case "$choice" in
                Y | y)
                    aur_helper="yay"
                    break
                    ;;
                P | p)
                    aur_helper="paru"
                    break
                    ;;
                E | e)
                    aur_helper="none"
                    break
                    ;;
                *) echo "Invalid choice, try again." ;;
                esac
            done

            if [ "$aur_helper" != "none" ]; then
                echo "Installing dependencies..."
                sudo pacman -S --needed git base-devel || return

                echo "Installing your chosen AUR helper..."
                cd "/tmp" || return
                git clone "https://aur.archlinux.org/$aur_helper-bin.git" || return
                cd "$aur_helper-bin/" || return
                makepkg -sirc || return
                cd ~ || return
            else
                echo "No AUR helper was installed. Exiting..."
            fi
        fi
        ;;
    *)
        echo "Your distribution does not support the AUR. Exiting..."
        aur_helper="unsupported"
        ;;
    esac

    # Since other functions use this value, export it as an environment variable for easier fetching
    export AUR_HELPER="$aur_helper"
    echo "$AUR_HELPER"
}

# Automatically install the needed support files for this .bashrc file
install_bashrc_support() {
    local dtype
    dtype=$(distribution)

    case "$dtype" in
    redhat) sudo yum install multitail tree zoxide trash-cli fzf bash-completion fastfetch ;;
    suse) sudo zypper install multitail tree zoxide trash-cli fzf bash-completion fastfetch ;;
    debian)
        sudo apt install multitail tree zoxide trash-cli fzf bash-completion
        # Fetch the latest fastfetch release URL for linux-amd64 deb file
        local FASTFETCH_URL
        FASTFETCH_URL=$(curl -s https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | grep "browser_download_url.*linux-amd64.deb" | cut -d '"' -f 4)

        # Download the latest fastfetch deb file
        curl -sL "$FASTFETCH_URL" -o /tmp/fastfetch_latest_amd64.deb

        # Install the downloaded deb file using apt
        sudo apt install /tmp/fastfetch_latest_amd64.deb
        ;;
    arch)
        case "$AUR_HELPER" in
        yay | paru)
            $AUR_HELPER -S --needed multitail tree zoxide trash-cli fzf bash-completion fastfetch
            ;;
        *)
            echo "AUR_HELPER environment variable not set or with invalid value. Run the 'get_aur_helper' function and try again."
            ;;
        esac
        ;;
    slackware) echo "No install support for Slackware" ;;
    *) echo "Unknown distribution" ;;
    esac
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

function hb {
    if [ $# -eq 0 ]; then
        echo "No file path specified."
        return
    elif [ ! -f "$1" ]; then
        echo "File path does not exist."
        return
    fi

    local uri hasteKey response

    uri="http://bin.christitus.com/documents"
    if response=$(curl -s -X POST -d @"$1" "$uri"); then
        hasteKey=$(echo "$response" | jq -r '.key')
        echo "http://bin.christitus.com/$hasteKey"
    else
        echo "Failed to upload the document."
    fi
}

# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# Functions that you don't want to keep defined
# outside of this file's scope can be undefined
# like so: unset -f <function name>
# The same applies for variables: unset <variable>
