## https://wiki.archlinux.org/title/Environment_variables#Using_shell_initialization_files

# This script was written for Arch Linux btw, so you may need to adapt it (package names, where to put it, etc.)
# if you want to use it in other distros. Also, make sure that everything needed for this to work is already set up.


# -----------------------------------------------------
# Helper functions
# -----------------------------------------------------

# Print informational messages only in interactive shells,
# so they don't end up in the journal when the graphical session sources /etc/profile
message() {
    case $- in
        *i*) printf '%s\n' "$*" ;;
        *) ;;
    esac
}

# Errors are always printed (to stderr), so they are logged even in non-interactive logins
err() {
    printf '%s\n' "$*" >&2
}

# -----------------------------------------------------
# Hardware Video Acceleration - Vulkan
# -----------------------------------------------------

# Select the Vulkan GPU by vendor priority (AMD, Intel, NVIDIA) among the GPUs
# that have a render node, so a GPU handed to a VM (vfio-pci, no render node)
# is skipped. The IDs come from sysfs: running vulkaninfo here would wake the
# NVIDIA GPU from RTD3 on every login, and cost a fraction of a second.
## https://wiki.archlinux.org/title/Vulkan#Switching_between_devices
set_mesa_vk_device() {
    unset MESA_VK_DEVICE_SELECT
    for vendor in 0x1002 0x8086 0x10de; do
        for node in /sys/class/drm/renderD*; do
            read -r found 2>/dev/null < "${node}/device/vendor" || continue
            [ "${found}" = "${vendor}" ] || continue
            read -r device < "${node}/device/device" || continue
            # Mesa's format: vendor:device, in hex without "0x"
            export MESA_VK_DEVICE_SELECT="${vendor#0x}:${device#0x}"
            message "MESA_VK_DEVICE_SELECT set to ${MESA_VK_DEVICE_SELECT}"
            unset vendor node found device
            return 0
        done
    done
    unset vendor node found device
    err "No GPU with a render node found; Vulkan picks one by itself."
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



# -----------------------------------------------------
# Cleanup
# -----------------------------------------------------
# The functions defined here should not be available beyond this file's scope.
unset -f set_mesa_vk_device message err