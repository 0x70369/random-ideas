#
# ~/.bash_profile
#

# DON'T CHANGE THIS FILE
# Add or edit files in ~/.config/bashprofile.d instead.

# Login shells: load the POSIX profile first (environment for all shells)
# shellcheck source=/dev/null
[[ -f ~/.profile ]] && . ~/.profile

for file in ~/.config/bashprofile.d/*.bash; do
    [[ -r ${file} ]] || continue
    . "${file}" || printf 'Failed to load: %s\n' "${file}" >&2
done
unset file

# shellcheck source=/dev/null
[[ -r ~/.bashrc ]] && . ~/.bashrc
