# Alienware m16 R1 — Hardware, uses and kernel configuration requirements

Document last updated: 2026-11-13

This document describes the system as it should be (Arch Linux reinstalled with the repository's scripts, and the `linux-tkg` kernel built with the `alienware.myfrag` fragment). The fragment's comments cite the section numbers used here.

## 0. Ground rules

- The kernel configured here will be used only on this laptop. It will not be used on other computers, nor in VM guests on this laptop.
- When in doubt, always check the official online documentation of the projects, programs and applications the user uses.
- Keep the debugging infrastructure that could realistically be used with this kernel. Whatever the Kconfig says is not worth it must be removed.
- The official Kconfig is the highest authority and must always be checked. If the user wants something that goes against the Kconfig's recommendation, point it out and let the user choose.
- Maximum performance and efficiency are this kernel's goal, but never at the cost of the system's security.
- Every security lever in the Kconfig stays on, except those the Kconfig says to leave at N when in doubt ("If unsure, say N" or equivalent) and those that would break a declared use (the cases are in 33.5).
- Whatever covers hardware this laptop doesn't have must be removed.
- Everything that can be built as a module should be, unless it is essential to boot the system or extremely common (such as support for scripts with #!).
- If the user modularizes something that shouldn't be, explain why and let them choose.
- Everything in use on the laptop must be kept: a driver bound to a device, a loaded module, or an interface some program uses. The only declared exception is the Micron SSD (see 8). Modules that load only because another option in the configuration requires them, with no device on this laptop, don't count as in use.
- If the Kconfig shows that an option to be disabled is selected by another one that stays on ("Selected by"), respect the dependency and tell the user.

## 1. General identification

- Model: Alienware m16 R1 (Dell / Alienware), SKU / Platform ID 0BFB
- Motherboard: Dell 00DK46, rev. A00
- Service Tag: 80S9K34
- BIOS 1.36.0 (2026-10-22), installed on 2026-11-11 in place of 1.34.0. The hidden menu is byte-for-byte identical to 1.34.0's; what changes is the Intel ME (16.1.40.2765 → 16.1.42.2872), the EC package (1.15.0 → 1.16.0), the BIOS Connect network drivers and security modules (cryptography, TPM, variables and Dell's WMI). The embedded microcode is still 0x133
- System: Arch Linux with KDE Plasma
- Boot: `systemd-boot` with UKIs, through shim (18)
- Kernels: `linux-tkg` (the custom one) and, as fallbacks, `linux` and `linux-zen`, all with the `nvidia` (615.78.08) and `looking-glass` (B7) DKMS modules

## 1A. Firmware: settings that affect the kernel

Changed by the user in the hidden menu (Smokeless UMAF) or checked at their defaults. See Section 7 of the wiki page for paths and offsets.

A firmware reset (loading the defaults) returns every changed setting below to Dell's value, and a BIOS update returns some of them: after either one, check the whole list (section 7 of the wiki works as a checklist). The 2026-11-12 reset undid all of them, and they were set again.

**Changed:**

- ACPI S3 Support: Enabled (Dell ships Disabled) → S3 sleep (`deep`) exists and is used
- UnderVolt Protection: Disabled and OverClocking Feature: Enabled → allow `intel-undervolt`'s MSR undervolt
- Legacy Game Compatibility Mode: Enabled → Scroll Lock toggles the E-cores' standby; also enables the PS/2 keyboard/mouse in Platform Settings
- WDT Enable: Enabled (the OC watchdog, used by XTU on Windows)
- BIST: Enabled (CPU self-test on every reset)
- REFRESH_2X_MODE: Enabled for WARM or HOT (the RAM refresh rate doubles when it gets hot)
- Native ASPM (ACPI Settings, `Setup` offset `0x12`): Enabled (Dell ships Disabled) → the firmware hands ASPM control to the kernel through `_OSC`, and the tuned profiles' policies (32A.5) take effect
- D3 Setting for Storage (ACPI Settings, `Setup` offset `0xAB2`): D3Cold (Dell ships D3Hot) → in s2idle, the NVMe can lose power completely; no effect with S3
- EC CS Debug Light (ACPI Settings, `Setup` offset `0x32`; default Disabled): Enabled → the Caps Lock light turns on when the EC enters its power-saving mode. So the Caps Lock light alone can't tell whether the system froze or the key is on
- Advanced Error Reporting on PCI Express Root Port 25 (Thunderbolt, `PchSetup` offset `0x283`): Enabled (Dell ships Disabled) → PCIe errors on the Thunderbolt link are reported to the kernel
- Tcc Offset Lock Enable: Enabled (1.36.0 came with Disabled)
- RFI Mitigation (Connectivity Configuration, `PchSetup` offset `0x738`): Enabled (Dell ships Disabled) → `iwlwifi` can ask the memory controller for a small shift in the DDR frequency when it interferes with the Wi-Fi channel in use
- Disable Fast PKG C State Ramp for IA Domain and for GT Domain (Power & Performance > CPU VR Settings > Acoustic Noise Settings, `CpuSetup` offsets `0x1FD` and `0x1FE`): TRUE (default FALSE) → the voltage regulators ramp up slowly when leaving the package's deep idle states, against coil whine
- Config TDP (Power & Performance): Nominal (the boot level) with PL1 55 W and PL2 86 W, the same as `alienware-balanced` (Dell ships 165/165 W); Level 1 with 157/157 W; Level 2 undefined. On Linux, the tuned profiles rewrite the limits (32A.4)
- Thermal Device (B0:D4:F0) (System Agent (SA) Configuration, `SaSetup` offset `0x7C`): Enabled (default Disabled) → exposes `00:04.0` (`proc_thermal_pci`) and with it `intel-rapl-mmio`, which tuned writes to; without it, the firmware's MMIO limit would cap the CPU
- Cpu CrashLog (Device 10) (System Agent (SA) Configuration, `SaSetup` offset `0xF6`): Enabled (default Disabled) → a record of the CPU's state on severe hardware errors, which survives a reboot (32A.16)
- L1 Substates on PCI Express Root Port 25 (Thunderbolt, `PchSetup` offset `0x2D7`): L1.1 & L1.2 (Dell ships Disabled) → the Thunderbolt link can enter L1.1/L1.2, which the kernel only uses with the `powersupersave` ASPM policy (7)
- Firmware Configuration (`Setup` offset `0xA`): Production (default Test)
- Skip Power Check (Platform Settings > System Firmware Update Config, `Setup` offset `0x83B`): Disabled (Dell ships Enabled) → the firmware checks the charger and the battery charge before updating itself
- Boot performance mode (`CpuSetup` offset `0x13`): Max Battery (default Turbo Performance) → the CPU stays at its minimum frequency from power-on until `intel_pstate` takes over; less heat and current during POST, slightly slower boot
- Thermal Velocity Boost Down Bins (`CpuSetup` offsets `0x34E` and `0x351`): 2 above 70 °C and 4 above 100 °C (default 1 and 2) → the maximum ratio drops to 52x and 50x when the CPU gets hot
- Turbo ratio limits: a single range, 54x for up to 8 P-cores and 39x for up to 16 E-cores (there used to be 4 identical ranges of each)
- EFI Network (PCH-IO Configuration, `Setup` offset `0x49`): Disabled (Dell ships Onboard NIC & WiFi) → no network stack in the firmware; no network boot or BIOS Connect, and fwupd still updates the firmware
- LPM S0i2.1 (`PchSetup` offset `0x14`): Enabled (Dell ships Disabled); only affects s2idle, no effect with S3
- Power Limit 2: 157 W (the option is hidden in 1.36.0's setup; on Linux, tuned sets PL2); maximum ratio 54x on the P-cores and 39x on the E-cores (clusters); BCLK 100.00 MHz; iGPU up to 1650 MHz; IccMax 215 A (IA) and 30 A (GT)

**Kept at their defaults because the system depends on them:**

- VMX and VT-d: Enabled (KVM and passthrough)
- Above 4GB MMIO and Resizable BAR (Auto): required by `NVreg_EnableResizableBar=1`
- ACS on every root port: Enabled → the dGPU sits in its own IOMMU group without the ACS override patch
- Advanced Error Reporting on every root port (`SaSetup` from `0x341`, `PchSetup` from `0x26B`, one byte per port): Enabled → the kernel receives each link's PCIe errors. Root Port 25 was the only one Dell shipped with it off
- ACPI D3Cold Support: Enabled → required for the dGPU to power off completely (RTD3)
- DeepSx Power Policies (`PchSetup` offset `0x4`): Disabled. `Enabled in S4-S5` made the firmware reset itself when powering on from S5 on AC (2026-11-13)
- L1 Substates on the PCH root ports in use, 3 (Ethernet), 13 (Micron), 18 (SD reader) and 21 (ADATA) (`PchSetup` offsets `0x2C1`, `0x2CB`, `0x2D0` and `0x2D3`): L1.1 & L1.2 → the links can enter L1.1/L1.2, which the kernel only uses with the `powersupersave` policy (32A.5); on the Ethernet link, `r8169` keeps ASPM off (6)
- Restore Setup Default (Platform Settings > System Firmware Update Config, `Setup` offset `0x83A`): Disabled → a firmware update doesn't restore every default
- DTBT RTD3 CLKREQ Delay value (ACPI D3Cold settings, `Setup` offset `0x985`): 0 ms. Wait after changing CLKREQ when powering the Thunderbolt controller back on; 200 ms is the value to try if the failure in 7 comes back
- Package Power Limit MSR Lock: Disabled → `tuned` can write the RAPL limits at runtime
- Tcc Activation Offset: 0, with the Tcc Offset Lock (above) → throttling starts at the 100 °C Tjmax, and `intel-undervolt`'s `tjoffset` is ignored
- PROCHOT Lock (`CpuSetup` offset `0x7D`) and Bi-directional PROCHOT#: Enabled → the CPU slows down when the EC signals that another part (GPU, regulators) is overheating, and the system can't turn that response off through the MSR
- Platform Debug Consent (`SiSetup` offset `0x1`): Disabled → no Intel DCI or Trace Hub (CPU debugging over USB, below the system and Secure Boot)
- Intel Dynamic Tuning Technology, INT3400 Device and Processor Thermal Device (SA Thermal Device): Enabled → `int3400 thermal`, `proc_thermal_pci` and the `int3403` sensors (22); Charger, Power and Battery Participant off
- Enable TCO Timer (`PchSetup` offset `0x11`): Disabled → no WDAT table and no chipset ACPI timer; `iTCO_wdt` works anyway (20)
- System Time and Alarm Source: ACPI Time and Alarm Device, with the legacy RTC also present → `acpi-tad` and `rtc_cmos` (`/dev/rtc0`, used to wake up at a set time)
- HID Event Filter Driver: Enabled → `INTC1070` (`intel-hid`)
- Pseudo G3: Enabled (Intel's default is Disabled) and Charging Method: Normal Charging → when off and on battery, the EC cuts almost all power; charging without the fast mode, which wears the battery more (30)

**In Dell's F2 menu:**

- Hybrid Graphics: enabled (without it the dGPU drives every display and never powers off)
- Discrete Graphics Controller Direct Output Mode: enabled (for the lowest latency between the dGPU and external monitors); with an external monitor connected, the dGPU stays awake

## 1B. Kernel command line

Assembled from `/etc/cmdline.d/` and embedded in the UKI; it applies to all three kernels. One file per line:

```text
root.conf          root=/dev/mapper/root rootfstype=btrfs rootflags=subvol=/Arch/@
sd-encrypt.conf    rd.luks.name=<LUKS UUID>=root rd.luks.options=password-echo=no,tries=2,timeout=60s
hibernation.conf   hibernate.compressor=lz4
zswap.conf         zswap.enabled=1 zswap.shrinker_enabled=1 zswap.compressor=zstd zswap.max_pool_percent=23 zswap.accept_threshold_percent=90
iommu.conf         intel_iommu=on
audio.conf         threadirqs
pstore.conf        efi_pstore.pstore_disable=0
miscellaneous.conf loglevel=7
```

- hibernation without `resume=`: when hibernating, systemd writes the swapfile's device and offset (also computed for btrfs) to the `HibernateLocation` EFI variable, and the initramfs's `systemd-hibernate-resume-generator` reads it and resumes after `sd-encrypt` opens the root. Recreating the swapfile requires no change. Requires efivarfs in the initramfs (`EFIVAR_FS=y`, 33.3)
- `hibernate.compressor=lz4`: lz4 decompresses faster than the default lzo. In `linux-tkg` lz4 is already the default (`HIBERNATION_COMP_LZ4`), and the parameter only has an effect on `linux` and `linux-zen`
- zswap: zstd compressor (higher compression ratio; memory use is high with the VM and the tmpfs build) and a 23% pool. 7.2 no longer offers a zpool choice (zsmalloc is the only allocator). In `linux-tkg` zswap is already on and uses zstd by default
- `intel_iommu=on`: turns on the IOMMU (two units, `dmar0` and `dmar1`, 39-bit addresses). Redundant in `linux-tkg` (`INTEL_IOMMU_DEFAULT_ON=y`)
- `threadirqs`: threaded interrupt handlers, for low-latency audio
- `efi_pstore.pstore_disable=0`: turns on pstore's EFI backend in `linux` and `linux-zen`, whose configuration disables it by default; redundant in `linux-tkg`
- related sysctl: `kernel.sysrq = 1` (`/etc/sysctl.d/sysrq.conf`, see 33.6)

## 2. CPU and platform

- CPU: Intel Core i9-13900HX (Raptor Lake-HX), 24 cores / 32 threads: 8 P-cores with SMT and 16 E-cores
- `NR_CPUS`=32
- Addressing: 39 physical bits, 48 virtual bits (no `la57`: 5-level paging has no use here)
- Microcode 0x137, loaded early by the `intel-ucode` package (`mkinitcpio`'s `microcode` hook), newer than the 0x133 embedded in the BIOS
- No Total Memory Encryption (no `tme` flag)
- No SGX, TDX or RDT/resctrl (no `sgx`, `rdt_a`, `cat_l2`, `cat_l3`, `cqm_llc` or `mba` flags): `X86_SGX`, `INTEL_TDX_HOST` and `X86_CPU_RESCTRL` go
- `intel_pstate` in `active` mode, with `hwp` and `hwp_epp`: Turbo Boost Max 3.0 (`INTEL_TURBO_MAX_3`), which only matters without HWP, goes

**Relevant `/proc/cpuinfo` flags:**

`vmx ept ept_ad vnmi x2apic tsc_deadline_timer hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req hfi ibt user_shstk split_lock_detect intel_pt arch_lbr pku ospke umip waitpkg avx2 avx_vnni sha_ni gfni vaes vpclmulqdq movdiri movdir64b serialize fsrm clwb rdpid md_clear flush_l1d arch_capabilities ibrs_enhanced`

- `ibt` and `user_shstk`: CET available (IBT in the kernel, shadow stack for userspace)
- `hwp*` and `hfi`: Intel P-state with HWP/EPP and Intel HFI
- There is no AVX-512.

**Vulnerabilities the kernel reports (`bugs`):**

`spectre_v1 spectre_v2 spec_store_bypass swapgs eibrs_pbrsb rfds bhi spectre_v2_user vmscape`

Their mitigations stay (security above performance). Those not on the list don't affect this CPU.

Several kernel drivers cover Raptor Lake HX under names that still say Alder Lake (for example, `PINCTRL_ALDERLAKE`, `SND_SOC_SOF_ALDERLAKE` and the `adls` DMC firmware).

### ACPI devices

Only the present ones (`status` other than 0). The ACPI table also describes several absent devices, which don't count.

- Platform: `PNP0C09` (EC), `PNP0C14` (12 WMI blocks), `PNP0C0A` (battery), `ACPI0003` (AC), `PNP0C0D` (lid), `PNP0C0E` (sleep button), `ACPI000C` (processor aggregator), `ACPI000E` (time and alarm, `acpi-tad`), `PNP0B00` (RTC), `PNP0103` (HPET), `PNP0A08` (PCIe root), `PNP0C02` (motherboard resources)
- Processors: 64 `ACPI0007` objects for 32 threads (the firmware declares extra objects)
- Intel: `INTC1085` (Raptor Lake pinctrl, `alderlake-pinctrl`), `INTC1070` (`intel-hid`), `INTC6001` (TPM CRB, `tpm_crb_acpi`), `INT33A1` (PEP, `intel_pmc_core`)
- DPTF: `INTC10A0` (`int3400 thermal`) and six `INTC1046` participants (`int3403 thermal`)
- Dell: `DLLK0BFB` (PS/2 keyboard, `i8042 kbd`) and `DLL0BFB` (PS/2 auxiliary port, `i8042 aux`)
- Touchpad: `VEN_06CB` (Synaptics), `i2c_hid_acpi`
- USB-C: `USBC000` (UCSI, `ucsi_acpi`)
- No driver bound even in Arch's kernel, which has almost every driver, so they require nothing: `INT340E`, `INTC109C`, `NVDA0820` (the NVIDIA driver can use it through ACPI methods without binding to it) and `PRP00001` (2 instances). `PNP0000`, `PNP0100`, `PNP0103`, `PNP0A08` and `PNP0C02` are handled by the kernel core.
- Absent, so unused: the MIPI camera sensors (`OVTI01AS`, `INT33BE`, `SONY362A`, `SONY488A`) and the camera devices `INT3471`/`INT3472`/`INT3474` (the real webcam is USB, so IPU and MIPI sensor drivers stay out); the Microchip power monitors `MCHP1930`/`MCHP1940` (PAC193x/PAC194x); `DELL0029`, `DELL0033`, `DELLABC6`, `TXNW3643`, `INT3420`, `INT33E1`, `INT3519`, `INT3533`, `INTC1001`, `INTC1092`, `INTC10A3`; and `PNP0C0C` (the power button uses the ACPI fixed event)

### Platform drivers in use

`ac`, `acpi-battery`, `acpi-button`, `acpi-ec`, `acpi-tad`, `acpi-wmi`, `alarmtimer`, `alderlake-pinctrl`, `dell-smbios`, `dmic-codec`, `hid_sensor_custom`, `i2c_designware`, `i8042`, `idma64`, `int3400 thermal`, `int3403 thermal`, `intel-hid`, `intel_pmc_core`, `intel_rapl_msr`, `iTCO_wdt`, `pcspkr`, `processor_aggregator`, `rtc_cmos`, `rtsx_pci_sdmmc`, `skl_hda_dsp_generic`, `tpm_crb_acpi`, `ucsi_acpi`

- `pcspkr` (the PC speaker beep) is bound, so it stays
- the laptop has no UART at all (no `PNP0501`, no `ttySN ... is a 16550A` in dmesg): `SERIAL_8250` goes; the USB serial adapters (13) don't depend on it
- `dcdbas` isn't a platform driver, but `dell_smbios` uses it (SMM backend)
- `efi-framebuffer`/`simple-framebuffer` disappear when `i915` takes over the display, but are needed early in boot (33.3)
- `coretemp` isn't a platform driver, but it is in use (23)

### Modules in use

Collected with `lsmod` on Arch's kernel and gathered in `modprobed.db` (31). All of them stay, except those on the "Disable" list below. Grouped:

- CPU, power and telemetry: `coretemp`, `intel_cstate`, `intel_uncore`, `intel_uncore_frequency`, `rapl`, `intel_rapl_msr`, `intel_rapl_common`, `x86_pkg_temp_thermal`, `intel_powerclamp`, `intel_tcc_cooling`, `acpi_pad`, `intel_pmc_core`, `intel_pmc_ssram_telemetry`, `intel_pmc_pwrm_telemetry`, `intel_vsec`, `pmt_telemetry`, `pmt_discovery`, `pmt_class`
- DPTF: `int3400_thermal`, `int3403_thermal`, `int340x_thermal_zone`, `acpi_thermal_rel`, `processor_thermal_device_pci` and its submodules (`rapl`, `rfim`, `mbox`, `power_floor`, `wt_hint`, `wt_req`, `soc_slider`, `platform_temperature_control`)
- Dell/Alienware/WMI: `wmi`, `wmi_bmof`, `alienware_wmi`, `dell_wmi`, `dell_wmi_descriptor`, `dell_wmi_ddv`, `dell_wmi_sysman`, `dell_smbios`, `dcdbas`, `dell_smm_hwmon`, `nvidia_wmi_ec_backlight`, `intel_hid`, `sparse_keymap`, `video`
- Graphics: `i915`, `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm`, `drm_display_helper`, `ttm`, `cec`, `i2c_algo_bit`
- Audio: `snd_sof_pci_intel_tgl` and the SOF stack, `snd_soc_skl_hda_dsp`, `snd_hda_intel`, `snd_hda_codec_alc269`, `snd_hda_codec_intelhdmi`, `snd_hda_codec_nvhdmi`, `snd_seq`, `snd_seq_dummy`, `snd_hrtimer`, `snd_ctl_led`
- Network: `iwlmvm`, `iwlwifi`, `mac80211`, `cfg80211`, `r8169`, `realtek`, `ax88179_178a`, `usbnet`, `mii`, `ptp`
- Bluetooth: `btusb`, `btintel`, `bluetooth`, `bnep`, `rfcomm`
- Netfilter (firewalld): `nf_tables`, `nft_ct`, `nft_fib_inet`/`ipv4`/`ipv6`, `nft_reject_inet`/`ipv4`, `nft_masq`, `nft_chain_nat`, `nf_conntrack` with the `ftp`, `tftp`, `irc`, `sip`, `h323`, `pptp`, `sane` and `netbios_ns` helpers and the matching `nf_nat` ones
- Storage: `nvme`, `nvme_core`, `dm_crypt`, `dm_integrity`, `dm_mod`, `trusted`, `encrypted_keys`, `uas`, `usb_storage`, `sg`, `vfat`, `fat`, `rtsx_pci`, `rtsx_pci_sdmmc`, `mmc_core`, `mmc_block`
- SPI flash: `spi_intel_pci`, `spi_intel`, `spi_nor`, `mtd` (27)
- Cryptography: `aesni_intel`, `gf128mul`, `ccm`, `af_alg`, `algif_hash`, `algif_skcipher`, `crypto_user`
- Virtualization: `kvm_intel`, `kvm`, `irqbypass`, `vfio_pci`, `vfio_pci_core`, `vfio_iommu_type1`, `vfio`, `iommufd`
- Input and sensors: `i2c_hid_acpi`, `i2c_hid`, `hid_multitouch`, `intel_ish_ipc`, `intel_ishtp`, `intel_ishtp_hid`, `hid_sensor_hub`, `hid_sensor_custom`, `psmouse`, `serio_raw`, `mousedev`, `joydev`, `mac_hid`, `pcspkr`
- I2C/SMBus: `i2c_i801`, `i2c_smbus`, `i2c_mux`, `i2c_dev`, `intel_lpss_pci`, `intel_lpss`, `idma64`, `spd5118`
- Webcam: `uvcvideo`, `videodev`, `videobuf2_*`, `mc`
- USB-C/Thunderbolt: `thunderbolt`, `typec`, `typec_ucsi`, `ucsi_acpi`, `roles`
- Other: `mei_me`, `mei_hdcp`, `mei_pxp`, `iTCO_wdt`, `intel_pmc_bxt`, `pinctrl_alderlake`, `acpi_tad`

Declared uses that don't show up in `lsmod` all the time (VPN/TUN, WireGuard, libvirt's bridge and `vhost_net`, `uinput`, controllers, USB serial, USB MIDI and others) still count.

**Disable** (they load on Arch's kernel only because the configuration pulls them in, with no hardware on this laptop):

- `BT_HCIBTUSB_RTL`, `BT_HCIBTUSB_BCM` and `BT_HCIBTUSB_MTK` (and with them `btrtl`, `btbcm` and `btmtk`): the internal Bluetooth is Intel (`btintel`); they would only be missed with an external USB adapter from those brands
- `DRM_XE` (and with it `drm_gpusvm_helper`, `drm_gpuvm`, `gpu_sched`): the Raptor Lake iGPU is served by `i915`; on it `xe` only works when forced (`force_probe`). `nvidia-uvm`'s HMM goes with it (4)
- `DRM_NOUVEAU`: the dGPU uses the `nvidia` driver (`nvidia-utils` blacklists `nouveau`)
- `SND_SOC_INTEL_AVS`: an alternative Intel DSP driver; audio uses SOF
- `SND_SOC_SOF_INTEL_SOUNDWIRE` and `SOUNDWIRE` (and with them `soundwire_intel`, `soundwire_cadence`, `soundwire_bus`): there is no SoundWire device; nothing that stays on selects `SOUNDWIRE`, and SOF, HDA and SDCA keep working
- `NVME_HOST_AUTH` (`nvme_auth`, `nvme_keyring`: NVMe over Fabrics authentication), `TRUSTED_KEYS_TEE`/`TEE` (trusted keys use only the TPM), `MACVLAN`/`MACVTAP` (`tap`; the VMs use a bridge and `tun`, 16)

### Full PCI listing

The listing below is the reference for IDs and drivers; the following sections only cite each device's address. The "Kernel modules" line lists Arch's kernel candidates, including those that go (`xe`, `nouveau`, `snd_soc_avs`, `ie31200_edac`, `shpchp`).

```console
$ lspci -PPknnQ
00:00.0 Host bridge [0600]: Intel Corporation Device [8086:a702] (rev 01)
	Subsystem: Dell Device [1028:0bfb]
	Kernel modules: ie31200_edac
00:01.0 PCI bridge [0604]: Intel Corporation Raptor Lake PCI Express 5.0 Graphics Port (PEG010) [8086:a70d] (rev 01)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:02.0 VGA compatible controller [0300]: Intel Corporation Raptor Lake-S UHD Graphics [8086:a788] (rev 04)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: i915
	Kernel modules: i915, xe
00:04.0 Signal processing controller [1180]: Intel Corporation Raptor Lake Dynamic Platform and Thermal Framework Processor Participant [8086:a71d] (rev 01)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: proc_thermal_pci
	Kernel modules: processor_thermal_device_pci
00:08.0 System peripheral [0880]: Intel Corporation GNA Scoring Accelerator module [8086:a74f] (rev 01)
	Subsystem: Dell Device [1028:0bfb]
00:12.0 Serial controller [0700]: Intel Corporation 700 Series Chipset Family Integrated Sensor Hub [8086:7a78] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: intel_ish_ipc
	Kernel modules: intel_ish_ipc
00:14.0 USB controller [0c03]: Intel Corporation 700 Series Chipset Family USB 3.2 Gen 2x2 (20 Gbs) xHCI Host Controller [8086:7a60] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: xhci_hcd
	Kernel modules: mei_me
00:14.2 RAM memory [0500]: Intel Corporation 700 Series Chipset Family Shared SRAM [8086:7a27] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
00:14.3 Network controller [0280]: Intel Corporation 700 Series Chipset Family CNVi Wi-Fi [8086:7a70] (rev 11)
	Subsystem: Rivet Networks Device [1a56:1672]
	Kernel driver in use: iwlwifi
	Kernel modules: iwlwifi
00:15.0 Serial bus controller [0c80]: Intel Corporation 700 Series Chipset Family I2C Controller #0 [8086:7a4c] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: intel-lpss
	Kernel modules: intel_lpss_pci
00:15.1 Serial bus controller [0c80]: Intel Corporation 700 Series Chipset Family I2C Controller #1 [8086:7a4d] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: intel-lpss
	Kernel modules: intel_lpss_pci
00:16.0 Communication controller [0780]: Intel Corporation 700 Series Chipset Family CSME HECI #1 [8086:7a68] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: mei_me
	Kernel modules: mei_me
00:1a.0 PCI bridge [0604]: Intel Corporation 700 Series Chipset Family PCIe Root Port #25 [8086:7a48] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1b.0 PCI bridge [0604]: Intel Corporation 700 Series Chipset Family PCIe Root Port #18 [8086:7a41] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1b.4 PCI bridge [0604]: Intel Corporation 700 Series Chipset Family PCIe Root Port #21 [8086:7a44] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1c.0 PCI bridge [0604]: Intel Corporation 700 Series Chipset Family PCIe Root Port #3 [8086:7a3a] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1d.0 PCI bridge [0604]: Intel Corporation 700 Series Chipset Family PCIe Root Port #13 [8086:7a34] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1f.0 ISA bridge [0601]: Intel Corporation HM770 Chipset eSPI Controller [8086:7a0c] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
00:1f.3 Multimedia audio controller [0401]: Intel Corporation 700 Series Chipset Family HD Audio [8086:7a50] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: sof-audio-pci-intel-tgl
	Kernel modules: snd_soc_avs, snd_sof_pci_intel_tgl, snd_hda_intel
00:1f.4 SMBus [0c05]: Intel Corporation 700 Series Chipset Family SMBus [8086:7a23] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: i801_smbus
	Kernel modules: i2c_i801
00:1f.5 Serial bus controller [0c80]: Intel Corporation 700 Series Chipset Family SPI (flash) Controller [8086:7a24] (rev 11)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: intel-spi
	Kernel modules: spi_intel_pci
00:01.0/01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD106M [GeForce RTX 4070 Max-Q / Mobile] [10de:2860] (rev a1)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: nvidia
	Kernel modules: nouveau, nvidia_drm, nvidia
00:01.0/01:00.1 Audio device [0403]: NVIDIA Corporation AD106M High Definition Audio Controller [10de:22bd] (rev a1)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: snd_hda_intel
	Kernel modules: snd_hda_intel
00:1a.0/02:00.0 PCI bridge [0604]: Intel Corporation Thunderbolt 4 Bridge [Maple Ridge 4C 2020] [8086:1136] (rev 02)
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1a.0/02:00.0/03:00.0 PCI bridge [0604]: Intel Corporation Thunderbolt 4 Bridge [Maple Ridge 4C 2020] [8086:1136] (rev 02)
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1a.0/02:00.0/03:01.0 PCI bridge [0604]: Intel Corporation Thunderbolt 4 Bridge [Maple Ridge 4C 2020] [8086:1136] (rev 02)
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1a.0/02:00.0/03:02.0 PCI bridge [0604]: Intel Corporation Thunderbolt 4 Bridge [Maple Ridge 4C 2020] [8086:1136] (rev 02)
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1a.0/02:00.0/03:03.0 PCI bridge [0604]: Intel Corporation Thunderbolt 4 Bridge [Maple Ridge 4C 2020] [8086:1136] (rev 02)
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: pcieport
	Kernel modules: shpchp
00:1a.0/02:00.0/03:00.0/04:00.0 USB controller [0c03]: Intel Corporation Thunderbolt 4 NHI [Maple Ridge 4C 2020] [8086:1137]
	Subsystem: Intel Corporation Device [8086:0000]
	Kernel driver in use: thunderbolt
	Kernel modules: thunderbolt
00:1a.0/02:00.0/03:02.0/38:00.0 USB controller [0c03]: Intel Corporation Thunderbolt 4 USB Controller [Maple Ridge 4C 2020] [8086:1138]
	Kernel driver in use: xhci_hcd
	Kernel modules: xhci_pci
00:1b.0/6c:00.0 Unassigned class [ff00]: Realtek Semiconductor Co., Ltd. RTS525A PCI Express Card Reader [10ec:525a] (rev 01)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: rtsx_pci
	Kernel modules: rtsx_pci
00:1b.4/6d:00.0 Non-Volatile memory controller [0108]: ADATA Technology Co., Ltd. XPG GAMMIXS1 1L, XPG GAMMIX S5, LEGEND 710 / 740, SWORDFISH NVMe SSD (DRAM-less) [1cc1:5766] (rev 01)
	Subsystem: ADATA Technology Co., Ltd. XPG GAMMIXS1 1L, XPG GAMMIX S5, LEGEND 710 / 740, SWORDFISH NVMe SSD (DRAM-less) [1cc1:5766]
	Kernel driver in use: nvme
	Kernel modules: nvme
00:1c.0/6e:00.0 Ethernet controller [0200]: Realtek Semiconductor Co., Ltd. Killer E3000 2.5GbE Controller [10ec:3000] (rev 06)
	Subsystem: Dell Device [1028:0bfb]
	Kernel driver in use: r8169
	Kernel modules: r8169
```

## 3. Memory

- 32 GB DDR5: 2 × 16 GB SK hynix `HMCG78AGBSA095N` (JEDEC code `80AD`), DDR5-5600, running at 5600 MT/s
- Non-ECC modules: `ie31200_edac` (the host bridge's candidate) has nothing to report and goes
- Double refresh when the RAM gets hot, set in the firmware (REFRESH_2X_MODE)
- The kernel is compiled in tmpfs (`/tmp/kernel-build`, 42 GiB), so RAM/swap matter to the build workflow

## 4. GPUs

### Intel iGPU

- `00:02.0` [8086:a788], `i915` driver
- The system's default GPU

### Internal display

- `eDP-1`, 2560×1600, with 60.01 Hz and 240.02 Hz modes (the preferred one); 1.25 scaling in Plasma
- no VRR, HDR or wide color gamut (KScreen: "incapable")
- no PSR (Panel Self Refresh): debugfs's `i915_edp_psr_status` and `eDP-1/i915_psr_sink_status` answer "No such device", which `i915` does when the panel doesn't declare PSR support. Without PSR, the iGPU reads the framebuffer and sends a picture to the panel every frame, even when the screen is still, which limits the package's idle states (32A.15)
- brightness controlled by `nvidia_wmi_ec_backlight`

### NVIDIA dGPU

- `01:00.0` [10de:2860], GeForce RTX 4070 Laptop (AD106M), `nvidia` driver
- 8 GB of VRAM (8188 MiB usable); default power limit 90 W, maximum 140 W, minimum 5 W

**Use:**

- Driver: Arch's `nvidia-open-dkms`, built through DKMS for each kernel and signed with the MOK
- dGPU passthrough to VMs is possible; by default it stays on the host (`vfio.conf` is fully commented out)
- GPU tuning/undervolt through the NVML API (32)
- OpenCL (`opencl-nvidia`), which uses `nvidia_uvm`; no CUDA package

**Power management (the dGPU powers off completely, RTD3):**

```text
options nvidia NVreg_RegistryDwords="OverrideMaxPerf=0x1" NVreg_UseKernelSuspendNotifiers=1 NVreg_TemporaryFilePath="/var/tmp" NVreg_DynamicPowerManagement=0x02 NVreg_EnableResizableBar=1 NVreg_EnableGpuFirmwareLogs=1
```

- `NVreg_DynamicPowerManagement=0x02`: fine-grained RTD3; the dGPU reaches D3cold
- udev rules set `power/control=auto` on NVIDIA's VGA/3D functions when they are added/bound to the driver, and `on` when unbound
- `nvidia-persistenced` runs without `--uvm-persistence-mode` (UVM mode would disable RTD3)
- `nvidia-powerd` (Dynamic Boost) and the `nvidia-suspend`/`-resume`/`-hibernate` services active
- the iGPU is the default GPU for Vulkan and VA-API (`LIBVA_DRIVER_NAME` isn't set globally); the NVIDIA GPU is used on demand with `prime-run`
- video: VA-API in Firefox and in Chromium browsers; QSV/VPL (`intel-media-driver`/oneVPL) too
- with Direct Output Mode enabled, an external monitor keeps the dGPU awake
- the `alienware-battery` profile forces it off if it stays awake (32A.14)
- check: `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` = `suspended` (reading through NVML, as btop does, wakes it up)

**Kernel requirements:** PCI runtime PM, D3cold through ACPI, suspend/hibernate, and whatever `nvidia-open-dkms` needs to build (DRM/KMS). `nvidia` also needs `NUMA`, `MEMORY_HOTPLUG`, `ZONE_DEVICE` and `DEVICE_PRIVATE`, which stay.

**`nvidia-uvm`'s HMM:** it is only built with HMM (CUDA accessing memory allocated with plain `malloc`) if `HMM_MIRROR` and `DEVICE_PRIVATE` are on. `HMM_MIRROR` has no prompt of its own in the Kconfig, and in this configuration only `DRM_XE` (through `DRM_GPUSVM`) selects it. With `xe` out, HMM goes; OpenCL, NVENC/NVDEC, Vulkan, NVML and PRIME don't use it. If it is ever needed, `CONFIG_DRM_XE=m` brings it back (`xe` builds, but doesn't bind to the iGPU without `force_probe`).

## 5. Audio

### Controllers

- Intel `00:1f.3` [8086:7a50], `sof-audio-pci-intel-tgl` driver, enabled by `SND_SOC_SOF_ALDERLAKE` (`pci-tgl.c` lists RPL-S under that option; `SND_SOC_SOF_TIGERLAKE` goes)
- NVIDIA HDMI `01:00.1` [10de:22bd], `snd_hda_intel` driver

### ALSA

```text
0 [NVidia]: HDA-Intel - HDA NVidia
1 [sofhdadsp]: sof-hda-dsp - sof-hda-dsp
              Alienware-Alienwarem16R1-00DK46
```

### Codecs

- Main analog/internal: Realtek ALC3254, served by `snd_hda_codec_alc269` (ALC269 family); the other Realtek codecs (ALC260, 262, 268, 662, 680, 861, 861-VD, 880, 882) and the ATI, NVIDIA MCP and Tegra HDMI ones go (requires `EXPERT`, 31)
- Intel HDMI/DP: Intel Raptor Lake HDMI
- NVIDIA HDMI/DP: NVIDIA GPU a6 HDMI/DP
- No SoundWire device, no Cirrus/CS35/CS40/CS42/CS47/Madera/Arizona/Wolfson I2C modules or devices: those MFDs go. Smart amplifiers in other audio menus must be evaluated separately; don't extend the removal to every Cirrus/TI driver without checking
- The laptop has a 3.5 mm jack, used regularly; USB sound devices are also used

### Audio uses

- PipeWire for everything, including ALSA, PulseAudio and JACK
- low latency and top sound quality
- `threadirqs` (1B)
- user limits: `LimitRTPRIO=98` and `LimitMEMLOCK=infinity`, plus the `realtime-privileges` package (`realtime` group)
- recording musical instruments, USB audio interfaces, Ardour

**Keep:**

- USB Audio Class and USB MIDI
- the ALSA sequencer (`SND_SEQUENCER`), used by PipeWire for MIDI
- Intel/Realtek HDA, Intel and NVIDIA HDMI/DP
- Bluetooth audio

## 6. Network

### Wi‑Fi

- `00:14.3` [8086:7a70], subsystem Rivet Networks [1a56:1672], `iwlwifi` driver
- Killer Wi-Fi 6E AX1675i 160 MHz (211NGW), the Killer version of the AX211 (CNVi): GF RF, `so-a0-gf-a0-89.ucode` firmware with `iwlmvm`
- Keep `iwlwifi` and whatever it needs; remove absent Wi‑Fi families and old Intel Wi‑Fi drivers
- `WLAN_VENDOR_*` menus: only Intel stays

### Bluetooth

- AX211, USB (`8087:0033`): the Intel PCIe frontend (`BT_INTEL_PCIE`, Lunar Lake onward) goes
- Keep HCI USB

**Uses:** Xbox, PlayStation and Steam Controller gamepads, Bluetooth audio and other Bluetooth peripherals.

### Ethernet

- `6e:00.0` Killer E3000 2.5GbE [10ec:3000], `r8169` driver, `enp110s0` interface; Realtek PHY, with the PHY's hwmon kept
- ASPM off on the link (root port #3, `00:1c.0`), including L1.1/L1.2: `r8169` disables ASPM on this chip (RTL8125) because of known hangs. Turning on L1.2 didn't reduce power draw (32A.15), so it stays that way
- `NET_VENDOR_*` menus: only Realtek stays

### Software/network

- WireGuard and OpenVPN
- NetworkManager (with wpa_supplicant), including a Wi-Fi hotspot (`ipv4.method shared`): AP mode on `iwlwifi`, NAT/masquerade and NetworkManager's `dnsmasq`
- IPv6 privacy extensions
- DNS over TLS through systemd-resolved
- mDNS: systemd-resolved only resolves (`MulticastDNS=resolve`), and Avahi responds
- `firewalld` through `nftables`
- LocalSend
- QEMU/libvirt networks, TUN/TAP
- USB networking: Raspberry Pi, Arduino and ESP32 over USB/network, iPhone USB Ethernet (`ipheth`), Android

### QoS

- `fq_codel` as the default qdisc (`NET_SCH_FQ_CODEL=m`, `DEFAULT_FQ_CODEL`; systemd's `net.core.default_qdisc` sysctl loads the module at boot). linux-tkg would switch the default to CAKE; the fragment returns it to fq_codel
- FQ and CAKE as modules
- ingress / flower / matchall / gact / mirred kept
- the other qdiscs/classifiers/actions go
- TCP: only CUBIC, built in and the default (the default must be built in); the other algorithms go

## 7. USB-A, USB-C and Thunderbolt

### Controllers

- Main xHCI `00:14.0` [8086:7a60], USB 3.2 Gen 2x2 (20 Gb/s), `xhci_hcd` driver
- Thunderbolt 4 Maple Ridge: bridges `02:00.0` and `03:00.0`–`03:03.0` [8086:1136], NHI `04:00.0` [8086:1137] (`thunderbolt` driver), xHCI `38:00.0` [8086:1138] (`xhci_pci`)

### USB devices

**Internal:**

- `0d62:d2b0` Darfon, internal keyboard, `usbhid` (also sends the macro keys, 11)
- `187c:0551` Alienware AW-ELC, RGB lighting controller, `usbhid`. No program controls it on Linux: brightness changes with Fn+F7 (low, high and off), and the colors were stored in it by AlienFX-Tools on Windows. It doesn't show up in `/sys/class/leds/`, so tuned can't control it
- `0bda:555d` Realtek, webcam, `uvcvideo` (interface 4, "Application Specific", has no driver)
- `8087:0033` Intel AX211 Bluetooth, `btusb`

Autosuspend: Bluetooth and the webcam have `power/control=auto`; the internal keyboard and the AW-ELC have `on` (tuned's `autosuspend=1` doesn't change them). Forcing their autosuspend didn't reduce power draw (32A.15).

**External devices in use:**

- `152d:0583` JMicron JMS583, USB-to-NVMe bridge (external SSD), `uas`
- `0b95:1790` ASIX AX88179, USB Ethernet, `ax88179_178a`
- `30fa:1440` gaming mouse, `usbhid`

**Known problem:** with the `powersupersave` ASPM policy (the Thunderbolt links are the only ones with L0s on under it), waking the Thunderbolt NHI (`04:00.0`) and xHCI (`38:00.0`) at runtime, for example with `lspci -vvv`, can leave them dead (`not ready 1023ms after resume; giving up`, `HC died`, a warning at `drivers/thunderbolt/nhi.c:142`, `failed to send driver ready to ICM`) until a reboot. Cause not yet confirmed. In the firmware (PCI Express Root Port 25), the Thunderbolt link comes with ASPM L1 only, no L1 Substates, Hot Plug on and Advanced Error Reporting off: the L0s the kernel turns on under `powersupersave` is something the firmware doesn't configure on this link. This port's AER and L1 Substates (L1.1 & L1.2) were turned on in the firmware (1A); if the failure becomes more frequent, the L1 Substates are the first thing to turn off. In ACPI D3Cold settings, the firmware lets the Thunderbolt controller power off at runtime (DTBT RTD3 Enable and DTBT RTD3 CLKREQ Enable on, TBT Power-off delay = 5000 ms): it's this power-off and power-on path that fails. The DTBT RTD3 CLKREQ Delay value stays at 0 ms for now (1A). If the failure comes back, the tests are, in this order: turn off Root Port 25's L1 Substates, set the CLKREQ Delay to 200 ms, turn off L0s on the links and, last, DTBT RTD3 CLKREQ, measuring power draw before and after.

**Keep:**

- Thunderbolt 4, USB-C, USB Power Delivery / UCSI (`thunderbolt`, `ucsi_acpi`, `typec_ucsi`, `typec`)
- DisplayPort Alt Mode
- monitors over USB-C/HDMI/miniDP
- Thunderbolt docks/hubs and devices

## 8. Internal storage

### ADATA NVMe

- `6d:00.0` [1cc1:5766], 2 TB ADATA XPG LEGEND 710, `nvme` driver
- A 512 GB Micron 2450 SSD is also installed (`6f:00.0`), but is disregarded: it won't be used

### Root / partitions

- FAT32 ESP at `/boot`, 253 MB, shared with Windows; holds the `vmlinuz-*` files and the UKIs of all three kernels (about 100 MB free)
- root on LUKS2 + Btrfs (`/dev/mapper/root`), no discard: TRIM fully disabled, neither `discard` nor `fstrim.timer`
- LUKS2: `aes-xts-plain64` cipher with a 512-bit key (AES-256 in XTS), 512-byte sectors, `argon2id` PBKDF. The kernel needs dm-crypt, dm-integrity (the `sd-encrypt` hook requires it), XTS and AES with AES-NI in the initramfs; argon2id runs in `cryptsetup`
- every subvolume mounted with `relatime,nodiscard,compress=zstd:3`
- Btrfs with the `crc32c` checksum and the `mixed_backref`, `big_metadata`, `extended_iref`, `skinny_metadata`, `no_holes` and `compress_zstd` features; no data in lzo

**Subvolumes:** Arch's are inside the common `Arch/` directory (not a subvolume); the shareable ones are at the top level.

| Subvolume | Mount point |
|---|---|
| `Arch/@` | `/` |
| `Arch/@root` | `/root` |
| `Arch/@varlog` | `/var/log` |
| `Arch/@varcache` | `/var/cache` |
| `Arch/@vartmp` | `/var/tmp` |
| `Arch/@libvirt-images` | `/var/lib/libvirt/images` (no CoW) |
| `Arch/@swap` | `/.swap` |
| `Arch/@snapshots` | `/.snapshots` |
| `@home` | `/home` |
| `@matlab` | `/usr/local/MATLAB` |

**tmpfs:** `/tmp`, `/temp` and `/tmp/kernel-build` (42 GiB) with `huge=within_size` (THP in shmem) and `usrquota` (tmpfs quotas).

**External media filesystems:**

- exFAT
- NTFS: udisks2 tries `ntfs3` first (`ntfs_drivers=ntfs3,ntfs`), which stays; in the fallback and with `mount -t ntfs`, the `/usr/bin/mount.ntfs` helper points to `ntfs-3g`. The kernel's new NTFS driver (`NTFS_FS=m`, without `NTFS_DEBUG`; since 7.1, faster than `ntfs3` at writing and mounting) is being tested to become the default (with `mount -i -t ntfs`, which skips the helper); if it passes, udisks2 switches to it and `ntfs3` goes
- FAT (classmates' USB drives; `vfat` with the codepages and charsets in use, such as cp437 and utf8)
- ISO images (ISO 9660 with Joliet and Rock Ridge, UDF, mounted through loop)

**Mounted filesystems:** `btrfs`, `vfat`, `tmpfs`, `hugetlbfs`, `fuse.portal` (Flatpak's document portal), `autofs` (systemd's automount), `efivarfs`, `pstore`, `cgroup2`, `bpf`, `configfs`, `debugfs`, `tracefs`, `securityfs`, `mqueue`, plus `proc`, `sysfs`, `devtmpfs` and `devpts`.

**FUSE is essential:** `ntfs-3g`, AppImages (GearLever), `ifuse` (iPhone) and Flatpak's document portal depend on it.

**Windows:** an NTFS partition (nicknamed Bosta11), not in fstab, mounted with `ntfs-3g`; the ESP is the same as Arch's. BitLocker uses the physical TPM (19).

**initramfs (`mkinitcpio`):** the files in `/etc/mkinitcpio.conf.d/` override `/etc/mkinitcpio.conf`:

```text
HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
MODULES=(zstd lz4)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-19 --long -v)
MODULES_DECOMPRESS="yes"
```

- the `systemd` hook replaces `udev`; `sd-encrypt` opens LUKS
- no `kms` hook (33.3)
- `zstd` and `lz4` are in `MODULES` for zswap and hibernation; since `CRYPTO_ZSTD`, `CRYPTO_LZ4` and `CRYPTO_LZO` are built into all three kernels, the entries have no effect (33.3)
- mkinitcpio already adds `-T0` to the zstd options; with `MODULES_DECOMPRESS`, modules and firmware go in uncompressed and are compressed together with the image
- the custom kernel only has the zstd initramfs decompressor (33.3)

**I/O scheduler:** `/etc/udev/rules.d/60-ioschedulers.rules` requests `mq-deadline` for USB disks and SD cards (`sd[a-z]*`, `mmcblk[0-9]*`); the NVMe stays on `none`. In `linux-tkg` mq-deadline is a module, and the kernel only loads it when something writes to `queue/scheduler`.

### Swap / hibernation

- 16 GiB Btrfs swapfile at `/.swap/swapfile`
- hibernation compressed with lz4, located by systemd through `HibernateLocation` (1B); `zswap` with zstd
- `HibernateMode=platform` (with `shutdown`, hibernation never worked); sleep with `MemorySleepMode=deep` and `SuspendState=mem` (S3 enabled in the firmware)
- `systemd-oomd` active: kills processes on memory pressure (`ManagedOOMMemoryPressureLimit=70%` in user sessions) and on swap use; depends on PSI and on cgroup v2's memory controller
- `zram` isn't needed with swapfile + `zswap`
- pstore with the EFI backend on (1B; the Kconfig default in `linux-tkg`) and `systemd-pstore.service` enabled: each crash writes a few KB to NVRAM, and the service moves them to `/var/lib/systemd/pstore` and erases them from NVRAM (`/etc/systemd/pstore.conf` at its defaults)

### External storage

- external SSDs/HDDs/USB drives; an external SSD with LUKS + Btrfs + subvolumes, where the user doesn't allow discard
- SATA SSD and HDD through a USB-SATA adapter. One of them, the SanDisk SSD PLUS 240 GB, is the Faltir-win10 VM's disk (`/dev/disk/by-id/ata-SanDisk_SSD_PLUS_240GB_184027805329`). The `ata-` name comes from udev, which reads the ATA identification through the adapter (`uas`/`usb-storage` + `sd_mod`): the laptop has no SATA controller, so `ATA` (libata) goes without affecting it

**Keep:** USB Mass Storage, UAS, SCSI disk and SCSI generic. Don't remove external support just because the internal disks are NVMe.

### NVMe policy

- NVMe is critical; available early (root)
- APST on for both NVMe drives and ASPM L1 with L1.1/L1.2 on both links; the Micron, though unused, doesn't block idle states. Don't change latency/APST without need
- keep NVMe hwmon

## 9. SD reader

- `6c:00.0` Realtek RTS525A [10ec:525a], `rtsx_pci` driver
- Keep `rtsx_pci`, `rtsx_pci_sdmmc` and `mmc_block` (needed to read a card). The reader isn't eMMC: `RPMB` goes

## 10. Webcam

- Built-in webcam, Realtek `0bda:555d`, used by the user

**Keep:** media camera, media USB, UVC and UVC input events.

## 11. Keyboard, mouse, touchpad and HID

### Internal keyboard

- The internal keyboard is USB: Darfon `0d62:d2b0`, `usbhid`
- The i8042/PS2 controller is also active, with the keyboard (`DLLK0BFB`) and auxiliary port (`DLL0BFB`) bound to `i8042` (the firmware's Legacy Game Compatibility Mode enables the PS/2 keyboard/mouse). Keep `i8042` and `atkbd`
- The macro keys arrive through the same USB HID device: an hwdb file maps usages `0xc0051`–`0xc0055` to `macro1`–`macro5`
- Don't confuse the USB keyboard with the embedded keyboard drivers in the Keyboards submenu
- Other vendors' PS/2 touchpad protocols (ALPS, BYD, Cypress, Elantech, FocalTech, Lifebook, Logitech PS/2, Sentelic, Touchkit, Trackpoint) go; `psmouse`'s Synaptics ones stay, since that is the touchpad's maker
- `INPUT_TOUCHSCREEN` and `INPUT_TABLET` go: there is no touchscreen or graphics tablet

### Touchpad

The touchpad is `VEN_06CB` (Synaptics), bound to `i2c_hid_acpi`:

```text
Intel LPSS PCI
 -> intel_lpss_pci
 -> i2c_designware platform
 -> i2c-hid-acpi
 -> hid-multitouch
 -> touchpad
```

**Controllers:** `00:15.0` and `00:15.1` [8086:7a4c/7a4d], `intel-lpss` driver (`intel_lpss_pci` module)

### USB HID / Logitech

USB mice and keyboards: Logitech K230, Logitech M280/M320/M275, Logitech Unifying Receiver (C52B), Dazz GMO3000 gaming mouse, Dell KB216p keyboard and other USB HID devices/wireless receivers.

**Keep:** generic HID, USB HID, Logitech HID, DJ and HID++, RGB peripherals.

## 12. Gamepads

**Use:**

- Xbox 360 and One
- PlayStation 3 and 4/5
- Steam Controller
- Third-party gamepads (including through wireless USB adapters, besides Bluetooth)
- Racing wheels: the user doesn't have one yet, so `LOGIWHEELS_FF` and `HID_PID` stay off; after buying one, turn the brand's driver back on and load the module before the next build. The Logitech G940 joystick goes

**Keep:**

- `xpad`, with force feedback and the Guide LED
- `hid-playstation`, with force feedback
- `hid-steam`
- `hid-sony`, `hid-nintendo`, `hid-microsoft` (Xbox controllers over Bluetooth) and `hid-logitech`
- Bluetooth HIDP
- generic USB HID
- `uinput`: Steam Input creates virtual controllers through `/dev/uinput`

Don't confuse gamepads with Remote Controller/LIRC/IR: `LIRC`, `RC_CORE` and remote control passthrough over HDMI-CEC (`MEDIA_CEC_RC`) go; `i915`'s CEC stays.

## 13. Arduino, ESP32 and Raspberry Pi

**Uses:** Arduino, ESP32 and Raspberry Pi, over USB serial and USB networking.

**Keep:** CDC ACM, CH341/CH340, CP210x, FTDI SIO, PL2303 and USB serial generic.

```text
Arduino -> CDC ACM / CH340 / FTDI
ESP32   -> CP210x / CH340 / CDC ACM
RPi     -> USB serial and/or USB networking
```

### Don't confuse

- `SPI_CH341` isn't needed just because a CH340/CH341 serial adapter is used
- FTDI MPSSE GPIO is only needed with deliberate use of an FT232H/FT2232H in MPSSE mode for GPIO/JTAG/SPI
- The host's GPIO/SPI/I2C/1-Wire must not be enabled just because they exist on the external boards; a sensor attached to the ESP32 is controlled by the ESP32
- The USB serial adapters don't use the 8250 driver

### USB networking

**Keep:** Raspberry Pi USB gadget/network, CDC Ethernet, CDC NCM, RNDIS host, ASIX AX88179, Realtek RTL8152/8153, iPhone (`ipheth`) and Android USB Ethernet. `cdc_subset` (old USB adapters) goes.

## 14. Phones

- Connects Android and iPhone/iOS: keep the matching USB networking
- Don't enable WWAN modems: the laptop has no WWAN hardware

## 15. Printer and scanner

- Canon E4210, over the network: `ipps://248FC3000000.local:631/ipp/print` (CUPS, discovered through Avahi's mDNS), with SANE
- IPP-USB isn't used; `USB_PRINTER` stays as a module for an occasional USB printer
- keep multicast/mDNS

## 16. Virtualization

**Uses:**

- QEMU, KVM and libvirt; SPICE over a Unix socket
- GPU passthrough with Looking Glass B7 and the `kvmfr` module (out of tree, through DKMS and signed with the MOK; `static_size_mb=256`)
- NVMe and USB passthrough
- TPM: the Windows 11 VM (the bare-metal install, also used as a VM) gets the physical TPM through `/dev/tpmrm0`; the Windows 10 VM uses an emulated TPM (`swtpm`)
- physical disks in VMs, including a virtual disk assembled with device-mapper (`dm-linear`) over the physical Windows partitions, with loop images (`loop max_part=15`)
- shared folder with `virtiofsd` (shared VM memory)
- CPU isolation through a libvirt hook, via cgroups (systemd's `AllowedCPUs`): vCPUs on P-cores 8–15, the emulator on 16–17, the iothread on 18–19; the host keeps 0–7 and 20–31
- dynamic hugepages: `vm.nr_overcommit_hugepages=8192` (16 GiB), with memory compaction before the VM starts (`/proc/sys/vm/compact_memory`); HVO on by default
- nested virtualization: `kvm_intel nested=1`
- dummy HDMI/miniDP
- IOMMU on (1B)
- VM disks with `io="native"` (Linux AIO), `cache="none"`, `discard="unmap"` and iothreads
- VMs: `archlinux`, `Bosta10`, `Bosta11-bare-metal` (disk `/dev/mapper/windows-VM`) and `Faltir-win10` (SATA SSD over USB, 8). All with `type='network'` networking on the `default` network (NAT, `virbr0` bridge with STP), a `virtio` NIC and `virtio-vga-gl` video; none uses macvtap (`type='direct'`)

**Options:** `KVM_INTEL`, `KVM_HYPERV` (Hyper-V enlightenments for the Windows VMs), `VFIO_PCI`, `VHOST_NET`, `TUN`, `BRIDGE` stay; `KVM_AMD`, `KVM_XEN` (Xen emulation for guests), `KVM_INTEL_TDX` and `MACVLAN`/`MACVTAP` go.

**Keep:** KVM Intel, IOMMU, VFIO/VFIO PCI and passthrough, TUN/TAP, device-mapper and loop, hugetlbfs and memory compaction, Linux AIO, bridge with nftables and `vhost_net`, cgroup v2 cpusets.

**Crucial rule:** the kernel is the physical host, not the guest. Don't enable VirtIO/Xen/Hyper-V/VMware frontends just because the host runs VMs. The system doesn't use Xen.

## 17. Games

**Uses:** Steam, Proton, Wine, emulation, gamepads (12), NVIDIA, a gaming VM with passthrough.

- Steam's sandbox (pressure-vessel), Flatpak (`bubblewrap` without setuid) and the Chromium browsers' sandbox (such as Helium) need unprivileged user namespaces: `USER_NS=y` and, in linux-tkg, `USER_NS_UNPRIVILEGED=y` (an option from the `0001-add-sysctl-to-disallow-unprivileged-CLONE_NEWUSER` patch, on by default)
- `ntsync` (`CONFIG_NTSYNC=m`, used by recent Proton); in `linux-tkg.cfg`, `_ntsync="false"` only refers to the patch for old kernels
- Wine needs `MODIFY_LDT_SYSCALL` and `X86_16BIT`, which stay even though they are legacy interfaces; 32-bit support (`IA32_EMULATION`) stays for Steam
- vsyscall page emulation goes (`X86_VSYSCALL_EMULATION`): only static glibc binaries from before 2011 use it

**Requirements:** avoid unnecessary latency and overhead; keep peripherals and HDMI/miniDP/USB-C.

## 18. Secure Boot, UKI and signing

- Secure Boot active, with the laptop's default keys: PK, KEK and db/dbx were not changed (db/dbx are updated by fwupd)
- Own MOKs sign the system's binaries, through shim in `EFI/systemd/` (with a copy in `EFI/arch/` for fwupd), installed by the repository's scripts (`shim-setup.sh`, `systemd-boot-setup-shim.sh`); the firmware's boot entry points to `\EFI\systemd\shimx64.efi`
- `systemd-boot`, signed with the MOK by a pacman hook
- UKIs generated by `mkinitcpio`; the `kernel-sbsign` and `uki-sbsign` hooks sign the kernel and the UKI with the MOK. Each kernel has a preset with `default_uki` and no fallback; `linux-tkg`'s (`/etc/mkinitcpio.d/linux-tkg.preset`) is a copy of `linux-zen.preset` with the name changed, created before installing the package (otherwise the install hook creates a preset from the template, which builds an initramfs instead of a UKI)
- The DKMS modules (`nvidia-open-dkms`, `kvmfr`) are signed by DKMS with the module-signing MOK (`custom-moks.conf`, "Mr. Robot Alienware Machine Owner Key - Module Signing"), not with the kernel's module key. The kernel trusts it through the `.machine` keyring, loaded from `MokListRT` (`mokutil --trust-mok` active)
- Expected `/proc/sys/kernel/tainted`: 4100 = 4096 (out-of-tree modules, DKMS) + 4 (MSR writes by `intel-undervolt`). Bit 13 (8192, unsigned module) must not appear
- MOKs: `MOK.crt` and `MOK-module-signing.crt` have `CA:TRUE` and no keyUsage. That's why `INTEGRITY_CA_MACHINE_KEYRING` stays off: with it, only MOKs with `CA:TRUE` and `keyCertSign` go into `.machine`, both would go to the platform keyring (which doesn't apply to modules), and nvidia and kvmfr would stop loading
- `MokListRT` also has `Red Hat, Inc.: fedoraca`, `grub` and `MultiOS-USB`. With MOK trust on, the kernel accepts modules signed by any of them, and shim boots whatever they sign. Remove the unused ones (`mokutil --export`, `mokutil --delete MOK-000N.der` and confirm in MokManager); keep `MultiOS-USB` and `grub` if the MultiOS-USB drive is booted with Secure Boot
- fwupd updates the firmware through UEFI capsules (ESRT, efivarfs) and signs its own EFI binary with the MOK
- MOK keys in `/root/secureboot/keys/` (back them up before reinstalling)

**Module signing in the kernel:**

- `MODULE_SIG=y`, `MODULE_SIG_ALL=y`, SHA-512
- `MODULE_SIG_FORCE=y`: a module without a valid signature doesn't load. If DKMS signing fails, nvidia doesn't load: `linux` and `linux-zen` remain as fallbacks
- no `MODULE_FORCE_LOAD` or `MODULE_FORCE_UNLOAD`
- linux-tkg's PKGBUILD uses `options=('!strip')`, and `_STRIP="true"`'s `INSTALL_MOD_STRIP=1` acts before signing in `modules_install`: the signatures stay valid

Don't break Secure Boot when modularizing boot drivers.

**Lockdown:** with lockdown in integrity mode, common alongside Secure Boot, the kernel disables hibernation. Since hibernation is used, `LOCK_DOWN_KERNEL_FORCE_NONE` stays, with `SECURITY_LOCKDOWN_LSM_EARLY=y` (no effect while lockdown is none). With lockdown at none, `kexec_load` would let root boot an unsigned kernel, bypassing Secure Boot: kexec and kdump go (33.5).

**Display at boot:** the LUKS password prompt (`sd-encrypt`) appears before the GPU driver loads, through the UEFI framebuffer (`simple-framebuffer` via `simpledrm`, 33.3).

## 19. TPM 2.0

```text
driver: /sys/bus/platform/drivers/tpm_crb_acpi
TPM version: 2
device: /sys/devices/platform/INTC6001:00
DRIVER=tpm_crb_acpi
MODALIAS=acpi:INTC6001:MSFT0101:
```

- ACPI/EFI: SSDT Tpm2Tabl, Dell TPM2 table, TPMFinalLog, TPMEventLog
- systemd does the TPM PCR Barrier in the initrd, the PCR measurements, the Machine ID measurement and the Early TPM SRK Setup
- actual interface: CRB. `TCG_TIS` and `TCG_TIS_CORE` (TIS/FIFO/SPI/I2C) go
- `TCG_TPM=m` and `TCG_CRB=m`: the `sd-encrypt` hook puts `tpm_crb` and `tpm` in the UKI (filtered by autodetect, 33.3); `MODULES` isn't needed
- `/dev/tpmrm0` (the kernel's resource manager) is passed to the bare-metal Windows 11 VM (16)
- the physical TPM is used by systemd (measurements, `systemd-creds`, used in the hotspot script) and by Windows' BitLocker

## 20. Watchdog

```text
/dev/watchdog
/dev/watchdog0

identity: iTCO_wdt
driver: /sys/bus/platform/drivers/iTCO_wdt
Found a Intel PCH TCO device, Version=6, TCOBASE=0x0400, heartbeat=30 sec, nowayout=0
```

- actual watchdog: Intel TCO (`iTCO_wdt`, with `intel_pmc_bxt`); stays
- ACPI WDAT absent: the firmware only publishes it with Enable TCO Timer on, and that stays off (1A); `iTCO_wdt` doesn't depend on it
- softdog and pretimeout unnecessary; `nowayout=0` desired

### NMI watchdog

- hard lockup detector through a PMU counter (`NMI watchdog: Enabled. Permanently consumes one hw-PMU counter.`), separate from iTCO
- the `tuned` profiles turn it on and off at runtime, so the support stays built (32A.9)

## 21. Intel Integrated Sensor Hub

- `00:12.0` [8086:7a78], `intel_ish_ipc` driver, with `intel_ishtp` and `intel_ishtp_hid` (`hid_sensor_hub`/`hid_sensor_custom` sensors); keep the path

## 22. DPTF / Intel thermal

- `00:04.0` [8086:a71d], `proc_thermal_pci` driver (`processor_thermal_device_pci` module)

**Keep:** INT340X / processor thermal, package temperature thermal, coretemp, Intel HFI, Raptor Lake TCC cooling, thermal hwmon.

**Decisions:**

- the Bay Trail/Broxton drivers and the old Intel PCH Thermal Reporting don't match the hardware
- `intel_powerclamp` is in use, so it stays
- main thermal governor: step_wise
- Tjmax 100 °C, no offset: the firmware's Tcc Offset Lock locks the register, so system tools don't change the throttling point
- no thermal emulation
- there is no ACPI fan (`PNP0C0B` or `INTC1048`): the fans come from Dell SMM and WMI (23). `ACPI_FAN` stays as a module only because `INT340X_THERMAL` selects it
- `ACPI_THERMAL` built in (the Kconfig calls it "HIGHLY recommended"; as a module, the firmware's thermal zones would only take effect after the LUKS prompt)
- thermald disabled (32)
- generic ACPI thermal zone (the firmware's Platform Thermal Configuration, at its defaults): critical trip point at 119 °C (the kernel shuts the system down), passive trip points off (the kernel doesn't slow the CPU because of it; throttling comes from the TCC at 100 °C) and active trip points without effect, since there is no ACPI fan

## 23. HWMON

| Source | Driver | What it exposes |
|---|---|---|
| CPU | `coretemp` | package and each core (Tjmax 100 °C) |
| Dell SMM | `dell_smm_hwmon` | 4 fans, 9 temperatures and manual PWM fan control |
| Dell DDV (WMI) | `dell_wmi_ddv` | the same fans and temperatures as Dell SMM, with names (CPU, Video, Ambient, SODIMM) |
| Alienware WMI | `alienware_wmi` | CPU and GPU fans, CPU and GPU temperatures |
| RAM | `spd5118` | both DDR5 modules, on the I801 SMBus (addresses `0x50` and `0x52`) |
| NVMe | NVMe hwmon | the ADATA (`6d:00.0`) and the disregarded Micron (`6f:00.0`) |
| Wi-Fi | `iwlwifi` | AX211 temperature |
| Ethernet | Realtek PHY hwmon | PHY temperature |
| Power | power_supply hwmon | battery `BAT0` and both USB-C ports (UCSI) |

- all of them stay, including `dell_wmi_ddv` and `alienware_wmi`'s hwmon, which repeat data from `dell_smm_hwmon`; `HWMON` core as a module
- legacy `/proc/i8k` (`I8K`) goes

## 24. Dell/Alienware WMI

- `dell_wmi`, `alienware_wmi`, `dell_smbios` (with `dcdbas`), `dell_wmi_sysman` (BIOS settings through `firmware-attributes`), `dell_wmi_ddv` (sensors, 23), `nvidia_wmi_ec_backlight` (brightness)
- `alienware_wmi` provides the `platform_profile` used by the tuned profiles (32A.3)
- WMI GUIDs: Alienware's WMAX (`A70591CE-…`) and Dell SMBIOS's (`A80593CE-…`), among others. The legacy Alienware GUID (`A90597CE-…`, AlienFX) doesn't exist: `ALIENWARE_WMI_LEGACY` goes, `ALIENWARE_WMI_WMAX` stays

## 25. Intel MEI

- `00:16.0` CSME HECI #1 [8086:7a68], `mei_me` driver, with `mei_hdcp` and `mei_pxp`; stays
- the iAMT watchdog (`MEI_WDT`) and other specialized MEI devices go

## 26. I2C

- I2C core built in (ACPI I2C OpRegion, touchpad, Intel LPSS, enumerated internal devices)
- I801: `00:1f.4` [8086:7a23], `i801_smbus` driver; `I2C_I801` stays
- DesignWare: Intel LPSS uses DesignWare Platform (`i2c_designware.0` and `.1`); `I2C_DESIGNWARE_CORE` and `I2C_DESIGNWARE_PLATFORM` as modules. `I2C_DESIGNWARE_PCI` and the Bay Trail semaphore go
- i2c-dev: `I2C_CHARDEV` stays, because `i2c_dev` is loaded by the `/usr/lib/modules-load.d/` files of the `i2c-tools`, `ddcutil` (DDC/CI, external monitor brightness) and `fwupd` packages
- I2C mux: the `I2C_MUX` core is selected by a dependency and stays; the specific muxes go
- `I2C_SLAVE` goes

## 27. SPI

- PCH SPI flash: the `00:1f.5` controller uses `spi_intel_pci`, with `spi_intel`, `spi_nor` and `mtd`; they stay. The driver only allows reading the flash by default (the `writeable` parameter off)
- `SPI_INTEL_PLATFORM` (platform variant, no device here), `spidev` and `SPI_CH341` stay out

## 28. Pinctrl / GPIO

- Raptor Lake HX uses the Intel Alder Lake pinctrl: `PINCTRL_INTEL` and `PINCTRL_ALDERLAKE` (not Tiger Lake)
- userspace GPIO unnecessary: `GPIO_CDEV` (and with it the v1 ABI) goes through block 8 of the `.myfrag` (`EXPERT`); `GPIO_SYSFS` off. If the GPIO core is forced on, don't break dependencies to remove it
- Arduino/ESP32/RPi over USB don't justify GPIO on the host

## 29. Regulators / PMIC

- `intel-undervolt` and NVML don't depend on `CONFIG_REGULATOR`; the framework is for kernel-managed PMICs, which don't exist here
- Maxim/TI/Richtek/NXP/MediaTek regulators go
- `REGULATOR` / fixed voltage regulator is selected by a dependency: don't force N until that dependency is identified

## 30. Battery / power supply

- battery `BAT0`: DELL 70N2F3B (made by SMP), Li-poly, manufactured 2023-12-26; design capacity ~84.28 Wh (7393 mAh × 11.4 V), ~71% health
- driver: ACPI battery (`acpi-battery`, `PNP0C0A`); SBS isn't used
- the battery reports `current_now`, `voltage_now` and `charge_now`, not `power_now`: power is the product of the first two (µA × µV = 10⁻¹² W), and a period's average comes from the change in `charge_now`
- power sources: `AC` (`ac` driver) and two USB-C ports (`ucsi-source-psy-USBC000:001` and `:002`, `ucsi_acpi` driver)

**Keep:** power supply class, ACPI battery, AC adapter, power supply hwmon. Specific fuel gauge/charger drivers go.

## 31. linux-tkg and build

**Files:**

- `~/.config/frogminer/linux-tkg.cfg` (tkg's external configuration)
- `~/.config/frogminer/alienware.myfrag`, copied as a regular file to `/opt/linux-tkg/` with `install -m644` after every change: tkg only applies *regular* files ending in `.myfrag` inside its own directory (`find "$_where"/ -type f -name "*.myfrag"`), and a symlink is silently ignored. No other `.myfrag` may be left in `/opt/linux-tkg/`
- `~/.local/share/modprobed-db/modprobed.db` (357 modules)
- tkg repository at `/opt/linux-tkg`; build in tmpfs (`/tmp/kernel-build`, 42 GiB), 5–6 min on the performance profile with ~7 GiB of RAM

**`linux-tkg.cfg`:**

- `_custom_pkgbase="linux-tkg"`: packages `linux-tkg` and `linux-tkg-headers`, image `/boot/vmlinuz-linux-tkg`, preset `linux-tkg.preset` (18)
- version: the latest stable of the series chosen at build time (`_version` empty: the script asks; `"7.2-latest"` or a tag such as `"v7.2.15"` pins the choice). The 7.2 and 7.3 series are maintained by linux-tkg
- base: with `_distro="Arch"` and `_configfile` empty, tkg starts from `linux-tkg-config/7.2/config.x86_64`, which is Arch's `linux` configuration
- BORE scheduler (`_bore_min_base_slice_ns=2000000`)
- GCC (`_lto_mode` only applies to clang, so LTO stays off); `-O3` (`_compileroptlevel=2`); `-march=native` (`_processor_opt=native`, put in the Makefile by tkg and kept for DKMS)
- `_tickless=2` → tickless-idle (`NO_HZ_IDLE`); 1000 Hz; 32 CPUs
- NUKR; MGLRU on; `_zenify` and `_glitched_base` on
- `_STRIP="true"`: strips DWARF from the modules (`INSTALL_MOD_STRIP=1`, which keeps the `.BTF` section) and from the headers' `vmlinux`. tkg also turns on `DEBUG_INFO_NONE`, which would turn BTF off; the fragment turns debug info back on
- `_irq_threading="false"` (IRQ threading comes from `threadirqs`); `_acs_override="false"` (the firmware's ACS already isolates the dGPU)
- debug, ftrace and NUMA aren't disabled by tkg (`_debugdisable`, `_ftracedisable`, `_numadisable` = false); `_kernel_on_diet` off; `PREEMPT_RT` off
- `_modprobeddb="true"`, with `_modprobeddb_db_path=~/.local/share/modprobed-db/modprobed.db`
- `_menunconfig="1"` (opens `menuconfig` on every build), `_diffconfig="true"` and `_diffconfig_name="menuconfig-diff.txt"`
- no effect on 7.2: `_fsync_backport`, `_fsync_legacy`, `_zfsfix`, `_ntsync` (`CONFIG_NTSYNC` stays on, 17), `_random_trust_cpu`, `_aggressive_ondemand`, `_install_after_building` and the LLVM options
- compiler: GCC 16.2.1, no `-fsanitize=kcfi`; `-fzero-call-used-regs` supported

**Build order (`linux-tkg-config/prepare`):** base `config.x86_64` → `make localmodconfig` with the database → tkg's own tweaks (`DEBUG_INFO_NONE` from `_STRIP`, `NR_CPUS`, tickless, `MAXSMP` off, `SYSFB_SIMPLEFB` off, CAKE as the default qdisc, etc.) → each `*.myfrag` through `merge_config.sh -m`, in alphabetical order → `olddefconfig` → `menuconfig` → `diffconfig`. The fragment is applied after tkg's tweaks and overrides them.

- `localmodconfig` turns off the m options whose module isn't in the database and doesn't touch the y ones; whatever it drops by mistake comes back through the fragment
- `diffconfig` writes only that `menuconfig` session's changes to `$_where/menuconfig-diff.txt`, and that file is **not** reapplied on the next build: every `menuconfig` choice that should stick has to go into the fragment. The generated name must not end in `.myfrag`, or it would be applied automatically

**`modprobed.db`:** the database only has what was loaded as a module on the running kernel. Rarely used modules must be loaded at least once before the build, or they disappear. Besides what `modprobed-db` collected, the inventory's modules were added to the database by hand: NLS codepages, `nbd`, `ntsync`, `mmc_block`, USB serial (`cdc_acm`, `usbserial`, `ch341`, `cp210x`, `ftdi_sio`, `pl2303`), `rndis_host`, `r8152`, gamepads (`xpad`, `hid_playstation`, `led_class_multicolor`, `hid_sony`, `hid_steam`, `hid_nintendo`, `hid_logitech`), `hidp`, USB audio and MIDI (`snd_usb_audio`, `snd_usbmidi_lib`, `snd_rawmidi`, `snd_ump`, `snd_seq_midi`, `snd_seq_midi_event`), qdiscs and classifiers (`sch_fq`, `sch_cake`, `sch_fq_codel`, `sch_ingress`, `cls_flower`, `cls_matchall`, `act_gact`, `act_mirred`) and those built into the base that the fragment turns into m (`tpm`, `tpm_crb`, `btrfs`, `fuse`, `xts`, `msr`, `usbhid`, `hid_generic`, `xhci_*`, `i8042`, `atkbd`, `serio`, `libps2`, `sd_mod`, `scsi_mod`, `autofs4`, `configfs`, `ac`, `battery`, `button`, `i2c_designware_*`). `modprobed-db store` only adds, so they stay. The NVIDIA modules (DKMS) don't need to be in the database.

**Build and boot workflow requirements:**

- DKMS to build for each kernel: `nvidia` and `looking-glass` (`kvmfr`); check with `dkms status`
- Arch's `linux-firmware` is zstd-compressed: the kernel must load zstd firmware (`FW_LOADER_COMPRESS_ZSTD`), or Wi-Fi, Bluetooth, the iGPU (GuC/HuC/DMC), audio (SOF) and Ethernet stop working
- zstd-compressed modules (`MODULE_COMPRESS_ZSTD`), matching `mkinitcpio`'s `MODULES_DECOMPRESS`
- fallback kernels: `linux` and `linux-zen`, because new kernel versions sometimes break `nvidia-open-dkms` for a while. `linux-zen` also serves as a reference: a problem that goes away on it points to linux-tkg's choices

**Kept from the base (Arch's `linux` configuration):**

- signing and keyrings: `INTEGRITY_MACHINE_KEYRING`, `INTEGRITY_PLATFORM_KEYRING`, `SECONDARY_TRUSTED_KEYRING`, `LOAD_UEFI_KEYS` (the kernel trusts the MOK for the DKMS modules)
- LSMs: `CONFIG_LSM="landlock,lockdown,yama,integrity,bpf"`, `BPF_LSM=y`; `SECURITY_APPARMOR`, `SECURITY_SELINUX` and `SCHED_CLASS_EXT` (sched_ext) built without active use, kept
- system: `PSI`, `USER_NS`, `CPUSETS`, `AIO`, `IO_URING`, `FANOTIFY_ACCESS_PERMISSIONS`, `IRQ_FORCED_THREADING`
- memory: `HUGETLBFS`, `COMPACTION`, `LRU_GEN_ENABLED`, `TMPFS_QUOTA`, `ZSWAP_DEFAULT_ON`, `ZSWAP_SHRINKER_DEFAULT_ON`, `ZSWAP_COMPRESSOR_DEFAULT_ZSTD` with `CRYPTO_ZSTD=y`; `COMPACT_UNEVICTABLE_DEFAULT=1` (`linux`'s default, which favors huge pages; if audio gets xruns, try `vm.compact_unevictable_allowed=0` through sysctl)
- scheduling: `PREEMPT=y` with `PREEMPT_DYNAMIC` (`full` mode, with `lazy` available)
- boot: `EFI_STUB`, `EFI_ESRT`, `RD_ZSTD`, `KERNEL_ZSTD`
- CPU: `X86_KERNEL_IBT`, `X86_USER_SHADOW_STACK`, every Intel mitigation

**The `alienware.myfrag` fragment:** each line is commented with the section of this document that justifies it. Validated by simulation on the 7.2.15 source (base → `localmodconfig` with the real database → tkg's tweaks → fragment → `olddefconfig`, and also on top of a real build's `kernelconfig.new`); every line ends up with the requested value. Blocks:

1. debug: turns BTF back on (`DEBUG_INFO_DWARF5`, `_BTF`, `_BTF_MODULES`, `_COMPRESSED_ZSTD`) and removes tests, fault injection, `MMIOTRACE`, debugging over xHCI/EHCI, `OVMF_DEBUG_LOG`, kexec/kdump/Live Update and debug counters on hot paths (`LOCK_EVENT_COUNTS`, `X86_CPA_STATISTICS`); turns on pstore's EFI backend
2. CPU and host role: Intel only (no AMD, AMD-only mitigations, AMD IOMMU), no SGX/TDX/RDT, no `INTEL_TURBO_MAX_3`, no embedded Intel platforms, no guest role (`HYPERVISOR_GUEST`, Hyper-V, VirtIO frontends, `REMOTEPROC`), `INTEL_IOMMU_DEFAULT_ON`, `HIBERNATION_COMP_LZ4`, no x32 ABI, no `ioperm`/`iopl`, `/dev/mem`, `/dev/port` and `/dev/snapshot`, no EFI handover
3. the "Disable" items from section 2
4. absent hardware: SATA, AGP, VESA, EHCI/OHCI/UHCI, UART 8250, PMICs, touchscreen, TV/radio/platform cameras, IR, NVMe multipath/auth, DAX, zoned devices, HBAs, SR-IOV and other server PCI features, NPU, SoC infrastructure, server RAS, NAND flash, eMMC
5. security (33.5): unused LSMs, initramfs decompressors other than zstd, partition tables other than GPT/MBR, datacenter protocols, hardening
6. built-in → module (33.2)
7. safety net: the declared rarely used modules, as m, in case the database lacks them
8. `EXPERT=y` and what only goes away with it: support for AMD/Hygon/Centaur/Zhaoxin CPUs, PS/2 protocols, `GPIO_CDEV`, `UID16`, `SGETMASK_SYSCALL`, vsyscall emulation, firmware memory maps, the VGA console and absent HD-audio codecs. Turning on `EXPERT` changes no other option, and its Kconfig warning isn't an "If unsure, say N"
9. the user's `menuconfig` choices and fixes:
   - `DM_INTEGRITY=m` (required by the `sd-encrypt` hook; `localmodconfig` was removing it) and `SYSFB_SIMPLEFB=y` (tkg turns it off, which would leave simpledrm without a framebuffer and the LUKS prompt invisible)
   - TCP: CUBIC built in and the default; Westwood+, Vegas, YeAH and BBR out (2026-11-13, unused)
   - `X86_NATIVE_CPU` (redundant with `_processor_opt=native`, no side effect)
   - `DPM_WATCHDOG`: if a driver hangs suspend or resume, it warns at 60 s and panics at 120 s (saved to pstore)
   - THP set to `madvise` (programs that ask for it, such as QEMU, keep using it); HVO on by default
   - SOF `ALDERLAKE` only (5); `USB_PRINTER=m` (15); MTD, CPU and camera LED triggers out; `FIRMWARE_EDID` out (`i915` and `nvidia` read the EDID straight from each output)
   - `ALLOW_DEV_COREDUMP=y`: firmware coredumps from iwlwifi and i915 for debugging (only root can read them, and the dump disappears after 5 minutes)
   - `RUST_BITMAP_HARDENED` and `DEBUG_NMI_SELFTEST` (both "If unsure, say N", chosen by the user; negligible cost)
   - `CRYPTO_SELFTESTS` (without FULL): tests each crypto API algorithm at registration and blocks faulty implementations
   - `CRYPTO_HW` out (QAT, CCP, Padlock and similar accelerators don't exist; AES-NI and SHA-NI are in another Kconfig section)
   - kmemleak, UBSAN and `NTFS_DEBUG` out (2026-11-13): permanent cost without realistic use (33.6)
   - `NET_VENDOR_*` and `WLAN_VENDOR_*` menus off, except Realtek (Ethernet) and Intel (Wi-Fi)
   - `ACPI_EC_DEBUGFS` and `USB_STORAGE_DEBUG` stay out: the first allows writes to the EC that can hang it badly enough to require pulling the battery; the second writes a journal message for every command sent to a USB drive, with no way to turn it off

**Kept on purpose:** `NUMA` (linux-tkg warns that turning it off breaks CUDA/NVENC), `MEMORY_HOTPLUG`/`ZONE_DEVICE`/`DEVICE_PRIVATE` (nvidia), `PCI_P2PDMA` (`VFIO_PCI_DMABUF` depends on it), the cpufreq and thermal governors (32A), `ACPI_DEBUG`, the latency tracers (`HWLAT`, `OSNOISE`, `TIMERLAT`, useful for xruns), `PROC_KCORE` (perf/drgn), iwlwifi's debug.

## 32. Undervolt / power tuning

### CPU

- `intel-undervolt`, through MSR; the firmware only accepts the undervolt because UnderVolt Protection is disabled
- offsets: CPU −100 mV, GPU −70 mV, CPU Cache −100 mV, System Agent −70 mV, Analog I/O −70 mV; reapplied by the daemon every 60 min
- `X86_MSR` as a module: `intel-undervolt` runs `/sbin/modprobe msr` before using it; no `modules-load.d` needed
- the configuration (`/etc/intel-undervolt.conf`) only has the `undervolt` lines, plus `daemon undervolt`, `daemon power` and `daemon tjoffset` with no `power` or `tjoffset` values: nothing uses `/dev/mem`, which `intel-undervolt` only opens for MMIO power limits and Tjunction. The power limits come from tuned through powercap (32A.4). `DEVMEM` goes; turn it back on if `power` or `tjoffset` are ever used in `intel-undervolt`
- don't confuse with the regulator framework

### GPU

- tuning through the NVML API, with the NVIDIA driver (no regulator framework)
- `nvidia-undervolt.service` (oneshot, after `nvidia-persistenced`): clocks locked between 210 and 2175 MHz and clock offsets per P-state (P0 +300, P3 +255, P4 +240, P5 +225, P8 +180 MHz)
- `nvidia-persistenced` keeps these settings while the driver is loaded

### Tools

- `tuned` and `tuned-ppd`
- powertop and turbostat (used to tune the tuned profiles)
- `nvidia-powerd` (Dynamic Boost), active; only has an effect on AC
- thermald disabled (`systemctl disable --now thermald`): in the package service's `--adaptive` mode, it applies the DPTF tables' limits on top of the profiles (PL1 went to 165 W in MSR and MMIO, or to 55 W, instead of `alienware-battery`'s 12 W) and brings no gain at idle

When removing governors/thermal facilities, consider whether a tool depends on them.

## 32A. Custom tuned profiles

The laptop has four custom `tuned` profiles, plus a common set (`alienware-common`) that all of them include. When choosing kernel options, keep the interfaces these profiles manipulate dynamically.

### 32A.1 Profiles and goals

#### alienware-common

- never selected on its own; gathers the common sysctls and PCI runtime PM
- `power-policy.bash`, next to it, has the shared code: platform profile, RAPL, Wi-Fi and dGPU (32A.4 and 32A.14)

#### alienware-balanced

- the everyday default profile on AC; goal: overall balance

#### alienware-balanced-battery

- light use on battery (the user's typical use away from the outlet)
- inherits `alienware-balanced` and leans toward saving: EPB `balance-power`, lower RAPL limits, ASPM `powersupersave`, USB autosuspend, Wi-Fi power save, no network wakeup and no NMI watchdog

#### alienware-performance

- AC only; goal: deterministic performance with higher power draw
- uses `platform_profile`=balanced-performance, not performance, because on the Alienware the performance profile maps to AWCC Overdrive and pins the fans at maximum
- uses the `powersave` governor with EPP `balance_performance`, not the `performance` governor: with the latter, `intel_pstate` forces EPP to `performance`, the CPU never rests and the voltage regulators produce audible coil whine

#### alienware-battery

- battery only; goal: maximize battery life, stricter than balanced-battery: boost off, `quiet` platform profile and the dGPU forced off (32A.14)

### 32A.2 CPUFreq, Intel P-state, EPB/EPP and boost

| Profile | Governor | EPB | EPP | Boost |
|---|---|---|---|---|
| balanced | powersave | normal | balance_power | on |
| balanced-battery | powersave | balance-power | balance_power | on |
| performance | powersave | performance | balance_performance | on |
| battery | powersave | power | power | off |

**Kernel requirements:**

- CPU frequency scaling and Intel P-state in active mode, with HWP; in that mode, `powersave` and `performance` are `intel_pstate`'s own policies
- EPB and EPP interfaces
- turning boost on/off at runtime
- don't remove a governor just because it isn't the default (the generic ones stay as modules, loaded when chosen)

### 32A.3 ACPI platform profile

| Profile | `/sys/firmware/acpi/platform_profile` |
|---|---|
| balanced | balanced |
| balanced-battery | balanced |
| performance | balanced-performance |
| battery | quiet |

When stopping, the profiles hand `balanced` back to the firmware. A `platform_profile` change can make the EC reprogram the RAPL limits.

**Requirements:** ACPI platform profile and the Dell/Alienware/ACPI drivers that provide it. It takes an active part in the power policy.

### 32A.4 Intel RAPL / powercap

The profiles write to `/sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw` and to `/sys/class/powercap/intel-rapl-mmio:0/` (both backends get the same values).

The firmware allows up to 157 W of package power (PL2). The laptop's total power limit is 330 W (the adapter's capacity).

| Profile | PL1 / long term | PL1 window | PL2 / short term | PL4 / peak |
|---|---:|---:|---:|---:|
| balanced | 55 W | 64 s | 86 W | 160 W |
| balanced-battery | 24 W | 28 s | 48 W | 72 W |
| performance | 117 W | 128 s | 157 W | 330 W |
| battery | 12 W | 16 s | 24 W | 42 W |

The limits are written so that `PL1 <= PL2 <= PL4` holds after every write: those going up, from the top down (PL4, PL2, PL1); then those going down, from the bottom up.

**Implementation (`power-policy.bash`):**

- the firmware applies `platform_profile` asynchronously: the RAPL writes wait 16 s after the change, inside a transient systemd unit (`systemd-run`), so `tuned` isn't blocked
- each profile change uses a unique unit name and a run ID: a run superseded by a newer change exits without writing
- the check at 10, 20 and 30 s verifies the *effective* limit (the lower of MSR and MMIO) and rewrites it if the EC changed it; in `quiet`, the EC sets the MMIO PL1 back to 50 W, but the MSR still applies, and the effective limit stays right
- the result goes to the journal (`Applied platform profile ...`)
- the PKG_POWER_LIMIT lock is disabled in the firmware, so the writes work

**Requirements:** Intel RAPL (MSR and MMIO, `processor_thermal_rapl`), the `powercap` framework and the sysfs interface.

### 32A.5 PCI runtime PM and ASPM

All profiles use (through `alienware-common`) `/sys/bus/pci/devices/*/power/control=auto`.

| Profile | ASPM policy |
|---|---|
| balanced | powersave |
| balanced-battery | powersupersave |
| performance | performance |
| battery | powersupersave |

**Requirements:** PCI runtime PM and PCIe ASPM with runtime policy changes; don't build the kernel with ASPM permanently disabled.

### 32A.6 HDA audio and power saving

The profiles change `/sys/module/snd_hda_intel/parameters/power_save`:

| Profile | Timeout |
|---|---:|
| balanced | 10 s |
| balanced-battery | 10 s |
| performance | 0 s |
| battery | 1 s |

The NVIDIA HDMI codec shows up in powertop as one of the biggest consumers, and suspending the codec saves power, but resuming can produce an audible pop: balanced and balanced-battery use 10 s to reduce the pops, battery accepts 1 s, performance disables it.

**Requirements:** `snd_hda_intel` power management, the `power_save` parameter and Intel/NVIDIA HDA runtime PM.

### 32A.7 Swap, zswap and page-cluster

All profiles use (through `alienware-common`):

```ini
vm.swappiness=60
vm.page-cluster=1
```

With `zswap`, large per-page-fault readahead tends to be wasted when the page comes back from the compressed pool in RAM; page-cluster=1 keeps a small readahead for pages `zswap` rejected.

**Requirements:** swap, `zswap`, `vm.swappiness` and `vm.page-cluster`.

### 32A.8 Writeback / VM

| Profile | Sysctls |
|---|---|
| balanced (`alienware-common` default) | `vm.dirty_writeback_centisecs=500` |
| balanced-battery | `vm.dirty_writeback_centisecs=1500` |
| performance | `dirty_bytes=10%`, `dirty_background_bytes=3%`, `vm.dirty_writeback_centisecs=500` |
| battery | `vm.dirty_writeback_centisecs=1500`, `vm.dirty_expire_centisecs=6000` |

On battery, writeback is grouped into less frequent bursts to keep the NVMe truly idle for longer; battery accepts a larger window of not-yet-persisted data in case of a crash.

### 32A.9 NMI watchdog

| Profile | `kernel.nmi_watchdog` |
|---|---:|
| balanced | 1 |
| balanced-battery | 0 |
| performance | 1 |
| battery | 0 |

NMI watchdog / hard lockup detector support stays built, and `tuned` decides its state at runtime. While the hang in 32A.16 is being investigated, the battery profiles also use 1.

### 32A.10 USB autosuspend

The balanced-battery and battery profiles use the `[usb]` plugin with `autosuspend=1`.

**Requirements:** USB runtime PM and autosuspend, with the actual drivers for USB audio, HID, webcam, phones and development boards compatible with that mechanism.

### 32A.11 Wi-Fi power save

The balanced-battery and battery profiles turn on 802.11 power save through a script (`wifi_powersave_on` at start, `wifi_powersave_restore` at stop), because it has no sysfs interface.

**Requirements:** `iwlwifi`/cfg80211/mac80211 power management, switchable at runtime.

### 32A.12 Wake-on-LAN and network wakeup

In the balanced-battery and battery profiles: `/sys/class/net/*/device/power/wakeup=disabled` and, on the Killer E3000 (`enp110s0`), `wake_on_lan=d`. That way Wi-Fi and Ethernet aren't armed as wakeup sources on battery, and the E3000's PHY doesn't stay active waiting for magic packets.

**Requirements:** device wakeup infrastructure, Wake-on-LAN/ethtool on `r8169`/the Realtek PHY and runtime PM for the network interfaces. The profiles need the support in order to turn it off.

### 32A.13 menuconfig selection rule derived from the profiles

The kernel provides mechanisms, and `tuned` chooses the policy at runtime. Don't remove a feature just because one of the profiles leaves it off: if another profile turns it on or changes it, the support stays built. Everything that appears in 32A.2 to 32A.12 and 32A.14 counts as used.

### 32A.14 dGPU forced off (alienware-battery)

- after applying the profile, a transient unit (`alienware-dgpu`) checks whether the dGPU reached D3cold
- if it didn't, it logs to the journal what keeps it awake (`journalctl -t alienware-dgpu`): processes with `/dev/nvidia*` or the DRM nodes open, and active NVIDIA services
- when it's safe (no users), it stops `nvidia-persistenced`, removes the dGPU's PCI functions (`/sys/bus/pci/devices/*/remove`) and writes the services to restart to `/run/tuned/alienware-dgpu-removed`; on a profile change, a PCI rescan (`/sys/bus/pci/rescan`) brings it back and restarts `nvidia-persistenced` and `nvidia-undervolt`

**Requirements:** PCI device hotplug/removal through sysfs, PCI rescan, PCI runtime PM and D3cold through ACPI.

### 32A.15 Battery power draw

With `alienware-battery`, 20% brightness, the display at 60 Hz and the screen on, the battery supplies ~17–18 W, of which the package uses only ~4.6–4.9 W. The rest comes from the platform (display, chipset, memory, SSDs, Wi-Fi, lighting, conversion losses).

- the package stays in PC2/PC3; PC6/PC8 barely happen and PC10 never does, because the panel without PSR (4) keeps framebuffer reads active. With the screen on, the processor-side tweaks are at their limit
- cores: P-cores 85–97% in CC7, E-cores 96–99% in CC6
- LTRs limiting the package (`intel_pmc_core`, `ltr_show`): Wi-Fi (CNV) 102 µs, xHCI 46 µs, `SOUTHPORT_F` 30.7 µs
- tested with no measurable gain, so left out of the profiles: autosuspend of the internal keyboard and the AW-ELC; L1/L1.2 on the Ethernet link
- keyboard lighting: off 16.75 W, low 17.18 W (+0.4 W), high 17.62 W (+0.9 W). On battery, turning it off gains about 3% (low) to 5% (high) of battery life
- measuring tools: `turbostat`, `intel_pmc_core`'s counters (`package_cstate_show`, `ltr_show`) and the average power from the change in the battery's `charge_now` (30)

### 32A.16 Hang under investigation

A complete hang (frozen screen, no response to Ctrl+Alt+F, nothing written to the journal) happened right after a `tuned-adm profile alienware-battery` with thermald on and the session locked. The cause wasn't identified; with thermald disabled and the session unlocked, the same switch didn't hang. Capture set up until the cause shows up (temporary files, to be deleted later):

- `kernel.nmi_watchdog=1` in the battery profiles too (32A.9)
- `/etc/sysctl.d/90-debug-travamento.conf`: `kernel.hardlockup_panic=1`, `kernel.softlockup_panic=1`, `kernel.panic=10` (the lockup becomes a panic, saved to pstore, and the system reboots after 10 s)
- `/etc/systemd/journald.conf.d/90-debug-sync.conf`: `SyncIntervalSec=10s`
- EFI pstore and `systemd-pstore` (8), `DPM_WATCHDOG` in `linux-tkg` (31) and full SysRq (33.6)
- CPU crashlog: on in the firmware (1A) and read by `intel_pmt_crashlog` (`CONFIG_INTEL_PMT_CRASHLOG=m` in the fragment), in `/sys/class/intel_pmt/crashlog*`

## 33. Requirements for choosing menuconfig options

### 33.1 The kernel is specific to this Alienware

- Keep all real hardware, the real uses and the already declared future uses
- Remove hardware from other platforms/absent manufacturers
- Don't keep drivers "just in case" without a declared plausible use
- Don't remove base infrastructure if real hardware depends on it
- Tell generic infrastructure apart from specific drivers

### 33.2 Preference for modules

Maximize m over y. Use y when needed early, when the Kconfig requires it, when there is a real advantage, or when the core must exist before its consumers. Each subsystem's decisions are in its own section.

**Modules in `linux-tkg`** (every tristate option that can be a module without losing function), besides those in 33.3:

- `FUSE_FS`, `AUTOFS_FS`, `CONFIGFS_FS`, `BINFMT_MISC`, `EXT4_FS`, `NTFS_FS`, `UNICODE`
- `ACPI_AC`/`_BATTERY`/`_BUTTON`, `ACPI_FAN`
- `USB`, `USB_SERIAL`, `HID`, `SERIO`, `INPUT_EVDEV`, `INPUT_LEDS`, `LEDS_CLASS`, `BACKLIGHT_CLASS_DEVICE`, `HWMON`, `WATCHDOG_CORE`, `EDAC`/`EDAC_GHES`, `EXTCON`, `DMI_SYSFS`, `PCI_STUB`, `HW_RANDOM`, the dma-buf heaps
- `SCSI`/`BLK_DEV_SD`, `I2C_DESIGNWARE_*`, `X86_MSR`/`X86_CPUID`
- the `MQ_IOSCHED_DEADLINE` (8), BFQ and Kyber I/O schedulers; the generic cpufreq governors
- network: `PACKET`, `PACKET_DIAG`, `UNIX_DIAG`, `NET_SCH_FQ_CODEL` (6), `NET_DROP_MONITOR`, `CONNECTOR` (`PROC_EVENTS` goes, and no program uses it)
- cryptography: AES, CBC, CTR, CTS, ECDH, MD5, SHA-1, SHA-3, BLAKE2b, xxHash, CRC32c, `CRYPTO_DRBG`, `CRYPTO_JITTERENTROPY`, `CRYPTO_PCRYPT`, `CRYPTO_LZ4HC`. KDE Wallet, gnome-keyring, GPG and the like encrypt in userspace and don't depend on them
- `IKCONFIG` (with `IKCONFIG_PROC`) and `IKHEADERS`

**Stay y:** `BINFMT_SCRIPT` and `BINFMT_ELF`, `FW_LOADER`, `EFI_VARS_PSTORE` (crashes from early boot), `TCP_CONG_CUBIC` (the TCP default), `EFIVAR_FS` (33.3), `DRM`/`DRM_SIMPLEDRM`/`FB` (33.3), `ACPI_THERMAL` (22), `RTC_DRV_CMOS` (correct clock from boot through `RTC_HCTOSYS`, including in the initramfs's journal), `NVME` available early, the I2C core (26), and the options selected by others that must stay built in (for example, module-signing cryptography, `NLS` through ACPI and USB).

### 33.3 Initramfs/UKI

A module doesn't mean unavailable at boot. The user uses `mkinitcpio`, UKI and `systemd-boot`.

**How `mkinitcpio` chooses the modules** (read from the source code, commit `68ebfd2` from 2026-10-18):

- `autodetect` reads `DRIVER=` and `MODALIAS=` from every `uevent` in the running kernel's `/sys/devices`, resolves them with the target kernel's `modprobe -R`, and adds the root filesystem's module (`fs-btrfs`). The following hooks only include modules from that list. That's why the UKI must be generated with the hardware visible (this also applies in the reinstall's chroot)
- built-in options are read from `modules.builtin.modinfo` and skipped without error: switching an option between y and m doesn't require changing `MODULES` or the hooks, except for what no hook includes
- each module brings along its dependencies (`depends`), its `softdep`s and the firmware it declares; `weakdep` isn't followed
- `MODULES` goes into the image and is loaded explicitly at boot (`/etc/modules-load.d/MODULES.conf` in the initramfs). It's for what no hook includes
- `mkinitcpio -M` shows the autodetect list; `mkinitcpio -v` shows each module added

**What each hook in use puts in the UKI:**

| Hook | Always (if the module exists) | Only if autodetected |
|---|---|---|
| `systemd` | `crypto-lzo`, `crypto-lz4` | — |
| `microcode` | only this CPU's microcode (`GenuineIntel.bin`), in the early cpio | — |
| `keyboard` | `usbhid`, `xhci_pci`, `xhci_hcd`, `ehci`/`ohci`, `thunderbolt` | USB controllers, `drivers/hid`, `serio` (i8042) and `input/keyboard` (atkbd) |
| `block` | `nvme`, `ahci`, `sd_mod`, `usb_storage`, `uas`, `mmc_block`, `virtio_blk`, `virtio_scsi` | `block`, `ata`, `scsi`, `nvme`, MMC, SPI, PCI controllers, MFD, clk, PHY, regulators |
| `sd-encrypt` | `dm-crypt`, `dm-integrity`, `hid-generic`, every module in `/crypto/` (unfiltered) | `drivers/char/tpm` (`tpm_crb`, `tpm`) |
| `filesystems` | `vfat` (with `nls_ascii` and `nls_cp437`) | the root fs (`btrfs`) |

**No `kms` hook:** `i915` doesn't go into the UKI, and the LUKS password prompt appears through `simpledrm`. `kms` would make the UKI much larger because of firmware: autodetect would also resolve the dGPU's modalias to `nouveau` (`modprobe -R` ignores the blacklist) and the iGPU's to `xe`, and each module brings all the firmware it declares. With `DRM_NOUVEAU` and `DRM_XE` off, `i915` and its firmware would remain, still unnecessary. To measure: `mkinitcpio -A kms -s -g /tmp/kms.img` and `du` on the build directory it reports.

**Display from early boot:** `DRM`, `DRM_SIMPLEDRM` and `FB` stay built in. As modules they would save nothing (`i915` and `nvidia_drm` load the DRM core on every boot), would leave the screen black until the initramfs, hiding early-boot errors and panics, and would make the LUKS prompt depend on `MODULES`. `simpledrm` needs `SYSFB_SIMPLEFB=y`, which tkg turns off and the fragment turns back on.

**Consequences for modularization:**

- can be m without changing anything in `mkinitcpio`: `NVME`, `BTRFS_FS`, `DM_CRYPT`, `DM_INTEGRITY`, `CRYPTO_AES_NI_INTEL`, `CRYPTO_XTS`, `TCG_TPM`, `TCG_CRB`, `USB_XHCI_PCI`/`USB_XHCI_HCD`, `USB_HID`, `HID_GENERIC`, `SERIO_I8042`, `KEYBOARD_ATKBD`, `VFAT_FS` and the NLS ones
- stay y, because they are used before the initramfs runs or because no hook includes the module: `BLK_DEV_INITRD` with `RD_ZSTD`, `DEVTMPFS`, `EFI_STUB`, `DRM_SIMPLEDRM` (password screen), `EFIVAR_FS` (the initramfs's systemd reads `HibernateLocation`, 1B), `UNIX` (systemd uses AF_UNIX sockets from PID 1), `BINFMT_ELF` and `BINFMT_SCRIPT`
- `zswap`: the compressor is chosen in an initcall, before the initramfs's systemd loads `MODULES`. `CRYPTO_ZSTD` (and `CRYPTO_LZ4`, `CRYPTO_LZO`) is y in the base and stays; the `MODULES` entries have no effect
- initramfs decompressors: only `RD_ZSTD` (the UKI uses zstd); the other `RD_*` go. If mkinitcpio's `COMPRESSION` changes, turn the matching `RD_*` back on, or the UKI won't boot
- `CRYPTO_MODULES`: without it, `sd-encrypt` puts every cryptography module in the UKI, which with maximum modularization means dozens. The variable is undocumented, but `sd-encrypt` reads it from the configuration (it can go in `/etc/mkinitcpio.conf.d/`); for `aes-xts-plain64`, the minimal list would be `aesni_intel xts`. Check with `mkinitcpio -v` and a test boot, with another kernel at hand
- no fallback UKI (a preset without `autodetect`): it would include every block, USB host, HID, input, cryptography and filesystem module, and would grow with modularization. The other two kernels play that role, and the ESP shared with Windows has no room for another UKI
- `MODULES_DECOMPRESS="yes"`: modules and firmware are decompressed and go into the image's zstd compression, which shrinks the UKI at level 19. The firmware on disk stays in zstd (`FW_LOADER_COMPRESS_ZSTD=y`)

### 33.4 Performance

High priority, but not above security. Avoid:

- unnecessary debugging (when the Kconfig discourages it), test drivers and simulators
- unused tracing (powertop needs the perf events and tracepoints)
- useless periodic work
- unnecessary thermal/power mechanisms that reduce performance (except when they increase hardware reliability)
- guest drivers on the host, unused qdiscs/classifiers, large drivers for impossible hardware

But don't sacrifice real functionality for a few KB.

### 33.5 Security

**Prefer settings that:** reduce the attack surface, avoid unnecessary raw access and raw flash/firmware access, remove legacy userspace interfaces and unused test/debug code, and work with Secure Boot. The concrete cases (GPIO, i2c-dev, SPI, thermal emulation, LIRC, watchdogs) are in their own sections.

**Active LSMs:** `capability,landlock,lockdown,yama,bpf`.

**systemd:** the REQUIREMENTS section of systemd's README (cgroup v2, BPF, seccomp, namespaces, among others) is a mandatory reference.

**tty line disciplines in use:** only `n_tty` and `n_null`: turning `LDISC_AUTOLOAD` off breaks nothing.

**The fragment's decisions, by section 0's security lever rule:**

- kept from the base: `X86_KERNEL_IBT`, shadow stack, `INIT_STACK_ALL_ZERO`, `INIT_ON_ALLOC_DEFAULT_ON`, `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `SLAB_FREELIST_RANDOM`/`_HARDENED`, `SLAB_BUCKETS`, `RANDOMIZE_KSTACK_OFFSET_DEFAULT`, `STACKPROTECTOR_STRONG`, `SECURITY_DMESG_RESTRICT`, `BPF_UNPRIV_DEFAULT_OFF`, `BPF_JIT_ALWAYS_ON`, `DEFAULT_MMAP_MIN_ADDR=65536`, every Intel CPU mitigation and the common ones
- turned on: `INIT_ON_FREE_DEFAULT_ON` (the most expensive; `init_on_free=0` on the command line turns it off for measuring), `ZERO_CALL_USED_REGS`, `SLAB_MERGE_DEFAULT` off, `KMALLOC_PARTITION_CACHES`, `PROC_MEM_NO_FORCE`, `MODULE_SIG_FORCE` (18), `SECURITY_LOCKDOWN_LSM_EARLY`
- UBSAN out: without `UBSAN_TRAP` it only warns in dmesg, blocking nothing, and it is debugging with a cost across the whole kernel and the DKMS modules; with the trap, harmless behavior would bring down the kernel or nvidia
- interfaces and raw access removed: `DEVMEM` (32), `DEVPORT`, `X86_IOPL_IOPERM`, `HIBERNATION_SNAPSHOT_DEV` (`/dev/snapshot`, no uswsusp), `KEXEC`/`KEXEC_FILE`/`CRASH_DUMP`/`KEXEC_HANDOVER`/`LIVEUPDATE`, `X86_X32_ABI`, `LDISC_AUTOLOAD`, `NVRAM`, `EFI_HANDOVER_PROTOCOL`, `MODULE_FORCE_LOAD`/`_UNLOAD`, `SND_OSSEMUL`, `ACPI_EC_DEBUGFS`; with `EXPERT`: `UID16`, `SGETMASK_SYSCALL`, `X86_VSYSCALL_EMULATION`, `EFI_RUNTIME_MAP`, `FIRMWARE_MEMMAP`, `GPIO_CDEV`
- reduced attack surface: LSMs built outside the active list (`SECURITY_SMACK`, `_TOMOYO`, `_LOADPIN`, `_SAFESETID`, `_IPE`; AppArmor and SELinux stay), initramfs decompressors other than zstd, partition tables other than GPT and MBR (AIX, Mac, BSD, Minix, Solaris, LDM, Karma), datacenter/BMC/router network protocols (DCB, MCTP, NC-SI, MPLS, PSP, switchdev, netkit, SRv6, RPL, IOAM, MRP, CFM), `BSD_PROCESS_ACCT`, `CGROUP_RDMA`, `ACCESSIBILITY`
- at N because the Kconfig says so: `BUG_ON_DATA_CORRUPTION` and `PANIC_ON_OOPS` ("If unsure, say N"), `PAGE_TABLE_CHECK` ("If unsure say n"), `STRICT_SIGALTSTACK_SIZE` ("Say 'N' unless you want to really enforce"), `IMA` and `EVM`, `SYSFS_SYSCALL`, the development `DEBUG_*` options
- `ALLOW_DEV_COREDUMP` stays (31): the Kconfig says "If unsure, say Y" and only adds "Say 'N' for more sensitive systems"
- off because they would break declared uses: `STATIC_USERMODEHELPER` (on-demand module loading through modprobe and systemd-coredump would go through an intermediate binary Arch doesn't have), lockdown in integrity/confidentiality (hibernation, 18), `SECURITY_LOADPIN` (would only accept modules and firmware from the initramfs), `MODIFY_LDT_SYSCALL` and `X86_16BIT` (Wine, 17), `INTEGRITY_CA_MACHINE_KEYRING` (the MOKs have no keyUsage, 18), `IO_URING` and `KCMP` (in use; `KCMP` is required by systemd and selected by DRM)
- unavailable with GCC: kCFI (GCC 16.2 doesn't accept `-fsanitize=kcfi`), `KSTACK_ERASE` (requires Clang's stack depth callback) and `RANDSTRUCT` (would break the DKMS modules with precompiled objects)

**Security mechanisms in use:** Secure Boot with MOK (18), TPM 2.0 (19), `firewalld`/`nftables` (6), fwupd and ClamAV. ClamAV does on-demand scanning, but real-time scanning (`clamonacc`) may come into use: it depends on `FANOTIFY` and `FANOTIFY_ACCESS_PERMISSIONS`, which stay.

### 33.6 Debug

- **the user's goal:** diagnose errors caused by the build choices and general errors in the programs in use. Don't keep debugging just because it exists
- stay: `IKCONFIG`/`IKCONFIG_PROC` (`/proc/config.gz`, to compare with zen), `KALLSYMS`/`KALLSYMS_ALL` (function names in oopses), `PRINTK_TIME`, `DYNAMIC_DEBUG`, `MAGIC_SYSRQ`, pstore (`PSTORE`, `EFI_VARS_PSTORE` with the backend on, `PSTORE_COMPRESS`), `FTRACE`/`FUNCTION_TRACER`, `KPROBES`/`KPROBE_EVENTS`/`UPROBE_EVENTS`, `PERF_EVENTS`, `BPF_SYSCALL`/`BPF_EVENTS` (bpftrace), `DEBUG_FS`, `COREDUMP` (`coredumpctl`), the latency tracers (`HWLAT_TRACER`, `OSNOISE_TRACER`, `TIMERLAT_TRACER`), `ACPI_DEBUG`, `PM_DEBUG`, `PROC_KCORE` (perf and drgn), `SLUB_DEBUG` (off at runtime), iwlwifi's debug, `DPM_WATCHDOG` and `DEBUG_NMI_SELFTEST` (while the investigation in 32A.16 lasts)
- `DEBUG_INFO_BTF` stays because systemd uses the BPF LSM, which requires BTF; with `DEBUG_INFO_COMPRESSED_ZSTD`. DWARF (decoding source lines, full drgn, `crash`, `perf probe` with variables) isn't needed: `_STRIP="true"` with BTF turned back on by the fragment, and a build with `_STRIP="false"` and `_NUKR="false"` only if a kernel bug needs decoding
- program errors don't depend on kernel debugging: the symbols for Arch's packages come through debuginfod
- go: `X86_DECODER_SELFTEST`, `DEBUG_RODATA_TEST`, `DEBUG_SHIRQ`, `RUNTIME_TESTING_MENU`, `FUNCTION_ERROR_INJECTION`, `BLK_ERROR_INJECTION`, `MMIOTRACE` ("If you are not helping to develop drivers, say N"), `USB_XHCI_DBGCAP`/`EARLY_PRINTK_USB_XDBC` and `EARLY_PRINTK_DBGP` (they need a debug cable and another computer), `OVMF_DEBUG_LOG` (VM only), `MEDIA_TEST_SUPPORT`, `LOCK_EVENT_COUNTS` and `X86_CPA_STATISTICS` (counters on hot paths that nobody reads), `USB_STORAGE_DEBUG`, kdump, kmemleak (its hooks stay on every allocation even when off), UBSAN and `NTFS_DEBUG` (it only debugs the driver itself)
- Magic SysRq with every function (`kernel.sysrq = 1` in `/etc/sysctl.d/sysrq.conf`; systemd's default only allows sync), to recover from hangs with REISUB

### 33.7 Specific hardware > generic name

**Base decisions on:**

- `lspci -knnQ`, `lsusb`, ACPI IDs, sysfs, loaded driver, ALSA codecs, hwmon, DMI
- `/sys/class/watchdog`, ACPI WDAT, SoundWire sysfs, TPM sysfs/ACPI, power_supply sysfs, `lsmod`, `/proc/cpuinfo`
- present ACPI devices: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" != 0 ] && echo "$(cat $d/hid 2>/dev/null) ${d##*/}"; done | sort -u`
- the driver of each present ACPI device: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" = 0 ] && continue; a=$(readlink $d/driver); b=$(readlink $d/physical_node/driver); echo "${d##*/} acpi:${a##*/} phys:${b##*/}"; done 2>/dev/null | grep -v '^device:\|^ACPI0007\|^LNX'`
- platform drivers with a bound device (the `/sys/bus/platform/drivers` list alone shows every registered driver): `for d in /sys/bus/platform/drivers/*; do [ -n "$(find "$d" -maxdepth 1 -type l ! -name module)" ] && echo "${d##*/}"; done`
- programs that use a netlink protocol (for example, the connector, protocol 11): `awk 'NR>1 && $2==11 {print $3}' /proc/net/netlink | sort -u` (only `0` means the kernel alone)
- `modprobed-db`, to record the modules loaded over weeks
- other commands that can extract more information about the system

Don't assume from the name. Examples:

- Alder Lake pinctrl is correct for Raptor Lake HX
- NVIDIA GPU I2C isn't needed just because there is an NVIDIA GPU
- the old Intel PCH thermal isn't needed just because there is an Intel PCH
- Intel USBIO GPIO isn't needed just because it's Intel
- ChromeOS EC isn't needed just because the laptop has an EC
- PMIC drivers aren't needed just because there is a battery
- VirtIO frontends aren't needed just because the host runs QEMU

When in doubt, ask the user (provide commands to gather new information); never invent or assume hardware.

### 33.8 Host vs guest

The kernel is the physical Alienware host and won't be used in guests. Don't enable: Hyper-V guest, Xen frontend, VirtIO frontend, VMware guest, KVM guest PTP, virtual GPIO/I2C.

## 34. Precedence of information

- The most recent measured data sent by the user
- The most recent decision in the chat
- An earlier decision in the chat
- This document
- Generic knowledge, only if the user asks for a new recommendation

Never let an old `.myfrag` prevail over a later explicit decision.

## 35. Operational summary

**This is a:**

- Alienware m16 R1, BIOS 1.36.0
- i9-13900HX, 24C/32T, microcode 0x137
- 32 GB DDR5
- Intel UHD + RTX 4070 Laptop
- Realtek ALC3254 + Intel/NVIDIA HDMI
- Intel AX211 Wi‑Fi/Bluetooth
- Killer E3000 / `r8169`
- Thunderbolt 4 Maple Ridge
- Realtek RTS525A SD
- ADATA NVMe (the installed Micron is disregarded)
- Btrfs root (zstd:3, no TRIM) inside LUKS2
- 16 GiB Btrfs swapfile + `zswap` (zstd) + hibernation (lz4, no `resume=`) + S3
- dGPU with RTD3 (can power off); iGPU as the default
- Secure Boot + shim + MOK + UKI + `mkinitcpio`
- TPM 2.0 CRB
- iTCO watchdog
- UVC webcam
- QEMU/KVM/libvirt + passthrough (GPU, NVMe, USB, physical TPM) + Looking Glass (`kvmfr`) + hugepages + emulated TPM (Windows 10 VM)
- WireGuard/OpenVPN/`firewalld`/`nftables`
- Arduino/ESP32/RPi and common USB serial
- USB/MIDI audio interfaces
- Canon E4210 through IPP/CUPS/SANE/Avahi
- Xbox/PlayStation/Steam Controller
- Android/iPhone
- external USB storage/network
- CPU undervolt through `intel-undervolt`; GPU tuned through NVML
- four custom `tuned` profiles (32A): balanced, balanced-battery, performance and battery; thermald disabled

**Priorities (in section 0's order):**

- keep the declared uses
- security (every lever, except "If unsure, say N" and broken uses)
- performance
- real hardware (remove the absent)
- modularization
- minimalism
