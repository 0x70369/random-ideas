#!/bin/env bash

# Login into tty1 to launch KDE Plasma

if [[ -z $DISPLAY ]] && [[ -z "$WAYLAND_DISPLAY" ]] && [[ "$(tty)" = /dev/tty1 ]] && [[ -z $SSH_CONNECTION ]]; then
	printf "\n"

	export QT_QPA_PLATFORM=wayland
	export GDK_BACKEND=wayland
	export XDG_SESSION_TYPE=wayland
	export XDG_CURRENT_DESKTOP=KDE
	export KDE_FULL_SESSION=true
	##export MOZ_ENABLE_WAYLAND=1   # Add this in the app's settings via Flatseal

	/bin/cat <<"EOF"
____    __    ____  _______  __        ______   ______   .___  ___.  _______
\   \  /  \  /   / |   ____||  |      /      | /  __  \  |   \/   | |   ____|
 \   \/    \/   /  |  |__   |  |     |  ,----'|  |  |  | |  \  /  | |  |__
  \            /   |   __|  |  |     |  |     |  |  |  | |  |\/|  | |   __|
   \    /\    /    |  |____ |  `----.|  `----.|  `--'  | |  |  |  | |  |____
    \__/  \__/     |_______||_______| \______| \______/  |__|  |__| |_______|

.______        ___       ______  __  ___
|   _  \      /   \     /      ||  |/  /
|  |_)  |    /  ^  \   |  ,----'|  '  /
|   _  <    /  /_\  \  |  |     |    <
|  |_)  |  /  _____  \ |  `----.|  .  \   __
|______/  /__/     \__\ \______||__|\__\ (__)
EOF

	printf "\n\n"

	printf "Starting KDE Plasma (Wayland) in "
	sleep 1
	printf "3, "
	sleep 1
	printf "2, "
	sleep 1
	printf "1..."
	sleep 1

	printf "\n\n"

	## https://wiki.archlinux.org/title/KDE#From_the_console
	exec /lib/plasma-dbus-run-session-if-needed /bin/startplasma-wayland

	logout                                     # Prevent an endless loop in case Plasma fails to launch

fi
