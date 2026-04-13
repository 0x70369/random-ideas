#!/bin/env python


# Adapted from https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Undervolting_with_NVML
# And originally from https://www.reddit.com/r/linux_gaming/comments/1fm17ea/comment/lo7mo09


from pynvml import *
from ctypes import byref


nvmlInit()


# This sets the GPU to adjust - if this gives you errors or you have multiple GPUs, set to 1 or try other values.
myGPU = nvmlDeviceGetHandleByIndex(0)
print(f"myGPU value: {myGPU}")

# Figure out the minimum and maximum power values allowed.
min_power, max_power = nvmlDeviceGetPowerManagementLimitConstraints(myGPU)
print(f"Allowed range: {min_power} mW to {max_power} mW")

# The power limit can be set below in mW - 216W becomes 216000, etc.
# This value must be within the minimum and maximum allowed power limits.
# Remove or comment out the line below if you can't or don't want to adjust power limits.
##nvmlDeviceSetPowerManagementLimit(myGPU, 140000)

# Define the minimum and maximum clocks allowed.
# The clocks supported by your GPU can be verified with:
# nvidia-smi -q -d SUPPORTED_CLOCKS
nvmlDeviceSetGpuLockedClocks(myGPU,210,2175)
## Max clock used is from base specs for my RTX 4070 Laptop GPU:
## https://www.nvidia.com/en-us/geforce/laptops/40-series/#specs


# NOTE: Before configuring the next sections, you should check which P-States your GPU has
## https://www.reddit.com/r/linux_gaming/comments/1fm17ea/comment/n4vmb4k/

####################################
# ============ P0 State ============
####################################

# ============ Memory ============
# Uncomment and edit this section if desired.
# Note: The memory clock offset should be **multiplied by 2**.
# E.g. a desired offset of 500 means inserting
# a value of 1000 in the clockOffsetMHz line.
##infoMemP0 = c_nvmlClockOffset_t()
##infoMemP0.version = nvmlClockOffset_v1
##infoMemP0.type = NVML_CLOCK_MEM
##infoMemP0.pstate = NVML_PSTATE_0
##infoMemP0.clockOffsetMHz = 2000
### This offset is simply how much faster your memory will run.
### E.g. instead of running at 8000 MHz, the memory
### will run at 8000 + (2000 / 2) = 9000 MHz.

##nvmlDeviceSetClockOffsets(myGPU, byref(infoMemP0))


# ============ Core =============
infoCoreP0 = c_nvmlClockOffset_t()
infoCoreP0.version = nvmlClockOffset_v1
infoCoreP0.type = NVML_CLOCK_GRAPHICS
infoCoreP0.pstate = NVML_PSTATE_0
infoCoreP0.clockOffsetMHz = 300
## What this offset means is: The frequency-voltage
## curve is lifted up by 300 MHz.
## E.g. the voltage value originally assigned to 1875 MHz
## will now be used at 1875 + 300 = 2175 MHz.

nvmlDeviceSetClockOffsets(myGPU, byref(infoCoreP0))


####################################
# ============ P3 State ============
####################################

# ============ Memory ============
##infoMemP3 = c_nvmlClockOffset_t()
##infoMemP3.version = nvmlClockOffset_v1
##infoMemP3.type = NVML_CLOCK_MEM
##infoMemP3.pstate = NVML_PSTATE_3
##infoMemP3.clockOffsetMHz = 2000

##nvmlDeviceSetClockOffsets(myGPU, byref(infoMemP3))


# ============ Core =============
infoCoreP3 = c_nvmlClockOffset_t()
infoCoreP3.version = nvmlClockOffset_v1
infoCoreP3.type = NVML_CLOCK_GRAPHICS
infoCoreP3.pstate = NVML_PSTATE_3
infoCoreP3.clockOffsetMHz = 255

nvmlDeviceSetClockOffsets(myGPU, byref(infoCoreP3))


####################################
# ============ P4 State ============
####################################

# ============ Memory ============
##infoMemP4 = c_nvmlClockOffset_t()
##infoMemP4.version = nvmlClockOffset_v1
##infoMemP4.type = NVML_CLOCK_MEM
##infoMemP4.pstate = NVML_PSTATE_4
##infoMemP4.clockOffsetMHz = 2000

##nvmlDeviceSetClockOffsets(myGPU, byref(infoMemP4))


# ============ Core =============
infoCoreP4 = c_nvmlClockOffset_t()
infoCoreP4.version = nvmlClockOffset_v1
infoCoreP4.type = NVML_CLOCK_GRAPHICS
infoCoreP4.pstate = NVML_PSTATE_4
infoCoreP4.clockOffsetMHz = 240

nvmlDeviceSetClockOffsets(myGPU, byref(infoCoreP4))


####################################
# ============ P5 State ============
####################################

# ============ Memory ============
##infoMemP5 = c_nvmlClockOffset_t()
##infoMemP5.version = nvmlClockOffset_v1
##infoMemP5.type = NVML_CLOCK_MEM
##infoMemP5.pstate = NVML_PSTATE_5
##infoMemP5.clockOffsetMHz = 2000

##nvmlDeviceSetClockOffsets(myGPU, byref(infoMemP5))


# ============ Core =============
infoCoreP5 = c_nvmlClockOffset_t()
infoCoreP5.version = nvmlClockOffset_v1
infoCoreP5.type = NVML_CLOCK_GRAPHICS
infoCoreP5.pstate = NVML_PSTATE_5
infoCoreP5.clockOffsetMHz = 225

nvmlDeviceSetClockOffsets(myGPU, byref(infoCoreP5))


####################################
# ============ P8 State ============
####################################

# ============ Memory ============
##infoMemP8 = c_nvmlClockOffset_t()
##infoMemP8.version = nvmlClockOffset_v1
##infoMemP8.type = NVML_CLOCK_MEM
##infoMemP8.pstate = NVML_PSTATE_8
##infoMemP8.clockOffsetMHz = 2000

##nvmlDeviceSetClockOffsets(myGPU, byref(infoMemP8))


# ============ Core =============
infoCoreP8 = c_nvmlClockOffset_t()
infoCoreP8.version = nvmlClockOffset_v1
infoCoreP8.type = NVML_CLOCK_GRAPHICS
infoCoreP8.pstate = NVML_PSTATE_8
infoCoreP8.clockOffsetMHz = 180

nvmlDeviceSetClockOffsets(myGPU, byref(infoCoreP8))


nvmlShutdown()
