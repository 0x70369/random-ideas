#!/usr/bin/python
#
# Undervolts the NVIDIA GPU: locks its clock range and lifts the voltage-
# frequency curve per P-state. Any NVML error is raised, so a failure shows
# up in the service status. Adapted from the ArchWiki (originally a Reddit
# comment); check which P-states the GPU has before setting offsets.
## https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks#Undervolting_with_NVML
## https://www.reddit.com/r/linux_gaming/comments/1fm17ea/comment/n4vmb4k/

from ctypes import byref

import pynvml as nvml

GPU_INDEX = 0  # with several GPUs, try other indices

# Clock range in MHz (supported: nvidia-smi -q -d SUPPORTED_CLOCKS). The
# maximum is the boost clock of the RTX 4070 Laptop GPU:
## https://www.nvidia.com/en-us/geforce/laptops/40-series/#specs
LOCKED_CLOCKS_MHZ = (210, 2175)

# Power limit in mW (216 W = 216000), within the allowed range printed at
# start. None keeps the driver's default.
POWER_LIMIT_MW = None

# Clock offsets in MHz per P-state ({P-state: offset}). Core: the curve is
# lifted by the offset, e.g. with +300 the voltage used at 1875 MHz is used
# at 2175 MHz. Memory: twice the desired offset (2000 runs 8000 MHz memory
# at 9000 MHz); empty means no memory offsets.
OFFSETS_MHZ = {
    "core": (
        nvml.NVML_CLOCK_GRAPHICS,
        {0: 300, 3: 255, 4: 240, 5: 225, 8: 180},
    ),
    "memory": (nvml.NVML_CLOCK_MEM, {}),
}


def main() -> None:
    nvml.nvmlInit()
    try:
        gpu = nvml.nvmlDeviceGetHandleByIndex(GPU_INDEX)
        low, high = nvml.nvmlDeviceGetPowerManagementLimitConstraints(gpu)
        print(f"Allowed power limit: {low} to {high} mW")
        if POWER_LIMIT_MW is not None:
            nvml.nvmlDeviceSetPowerManagementLimit(gpu, POWER_LIMIT_MW)
            print(f"Power limit: {POWER_LIMIT_MW} mW")

        nvml.nvmlDeviceSetGpuLockedClocks(gpu, *LOCKED_CLOCKS_MHZ)
        print("Locked clocks: {} to {} MHz".format(*LOCKED_CLOCKS_MHZ))

        for name, (clock, offsets) in OFFSETS_MHZ.items():
            for pstate, mhz in offsets.items():
                offset = nvml.c_nvmlClockOffset_t()
                offset.version = nvml.nvmlClockOffset_v1
                offset.type = clock
                offset.pstate = getattr(nvml, f"NVML_PSTATE_{pstate}")
                offset.clockOffsetMHz = mhz
                nvml.nvmlDeviceSetClockOffsets(gpu, byref(offset))
                print(f"P{pstate} {name} offset: +{mhz} MHz")
    finally:
        nvml.nvmlShutdown()


if __name__ == "__main__":
    main()
