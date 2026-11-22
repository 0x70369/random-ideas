# -----------------------------------------------------
# Oh My Posh, with a blank line before each prompt
# -----------------------------------------------------
PROMPT_COMMAND=('printf "\n"' "${PROMPT_COMMAND[@]}")
# shellcheck disable=SC2312 # upstream init line
eval "$(oh-my-posh init bash \
    --config "${HOME}/.config/ohmyposh/kushal.omp.json")"

# -----------------------------------------------------
# Bash
# -----------------------------------------------------
# Visible bell instead of the audible one
bind "set bell-style visible"

# Check the window size after each command and, if necessary, update the
# values of LINES and COLUMNS
shopt -s checkwinsize

# Append to the history instead of overwriting it, so a new terminal keeps the
# old sessions' history
shopt -s histappend

# History: skip commands starting with a space and drop older duplicates; size
# of the history in memory and in ~/.bash_history; timestamps in the history
# command (not in the file). Plain shell variables: only bash uses them, so
# they don't need to be in the environment.
## https://www.gnu.org/software/bash/manual/html_node/Bash-Variables.html
HISTCONTROL=ignorespace:erasedups
HISTSIZE=666
HISTFILESIZE=3690
HISTTIMEFORMAT="%A, %d/%m/%Y %T: "
