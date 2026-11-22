# Fastfetch on pseudo-terminals only (terminal emulators)
if tty_path=$(tty) && [[ ${tty_path} == /dev/pts/* ]]; then
    fastfetch --config examples/13
fi
unset tty_path
