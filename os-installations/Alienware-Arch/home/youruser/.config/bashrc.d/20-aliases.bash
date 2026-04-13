#!/bin/env bash

# -----------------------------------------------------
# General
# -----------------------------------------------------
# Text editors
alias v='nvim'
alias vi='nvim'
alias vim='nvim'
alias n="nano"

# -----------------------------------------------------
# Shell
# -----------------------------------------------------
alias reload-bash=". ~/.bashrc; clear; fastfetch --config examples/13"
alias edit-alias="nano ~/.config/bashrc.d/20-aliases.bash"

# -----------------------------------------------------
# Applications
# -----------------------------------------------------
# yt-dlp aliases
alias yt-dlp="yt-dlp --color always --progress --check-formats --embed-thumbnail --embed-metadata  --xattrs -f - -o '/temp/%(title)s.%(ext)s'"
alias ytdlp-audio="yt-dlp --extract-audio --audio-format flac --audio-quality 0"

# zotify aliases (although there are maintained forks of the project, there are others as well, like votify and onthespot)
# Remember to install pipx
#alias zotify-download="zotify --config=$HOME/.config/zotify/config.json" # senha nova: !&9caiorotunno
#alias edit-zotify="nano $HOME/.config/zotify/config.json" # pipx install git+https://zotify.xyz/zotify/zotify@v1.0-dev OR pipx install git+https://github.com/yodaluca23/zotify.git@v1.0-dev

# Protontricks ---> https://github.com/Matoking/protontricks?tab=readme-ov-file#flatpak-recommended
alias protontricks="flatpak run com.github.Matoking.protontricks"
alias protontricks-launch="flatpak run --command=protontricks-launch com.github.Matoking.protontricks"

## https://wiki.archlinux.org/title/KDE#From_the_console
alias launch-plasma="/lib/plasma-dbus-run-session-if-needed /bin/startplasma-wayland"

# -----------------------------------------------------
# MATLAB
# -----------------------------------------------------
# Aliases for configuring MATLAB launch commands - remember to check if the symbolic link exists at /usr/local/bin; if not, create it before running these (or edit the aliases themselves)

# The aliases follow the instructions in these sections of the MATLAB article of the ArchWiki:
# - https://wiki.archlinux.org/title/MATLAB#OpenGL_acceleration ---> Remember to create the java.opts file, if needed;
# - https://wiki.archlinux.org/title/MATLAB#Running_on_Wayland
# - https://wiki.archlinux.org/title/MATLAB#Desktop_entry

##alias matlab="env LD_PRELOAD=/usr/lib/libstdc++.so LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/ QT_QPA_PLATFORM=xcb /usr/local/bin/matlab -useStartupFolderPref"

# The alias below has extra steps, documented in the following links:
# - https://wiki.archlinux.org/title/PRIME#Configure_applications_to_render_using_GPU
# - https://download.nvidia.com/XFree86/Linux-x86_64/570.153.02/README/primerenderoffload.html <--- Chapter 35 (accessed June 3rd, 2025; go to https://download.nvidia.com/XFree86/Linux-x86_64/ and navigate the tree to the latest version of the docs, or the one matching your driver's version)

# Only enable this alias if the dGPU is active, so MATLAB can benefit from extra performance
##if [[ "$LIBVA_DRIVER_NAME" = nvidia ]] && [[ "$VDPAU_DRIVER" = nvidia ]]; then

##alias MATLAB="env LD_PRELOAD=/usr/lib/libstdc++.so LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/ QT_QPA_PLATFORM=xcb prime-run /usr/local/bin/matlab -useStartupFolderPref -nosoftwareopengl"
##alias MATLAB="env LD_PRELOAD=/usr/lib/libstdc++.so LD_LIBRARY_PATH=/usr/lib/xorg/modules/dri/ QT_QPA_PLATFORM=xcb __NV_PRIME_RENDER_OFFLOAD=1 __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0 __GLX_VENDOR_LIBRARY_NAME=nvidia __VK_LAYER_NV_optimus=NVIDIA_only /usr/local/bin/matlab -useStartupFolderPref -nosoftwareopengl"

##fi

# Remember to install the packages mentioned in the sections linked above!
# Also also in this section, if you have a Nvidia GPU: https://wiki.archlinux.org/title/MATLAB#GPU_computing

# -----------------------------------------------------
# Formatting and Repairing
# -----------------------------------------------------
# Reformat my USB flash drives (uses exfatprogs, install it if not already present) (inform the partition after the alias, e.g. /dev/sda1) (you can specify a label with: -L <label>) (you can specify a full format with -f)
# More details in: man mkfs.exfat
alias reformat-usb128G="sudo mkfs.exfat -b 16M -c 128K -v"
alias reformat-usb32G="sudo mkfs.exfat -b 4M -c 32K -v"

# Repairing my USB flash drives (uses exfatprogs, install it if not already present) (inform the partition after the alias, e.g. /dev/sda1)
# More details in: man fsck.exfat
alias repair-exfat="sudo fsck.exfat -svp"
