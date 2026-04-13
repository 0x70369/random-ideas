#!/bin/env sh

## https://wiki.archlinux.org/title/Environment_variables#Using_shell_initialization_files

printf "\n"

# This script was written for Arch Linux btw, so you may need to adapt it (package names, where to put it, etc.)
# if you want to use it in other distros. Also, make sure that everything needed for this to work is already set up.


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
        echo "vulkaninfo not found. Did you install it?"
        return 1
    fi

    # Get available devices
    vk_devices=$(env LC_ALL=C MESA_VK_DEVICE_SELECT=list vulkaninfo 2>&1)

    # Print an error if none are found
    if [ -z "$vk_devices" ]; then
        echo "Failed to list Vulkan devices."
        return 1
    fi

    # Extract vendorID:deviceID from the output of vulkaninfo
    # If you won't change your hardware and/or do stuff like PCI passthrough, you can
    # hard-code the correct values instead of fetching them, which will speed up the functions's execution.

    # You may need to change the way this function extracts the values
    # from vk_devices if you have multiple GPUs from the same vendor.

    ### nvidia_id=$(grep -Eo "10de:[0-9a-f]{4}" <<< "$vk_devices" | head -n1) # Bash equivalent of the operation done below, kept for archival purposes.
    # The "\" in front of grep is to escape the alias. An alternative is to pass the absolute path, e.g. /bin/grep
    nvidia_id=$(echo "$vk_devices" | \grep -Eo "10de:[0-9a-f]{4}" | head -n1)
    intel_id=$(echo "$vk_devices" | \grep -Eo "8086:[0-9a-f]{4}" | head -n1)

    # Set the GPU used for Vulkan
    ## Remove and/or change the order of the vendors according to your system's
    ## configuration, in order to speed up the function's execution.
    for var in "$nvidia_id" "$intel_id"; do
        if [ -n "$var" ]; then
            export MESA_VK_DEVICE_SELECT="$var"
            echo "MESA_VK_DEVICE_SELECT set to $MESA_VK_DEVICE_SELECT"
            break
        fi
    done

    unset vk_devices nvidia_id intel_id
}
set_mesa_vk_device

# Enabling Vulkan Video support with Intel GPU
## https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_Vulkan_Video
export ANV_VIDEO_DECODE=1    # Legacy variable, not sure if it's relevant anymore, but it'll stay for now.
export ANV_DEBUG=video-decode,video-encode


# -----------------------------------------------------
# Hardware Video Acceleration - VA-API
# -----------------------------------------------------

# Function to set the LIBVA_DRIVER_NAME variable dynamically 
## https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_VA-API
# If the "libva-nvidia-driver" package isn't installed, the Nvidia GPU can't be used for VA-API.
set_vaapi_driver() {

    # This function relies on set_mesa_vk_device, as to not conflict with vfio-pci configuration
    ## https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Binding_vfio-pci_via_device_ID

    unset LIBVA_DRIVER_NAME

    case "$MESA_VK_DEVICE_SELECT" in
        10de:*)  # NVIDIA
            export LIBVA_DRIVER_NAME=nvidia
            echo "LIBVA_DRIVER_NAME set to nvidia"
            ;;
        
        8086:*)  # Intel
            export LIBVA_DRIVER_NAME=iHD
            echo "LIBVA_DRIVER_NAME set to iHD (Intel)"
            ;;

        1002:*)  # AMD
            export LIBVA_DRIVER_NAME=radeonsi
            echo "LIBVA_DRIVER_NAME set to radeonsi (AMD)"
            ;;

        *)
            echo "Unknown or unset MESA_VK_DEVICE_SELECT. LIBVA_DRIVER_NAME not set."
            ;;
    esac
}
set_vaapi_driver

# Enable MPEG4 for VA-API
## https://docs.mesa3d.org/envvars.html#va-api-environment-variables
## https://wiki.archlinux.org/title/Hardware_video_acceleration#VA-API_drivers
export VAAPI_MPEG4_ENABLED=true


# -----------------------------------------------------
# Hardware Video Acceleration - VDPAU
# -----------------------------------------------------

# Function to set the VDPAU_DRIVER variable dynamically 
## https://wiki.archlinux.org/title/Hardware_video_acceleration#Configuring_VDPAU
# If the "libvdpau-va-gl" package isn't installed, the Intel GPU can't be used for VDPAU

set_vdpau_driver() {

    # This function relies on set_mesa_vk_device, as to not conflict with vfio-pci configuration
    ## https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF#Binding_vfio-pci_via_device_ID

    unset VDPAU_DRIVER

    case "$MESA_VK_DEVICE_SELECT" in
        10de:*)  # NVIDIA
            export VDPAU_DRIVER=nvidia
            echo "VDPAU_DRIVER set to nvidia"
            ;;

        8086:*)  # Intel
            export VDPAU_DRIVER=va_gl
            echo "VDPAU_DRIVER set to va_gl (Intel)"
            ;;

        1002:*)  # AMD
            export VDPAU_DRIVER=radeonsi
            echo "VDPAU_DRIVER set to radeonsi (AMD)"
            ;;

        *)
            echo "Unknown or unset MESA_VK_DEVICE_SELECT. VDPAU_DRIVER not set."
            ;;
    esac
}
set_vdpau_driver


printf "\n"


# -----------------------------------------------------
# Hardware Acceleration
# -----------------------------------------------------
# Enable multi-threaded OpenGL rendering in Mesa
if [ -n "$MESA_VK_DEVICE_SELECT" ]; then
    export mesa_glthread=true
fi
