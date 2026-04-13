#!/bin/env bash

# I copied a lot of settings here and in the other config files from CTT's Bash prompt
## https://github.com/ChrisTitusTech/mybash

# I also define many things in /etc/bash.bash_aliases, which is sourced prior to these files.

# -----------------------------------------------------
# INIT
# -----------------------------------------------------

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

# Prevent doublesourcing
if [[ -z "${BASHRCSOURCED}" ]] ; then
    BASHRCSOURCED="Y"

    # the check is bash's default value
    [[ "$PS1" = '\s-\v\$ ' ]] && PS1='[\u@\h \W]\$ '

    case ${TERM} in
        Eterm*|alacritty*|aterm*|foot*|gnome*|konsole*|kterm*|putty*|rxvt*|tmux*|xterm*)
            PROMPT_COMMAND+=('printf "\033]0;%s@%s:%s\007" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"')
            ;;

        screen*)
            PROMPT_COMMAND+=('printf "\033_%s@%s:%s\033\\" "${USER}" "${HOSTNAME%%.*}" "${PWD/#$HOME/\~}"')
            ;;
    esac
fi
