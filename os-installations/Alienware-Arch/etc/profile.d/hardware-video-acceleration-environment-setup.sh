#!/bin/env sh

## https://wiki.archlinux.org/title/Environment_variables#Using_shell_initialization_files

# This script was written for Arch Linux btw, so you may need to adapt it (package names, where to put it, etc.)
# if you want to use it in other distros. Also, make sure that everything needed for this to work is already set up.


# -----------------------------------------------------
# Helper functions
# -----------------------------------------------------

# Print informational messages only in interactive shells,
# so they don't end up in the journal when the graphical session sources /etc/profile
msg() {
    case $- in
        *i*) printf '%s\n' "$*" ;;
    esac
}

# Errors are always printed (to stderr), so they are logged even in non-interactive logins
err() {
    printf '%s\n' "$*" >&2
}

msg ""


# -----------------------------------------------------
# Hardware Video Acceleration - Vulkan
# -----------------------------------------------------

# Function to set the MESA_VK_DEVICE_SELECT variable dynamically
# I created this so the system can automatically select the best available GPU,
# even when I'm doing PCI passthrough for VMs.
## https://wiki.archlinux.org/title/Vulkan#Switching_between_devices
set_mesa_vk_device() {

    unset MESA_VK_DEVICE_SELECT

    # Make sure vulkaninfo is installed
    if ! command -v vulkaninfo >/dev/null 2>&1; then
        err "vulkaninfo not found. Did you install it?"
        return 1
    fi

    # Get available devices
    vk_devices=$(env LC_ALL=C MESA_VK_DEVICE_SELECT=list vulkaninfo 2>&1)

    # Print an error if none are found
    if [ -z "$vk_devices" ]; then
        err "Failed to list Vulkan devices."
        return 1
    fi

    # Extract vendorID:deviceID from the output of vulkaninfo
    # If you won't change your hardware and/or do stuff like PCI passthrough, you can
    # hard-code the correct values instead of fetching them, which will speed up the functions's execution.

    # You may need to change the way this function extracts the values
    # from vk_devices if you have multiple GPUs from the same vendor.

    ### nvidia_id=$(grep -Eo "10de:[0-9a-f]{4}" <<< "$vk_devices" | head -n1) # Bash equivalent of the operation done below, kept for archival purposes.
    # The "\" in front of grep is to escape the alias. An alternative is to pass the absolute path, e.g. /bin/grep
    ##nvidia_id=$(echo "$vk_devices" | \grep -Eo "10de:[0-9a-f]{4}" | head -n1)
    intel_id=$(echo "$vk_devices" | \grep -Eo "8086:[0-9a-f]{4}" | head -n1)

    # Set the GPU used for Vulkan
    ## Remove and/or change the order of the vendors according to your system's
    ## configuration, in order to speed up the function's execution.
    for var in "$intel_id" "$nvidia_id"; do
        if [ -n "$var" ]; then
            export MESA_VK_DEVICE_SELECT="$var"
            msg "MESA_VK_DEVICE_SELECT set to $MESA_VK_DEVICE_SELECT"
            break
        fi
    done

    unset vk_devices nvidia_id intel_id var
}
set_mesa_vk_device

# Enabling Vulkan Video support with Intel GPU
## https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_Vulkan_Video
export ANV_VIDEO_DECODE=1    # Legacy variable, not sure if it's relevant anymore, but it'll stay for now.
export ANV_DEBUG=video-decode,video-encode


# -----------------------------------------------------
# Hardware Video Acceleration - VA-API
# -----------------------------------------------------
# LIBVA_DRIVER_NAME is deliberately left unset. libva then picks the driver from the GPU each
# program opened: the Intel render node (i915) loads iHD, the NVIDIA one (nvidia-drm) loads
# nvidia. Forcing a driver for the whole session breaks programs that render on the other GPU:
# with LIBVA_DRIVER_NAME=nvidia, Chromium-based browsers (which render on the Intel GPU) decode
# video on the NVIDIA GPU and hand the frames to the Intel one, which can't read NVIDIA's memory
# layout, so videos freeze and show artifacts while the audio keeps playing.
## https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_VA-API
# To decode on the NVIDIA GPU on purpose, set it for that program only, pointing to its render node:
## ls -l /dev/dri/by-path/
## LIBVA_DRIVER_NAME=nvidia mpv --hwdec=vaapi --vaapi-device=/dev/dri/renderD129 video.mkv


# -----------------------------------------------------
# OpenCL
# -----------------------------------------------------
# Nothing to set here. intel-compute-runtime and opencl-nvidia need no variables,
# and RUSTICL_ENABLE is deliberately left unset so that opencl-mesa (rusticl)
# stays inactive on the Intel GPU instead of duplicating intel-compute-runtime.


# -----------------------------------------------------
# Hardware Acceleration
# -----------------------------------------------------
# Enable multi-threaded OpenGL rendering in Mesa (affects the Intel GPU only,
# regardless of which GPU was selected for Vulkan)
export mesa_glthread=true


msg ""


# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
unset -f set_mesa_vk_device msg err