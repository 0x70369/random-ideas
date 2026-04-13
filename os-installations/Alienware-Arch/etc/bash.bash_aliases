#!/bin/env bash

# -----------------------------------------------------
# Notes
# -----------------------------------------------------
# This file is useless by itself. Make sure it is sourced by Bash.
# You can do this by adding the snippet below in the global configuration file. On Arch Linux, said file is: /etc/bash.bashrc

# if [ -r "/etc/bash.bash_aliases" ]; then
#     . "/etc/bash.bash_aliases"
# fi

# A better alternative is to use the script inside /etc/profile.d


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
    alias eza="eza -ah --icons=always --color=always"
    alias ls="eza"
    alias ll="eza -l"
    alias lr="eza -R"

    # Recurse as a tree ==> -T
    ## -L (level) controls how deep the tree goes
    ### A numerical argument is required: lT x
    ## -l (list format) is optional
    alias lT="eza -T -L"

    # Sort by OPTION ==> -s OPTION
    alias lx="eza -ls Extension"
    alias lz="eza -ls size"
    alias ld="eza -ls date"
else
    alias ls="ls -Ah --color=always"
    alias ll="ls -l"
    alias lr="ls -R"

    # Sort by OPTION
    alias lx="ls -lX"
    alias lz="ls -lS"
    alias ld="ls -lt"
fi

# dir aliases
alias dir="dir -Ash --color=always"
alias vdir="vdir -Ash --color=always"

# grep aliases
if command_exists rg; then
    alias grep="rg -p --engine=auto"
else
    alias grep="grep --color=always"
    alias fgrep="grep -F"
    alias egrep="grep -E"
fi

# Clear screen for real (it does not work in Terminology)
alias cls='echo -ne "\033c"'

if command_exists tldr; then
    alias tldr="tldr --color=always"
fi

# cat with wings
if command_exists bat; then
    alias cat="bat --color=always -P"
fi


# -----------------------------------------------------
# System
# -----------------------------------------------------
# Network
alias ping="ping -c 5"
alias test-internet="ping -c 5 ping.archlinux.org"
alias reset-network="sudo systemctl restart systemd-resolved.service NetworkManager.service"
alias openports="netstat -nape --inet" # Show open ports

# Adjust these 2 for your system
alias rebuild-initramfs="sudo mkinitcpio -P"
alias upgrade-system="sudo pacman -Syu; echo; flatpak upgrade; echo; flatpak uninstall --unused; echo; yay -Syu; echo; pipx upgrade-all; echo; sudo fwupdmgr get-updates; sudo sync"

# Power options
alias shutdown="systemctl poweroff"
alias reboot="systemctl reboot"
alias suspend="systemctl suspend"
alias hibernate="systemctl hibernate"

# Safety settings
alias mkdir="mkdir -vp"
alias cp="cp -iv"
alias mv="mv -iv"
alias ln="ln -iv"
alias rm="rm -iv"
alias chown="chown -v"
alias chmod="chmod -v"
alias mount="mount -v"
alias umount="umount -v"

# Remove a directory and all files inside it
alias rmdir="rm -riv"

# Safer alternative to rm
if command_exists trash; then
    alias del="trash -v"
fi

# Chris Titus Tech's Linux Utility: https://github.com/ChrisTitusTech/linutil
if command_exists curl; then
    alias LinUtil="cd /tmp; curl -fsSL https://www.christitus.com/linux | sh; cd"
fi

# ps aliases
alias ps="ps auxf"
alias p="ps aux | grep " # Search running processes

if command_exists multitail; then
    alias multitail="multitail --no-repeat -c"
fi


# -----------------------------------------------------
# Convenience stuff
# -----------------------------------------------------
alias log-out='loginctl terminate-user "$USER"'
alias lock-session="loginctl lock-session"
alias which-filetype="xdg-mime query filetype"

alias c='clear'
alias e='exit'

# Alias for accessing the Arch Wiki offline in a terminal (suggestion by Mental Outlaw: https://www.youtube.com/watch?v=Dg2Lek-xN70&t=324s)
# Requires the "wikiman" and "arch-wiki-docs" (or "arch-wiki-lite") packages
if command_exists wikiman; then
    alias archwiki="wikiman -s arch"
fi

# Show current date
alias da='date "+%Y-%m-%d %A %T %Z"'

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

alias home="cd ~"

# cd into the previous directory
alias bd='cd "$OLDPWD"'

# Search files in the current folder. Usage: f <search string>
alias f="find . | grep "

# Search command line history. Usage: h <search string>
alias h="history | grep "

# See if a command is aliased, a file, or a built-in command
alias check-command="type -t"

# Count all files (recursively) in the current folder
alias count-files="for t in files links directories; do echo \`find . -type \${t:0:1} | wc -l\` \$t; done 2> /dev/null"

# Aliases for archives
if command_exists tar; then
    alias tar="tar --acls --selinux --xattrs --totals --checkpoint=.10000"
    # tar's "-a" parameter enables archive format autodetection.
    
    # --checkpoint=.10000 makes tar print a dot on stdout after processing
    # 10000 records (by default, each record is 10 KiB), or 100 MiB.
    # This allows you to have a makeshift progress bar on your screen.
    
    ## Usage: <alias> <output archive file> <input files>
    alias mktar="tar -cvaf"
    
    ## Usage: <alias> <archive>
    alias untar="tar -xaf"
fi


# -----------------------------------------------------
# Non-root user stuff
# -----------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    alias root="sudo -i"
    alias sucat="sudo cat"

    if command_exists curl; then
        alias LinUtilRoot="cd /tmp; curl -fsSL https://www.christitus.com/linux | sudo sh; cd"
    fi

    if command_exists nano; then
        alias sunano="sudo nano"
    fi

    if command_exists nvim; then
        alias sunvim="sudo nvim"
    fi
fi


# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
# Users can define custom functions in their individual configuration.
unset -f command_exists
