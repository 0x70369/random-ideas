#!/bin/env bash

# -----------------------------------------------------
# Oh My Posh
# -----------------------------------------------------
POSH=agnoster

eval "$(oh-my-posh init bash --config $HOME/.config/ohmyposh/EDM115-newline.omp.json)"


# -----------------------------------------------------
# Bash
# -----------------------------------------------------
# Check if the current shell is interactive. If it is, disable the bell
[[ $- == *i* ]] && bind "set bell-style visible"

# Check the window size after each command and, if necessary, update the values of LINES and COLUMNS
shopt -s checkwinsize

# Causes bash to append to history instead of overwriting it, so if you start a new terminal, you have old session history
shopt -s histappend

## https://mywiki.wooledge.org/glob
# shopt -s extglob
# shopt -s nullglob
