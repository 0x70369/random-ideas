#!/bin/env bash

# -----------------------------------------------------
# Notes
# -----------------------------------------------------
# This file is useless by itself. Make sure it is sourced by Bash.
# You can do this by adding the snippet below in the global configuration file. On Arch Linux, said file is: /etc/bash.bashrc

# if [ -r "/etc/bash.bash_aliases" ]; then
#     . "/etc/bash.bash_aliases"
# fi

# Even though this file was written for Bash, >almost< everything here is POSIX-compatible,
# so you should be able to use this anywhere with minimal friction.

# This file was written for Arch Linux btw, some aliases aren't applicable for other distros.

# To temporarily bypass an alias, you can precede the command with a "\" or write its absolute path.
# E.g. the ls command is aliased, but to use the normal ls command you would type "\ls" or "/bin/ls".

# When in doubt over the stuff configured here, >>>read the manual pages<<< (and possibly the wiki for your distro, if it exists).

# -----------------------------------------------------
# Functions
# -----------------------------------------------------
# Function to conditionally add aliases
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# -----------------------------------------------------
# Customization
# -----------------------------------------------------
# neofetch aliases
if command_exists fastfetch; then
    alias nf="fastfetch"
    alias neofetch="fastfetch"
    alias pf="fastfetch"
    alias ff="fastfetch"
fi

# ls aliases
if command_exists eza; then
    # For icons to be well displayed, use a nerd font
    alias eza="eza -ah --icons=auto --color=auto"
    alias ls="eza"
    alias ll="eza -l"
    alias lr="eza -R"

    # Recurse as a tree ==> -T
    ## -L (level, optional) controls how deep the tree goes
    ### A numerical argument is required: lT -L x
    ## -l (list format) is optional
    alias lT="eza -T"

    # Sort by OPTION ==> -s OPTION
    alias lx="eza -ls Extension"
    alias lz="eza -ls size"
    alias ld="eza -ls date"
else
    alias ls="ls -Ah --color=auto"
    alias ll="ls -l"
    alias lr="ls -R"

    # Sort by OPTION
    alias lx="ls -lX"
    alias lz="ls -lS"
    alias ld="ls -lt"
fi

alias dir="dir -Ash --color=auto"
alias vdir="vdir -Ash --color=auto"

alias grep="grep --color=auto"
alias fgrep="grep -F"
alias egrep="grep -E"

# Clear screen for real (it does not work in Terminology)
alias cls='printf "\033c"'

if command_exists tldr; then
    alias tldr="tldr --color=auto"
fi

# cat with wings
if command_exists bat; then
    alias cat="bat --color=auto -P"
fi

# -----------------------------------------------------
# System
# -----------------------------------------------------
# Network
alias ping="ping -c 7"
alias test-internet="ping ping.archlinux.org"
alias reset-network="sudo systemctl restart systemd-resolved.service NetworkManager.service && sudo firewall-cmd --reload"
alias openports="ss -tulpn"

# Power options
alias suspend="systemctl suspend"
alias hibernate="systemctl hibernate"
alias soft-reboot="systemctl soft-reboot"

# Safety settings
for cmd in rmdir chmod chown chgrp mount umount; do
    alias "$cmd"="$cmd -v"
done
alias mkdir="mkdir -vp"
alias cp="cp -iv"
alias mv="mv -iv"
alias ln="ln -biv"
alias rm="rm -Iv"

# Remove a directory and all files inside it
alias rmd="rm -r"

# Safer alternative to rm
if command_exists trash; then
    alias del="trash -v"
fi

# Chris Titus Tech's Linux Utility: https://github.com/ChrisTitusTech/linutil
if command_exists curl; then
    alias LinUtil="cd /tmp; curl -fsSL https://www.christitus.com/linux | sh; cd"
fi

# ps aliases
alias pst="ps auxf"
alias p="\ps aux | grep " # Search running processes

if command_exists multitail; then
    alias multitail="multitail --no-repeat -c"
fi

alias rebuild-initramfs="sudo mkinitcpio -P"
## Be smart, use topgrade instead of a stupidly long and convoluted alias
#alias upgrade-system="sudo pacman -Syu; echo; flatpak upgrade; echo; flatpak uninstall --unused; echo; sudo -u mr_robot yay -Syu; echo; pipx upgrade-all; echo; sudo fwupdmgr get-updates; sudo sync"

# -----------------------------------------------------
# Convenience stuff
# -----------------------------------------------------
alias log-out='loginctl terminate-user "$USER"'
alias lock-session="loginctl lock-session"
alias which-filetype="xdg-mime query filetype"

alias c='clear'
alias e='exit'

# Alias for accessing the Arch Wiki offline in a terminal (suggestion by Mental Outlaw: https://www.youtube.com/watch?v=Dg2Lek-xN70&t=324s)
# Requires the "wikiman" and "arch-wiki-docs" packages
if command_exists wikiman; then
    alias archwiki="wikiman -s arch"
fi

# Show current date
alias da='date "+%Y-%m-%d %A %T %Z"'

# Add an "alert" alias for long running commands. Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# Search files in the current folder. Usage: f <search string>
alias f="find . | grep "

# Search command line history. Usage: h <search string>
alias h="history | grep "

# See if a command is aliased, a file, or a built-in command
alias check-command="command -V"

# Count all files (recursively) in the current folder
alias count-files='for t in f:files l:links d:directories; do printf "%s %s\n" "$(find . -type "${t%%:*}" | wc -l)" "${t#*:}"; done 2>/dev/null'

# Aliases for archives
if command_exists tar; then
    alias tar="tar -a --acls --selinux --xattrs --totals --checkpoint=.10000"
    # tar's "-a" parameter enables archive format autodetection.

    # --checkpoint=.10000 makes tar print a dot on stdout after processing
    # 10000 records (by default, each record is 10 KiB), or 100 MiB.
    # This allows you to have a makeshift progress bar on your screen.

    ## Usage: <alias> <output archive file> <input files>
    alias mktar="tar -cvf"

    ## Usage: <alias> <archive>
    alias untar="tar -xf"
fi

# -----------------------------------------------------
# Non-root user stuff
# -----------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    alias root="sudo -i"

    if command_exists curl; then
        alias LinUtilRoot="cd /tmp; curl -fsSL https://www.christitus.com/linux | sudo sh; cd"
    fi

    if command_exists flatpak; then
        alias flatpak="flatpak --user"
    fi

    # Make the shell expand aliases after sudo
    alias sudo='sudo '
fi

# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
# Users can define custom functions in their individual configuration.
unset -f command_exists
