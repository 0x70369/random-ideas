#!/bin/env sh

# Colors for man pages and other text shown by less(1), used when no other
# MANPAGER is selected. This can't go in environment.d(5), which doesn't
# interpret escape sequences, so printf generates the escape character here.
## https://wiki.archlinux.org/title/Color_output_in_console#Using_less

esc=$(printf '\033')

export LESS_TERMCAP_mb="${esc}[01;31m"    # Start blinking: bold red
export LESS_TERMCAP_md="${esc}[01;31m"    # Start bold: bold red
export LESS_TERMCAP_me="${esc}[0m"        # End blinking and bold
export LESS_TERMCAP_so="${esc}[01;44;33m" # Start standout (status line, search results): bold yellow on blue
export LESS_TERMCAP_se="${esc}[0m"        # End standout
export LESS_TERMCAP_us="${esc}[01;32m"    # Start underline: bold green
export LESS_TERMCAP_ue="${esc}[0m"        # End underline

unset esc
