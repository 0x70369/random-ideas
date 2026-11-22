# -----------------------------------------------------
# General
# -----------------------------------------------------
# Text editors
alias v="nvim"
alias vi="nvim"
alias vim="nvim"

# -----------------------------------------------------
# Shell
# -----------------------------------------------------
# Save the history, then replace the shell with a new one (nothing loads twice)
alias reload-bash="history -a; clear; exec bash"
alias edit-alias="nano ~/.config/bashrc.d/20-aliases.bash"

# -----------------------------------------------------
# Applications
# -----------------------------------------------------
# yt-dlp (the other options, and the output folder, are in
# ~/.config/yt-dlp/config)
alias yt-dlp="yt-dlp --check-formats -f -"
alias ytdlp-audio="yt-dlp --extract-audio --audio-format flac"

## https://github.com/Matoking/protontricks#flatpak-recommended
alias protontricks="flatpak run com.github.Matoking.protontricks"
alias protontricks-launch="flatpak run --command=protontricks-launch \
    com.github.Matoking.protontricks"

## https://wiki.archlinux.org/title/KDE#From_the_console
alias launch-plasma="/lib/plasma-dbus-run-session-if-needed startplasma-wayland"

# -----------------------------------------------------
# USB flash drives (exfatprogs)
# -----------------------------------------------------
# Give the partition after the alias (e.g. /dev/sda1). Optional: -L <label>,
# -f for a full format. See mkfs.exfat(8) and fsck.exfat(8)
alias reformat-usb128G="sudo mkfs.exfat -b 16M -c 128K -v"
alias reformat-usb32G="sudo mkfs.exfat -b 4M -c 32K -v"
alias repair-exfat="sudo fsck.exfat -spv"
