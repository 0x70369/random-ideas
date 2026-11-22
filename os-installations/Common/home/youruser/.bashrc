#
# ~/.bashrc
#

# DON'T CHANGE THIS FILE
# Add or edit files in ~/.config/bashrc.d instead.

# Everything below is for interactive shells only. Login shells source this
# file too (~/.bash_profile does), including the non-interactive one that
# starts the graphical session.
[[ $- != *i* ]] && return

for file in ~/.config/bashrc.d/*.bash; do
    [[ -r ${file} ]] || continue
    # shellcheck source=/dev/null
    . "${file}" || printf 'Failed to load: %s\n' "${file}" >&2
done
unset file
