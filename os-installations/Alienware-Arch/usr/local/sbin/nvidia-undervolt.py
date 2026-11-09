#!/usr/bin/env python

# Undervolt the NVIDIA GPU: lock its clock range and lift the voltage-frequency curve per P-state.
# Adapted from https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Undervolting_with_NVML
# (originally https://www.reddit.com/r/linux_gaming/comments/1fm17ea/comment/lo7mo09).
# Check which P-states the GPU has before setting offsets:
## https://www.reddit.com/r/linux_gaming/comments/1fm17ea/comment/n4vmb4k/
# Any NVML error is raised, so a failure shows up in the service status.

from ctypes import byref

import pynvml as nvml

# The GPU to adjust. With several GPUs, try other indices.
GPU_INDEX = 0

# Clock range in MHz. Supported clocks: nvidia-smi -q -d SUPPORTED_CLOCKS
# The maximum is the boost clock from the specs of the RTX 4070 Laptop GPU:
## https://www.nvidia.com/en-us/geforce/laptops/40-series/#specs
LOCKED_CLOCKS_MHZ = (210, 2175)

# Power limit in mW (216 W = 216000), must be within the alowed range (printed in stdout). None keeps the driver's default.
POWER_LIMIT_mW = None

# Core clock offset in MHz per P-state: the voltage-frequency curve is lifted by this much,
# e.g. with +300 the voltage originally used at 1875 MHz is used at 1875 + 300 = 2175 MHz.
# {PState: Offset}
CORE_OFFSETS_MHZ = {0: 300, 3: 255, 4: 240, 5: 225, 8: 180}

# Memory clock offset per P-state. Use twice the desired offset: 2000 runs 8000 MHz memory
# at 8000 + 2000 / 2 = 9000 MHz. Empty: no memory offsets.
# {PState: Offset}
MEMORY_OFFSETS_MHZ = {}


def set_offset(gpu, clock_type, pstate, mhz):
    offset = nvml.c_nvmlClockOffset_t()
    offset.version = nvml.nvmlClockOffset_v1
    offset.type = clock_type
    offset.pstate = getattr(nvml, f"NVML_PSTATE_{pstate}")
    offset.clockOffsetMHz = mhz
    nvml.nvmlDeviceSetClockOffsets(gpu, byref(offset))


def main():
    nvml.nvmlInit()
    try:
        gpu = nvml.nvmlDeviceGetHandleByIndex(GPU_INDEX)

        min_power, max_power = nvml.nvmlDeviceGetPowerManagementLimitConstraints(gpu)
        print(f"Allowed power limit: {min_power} mW to {max_power} mW")
        if POWER_LIMIT_mW is not None:
            nvml.nvmlDeviceSetPowerManagementLimit(gpu, POWER_LIMIT_mW)
            print(f"Power limit: {POWER_LIMIT_mW} mW")

        nvml.nvmlDeviceSetGpuLockedClocks(gpu, *LOCKED_CLOCKS_MHZ)
        print(f"Locked clocks: {LOCKED_CLOCKS_MHZ[0]} to {LOCKED_CLOCKS_MHZ[1]} MHz")

        for pstate, mhz in CORE_OFFSETS_MHZ.items():
            set_offset(gpu, nvml.NVML_CLOCK_GRAPHICS, pstate, mhz)
            print(f"P{pstate} core offset: +{mhz} MHz")
        for pstate, mhz in MEMORY_OFFSETS_MHZ.items():
            set_offset(gpu, nvml.NVML_CLOCK_MEM, pstate, mhz)
            print(f"P{pstate} memory offset: +{mhz} MHz")
    finally:
        nvml.nvmlShutdown()


if __name__ == "__main__":
    main()
