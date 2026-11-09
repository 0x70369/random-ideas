# Alienware m16 R1 — Hardware, usos e requisitos para configuração do kernel

Última atualização do documento: 2026-11-10

## 0. Regras Máximas

- O kernel sendo configurado aqui será usado exclusivamente nesse laptop. Ele não será usado nem em outros computadores, nem em VMs guests desse laptop.
- Em caso de dúvidas, sempre olhar a documentação online oficial dos projetos/programas/aplicações usados pelo usuário.
- Preservar infraestrutura de debugging que realisticamente poderia ser usada nesse kernel. O que o Kconfig disser que não vale a pena deve ser removido.
- O Kconfig oficial é a autoridade máxima e deve ser sempre consultado. Caso o usuário queira algo que vai contra a recomendação do Kconfig, comente e deixe o usuário escolher.
- A performance e eficiência máximas são o objetivo desse kernel, mas jamais ao custo da segurança do sistema.
- Todas as alavancas de segurança do Kconfig ficam ligadas, exceto as que o Kconfig manda deixar em N na dúvida ("If unsure, say N" ou equivalente) e as que quebrariam um uso declarado (decidido em 2026-11-10; os casos estão em 33.5).
- O que cobrir hardware não existente nesse laptop deve ser removido.
- Tudo que puder ser modularizado deve ser, salvo se for algo essencial para iniciar o sistema ou for extremamente comum (como suporte para scripts com #!).
- Se o usuário modularizar algo que não deveria ser, explicar e deixá-lo escolher.
- Tudo que estiver em uso no laptop deve ser mantido: driver ligado a um dispositivo, módulo carregado ou interface usada por algum programa. A única exceção declarada é o SSD Micron (ver 8). Módulos que carregam só porque outra opção da configuração os exige, sem dispositivo deste laptop, não contam como em uso.

## 1. Identificação geral

- Modelo: Alienware m16 R1
- Fabricante: Dell / Alienware
- SKU / Platform ID: 0BFB
- Placa-mãe: Dell 00DK46, rev. A00
- Service Tag / serial anteriormente registrado: 80S9K34
- Versão da BIOS anteriormente registrada: 1.34.0
- A BIOS 1.36.0 (2026-10-22) foi extraída e comparada com a 1.34.0: o menu escondido (módulo Setup) é idêntico byte a byte; mudam o Intel ME (16.1.40.2765 → 16.1.42.2872), o pacote do EC (1.15.0 → 1.16.0), os drivers de rede do BIOS Connect e módulos de segurança (criptografia, TPM, variáveis e WMI da Dell). O microcódigo embutido continua 0x133.
- EC firmware anteriormente registrado: 1.21
- Sistema principal: Arch Linux
- Desktop: KDE Plasma
- Boot: `systemd-boot` com UKIs
- Kernel customizado: `linux-tkg`
- Kernels instalados hoje: `linux` 7.2.14-arch1-1 e `linux-zen` 7.2.14-zen1-1 (em uso no levantamento de 2026-11-08)

## 1A. Firmware: configurações que afetam o kernel

Alteradas pelo usuário no menu escondido (Smokeless UMAF) ou conferidas nos padrões. Ver a Seção 7 da página da wiki para caminhos e offsets.

**Alteradas:**

- ACPI S3 Support: Enabled (a Dell entrega Disabled) → o sono S3 (`deep`) existe e é usado
- UnderVolt Protection: Disabled e OverClocking Feature: Enabled → permitem o undervolt por MSR do `intel-undervolt`
- Legacy Game Compatibility Mode: Enabled → Scroll Lock alterna o standby dos E-cores; também ativa teclado/mouse PS/2 nas Platform Settings
- WDT Enable: Enabled (watchdog do OC, usado pelo XTU no Windows)
- BIST: Enabled (autoteste da CPU a cada reset)
- REFRESH_2X_MODE: Enabled for WARM or HOT (refresh da RAM dobra quando ela esquenta)
- Power Limit 2: 157 W; multiplicador máximo 54x nos P-cores e 39x nos E-cores (clusters); BCLK 100,00 MHz; iGPU até 1650 MHz; IccMax 215 A (IA) e 30 A (GT)

**Mantidas nos padrões porque o sistema depende delas:**

- VMX e VT-d: Enabled (KVM e passthrough)
- Above 4GB MMIO e Resizable BAR (Auto): necessários ao `NVreg_EnableResizableBar=1`
- ACS em cada root port: Enabled → a dGPU fica no próprio grupo IOMMU sem o patch de ACS override
- ACPI D3Cold Support: Enabled → necessário para a dGPU desligar por completo (RTD3)
- Package Power Limit MSR Lock: Disabled → o `tuned` consegue escrever os limites RAPL em runtime
- Tcc Activation Offset: 0, com Tcc Offset Lock Enable: Enabled → o throttling começa no Tjmax de 100 °C, e o `tjoffset` do `intel-undervolt` é ignorado

**No menu F2 (Dell):**

- Hybrid Graphics: ativado (sem ele a dGPU controla todas as telas e nunca desliga)
- Discrete Graphics Controller Direct Output Mode: ativado (para a menor latência entre a dGPU e monitores externos); com um monitor externo ligado, a dGPU fica acordada

## 1B. Linha de comando do kernel

Montada a partir de `/etc/cmdline.d/` e embutida na UKI. Linha atual (`/proc/cmdline`, 2026-11-08) com as mudanças já decididas para o zswap, um parâmetro por linha:

```text
rd.luks.name=<UUID do LUKS>=root
rd.luks.options=password-echo=no,tries=2,timeout=60s
root=/dev/mapper/root rootfstype=btrfs rootflags=subvol=/@
resume=/dev/mapper/root resume_offset=533760 hibernate.compressor=lz4
zswap.enabled=1 zswap.shrinker_enabled=1 zswap.compressor=zstd zswap.max_pool_percent=23 zswap.accept_threshold_percent=90
intel_iommu=on
threadirqs
loglevel=7
```

- depois da reinstalação com o esquema de subvolumes planejado (ver 8), o `rootflags` passa a `subvol=/Arch/@`, e o `resume_offset` muda
- `hibernate.compressor=lz4`: lz4 descomprime mais rápido que o lzo padrão. No kernel próprio, o lz4 é o padrão do Kconfig (`HIBERNATION_COMP_LZ4=y` no `.myfrag`), e o parâmetro fica redundante
- `intel_iommu=on`: liga o IOMMU, que o kernel deixa desligado por padrão (`INTEL_IOMMU_DEFAULT_ON` não está ativo no zen); o kernel registra `DMAR: IOMMU enabled`, com duas unidades (`dmar0`, `dmar1`) e largura de endereço de 39 bits. No kernel próprio, `INTEL_IOMMU_DEFAULT_ON=y` (`.myfrag`) torna o parâmetro redundante; pode ficar sem efeito colateral
- pstore: a linha não tem `efi_pstore.pstore_disable=0`, e a configuração do Arch desliga o backend EFI por padrão (ver 8, Swap / hibernação)
- zswap: decidido trocar o compressor de lz4 para zstd (maior taxa de compressão; o uso de memória é alto com a VM e o build em tmpfs) e voltar a pool para 23% (a linha atual usa lz4 e 50%); o `zswap.zpool=zsmalloc` da linha atual sai, porque o 7.2 não tem mais escolha de zpool e o zsmalloc é o único alocador
- no kernel próprio, o zstd já é o padrão do Kconfig (`ZSWAP_COMPRESSOR_DEFAULT_ZSTD=y` na base, com `CRYPTO_ZSTD=y`)
- `threadirqs`: handlers de interrupção em threads, para áudio de baixa latência

## 2. CPU e plataforma

- CPU: Intel Core i9-13900HX
- Família: Raptor Lake-HX
- Topologia: 24 cores / 32 threads
- 8 P-cores
- 16 E-cores
- CPU híbrida Intel; SMT nos P-cores.
- O kernel foi pensado para `NR_CPUS`=32.
- Endereçamento: 39 bits físicos, 48 bits virtuais (sem `la57`: paginação de 5 níveis não tem uso aqui)
- Microcódigo em uso: 0x137, carregado cedo pelo pacote `intel-ucode` (hook `microcode` do `mkinitcpio`), mais novo que o 0x133 embutido na BIOS
- Sem Total Memory Encryption (sem a flag `tme`)
- Sem SGX, TDX e RDT/resctrl: não há as flags `sgx`, `rdt_a`, `cat_l2`, `cat_l3`, `cqm_llc` nem `mba` (conferido em 2026-11-09). `X86_SGX`, `INTEL_TDX_HOST` e `X86_CPU_RESCTRL` saem
- `intel_pstate` em modo `active`, com `hwp` e `hwp_epp` (conferido em 2026-11-09): o Turbo Boost Max 3.0 (`INTEL_TURBO_MAX_3`), que só serve sem HWP, sai

**Flags relevantes de `/proc/cpuinfo`:**

`vmx ept ept_ad vnmi x2apic tsc_deadline_timer hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req hfi ibt user_shstk split_lock_detect intel_pt arch_lbr pku ospke umip waitpkg avx2 avx_vnni sha_ni gfni vaes vpclmulqdq movdiri movdir64b serialize fsrm clwb rdpid md_clear flush_l1d arch_capabilities ibrs_enhanced`

- `ibt` e `user_shstk`: CET disponível (IBT no kernel, shadow stack para userspace)
- `hwp*` e `hfi`: Intel P-state com HWP/EPP e Intel HFI
- Não há AVX-512.

**Vulnerabilidades que o kernel reporta (`bugs`):**

`spectre_v1 spectre_v2 spec_store_bypass swapgs eibrs_pbrsb rfds bhi spectre_v2_user vmscape`

As mitigações dessas devem permanecer (segurança acima de performance). As que não aparecem na lista não afetam esta CPU.

Diversos drivers do kernel cobrem Raptor Lake HX com nomes que ainda contêm Alder Lake. Necessário verificar no Kconfig oficial.

### Dispositivos ACPI

Só os presentes (`status` diferente de 0). A tabela ACPI também descreve vários dispositivos ausentes, que não contam.

- Plataforma: `PNP0C09` (EC), `PNP0C14` (12 blocos WMI), `PNP0C0A` (bateria), `ACPI0003` (AC), `PNP0C0D` (tampa), `PNP0C0E` (botão de sono), `ACPI000C` (processor aggregator), `ACPI000E` (time and alarm, `acpi-tad`), `PNP0B00` (RTC), `PNP0103` (HPET), `PNP0A08` (raiz PCIe), `PNP0C02` (recursos da placa-mãe)
- Processadores: 64 objetos `ACPI0007` para 32 threads (o firmware declara objetos a mais)
- Intel: `INTC1085` (pinctrl Raptor Lake, `alderlake-pinctrl`), `INTC1070` (`intel-hid`), `INTC6001` (TPM CRB, `tpm_crb_acpi`), `INT33A1` (PEP, `intel_pmc_core`)
- DPTF: `INTC10A0` (`int3400 thermal`) e seis participantes `INTC1046` (`int3403 thermal`)
- Dell: `DLLK0BFB` (teclado PS/2, `i8042 kbd`) e `DLL0BFB` (porta auxiliar PS/2, `i8042 aux`)
- Touchpad: `VEN_06CB` (Synaptics), `i2c_hid_acpi`
- USB-C: `USBC000` (UCSI, `ucsi_acpi`)
- Sem driver ligado nem no kernel do Arch, que tem quase todos os drivers, então não pedem nada no kernel customizado: `INT340E`, `INTC109C`, `NVDA0820` (o driver da NVIDIA pode usá-lo por métodos ACPI, sem se ligar a ele) e `PRP00001` (2 instâncias). `PNP0000`, `PNP0100`, `PNP0103`, `PNP0A08` e `PNP0C02` são tratados pelo núcleo do kernel.
- Ausentes, portanto sem uso: os sensores de câmera MIPI (`OVTI01AS`, `INT33BE`, `SONY362A`, `SONY488A`) e os dispositivos de câmera `INT3471`/`INT3472`/`INT3474` (a webcam real é USB, então IPU e drivers de sensor MIPI ficam fora); os monitores de energia Microchip `MCHP1930`/`MCHP1940` (PAC193x/PAC194x); `DELL0029`, `DELL0033`, `DELLABC6`, `TXNW3643`, `INT3420`, `INT33E1`, `INT3519`, `INT3533`, `INTC1001`, `INTC1092`, `INTC10A3`; e o `PNP0C0C` (o botão de energia usa o evento fixo do ACPI)

### Drivers de plataforma em uso

`ac`, `acpi-battery`, `acpi-button`, `acpi-ec`, `acpi-tad`, `acpi-wmi`, `alarmtimer`, `alderlake-pinctrl`, `dell-smbios`, `dmic-codec`, `hid_sensor_custom`, `i2c_designware`, `i8042`, `idma64`, `int3400 thermal`, `int3403 thermal`, `intel-hid`, `intel_pmc_core`, `intel_rapl_msr`, `iTCO_wdt`, `pcspkr`, `processor_aggregator`, `rtc_cmos`, `rtsx_pci_sdmmc`, `serial8250`, `skl_hda_dsp_generic`, `tpm_crb_acpi`, `ucsi_acpi`

- `pcspkr` (bipe do PC speaker) está ligado, então fica
- `serial8250` aparece ligado, mas é o dispositivo de plataforma que o próprio driver 8250 cria: o laptop não tem nenhuma UART. O dmesg só mostra `Serial: 8250/16550 driver, 32 ports, IRQ sharing enabled`, sem nenhum `ttySN ... is a 16550A`, e não há dispositivo `PNP0501` (conferido em 2026-11-09). Decidido: `SERIAL_8250` sai; os adaptadores USB serial (13) não dependem dele
- `dcdbas` não é um driver de plataforma, mas está carregado e é usado pelo `dell_smbios` (backend SMM)
- `efi-framebuffer`/`simple-framebuffer` não aparecem porque o dispositivo é removido quando o `i915` assume a tela; continuam necessários no início do boot (ver 18)
- `coretemp` não aparece nesta lista, mas está carregado e funcionando (ver 23)

### Módulos carregados

Levantados com `lsmod` em 2026-11-08, no kernel do Arch. Todos ficam (regra da seção 0), exceto os que carregam só por dependência de configuração, listados no fim desta subseção. Agrupados:

- CPU, energia e telemetria: `coretemp`, `intel_cstate`, `intel_uncore`, `intel_uncore_frequency`, `rapl`, `intel_rapl_msr`, `intel_rapl_common`, `x86_pkg_temp_thermal`, `intel_powerclamp`, `intel_tcc_cooling`, `acpi_pad`, `intel_pmc_core`, `intel_pmc_ssram_telemetry`, `intel_pmc_pwrm_telemetry`, `intel_vsec`, `pmt_telemetry`, `pmt_discovery`, `pmt_class`
- DPTF: `int3400_thermal`, `int3403_thermal`, `int340x_thermal_zone`, `acpi_thermal_rel`, `processor_thermal_device_pci` e seus submódulos (`rapl`, `rfim`, `mbox`, `power_floor`, `wt_hint`, `wt_req`, `soc_slider`, `platform_temperature_control`)
- Dell/Alienware/WMI: `wmi`, `wmi_bmof`, `alienware_wmi`, `dell_wmi`, `dell_wmi_descriptor`, `dell_wmi_ddv`, `dell_wmi_sysman` (configurações da BIOS via `firmware_attributes_class`), `dell_smbios`, `dcdbas`, `dell_smm_hwmon`, `nvidia_wmi_ec_backlight`, `intel_hid`, `sparse_keymap`, `video`
- Gráficos: `i915` (em uso), `xe` (carregado sem uso; sai), `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm`, `drm_display_helper`, `ttm`, `cec`, `i2c_algo_bit`
- Áudio: `snd_sof_pci_intel_tgl` e a pilha SOF, `snd_soc_skl_hda_dsp`, `snd_soc_avs` (carregado sem uso; sai), `snd_hda_intel`, `snd_hda_codec_alc269`, `snd_hda_codec_intelhdmi`, `snd_hda_codec_nvhdmi`, `soundwire_intel`/`soundwire_bus`/`soundwire_cadence` (dependências do SOF, sem dispositivo SoundWire; saem), `snd_seq`, `snd_seq_dummy`, `snd_hrtimer`, `snd_ctl_led`
- Rede: `iwlmvm`, `iwlwifi`, `mac80211`, `cfg80211`, `r8169`, `realtek`, `ax88179_178a`, `usbnet`, `mii`, `ptp`
- Bluetooth: `btusb`, `btintel`, `bluetooth`, `bnep`, `rfcomm`; `btrtl`, `btbcm` e `btmtk` saem
- Netfilter (firewalld): `nf_tables`, `nft_ct`, `nft_fib_inet`/`ipv4`/`ipv6`, `nft_reject_inet`/`ipv4`, `nft_masq`, `nft_chain_nat`, `nf_conntrack` com os helpers `ftp`, `tftp`, `irc`, `sip`, `h323`, `pptp`, `sane`, `netbios_ns` e os `nf_nat` correspondentes
- Armazenamento: `nvme`, `nvme_core`, `nvme_auth`, `nvme_keyring`, `dm_crypt`, `dm_mod`, `trusted`, `encrypted_keys`, `tee`, `uas`, `usb_storage`, `sg`, `vfat`, `fat`, `rtsx_pci`, `rtsx_pci_sdmmc`, `mmc_core`
- Flash SPI: `spi_intel_pci`, `spi_intel`, `spi_nor`, `mtd` (ver 27)
- Criptografia: `aesni_intel`, `gf128mul`, `ccm`, `af_alg`, `algif_hash`, `algif_skcipher`, `crypto_user`
- Virtualização: `kvm_intel`, `kvm`, `irqbypass`, `vfio_pci`, `vfio_pci_core`, `vfio_iommu_type1`, `vfio`, `iommufd`
- Entrada e sensores: `i2c_hid_acpi`, `i2c_hid`, `hid_multitouch`, `intel_ish_ipc`, `intel_ishtp`, `intel_ishtp_hid`, `hid_sensor_hub`, `hid_sensor_custom`, `psmouse`, `serio_raw`, `mousedev`, `joydev`, `mac_hid`, `pcspkr`
- I2C/SMBus: `i2c_i801`, `i2c_smbus`, `i2c_mux`, `i2c_dev`, `intel_lpss_pci`, `intel_lpss`, `idma64`, `spd5118`
- Webcam: `uvcvideo`, `videodev`, `videobuf2_*`, `mc`
- USB-C/Thunderbolt: `thunderbolt`, `typec`, `typec_ucsi`, `ucsi_acpi`, `roles`
- Outros: `mei_me`, `mei_hdcp`, `mei_pxp`, `iTCO_wdt`, `intel_pmc_bxt`, `pinctrl_alderlake`, `acpi_tad`

`lsmod` só mostra o que estava carregado naquele momento. Usos declarados que não estavam ativos (VPN/TUN, WireGuard, bridge e `vhost_net` do libvirt, `uinput`, controles, USB serial, MIDI USB e outros) continuam valendo. Não aparecem também os componentes compilados dentro do kernel do Arch (por exemplo FUSE, Btrfs e o TPM).

Alguns módulos estão carregados só porque a configuração do Arch os puxa, e nenhum é necessário para o hardware deste laptop. Decidido: desligar as opções que os puxam.

- `btrtl`, `btbcm` e `btmtk`: o Bluetooth interno é Intel (`btintel`). O `btusb` só os exige porque está compilado com suporte a adaptadores Realtek, Broadcom e MediaTek (`BT_HCIBTUSB_RTL`, `_BCM`, `_MTK`). Só fariam falta com um adaptador Bluetooth USB externo dessas marcas.
- `xe`: a iGPU Raptor Lake é atendida pelo `i915`; nela o `xe` só funciona forçado (`force_probe`), em caráter experimental.
- `snd_soc_avs`: driver alternativo de DSP Intel; o áudio deste laptop usa o SOF.
- `soundwire_*`: dependências do suporte a SoundWire do SOF (`SND_SOC_SOF_INTEL_SOUNDWIRE`); o laptop não tem dispositivo SoundWire, e o áudio HDA funciona sem ele.
- Achados na revisão do `.myfrag` contra o Kconfig e o `modprobed.db` (2026-11-09):
  - `drm_gpusvm_helper`, `drm_gpuvm` e `gpu_sched`: dependências do `xe`
  - `nvme_auth` e `nvme_keyring`: puxados por `NVME_HOST_AUTH` (autenticação do NVMe over Fabrics, sem uso)
  - `tee`: puxado por `TRUSTED_KEYS_TEE`; as chaves confiáveis usam só o TPM
  - `tap`: puxado pelo `macvtap`, que o `localmodconfig` mantinha por causa do `vhost_net`; as VMs usam bridge e `tun` (ver 16)

**Desligar:**

- `BT_HCIBTUSB_RTL`, `BT_HCIBTUSB_BCM` e `BT_HCIBTUSB_MTK` (e, com eles, `BT_RTL`, `BT_BCM` e `BT_MTK` se nada mais os selecionar); fica `BT_HCIBTUSB` com o `BT_INTEL`
- `DRM_XE`; fica o `DRM_I915`
- `DRM_NOUVEAU`: a dGPU usa o driver proprietário `nvidia` (o `nvidia-utils` põe o `nouveau` na blacklist)
- `SND_SOC_INTEL_AVS`; fica o SOF
- `SND_SOC_SOF_INTEL_SOUNDWIRE` e o `SOUNDWIRE`: confirmado no Kconfig do 7.2.15 que nada que fica ligado seleciona o `SOUNDWIRE`; saem também `soundwire_intel`, `soundwire_cadence` e o `soundwire_amd`. SOF, HDA e SDCA continuam funcionando
- `NVME_HOST_AUTH`, `TRUSTED_KEYS_TEE`/`TEE`, `MACVLAN`/`MACVTAP`

Se o Kconfig mostrar que alguma dessas opções é selecionada por outra que fica ligada ("Selected by"), respeitar a dependência e avisar o usuário.

### PCI completo do laptop

A listagem abaixo é a referência para IDs e drivers; as seções seguintes só citam o endereço de cada dispositivo.

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

## 3. Memória

- 32 GB DDR5
- Registro anterior: 2 × 16 GB DDR5-5600
- Pentes sem ECC: o `ie31200_edac` aparece como candidato do host bridge, mas não tem o que reportar sem ECC
- Refresh 2x quando a RAM esquenta, configurado no firmware (REFRESH_2X_MODE)
- Compilação de kernel ocorre em tmpfs (`/tmp/kernel-build`, 42 GiB), portanto RAM/swap importam ao fluxo de build.

## 4. GPUs

A máquina tem 2 GPUs físicas.

### iGPU Intel

- `00:02.0` [8086:a788], driver `i915` (módulos `i915`, `xe`)
- GPU padrão do sistema

### dGPU NVIDIA

- `01:00.0` [10de:2860], GeForce RTX 4070 Laptop (AD106M), driver `nvidia` (módulos `nouveau`, `nvidia_drm`, `nvidia`)

**Registro anterior:**

- 8 GB / ~8188 MiB VRAM
- até ~140 W em contexto de capacidade
- registro de fábrica/configuração em torno de 90 W em contexto anterior

**Uso:**

- Driver usado: `nvidia-open-dkms` 615.78.08, empacotado pelos mantenedores do Arch Linux, compilado via DKMS para cada kernel e assinado com a MOK
- Uso/possibilidade de passthrough da dGPU para VMs. Por padrão a dGPU fica no host: o `vfio.conf` está todo comentado.
- Ajustes/undervolt da GPU via NVML API.

**Gerenciamento de energia (a dGPU deve poder desligar, RTD3):**

```text
options nvidia NVreg_RegistryDwords="OverrideMaxPerf=0x1" NVreg_UseKernelSuspendNotifiers=1 NVreg_TemporaryFilePath="/var/tmp" NVreg_DynamicPowerManagement=0x02 NVreg_EnableResizableBar=1 NVreg_EnableGpuFirmwareLogs=1
```

- `NVreg_DynamicPowerManagement=0x02`: RTD3 fine-grained
- regras udev põem `power/control=auto` nas funções VGA/3D da NVIDIA ao serem adicionadas/ligadas ao driver, e `on` ao serem desligadas
- `nvidia-persistenced` roda sem `--uvm-persistence-mode` (o modo UVM desativaria o RTD3)
- `nvidia-powerd` (Dynamic Boost) e os serviços `nvidia-suspend`/`-resume`/`-hibernate` estão ativos
- a iGPU é a GPU padrão para Vulkan e VA-API (o VDPAU saiu, e o `LIBVA_DRIVER_NAME` não é mais definido globalmente); a NVIDIA é usada sob demanda com `prime-run`
- vídeo: VA-API funciona no Firefox e nos navegadores Chromium; QSV/VPL (`intel-media-driver`/oneVPL) também
- com o Direct Output Mode ativado, um monitor externo mantém a dGPU acordada
- verificação: `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` = `suspended`

- RTD3 confirmado: a dGPU chega a D3cold (os 3–4 W lidos antes vinham do btop consultando a NVML); o perfil `alienware-battery` força o desligamento se ela continuar acordada (ver 32A.14)
- OpenCL instalado (`opencl-nvidia`), que usa o `nvidia_uvm`; nenhum pacote CUDA (conferido em 2026-11-09)

**Requisitos ao kernel:** PCI runtime PM, D3cold via ACPI, suspend/hibernate, e o que o `nvidia-open-dkms` exigir para compilar (DRM/KMS). O `nvidia` exige também `NUMA`, `MEMORY_HOTPLUG`, `ZONE_DEVICE` e `DEVICE_PRIVATE`, que ficam.

**HMM do `nvidia-uvm`:** ele só compila com HMM (CUDA acessando memória alocada com `malloc` comum) se `HMM_MIRROR` e `DEVICE_PRIVATE` estiverem ligados. `HMM_MIRROR` não tem pergunta própria no Kconfig, e nesta configuração só o `DRM_XE` (pelo `DRM_GPUSVM`) o seleciona. Hoje o HMM está ativo (`uvm_disable_hmm=N` no zen). Decidido: o `xe` sai (ver 2) e o HMM vai junto; OpenCL, NVENC/NVDEC, Vulkan, NVML e PRIME não usam HMM. Se um dia precisar dele, `CONFIG_DRM_XE=m` o devolve (o `xe` compila, mas não se liga à iGPU sem `force_probe`).

## 5. Áudio

### Controladores

- Intel `00:1f.3` [8086:7a50], driver `sof-audio-pci-intel-tgl` (módulos `snd_soc_avs`, `snd_sof_pci_intel_tgl`, `snd_hda_intel`)
- HDMI da NVIDIA `01:00.1` [10de:22bd], driver `snd_hda_intel`

### ALSA

```text
0 [NVidia]: HDA-Intel - HDA NVidia
1 [sofhdadsp]: sof-hda-dsp - sof-hda-dsp
              Alienware-Alienwarem16R1-00DK46
```

### Codecs confirmados

- Analógico/interno principal: Realtek ALC3254, atendido pelo `snd_hda_codec_alc269` (família ALC269); os outros codecs Realtek (ALC260, 262, 268, 662, 680, 861, 861-VD, 880, 882) e os HDMI ATI, NVIDIA MCP e Tegra saem, o que exige `EXPERT` (ver 31)
- HDMI/DP Intel: Intel Raptor Lake HDMI
- HDMI/DP NVIDIA: NVIDIA GPU a6 HDMI/DP
- Não foi encontrado dispositivo SoundWire ativo; os módulos `soundwire_*` carregam só como dependências do SOF, e o suporte a SoundWire do SOF sai (ver 2, Módulos carregados).
- Não foram encontrados módulos Cirrus/Madera/Arizona.
- Busca por dispositivos I2C Cirrus/CS35/CS40/CS42/CS47/Madera/Arizona/Wolfson não retornou nada.
- Os MFDs Cirrus/Wolfson/Madera/Arizona tratados no chat foram considerados desnecessários.
- Eventuais smart amplifiers em outros menus de áudio devem ser avaliados separadamente; não extrapolar a remoção de MFDs para todo driver Cirrus/TI sem verificação.
- O laptop tem entrada P3, que é regularmente usada; assumir que podem ser usados dispositivos de som via USB também.

### Usos de áudio

- PipeWire usado para tudo, incluindo ALSA, Pulseaudio e JACK
- interesse em baixa latência e máxima qualidade sonora
- `threadirqs` (ver 1B)
- limites do usuário: `LimitRTPRIO=98` e `LimitMEMLOCK=infinity`, além do pacote `realtime-privileges` (grupo `realtime`)
- gravação de instrumentos musicais
- interfaces de áudio USB
- Ardour

**preservar:**

- USB Audio Class
- USB MIDI
- ALSA sequencer (`SND_SEQUENCER`), usado pelo PipeWire para o MIDI
- HDA Intel/Realtek
- HDMI/DP Intel
- HDMI/DP NVIDIA
- áudio Bluetooth

## 6. Rede

### Wi‑Fi

- `00:14.3` [8086:7a70], subsystem Rivet Networks [1a56:1672], driver `iwlwifi`
- Tratado no contexto como Intel AX211 / Killer-branded Intel CNVi.
- Preservar `iwlwifi` e o que for necessário/relevante para ele.
- Remover famílias Wi‑Fi inexistentes no hardware interno.
- Remover drivers Intel Wi‑Fi antigos que não correspondem ao AX211.

### Bluetooth

- Bluetooth AX211.
- ID anteriormente registrado: 8087:0033.

**Usos:**

- Xbox
- PlayStation
- Steam Controller
- áudio Bluetooth
- outros periféricos Bluetooth
- Preservar HCI USB.
- O Bluetooth é USB (`8087:0033`, conferido em 2026-11-09): o frontend Intel PCIe (`BT_INTEL_PCIE`, Lunar Lake em diante) sai.

### Ethernet

- `6e:00.0` Killer E3000 2.5GbE [10ec:3000], driver `r8169`, interface `enp110s0`
- PHY Realtek.
- hwmon do PHY Realtek foi considerado útil.

### Software/rede

**Usos atuais ou preservados:**

- WireGuard e OpenVPN
- Gerenciamento de Internet via NetworkManager
- Hotspot Wi-Fi pelo NetworkManager (`ipv4.method shared`): modo AP no `iwlwifi`, NAT/masquerade e o `dnsmasq` do NetworkManager
- Extensões de privacidade do IPv6
- DNS over TLS via systemd-resolved
- mDNS: o systemd-resolved só resolve (`MulticastDNS=resolve`), e o Avahi responde
- `firewalld` via `nftables`
- LocalSend
- redes QEMU/libvirt
- TUN/TAP
- USB networking
- Raspberry Pi, Arduino e ESP32 via USB/rede
- iPhone USB Ethernet (ipheth) e compartilhamento de arquivos via USB
- Também considerar Android

### QoS

**Decisões anteriores:**

- `fq_codel` como qdisc default
- FQ e CAKE como módulos quando discutidos
- ingress / flower / matchall / gact / mirred mantidos onde necessários
- remover grande quantidade de qdiscs/classifiers/actions não usados

## 7. USB-A, USB-C e Thunderbolt

### Controladores

- xHCI principal `00:14.0` [8086:7a60], USB 3.2 Gen 2x2 (20 Gb/s), driver `xhci_hcd`
- Thunderbolt 4 Maple Ridge: bridges `02:00.0` e `03:00.0`–`03:03.0` [8086:1136], NHI `04:00.0` [8086:1137] (driver `thunderbolt`), xHCI `38:00.0` [8086:1138] (`xhci_pci`)

### Dispositivos USB

**Internos:**

- `0d62:d2b0` Darfon, teclado interno, `usbhid` (também envia as teclas de macro, ver 11)
- `187c:0551` Alienware AW-ELC, controlador da iluminação RGB, `usbhid` (controlado do userspace)
- `0bda:555d` Realtek, webcam, `uvcvideo` (a interface 4, "Application Specific", fica sem driver)
- `8087:0033` Intel AX211 Bluetooth, `btusb`

**Externos conectados no levantamento:**

- `152d:0583` JMicron JMS583, ponte USB para NVMe (SSD externo), `uas`
- `0b95:1790` ASIX AX88179, Ethernet USB, `ax88179_178a`
- `30fa:1440` mouse gamer, `usbhid`

**Módulos observados:**

- thunderbolt
- ucsi_acpi
- typec_ucsi
- typec

**Preservar:**

- Thunderbolt 4
- USB-C
- USB Power Delivery / UCSI
- DisplayPort Alt Mode
- monitores via USB-C/HDMI/miniDP
- docks/hubs e dispositivos Thunderbolt

## 8. Armazenamento interno

### NVMe ADATA

- `6d:00.0` [1cc1:5766], ADATA XPG de 2 TB, driver `nvme`
- Um SSD Micron também está instalado no laptop, mas deve ser desconsiderado: não será usado.

### Root / partições

- ESP FAT32 em `/boot`
- UKIs e `systemd-boot`
- root em LUKS2 + Btrfs (`/dev/mapper/root`), sem discard: TRIM totalmente desativado, nem `discard` nem `fstrim.timer`
- LUKS2: cifra `aes-xts-plain64` com chave de 512 bits (AES-256 em XTS), setores de 512 bytes, PBKDF `argon2id`. O kernel precisa de dm-crypt, XTS e AES com AES-NI disponíveis no initramfs; o argon2id roda no `cryptsetup`, no userspace
- todos os subvolumes montados com `relatime,nodiscard,compress=zstd:3`
- Btrfs com checksum `crc32c` e as features `mixed_backref`, `big_metadata`, `extended_iref`, `skinny_metadata`, `no_holes` e `compress_zstd` (`incompat_flags 0x371`); nenhum dado em lzo

**Subvolumes (esquema planejado; o sistema ainda não foi reinstalado com ele):** os do Arch ficam dentro do diretório comum `Arch/` (não é subvolume); os compartilháveis ficam no nível superior.

| Subvolume | Ponto de montagem |
|---|---|
| `Arch/@` | `/` |
| `Arch/@root` | `/root` |
| `Arch/@varlog` | `/var/log` |
| `Arch/@varcache` | `/var/cache` |
| `Arch/@vartmp` | `/var/tmp` |
| `Arch/@libvirt-images` | `/var/lib/libvirt/images` (sem CoW) |
| `Arch/@swap` | `/.swap` |
| `Arch/@snapshots` | `/.snapshots` |
| `@home` | `/home` |
| `@matlab` | `/usr/local/MATLAB` |

**tmpfs:**

- `/tmp`, `/temp` e `/tmp/kernel-build` (42 GiB) com `huge=within_size` (THP em shmem) e `usrquota` (quotas de tmpfs)

**Sistemas de arquivos das mídias externas:** exFAT, NTFS (o udisks2 tenta primeiro o `ntfs3` do kernel, o padrão `ntfs_drivers=ntfs3,ntfs`, por isso o `ntfs3` está no `modprobed.db` e fica; a partição do Windows usa o `ntfs-3g`, sobre FUSE; o driver NTFS novo, `NTFS_FS`, não é usado e sai), FAT (pendrives de colegas; `vfat` com as codepages e charsets usados, como cp437 e utf8) e imagens ISO (ISO 9660 com Joliet e Rock Ridge, UDF, montadas por loop). O SSD externo é LUKS + Btrfs.

**Sistemas de arquivos montados hoje:** `btrfs`, `vfat`, `tmpfs`, `hugetlbfs`, `fuse.portal` (portal de documentos do Flatpak), `autofs` (automount do systemd), `efivarfs`, `pstore`, `cgroup2`, `bpf`, `configfs`, `debugfs`, `tracefs`, `securityfs`, `mqueue`, além de `proc`, `sysfs`, `devtmpfs` e `devpts`.

**FUSE é essencial:** dependem dele o `ntfs-3g`, as AppImages (GearLever), o `ifuse` (iPhone) e o portal de documentos do Flatpak.

**Windows:**

- partição NTFS do Windows (apelidada de Bosta11) montada com `ntfs-3g`, que roda sobre FUSE
- ESP do Windows é a mesma do Arch, montada em `/boot`

**initramfs (`mkinitcpio`):** os arquivos efetivos são os de `/etc/mkinitcpio.conf.d/` (`hooks.conf`, `modules.conf`, `compression.conf`), que se sobrepõem ao `/etc/mkinitcpio.conf`. Versão do repositório:

```text
HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
MODULES=(zstd lz4)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-19 -T0 --long)
MODULES_DECOMPRESS="yes"
```

- o hook `systemd` substitui o `udev`; `sd-encrypt` abre o LUKS
- `zstd` e `lz4` estão em `MODULES` pelo `zswap` e pela hibernação; como `CRYPTO_ZSTD`, `CRYPTO_LZ4` e `CRYPTO_LZO` são embutidos em todos os kernels instalados e no próprio, as entradas não têm efeito (ver 33.3)
- initramfs comprimido com zstd, e os módulos descomprimidos dentro dele; o kernel próprio só tem o descompressor zstd de initramfs (ver 33.5)
- o sistema estava defasado em relação ao repositório em 2026-11-10: `hooks.conf` com o hook `udev` junto do `systemd` (redundante), `modules.conf` com `zstd lzo vfio_pci vfio vfio_iommu_type1` (nenhuma VM faz passthrough de dispositivo hoje) e `compression.conf` com `-z -T0 --long -v -M4096 -1 -C`. O `/etc/mkinitcpio.conf` ainda tem `kms` nos `HOOKS`, sem efeito por causa do `hooks.conf`. A aplicar: os arquivos do repositório e `mkinitcpio -P`

### Swap / hibernação

- Swapfile Btrfs: 16 GiB, em `/.swap/swapfile`
- hibernação usada, comprimida com lz4, e `zswap` com zstd (parâmetros em 1B)
- `HibernateMode=platform`; sono com `MemorySleepMode=deep` e `SuspendState=mem` (S3 ativado no firmware)
- `systemd-oomd` ativo: mata processos por pressão de memória (`ManagedOOMMemoryPressureLimit=70%` nas sessões de usuário) e por uso de swap; depende do PSI e do controlador de memória do cgroup v2
- preservar swap
- `zram` não é necessário no cenário atual de swapfile + `zswap`
- no kernel próprio, o zswap já fica ligado e com zstd por padrão (base), e o lz4 é o padrão da hibernação (`.myfrag`): os parâmetros de 1B ficam redundantes
- pstore: o sistema de arquivos está montado, mas o backend EFI estava desligado (`/sys/module/efi_pstore/parameters/pstore_disable` = `Y` no zen, porque a configuração do Arch tem `EFI_VARS_PSTORE_DEFAULT_DISABLE=y`), e `/sys/fs/pstore` estava vazio: nenhum crash era gravado (conferido em 2026-11-09). Decidido: o `.myfrag` volta ao padrão do Kconfig, backend ligado. Cada crash grava alguns KB na NVRAM; o `systemd-pstore.service` move os registros para `/var/lib/systemd/pstore` e os apaga da NVRAM. Ele estava desabilitado (2026-11-10) e precisa ser habilitado: `systemctl enable systemd-pstore.service` (`/etc/systemd/pstore.conf` fica nos padrões)

### Armazenamento externo

- Usa SSDs/HDDs/pen drives/discos externos.
- Há um SSD externo com LUKS + Btrfs + subvolumes.
- Nesse Btrfs externo, discard não é permitido pelo usuário.
- Pode usar SSD e HDD SATA via adaptador USB-SATA. Um deles, o SanDisk SSD PLUS 240 GB, é o disco da VM Faltir-win10 (`/dev/disk/by-id/ata-SanDisk_SSD_PLUS_240GB_184027805329`). O nome `ata-` vem do udev, que lê a identificação ATA do disco pelo adaptador (`uas`/`usb-storage` + `sd_mod`): o laptop não tem controladora SATA, então o `ATA` (libata) sai sem afetá-lo

**Preservar:**

- USB Mass Storage
- UAS
- SCSI disk
- SCSI generic quando útil

Não remover suporte externo só porque os discos internos são NVMe.

### Política NVMe

- NVMe é crítico.
- APST já foi considerado adequado/ótimo.
- Não alterar parâmetro de latência/APST sem necessidade.
- preservar NVMe hwmon.

## 9. Leitor SD

- `6c:00.0` Realtek RTS525A [10ec:525a], driver `rtsx_pci`
- Preservar `rtsx_pci` e suporte MMC/SD correspondente.
- `mmc_block` (necessário para ler um cartão) não estava no `modprobed.db` porque nenhum cartão tinha sido inserido; foi acrescentado (ver 31). O leitor não é eMMC: `RPMB` sai.

## 10. Webcam

- Webcam integrada ao laptop usada pelo usuário.
- ID anteriormente registrado: Realtek 0bda:555d

**Preservar:**

- media camera
- media USB
- UVC / USB Video Class
- input events UVC quando necessários

## 11. Teclado, mouse, touchpad e HID

### Teclado interno

- O teclado interno é USB: Darfon `0d62:d2b0`, `usbhid`.
- O controlador i8042/PS2 também está ativo, com teclado (`DLLK0BFB`) e porta auxiliar (`DLL0BFB`) ligados ao `i8042`; o Legacy Game Compatibility Mode do firmware ativa teclado/mouse PS/2. Manter `i8042` e `atkbd`.
- As teclas de macro chegam por um dispositivo USB HID interno, `0d62:d2b0`: um arquivo hwdb mapeia os usages `0xc0051`–`0xc0055` para `macro1`–`macro5`.
- Não confundir teclado USB com drivers específicos de teclados embarcados no submenu Keyboards.
- Protocolos PS/2 de touchpads de outros fabricantes (ALPS, BYD, Cypress, Elantech, FocalTech, Lifebook, Logitech PS/2, Sentelic, Touchkit, Trackpoint) saem; os Synaptics do `psmouse` ficam, por ser o fabricante do touchpad. Os que só aparecem com `EXPERT` saem pelo bloco 8 do `.myfrag`.
- `INPUT_TOUCHSCREEN` e `INPUT_TABLET` saem: não há tela sensível ao toque nem mesa digitalizadora.

### Touchpad

**Caminho confirmado (o touchpad é o `VEN_06CB`, Synaptics, ligado ao `i2c_hid_acpi`):**

```text
Intel LPSS PCI
 -> intel_lpss_pci
 -> i2c_designware platform
 -> i2c-hid-acpi
 -> hid-multitouch
 -> touchpad
```

**Controladores:** `00:15.0` e `00:15.1` [8086:7a4c/7a4d], driver `intel-lpss` (módulo `intel_lpss_pci`)

### USB HID / Logitech

- O usuário usa mouses e teclados USB.

**Periféricos registrados:**

- Logitech K230
- Logitech M280/M320/M275
- Logitech Unifying Receiver / C52B
- Mouse gamer Dazz GMO3000
- Teclado Dell KB216p
- outros HID USB/receptores sem fio

**Preservar:**

- HID genérico
- USB HID
- Logitech HID
- Logitech DJ
- Logitech HID++
- Suporte a periféricos com RGB

## 12. Gamepads

**Uso principal:**

- Xbox 360, One
- PlayStation 3, 4/5
- Steam Controller
- Gamepads third-party (incluindo controles com adaptadores USB para comunicação sem fio, além do Bluetooth)
- Volantes para jogos de corrida

**Preservar:**

- xpad
- force feedback Xbox
- LED Guide quando aplicável
- hid-playstation
- force feedback PlayStation
- hid-steam
- Bluetooth HIDP quando necessário
- USB HID genérico
- `uinput`: o Steam Input cria controles virtuais por `/dev/uinput`

- Volantes: suporte Logitech (`hid-logitech` com force feedback e configuração dos volantes); o manche Logitech G940 sai.
- Também ficam `hid-sony`, `hid-nintendo` e `hid-microsoft` (controles Xbox por Bluetooth).

Não confundir gamepads com Remote Controller/LIRC/IR, considerado desnecessário. Saem `LIRC`, `RC_CORE` e o repasse de controle remoto pelo HDMI-CEC (`MEDIA_CEC_RC`); o CEC do `i915` fica.

## 13. Arduino, ESP32 e Raspberry Pi

**Usa explicitamente:**

- Arduino
- ESP32
- Raspberry Pi
- USB serial essencial

**Preservar:**

- CDC ACM
- CH341/CH340
- CP210x
- FTDI SIO
- PL2303
- USB serial generic

**Caminhos típicos:**

```text
Arduino -> CDC ACM / CH340 / FTDI
ESP32   -> CP210x / CH340 / CDC ACM
RPi     -> USB serial e/ou USB networking
```

### Não confundir

- `SPI_CH341` não é necessário só por usar CH340/CH341 serial.
- FTDI MPSSE GPIO só é necessário se houver uso deliberado de FT232H/FT2232H etc. em MPSSE para GPIO/JTAG/SPI.
- GPIO/SPI/I2C/1-Wire do host não devem ser habilitados só porque existem nas placas externas.
- Um sensor ligado ao ESP32 é controlado pelo ESP32, não pelo kernel do Alienware.
- Os adaptadores USB serial não usam o driver 8250 (que sai, ver 2).

### USB networking

**Preservar suporte essencial para:**

- Raspberry Pi USB gadget/network
- CDC Ethernet
- CDC NCM
- RNDIS host
- ASIX AX88179
- Realtek RTL8152/8153
- iPhone & Android USB Ethernet
- o `cdc_subset` (adaptadores USB antigos) sai: os aparelhos declarados usam CDC ECM/NCM, RNDIS, `ipheth`, `ax88179_178a` e `r8152`

## 14. Telefones

- Conecta Android e iPhone/iOS.
- Preservar USB networking relevante.
- Não habilitar modems WWAN específicos só por conectar telefone.
- Este laptop não tem hardware WWAN, como suporte a cartões SIM por exemplo

## 15. Impressora e scanner

**Registro anterior:**

- Canon E4210
- IPP/CUPS/SANE
- Avahi para mDNS
- possibilidade de IPP-USB

**Requisitos:**

- preservar USB/rede necessários a impressão/scanner
- usblp apenas se o fluxo realmente depender dele
- preservar multicast/mDNS cotidiano

## 16. Virtualização

**Usa:**

- QEMU
- KVM
- libvirt
- SPICE via socket Unix
- passthrough de GPU - Looking Glass B7, com o módulo `kvmfr` (fora da árvore, via DKMS e assinado com a MOK; `static_size_mb=256`)
- passthrough de NVMe
- passthrough de USB
- TPM: a VM do Windows 11 (a instalação bare metal, usada também como VM) recebe o TPM físico em passthrough pelo `/dev/tpmrm0`; a VM do Windows 10 usa TPM emulado (`swtpm`)
- discos físicos em VM, inclusive um disco virtual montado com device-mapper (`dm-linear`) sobre as partições do Windows físico, com imagens em loop (`loop max_part=15`)
- pasta compartilhada com `virtiofsd` (memória da VM compartilhada)
- CPU isolation por hook do libvirt, via cgroups (`AllowedCPUs` do systemd): vCPUs nos P-cores 8–15, emulador nos 16–17, iothread nos 18–19; o host fica com 0–7 e 20–31
- hugepages dinâmicas: `vm.nr_overcommit_hugepages=8192` (16 GiB), com compactação de memória antes de a VM iniciar (`/proc/sys/vm/compact_memory`)
- virtualização aninhada: `kvm_intel nested=1`
- dummy HDMI/miniDP
- IOMMU ligado pelo `intel_iommu=on` (ver 1B)
- discos das VMs com `io="native"` (Linux AIO), `cache="none"`, `discard="unmap"` e iothreads
- VMs definidas (2026-11-09): `archlinux`, `Bosta10`, `Bosta11-bare-metal` (disco `/dev/mapper/windows-VM`) e `Faltir-win10` (SSD SATA por USB, ver 8). Todas com rede `type='network'` na rede `default` (NAT, bridge `virbr0` com STP), placa `virtio` e vídeo `virtio-vga-gl`; nenhuma usa macvtap (`type='direct'`), então `MACVLAN`/`MACVTAP` saem
- módulos de rede/virtualização de host que ficam: `KVM_INTEL`, `KVM_HYPERV` (enlightenments Hyper-V das VMs Windows), `VFIO_PCI`, `VHOST_NET`, `TUN`, `BRIDGE`; saem `KVM_AMD`, `KVM_XEN` (emulação de Xen para guests) e `KVM_INTEL_TDX`

**Preservar:**

- KVM Intel
- IOMMU
- VFIO
- VFIO PCI
- recursos de passthrough
- TUN/TAP
- device-mapper e loop
- hugetlbfs e compactação de memória
- Linux AIO
- bridge (a rede NAT padrão do libvirt é a bridge `virbr0` com nftables) e `vhost_net` (placas virtio)
- cpusets do cgroup v2

**Regra crucial:**

- O kernel sendo configurado aqui é o host físico, não o guest.
- Não habilitar frontends VirtIO/Xen/Hyper-V/VMware só porque o host roda VMs. Diferenciar sempre driver do host de driver que só seria útil dentro do guest.
- O sistema desse laptop não usa Xen.

## 17. Jogos

**Usos:**

- Steam
- Proton
- Wine
- emulação
- Xbox/PlayStation/Steam Controller
- NVIDIA
- possibilidade de VM de jogos com passthrough
- o sandbox do Steam (pressure-vessel), o Flatpak (`bubblewrap` sem setuid) e o sandbox dos navegadores Chromium (como o Helium) precisam de user namespaces sem privilégio: `USER_NS=y` e, no linux-tkg, `USER_NS_UNPRIVILEGED=y` (opção criada pelo patch `0001-add-sysctl-to-disallow-unprivileged-CLONE_NEWUSER`, ligada por padrão; desligada, bloquearia esses três)
- `ntsync` (`CONFIG_NTSYNC`, usado pelo Proton recente): fica ligado, como módulo; no `linux-tkg.cfg`, o `_ntsync="false"` só se refere ao patch para kernels antigos, e a opção do Kconfig deve ficar ligada

- o Wine precisa de `MODIFY_LDT_SYSCALL` e `X86_16BIT`, que ficam mesmo sendo interfaces antigas; o 32 bits (`IA32_EMULATION`) fica pelo Steam
- a emulação da página vsyscall sai (`X86_VSYSCALL_EMULATION`): só binários estáticos de glibc anteriores a 2011 a usam

**Requisitos:**

- evitar latência e overhead desnecessários
- preservar periféricos
- preservar HDMI/miniDP/USB-C

## 18. Secure Boot, UKI e assinatura

- Secure Boot ativo.
- Usa chaves padrão do laptop, isto é, PK, KEK e db/dbx não foram alteradas (exceto db/dbx que são atualizadas pelo fwupd).
- Usa MOKs próprias para assinar binários do sistema, via shim (em `/EFI/systemd/`, com cópia em `/EFI/arch/` para o fwupd).
- `systemd-boot`, assinado com a MOK por um hook do pacman.
- UKIs.
- `mkinitcpio` (padrão do Arch Linux); os hooks `kernel-sbsign` e `uki-sbsign` assinam o kernel e a UKI com a MOK.
- assinatura de módulos/kernel faz parte do fluxo.
- Os módulos DKMS (`nvidia-open-dkms`, `kvmfr`) são assinados pelo DKMS com a MOK de assinatura de módulos (`custom-moks.conf`), não com a chave de módulos do kernel. O kernel confia nela pelo keyring `.machine`, carregado da `MokListRT` (o `mokutil --trust-mok` está ativo). Conferido em 2026-11-10: `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm` e `kvmfr` assinados por "Mr. Robot Alienware Machine Owner Key - Module Signing"; a chave está no `.machine`; nenhum `module verification failed` no log.
- `/proc/sys/kernel/tainted` = 4100 no zen: 4096 (módulos de fora da árvore, o DKMS) + 4 (escrita em MSR pelo `intel-undervolt`). Sem o bit 13 (8192), de módulo sem assinatura.
- MOKs: `MOK.crt` e `MOK-module-signing.crt` têm `CA:TRUE` e nenhum keyUsage. Por isso `INTEGRITY_CA_MACHINE_KEYRING` fica desligado: com ele, só entram no `.machine` as MOKs com `CA:TRUE` e `keyCertSign`, as duas iriam para o keyring da plataforma (que não vale para módulos), e o nvidia e o kvmfr deixariam de carregar.
- A `MokListRT` tem também `Red Hat, Inc.: fedoraca`, `grub` e `MultiOS-USB`. Com a confiança na MOK ativa, o kernel aceita módulos assinados por qualquer uma delas, e o shim inicia o que elas assinarem. Recomendado remover as que não forem usadas (`mokutil --export`, `mokutil --delete MOK-000N.der` e confirmar no MokManager); manter `MultiOS-USB` e `grub` se o pendrive do MultiOS-USB for iniciado com Secure Boot.
- O fwupd atualiza o firmware por cápsulas UEFI (ESRT, efivarfs) e assina o próprio binário EFI com a MOK.

**Decisão consolidada anteriormente:**

- `MODULE_SIG`=y
- `MODULE_SIG_ALL`=y
- SHA-512
- `MODULE_SIG_FORCE`=y (decidido em 2026-11-10, com a regra das alavancas de segurança da seção 0; substitui a consolidação anterior, que o deixava desligado). Se a assinatura do DKMS falhar, o nvidia não carrega: os kernels `linux` e `linux-zen` ficam como reserva
- sem `MODULE_FORCE_LOAD` nem `MODULE_FORCE_UNLOAD`
- o PKGBUILD do linux-tkg usa `options=('!strip')`, e o `INSTALL_MOD_STRIP=1` do `_STRIP="true"` age antes da assinatura no `modules_install`: as assinaturas continuam válidas

Não quebrar Secure Boot ao modularizar drivers de boot.

**Lockdown:** com o lockdown em modo integrity, comum junto do Secure Boot, o kernel desativa a hibernação. Como a hibernação é usada, o lockdown não pode chegar a esse modo: fica `LOCK_DOWN_KERNEL_FORCE_NONE`, com `SECURITY_LOCKDOWN_LSM_EARLY=y` (sem efeito enquanto o lockdown estiver em none). Com o lockdown em none, o `kexec_load` deixaria o root iniciar um kernel não assinado, passando por cima do Secure Boot: kexec e kdump saem (ver 33.5).

**Tela no boot:** a senha do LUKS (`sd-encrypt`) aparece antes de o driver da GPU carregar, pelo framebuffer do UEFI (`simple-framebuffer`/`efi-framebuffer`, via `simpledrm` ou `efifb`).

## 19. TPM 2.0

**Confirmado:**

```text
driver: /sys/bus/platform/drivers/tpm_crb_acpi
TPM version: 2
device: /sys/devices/platform/INTC6001:00
DRIVER=tpm_crb_acpi
MODALIAS=acpi:INTC6001:MSFT0101:
```

**ACPI/EFI:**

- SSDT Tpm2Tabl
- tabela TPM2 Dell
- TPMFinalLog
- TPMEventLog

**systemd observou:**

- TPM PCR Barrier no initrd
- TPM PCR Measurements
- Machine ID Measurement
- Early TPM SRK Setup

**Requisitos:**

- TPM 2.0 usado
- interface real: CRB
- não precisa TIS/FIFO/SPI/I2C genéricos para o TPM atual (`TCG_TIS` e `TCG_TIS_CORE` saem; o driver ligado é o `tpm_crb_acpi`, conferido em 2026-11-09)
- foi decidido que TPM core e CRB podem ser módulos

### estratégia:

- `TCG_TPM`=m
- `TCG_CRB`=m
- o hook `sd-encrypt` já põe `tpm_crb` e `tpm` na UKI (filtrados pelo autodetect, ver 33.3); `MODULES` não é necessário
- O `/dev/tpmrm0` (resource manager do kernel) é passado à VM do Windows 11 bare metal (ver 16).
- O TPM físico é usado pelo systemd (medições, `systemd-creds`, usado no script do hotspot) e pelo BitLocker do Windows instalado no hardware.

## 20. Watchdog

**Confirmado:**

```text
/dev/watchdog
/dev/watchdog0

identity: iTCO_wdt
driver: /sys/bus/platform/drivers/iTCO_wdt
```

- ACPI WDAT: ausente

**módulos observados:**

- `iTCO_wdt`
- `intel_pmc_bxt`

**Log:**

```text
Found a Intel PCH TCO device
Version=6
TCOBASE=0x0400
initialized
heartbeat=30 sec
nowayout=0
```

**Conclusões:**

- watchdog real: Intel TCO / `iTCO_wdt`
- WDAT não usado
- manter iTCO
- softdog não necessário
- pretimeout considerado desnecessário
- nowayout=0 desejado

### NMI watchdog

**Log observado:**

```text
NMI watchdog: Enabled. Permanently consumes one hw-PMU counter.
```

- é diferente do iTCO
- consome um contador da PMU enquanto ligado
- os perfis do `tuned` o ligam e desligam em runtime, então o suporte deve estar no kernel (ver 32A.9)

## 21. Intel Integrated Sensor Hub

- `00:12.0` [8086:7a78], driver `intel_ish_ipc`

**Módulos já vistos/anotados:**

- `intel_ish_ipc`
- intel_ishtp
- intel_ishtp_hid
- Preservar o caminho se em uso.

## 22. DPTF / thermal Intel

- `00:04.0` [8086:a71d], driver `proc_thermal_pci` (módulo `processor_thermal_device_pci`)

**Preservar:**

- INT340X / processor thermal real
- package temperature thermal
- coretemp
- Intel HFI
- TCC cooling pertinente a Raptor Lake

**Decisões:**

- não usar drivers Bay Trail/Broxton só por serem Intel
- Intel PCH Thermal Reporting antigo não corresponde ao hardware atual
- `intel_powerclamp` está carregado, então fica
- governor térmico principal: step_wise
- Tjmax 100 °C, sem offset: o Tcc Offset Lock do firmware trava o registro, então ferramentas do sistema não alteram o ponto de throttling
- manter thermal hwmon
- não habilitar thermal emulation em uso normal
- não há ventoinha ACPI (`PNP0C0B` ou `INTC1048`, conferido em 2026-11-09): as ventoinhas vêm do Dell SMM e do WMI (23). `ACPI_FAN` fica como módulo só porque o `INT340X_THERMAL` o seleciona
- `ACPI_THERMAL` fica embutido (Kconfig: "HIGHLY recommended")

## 23. HWMON

**Sensores presentes (`sensors`):**

| Fonte | Driver | O que expõe |
|---|---|---|
| CPU | `coretemp` | pacote e cada núcleo (Tjmax 100 °C) |
| Dell SMM | `dell_smm_hwmon` | 4 ventoinhas, 9 temperaturas e controle PWM manual das ventoinhas |
| Dell DDV (WMI) | `dell_wmi_ddv` | as mesmas ventoinhas e temperaturas do Dell SMM, com nomes (CPU, Video, Ambient, SODIMM) |
| Alienware WMI | `alienware_wmi` | ventoinhas de CPU e GPU, temperaturas de CPU e GPU |
| RAM | `spd5118` | os dois pentes DDR5, no SMBus do I801 (endereços `0x50` e `0x52`) |
| NVMe | NVMe hwmon | o ADATA (`6d:00.0`) e o Micron desconsiderado (`6f:00.0`) |
| Wi-Fi | `iwlwifi` | temperatura do AX211 |
| Ethernet | Realtek PHY hwmon | temperatura do PHY (lia −0,5 °C no levantamento, provavelmente sem link) |
| Energia | power_supply hwmon | bateria `BAT0` e as duas portas USB-C (UCSI) |

**Decisões:**

- manter `coretemp`, `dell_smm_hwmon`, `spd5118` e NVMe hwmon
- manter também o `dell_wmi_ddv` e o hwmon do `alienware_wmi`, que estão em uso, mesmo repetindo dados do `dell_smm_hwmon`
- `/proc/i8k` legado foi considerado desnecessário salvo uso deliberado de software antigo
- Realtek PHY hwmon foi considerado útil

## 24. Dell/Alienware WMI

**Módulos observados/anotados:**

- dell_wmi
- alienware_wmi
- dell_smbios (com o `dcdbas`)
- dell_wmi_sysman (configurações da BIOS pelo `firmware-attributes`)
- dell_wmi_ddv (sensores, ver 23)
- outros Dell WMI relacionados
- o `alienware_wmi` fornece o `platform_profile` usado pelos perfis do tuned (32A.3)
- nvidia_wmi_ec_backlight
- GUIDs WMI presentes (2026-11-09): o WMAX do Alienware (`A70591CE-…`) e o do Dell SMBIOS (`A80593CE-…`), entre outros. O GUID do Alienware legado (`A90597CE-…`, AlienFX) não existe: `ALIENWARE_WMI_LEGACY` sai, `ALIENWARE_WMI_WMAX` fica

Preservar funcionalidades Dell/Alienware realmente usadas e o backlight correto.

## 25. Intel MEI

- `00:16.0` CSME HECI #1 [8086:7a68], driver `mei_me`
- MEI real deve ser preservado.
- Não manter watchdog iAMT ou outros dispositivos MEI especializados só porque mei_me existe.

## 26. I2C

### Core

**Importante para:**

- ACPI I2C OpRegion
- touchpad
- Intel LPSS
- dispositivos internos enumerados

**Decisão:**

- I2C core built-in (y)
- ACPI I2C OpRegion é uma razão concreta para isso

### I801

- `00:1f.4` [8086:7a23], driver `i801_smbus`
- preservar `I2C_I801`

### DesignWare

- Intel LPSS usa o DesignWare Platform (confirmado: o driver de plataforma `i2c_designware` está ligado a `i2c_designware.0` e `.1`, e não há `i2c_designware_pci`, 2026-11-09)
- não DesignWare PCI direto para 00:15.0/00:15.1: `I2C_DESIGNWARE_PCI` sai, e o semáforo do Bay Trail também
- `I2C_DESIGNWARE_CORE` e `I2C_DESIGNWARE_PLATFORM` como módulos

### i2c-dev

- o `i2c_dev` está carregado, então `I2C_CHARDEV` fica (regra da seção 0); a origem do carregamento pode ser vista em `/etc/modules-load.d/` e `/usr/lib/modules-load.d/`

### I2C mux

- muxes específicos removidos
- core `I2C_MUX` apareceu forçado

**não forçar N sem resolver Selected by:**

## 27. SPI

**SPI flash do PCH:**

- o controlador `00:1f.5` está ligado ao `spi_intel_pci`, e `spi_intel`, `spi_nor` e `mtd` estão carregados; pela regra da seção 0, ficam (isso substitui a decisão anterior de remover o acesso à flash)
- por padrão o driver só permite leitura da flash (parâmetro `writeable` desligado), o que preserva a segurança
- `SPI_INTEL_PLATFORM` (a variante de plataforma, sem dispositivo aqui) continua fora
- CH341 SPI não deve ser habilitado só porque CH341 serial é usado
- `spidev` continua fora

## 28. Pinctrl / GPIO

### Pinctrl correto

**Para Raptor Lake HX:**

- Intel Alder Lake pinctrl and GPIO driver
- `PINCTRL_INTEL`
- `PINCTRL_ALDERLAKE`
- não usar Tiger Lake pinctrl para o 13900HX

### GPIO userspace

- `/dev/gpiochipN` não é necessário ao uso normal
- GPIO ABI v1 desnecessária
- sysfs GPIO legado desnecessário
- se core estiver forçado, não quebrar dependências só para removê-lo
- `GPIO_CDEV` (e com ele a ABI v1) sai pelo bloco 8 do `.myfrag` (`EXPERT`); `GPIO_SYSFS` já está desligado

### Placas externas

- Arduino/ESP32/RPi via USB não justificam GPIO aleatório no host.

## 29. Regulators / PMIC

- `intel-undervolt` não depende de `CONFIG_REGULATOR`
- NVML/NVIDIA não depende de `CONFIG_REGULATOR`
- regulator framework é para PMICs/reguladores físicos geridos pelo kernel
- muitos reguladores Maxim/TI/Richtek/NXP/MediaTek foram considerados desnecessários
- `REGULATOR` / fixed voltage regulator ainda apareceu selecionado por dependência
- não forçar `REGULATOR`=n enquanto essa dependência não for identificada

## 30. Bateria / power supply

- bateria `BAT0`: DELL 70N2F3B (fabricante SMP), Li-poly, fabricada em 2023-12-26
- driver: bateria ACPI (`acpi-battery`, dispositivo `PNP0C0A`); SBS não é usado
- capacidade de projeto ~84,28 Wh (7393 mAh × 11,4 V); capacidade atual ~59,9 Wh (5254 mAh), ~71% de saúde; 144 ciclos
- fontes de energia: `AC` (driver `ac`) e duas portas USB-C (`ucsi-source-psy-USBC000:001` e `:002`, driver `ucsi_acpi`)

**Preservar:**

- power supply class
- bateria ACPI
- AC adapter
- power supply hwmon quando útil
- Drivers de fuel gauge/charger específicos não devem ser mantidos só porque existe bateria.

## 31. linux-tkg e build

**Contexto registrado:**

- projeto `linux-tkg`
- repo em `/opt`
- build em tmpfs `/tmp/kernel-build` (42 GiB)
- configuração de referência: a do `linux-zen` 7.2.14 em uso, salva com `zcat /proc/config.gz > ~/config-arch-7.2.14-zen1-1-zen`; mostra também o que o kernel compila embutido e que o `lsmod` não lista. Com `_distro="Arch"` e `_configfile` vazio, o linux-tkg parte do `linux-tkg-config/7.2/config.x86_64` do próprio repositório, que é a configuração do `linux` do Arch (gerada a partir do 7.2.15-arch1; idêntica à do `linux` 7.2.14-arch1-1 em uso, salva em `~/config-7.2.14-arch1-1`)
- comportamento atual (zen) a manter: THP em `always`; preempção dinâmica (`PREEMPT_DYNAMIC`) no modo `full`, com o modo `lazy` também disponível
- versão: o linux-tkg usa a versão estável mais recente da série escolhida na hora do build (7.2.15 em 2026-11-08); o `_version` do `.cfg` está vazio, então o script pergunta a cada build (`"7.2-latest"` ou uma tag como `"v7.2.15"` fixam a escolha). As séries 7.2 e 7.3 são mantidas pelo linux-tkg; a 7.1 está em fim de vida
- `linux` e `linux-zen` têm a mesma configuração, exceto 11 opções:
  - `-O2` no `linux`, `-O3` no zen (o linux-tkg usa `-O3` pelo `_compileroptlevel=2`)
  - `COMPACT_UNEVICTABLE_DEFAULT`: 1 no `linux`, 0 no zen (o zen não compacta páginas travadas na memória, para evitar picos de latência). Os patches do linux-tkg não mudam esse padrão. Decidido: fica 1, o padrão do `linux`, que favorece as páginas grandes (THP e VMs); se o áudio tiver xruns, testar `vm.compact_unevictable_allowed=0` por sysctl, sem recompilar
  - só no zen, por virem de patches dele: `ZEN_INTERACTIVE`, `TCP_CONG_BBR3`, `VHBA`, `USER_NS_UNPRIVILEGED` (no linux-tkg vem do patch próprio, ver 17), `FORCE_IRQ_THREADING`, `SCHED_ALT`, `PREEMPT_RT`, `X86_64_VERSION`
  - as tabelas abaixo, feitas a partir do zen, valem também para a base do linux-tkg
- configuração externa em `~/.config/frogminer/linux-tkg.cfg`; fragmento `alienware.myfrag` (ver "Fragmento" abaixo e os cuidados com `_STRIP` e `_diffconfig`)

**Configuração de referência (`linux-zen` 7.2.14, GCC 16.2.1): valores relevantes**

Já correspondem ao inventário:

| Área | Opções no zen |
|---|---|
| Firmware e módulos | `FW_LOADER_COMPRESS_ZSTD=y`, `MODULE_COMPRESS_ZSTD=y`, `MODULE_DECOMPRESS=y` |
| Assinatura | `MODULE_SIG=y`, `MODULE_SIG_ALL=y`, `MODULE_SIG_SHA512=y`, `MODULE_SIG_FORCE` desligado; `INTEGRITY_MACHINE_KEYRING=y`, `INTEGRITY_PLATFORM_KEYRING=y`, `SECONDARY_TRUSTED_KEYRING=y`, `LOAD_UEFI_KEYS=y` (o kernel confia na MOK para os módulos DKMS) |
| Lockdown | `SECURITY_LOCKDOWN_LSM=y` com `LOCK_DOWN_KERNEL_FORCE_NONE=y` (não bloqueia a hibernação) |
| LSMs | `CONFIG_LSM="landlock,lockdown,yama,integrity,bpf"`, `BPF_LSM=y`; `IMA` desligado |
| Debug/BPF | `DEBUG_INFO_BTF=y`, `DEBUG_INFO_BTF_MODULES=y`, `DEBUG_INFO_DWARF5=y`; `DEBUG_INFO_COMPRESSED_ZSTD` desligado (o `.myfrag` o liga) |
| Sistema | `PSI=y`, `USER_NS=y`, `CPUSETS=y`, `AIO=y`, `IO_URING=y`, `FANOTIFY_ACCESS_PERMISSIONS=y`, `IRQ_FORCED_THREADING=y` |
| Memória | `TRANSPARENT_HUGEPAGE_ALWAYS=y`, `HUGETLBFS=y`, `COMPACTION=y`, `LRU_GEN_ENABLED=y`, `TMPFS_QUOTA=y`, `ZSWAP_DEFAULT_ON=y`, `ZSWAP_SHRINKER_DEFAULT_ON=y` |
| Boot | `EFI_STUB=y`, `EFI_ESRT=y`, `EFIVAR_FS=y`, `EFI_VARS_PSTORE=y`, `DRM_SIMPLEDRM=y`, `FB_EFI=y`, `RD_ZSTD=y`, `KERNEL_ZSTD=y` |
| Embutidos (não aparecem no `lsmod`) | `BTRFS_FS=y`, `FUSE_FS=y`, `TCG_TPM=y`, `TCG_CRB=y`, `TCG_TIS=y`, `CRYPTO_XTS=y`, `X86_MSR=y`, `ACPI_PLATFORM_PROFILE=y`, `I8K=y` |
| CPU e segurança | `X86_KERNEL_IBT=y`, `X86_USER_SHADOW_STACK=y`, `MITIGATION_SPECTRE_BHI=y`, `MITIGATION_VMSCAPE=y`, `INIT_ON_ALLOC_DEFAULT_ON=y`, `HARDENED_USERCOPY=y`, `STACKPROTECTOR_STRONG=y`, `SLAB_FREELIST_HARDENED=y` |
| Escalonamento | `PREEMPT=y`, `PREEMPT_DYNAMIC=y`, `HZ_1000=y` |
| Módulos dos usos declarados | `NTSYNC=m`, `INPUT_UINPUT=m`, `VHOST_NET=m`, `BRIDGE=m`, `TUN=m`, `WIREGUARD=m`, `SND_SEQUENCER=m` |

Diferenças em relação ao que o inventário pede:

- `INTEL_IOMMU_DEFAULT_ON` está desligado; o IOMMU é ligado pelo `intel_iommu=on` (1B). O `.myfrag` o liga
- `HIBERNATION_DEF_COMP="lzo"`: o lz4 da hibernação vem do parâmetro de 1B; o `.myfrag` torna o lz4 o padrão. `ZSWAP_COMPRESSOR_DEFAULT="zstd"` já é o compressor decidido para o zswap
- `EFI_VARS_PSTORE_DEFAULT_DISABLE=y`: o backend EFI do pstore fica desligado (ver 8); o `.myfrag` volta ao padrão do Kconfig
- `NO_HZ_FULL=y` e `NR_CPUS=8192` no zen; o linux-tkg usa `NO_HZ_IDLE` e 32 CPUs
- `TCG_TPM` e `TCG_CRB` estão embutidos no zen; o inventário prefere módulos (19), e o `.myfrag` os passa a m
- `SECURITY_APPARMOR`, `SECURITY_SELINUX` e `SCHED_CLASS_EXT` (sched_ext) estão compilados sem uso ativo; decidido mantê-los
- `SPI_INTEL_PLATFORM=m`, `EDAC_IE31200=m` e `I8K=y` estão no zen, mas o inventário os deixa fora (27, 3 e 23); o `.myfrag` os desliga
- `CRYPTO_AES_NI_INTEL` e `DM_CRYPT` são módulos: o hook `sd-encrypt` os põe no initramfs

**Kernels de reserva:** `linux` e `linux-zen`. Versões novas do kernel às vezes quebram o `nvidia-open-dkms` por um tempo, então manter um kernel de reserva com DKMS funcionando é necessário.

**Requisitos do fluxo de build e boot:**

- módulos DKMS a compilar para cada kernel: `nvidia/615.78.08` e `looking-glass/B7` (`kvmfr`); conferir com `dkms status`
- o `linux-firmware` do Arch é comprimido em zstd: o kernel precisa carregar firmware zstd, senão Wi-Fi, Bluetooth, iGPU (GuC/HuC/DMC), áudio (SOF) e Ethernet param de funcionar
- módulos comprimidos (zstd) e o `MODULES_DECOMPRESS` do `mkinitcpio` precisam combinar com a compressão de módulos escolhida no Kconfig

**Configuração atual do `linux-tkg.cfg`:**

- escalonador BORE (`_bore_min_base_slice_ns=2000000`)
- GCC; `_lto_mode="thin"` só vale para clang, então com GCC o LTO fica desligado
- `-O3` (`_compileroptlevel=2`)
- `-march=native` (`_processor_opt=native`)
- `_tickless=2` → tickless-idle (`NO_HZ_IDLE`)
- 1000 Hz
- 32 CPUs
- NUKR
- `_STRIP="true"`: remove o DWARF dos módulos (`INSTALL_MOD_STRIP=1`, que mantém a seção `.BTF`) e do `vmlinux` dos headers. O tkg também liga `DEBUG_INFO_NONE`, que desligaria o BTF; o `.myfrag`, aplicado depois, religa o debug (`# CONFIG_DEBUG_INFO_NONE is not set`, `DEBUG_INFO_DWARF5`, `DEBUG_INFO_BTF`, `DEBUG_INFO_BTF_MODULES`, `DEBUG_INFO_COMPRESSED_ZSTD`)
- MGLRU ligado
- `_zenify` e `_glitched_base` ligados
- sem efeito no 7.2 (patch inexistente ou opção removida do kernel): `_fsync_backport`, `_fsync_legacy`, `_zfsfix`, `_ntsync` (o `CONFIG_NTSYNC` do Kconfig fica ligado, ver 17), `_random_trust_cpu`, `_aggressive_ondemand` (só para MuQSS/PDS/BMQ), `_install_after_building` (só fora do Arch) e as opções de LLVM
- `_irq_threading="false"` (a threading de IRQs vem do parâmetro `threadirqs`)
- `_acs_override="false"` (o ACS do firmware já isola a dGPU)
- debug, ftrace e NUMA não são desativados pelo tkg (`_debugdisable`, `_ftracedisable`, `_numadisable` = false)
- `_kernel_on_diet` desligado; `_modprobeddb="true"`, com `_modprobeddb_db_path=~/.local/share/modprobed-db/modprobed.db` (o caminho das versões atuais do `modprobed-db`; o `.cfg` apontava para `~/.config/modprobed.db`, corrigido em 2026-11-10)
- `_menunconfig="1"` (abre o `menuconfig` a cada build), `_diffconfig="true"` e `_diffconfig_name="menuconfig-diff.txt"`
- o `modprobed-db` roda `make localmodconfig` antes dos `.myfrag` e do `menuconfig`: desliga as opções m cujo módulo não está no banco e não mexe nas y. As mudanças de y para m (TPM, Btrfs etc.) continuam vindo do `.myfrag`/`menuconfig`, e o que o banco derrubar por engano pode voltar por eles
- `modprobed-db` instalado, com o timer ajustado para rodar a cada 10 s durante a coleta antes do primeiro build
- o banco só tem o que foi carregado como módulo no kernel em uso. Módulos de uso raro precisam ser carregados ao menos uma vez antes do build, senão somem: exFAT, ISO 9660, UDF, FAT (`vfat`, `nls_cp437`), `uas` (SSD externo), `ax88179_178a`, seriais do Arduino/ESP32 (`cdc_acm`, `cp210x`, `ch341`), `ipheth` (iPhone), gamepads, `uinput`, KVM/VFIO, `vhost_net`, `bridge`, `tun`, `loop`, `nbd`, `ntsync` e o `lz4` da hibernação
- em 2026-11-09, os módulos do inventário que faltavam no banco (295 módulos) foram acrescentados à mão, 62 ao todo, chegando a 357: codepages NLS, `nbd`, `ntsync`, `mmc_block`, seriais USB (`cdc_acm`, `usbserial`, `ch341`, `cp210x`, `ftdi_sio`, `pl2303`), `rndis_host`, `r8152`, gamepads (`xpad`, `hid_playstation`, `led_class_multicolor`, `hid_sony`, `hid_steam`, `hid_nintendo`, `hid_logitech`), `hidp`, áudio USB e MIDI (`snd_usb_audio`, `snd_usbmidi_lib`, `snd_rawmidi`, `snd_ump`, `snd_seq_midi`, `snd_seq_midi_event`), qdiscs e classificadores (`sch_fq`, `sch_cake`, `sch_fq_codel`, `sch_ingress`, `cls_flower`, `cls_matchall`, `act_gact`, `act_mirred`) e os que são embutidos na base e o `.myfrag` passa a m (`tpm`, `tpm_crb`, `btrfs`, `fuse`, `xts`, `msr`, `usbhid`, `hid_generic`, `xhci_*`, `i8042`, `atkbd`, `serio`, `libps2`, `sd_mod`, `scsi_mod`, `autofs4`, `configfs`, `ac`, `battery`, `button`, `i2c_designware_*`). O `modprobed-db store` só acrescenta, então eles ficam. Os módulos da NVIDIA (DKMS) não entram no banco, e não precisam
- `PREEMPT_RT` desligado
- `menuconfig` + `diffconfig`, com `olddefconfig`. O `diffconfig` grava em `$_where/$_diffconfig_name` só as mudanças feitas naquele `menuconfig` (compara com a configuração já com o fragmento aplicado). O fragmento fixo e o gerado precisam de nomes diferentes, e o gerado não pode terminar em `.myfrag`, senão é aplicado automaticamente: com `menuconfig-diff.txt`, está certo
- compilador: GCC 16.2.1, sem suporte a `-fsanitize=kcfi` (kCFI indisponível); `-fzero-call-used-regs` suportado

**Ordem do build no linux-tkg (lida no `linux-tkg-config/prepare`):** base `config.x86_64` → `make localmodconfig` com o banco → ajustes do próprio tkg (`DEBUG_INFO_NONE` do `_STRIP`, `NR_CPUS`, tickless, `MAXSMP` desligado etc.) → cada `*.myfrag` por `merge_config.sh -m`, em ordem alfabética → `olddefconfig` → `menuconfig` → `diffconfig`. O fragmento é aplicado depois dos ajustes do tkg e prevalece sobre eles.

**Fragmento `alienware.myfrag` (montado e revisado em 2026-11-09/10):**

- local: o tkg só aplica arquivos *regulares* terminados em `.myfrag` dentro do diretório dele (`find "$_where"/ -type f -name "*.myfrag"`, ou seja, `/opt/linux-tkg/`); um symlink é ignorado sem aviso. A cópia versionada fica em `~/.config/frogminer/alienware.myfrag` e vai para `/opt/linux-tkg/` com `install -m644`, a cada mudança. Em `/opt/linux-tkg/` havia um `alienware.myfrag` antigo (2026-08-19, 48930 bytes), a guardar com um nome que não termine em `.myfrag`
- validação: simulado no código-fonte do 7.2.15 (configuração do `linux` → `localmodconfig` com o banco real → ajustes do tkg → fragmento → `olddefconfig`); toda linha fica com o valor pedido. Validação só de Kconfig, sem compilar
- conteúdo, cada linha comentada com a seção deste documento que a justifica:
  1. debug: religa o BTF (`DEBUG_INFO_DWARF5`, `_BTF`, `_BTF_MODULES`, `_COMPRESSED_ZSTD`) e tira testes, injeção de falhas, `MMIOTRACE`, debug por xHCI/EHCI, `OVMF_DEBUG_LOG`, kexec/kdump/Live Update e contadores de debug em caminhos quentes (`LOCK_EVENT_COUNTS`, `X86_CPA_STATISTICS`)
  2. CPU e papel de host: só Intel (sem AMD, mitigações exclusivas de AMD, IOMMU AMD), sem SGX/TDX/RDT, sem plataformas Intel embarcadas, sem papel de guest (`HYPERVISOR_GUEST`, Hyper-V, frontends VirtIO, `REMOTEPROC`), `INTEL_IOMMU_DEFAULT_ON`, `HIBERNATION_COMP_LZ4`, sem ABI x32, sem `ioperm`/`iopl`, `/dev/mem`, `/dev/port` e `/dev/snapshot`, sem EFI handover
  3. os itens "Desligar" da seção 2
  4. hardware ausente: SATA, AGP, VESA, EHCI/OHCI/UHCI, UART 8250, PMICs, touchscreen, TV/rádio/câmeras de plataforma, IR, NVMe multipath/auth, DAX, zonados, HBAs, SR-IOV e outros recursos PCI de servidor, NPU, infraestrutura de SoC, RAS de servidor, flash NAND, eMMC
  5. segurança (ver 33.5): LSMs sem uso, descompressores de initramfs além do zstd, tabelas de partição além de GPT/MBR, protocolos de datacenter, endurecimento
  6. embutido → módulo (ver 33.2)
  7. rede de segurança: os módulos de uso raro declarados, como m, para o caso de o banco não os ter
  8. `EXPERT=y` e o que só sai com ele: suporte a CPUs AMD/Hygon/Centaur/Zhaoxin, protocolos PS/2, `GPIO_CDEV`, `UID16`, `SGETMASK_SYSCALL`, emulação vsyscall, coredumps de dispositivo, mapas de memória do firmware, console VGA e codecs HD-audio ausentes. Testado: ligar o `EXPERT` não muda nenhuma outra opção. Decidido em 2026-11-10, pela regra das alavancas de segurança (o aviso do Kconfig do `EXPERT` não é um "If unsure, say N")
- ficam de propósito: `NUMA` (o linux-tkg avisa que desligá-lo quebra CUDA/NVENC), `MEMORY_HOTPLUG`/`ZONE_DEVICE`/`DEVICE_PRIVATE` (nvidia), `PCI_P2PDMA` (o `VFIO_PCI_DMABUF` depende dele), governors do cpufreq e térmicos (32A), `ACPI_DEBUG`, os tracers de latência (`HWLAT`, `OSNOISE`, `TIMERLAT`, úteis para xruns), `PROC_KCORE` (perf/drgn), o debug do iwlwifi e os menus `NET_VENDOR_*`/`WLAN_VENDOR_*` (só menus)

## 32. Undervolt / power tuning

### CPU

- usa `intel-undervolt`
- mecanismo por MSR
- `X86_MSR` como módulo: o `msr` não carrega sozinho ao abrir `/dev/cpu/*/msr`, mas o `intel-undervolt` roda `/sbin/modprobe msr` antes (conferido no binário em 2026-11-09); não precisa de `modules-load.d`
- a configuração (`/etc/intel-undervolt.conf`) só tem as linhas `undervolt`, mais `daemon undervolt`, `daemon power` e `daemon tjoffset` sem valores de `power` nem `tjoffset`: nada usa o `/dev/mem`, que o `intel-undervolt` só abre para limites de potência e Tjunction por MMIO. Os limites de potência vêm do tuned pelo powercap (32A.4). Decidido: `DEVMEM` sai; religar se um dia usar `power` ou `tjoffset` no `intel-undervolt`
- não confundir com regulator framework
- offsets: CPU −100 mV, GPU −70 mV, CPU Cache −100 mV, System Agent −70 mV, Analog I/O −70 mV; reaplicados pelo daemon a cada 60 min
- o firmware só aceita o undervolt porque o UnderVolt Protection está desativado

### GPU

- usa undervolt/ajustes via NVML API
- usa driver NVIDIA
- não depende de regulator framework genérico
- `nvidia-undervolt.service` (oneshot, depois do `nvidia-persistenced`): clocks travados entre 210 e 2175 MHz e offsets de clock por P-state (P0 +300, P3 +255, P4 +240, P5 +225, P8 +180 MHz)
- o `nvidia-persistenced` mantém esses ajustes enquanto o driver estiver carregado

### Ferramentas

**Registradas:**

- `tuned`
- `tuned-ppd`
- powertop (usado apenas para melhorar os perfis customizados do tuned)
- thermald

Ao remover governors/thermal facilities, considerar se uma ferramenta realmente depende deles.

## 32A. Perfis customizados do tuned

O laptop possui quatro perfis customizados do `tuned`, mais um conjunto comum (`alienware-common`) que todos incluem. Eles fazem parte dos usos reais da máquina. Portanto, ao escolher opções do kernel, deve-se preservar as interfaces que esses perfis manipulam dinamicamente.

### 32A.1 Perfis e objetivos

#### alienware-common

- não é selecionado sozinho; reúne os sysctls e o PCI runtime PM comuns
- `power-policy.bash`, ao lado dele, tem o código compartilhado: platform profile, RAPL, Wi-Fi e dGPU (ver 32A.4 e 32A.14)

#### alienware-balanced

- perfil cotidiano padrão em AC
- objetivo: equilíbrio geral

#### alienware-balanced-battery

- uso leve em bateria (o uso típico do usuário fora da tomada)
- herda o `alienware-balanced` e puxa para a economia: EPB `balance-power`, limites RAPL menores, ASPM `powersupersave`, USB autosuspend, Wi-Fi power save, sem wakeup de rede e sem NMI watchdog

#### alienware-performance

- exclusivo para AC
- objetivo: desempenho determinístico com maior consumo
- usa `platform_profile`=balanced-performance, e não performance, porque no Alienware o perfil performance corresponde ao AWCC Overdrive e fixa as ventoinhas no máximo
- usa o governor `powersave` com EPP `balance_performance`, e não o governor `performance`: com este, o `intel_pstate` força a EPP em `performance`, a CPU nunca descansa e os reguladores de tensão produzem coil whine audível

#### alienware-battery

- exclusivo para bateria (antes chamado `alienware-powersave`)
- objetivo principal: maximizar autonomia, mais rígido que o balanced-battery: boost desligado, platform profile `quiet` e a dGPU forçada a desligar (32A.14)

### 32A.2 CPUFreq, Intel P-state, EPB/EPP e boost

**Os perfis dependem de troca dinâmica de governor, EPB, EPP e boost:**

| Perfil | Governor | EPB | EPP | Boost |
|---|---|---|---|---|
| balanced | powersave | normal | balance_power | ligado |
| balanced-battery | powersave | balance-power | balance_power | ligado |
| performance | powersave | performance | balance_performance | ligado |
| battery | powersave | power | power | desligado |

**Requisitos ao kernel:**

- preservar CPU frequency scaling
- preservar Intel P-state em modo ativo, com HWP; nesse modo, `powersave` e `performance` são políticas do próprio `intel_pstate`
- preservar interfaces de Energy Performance Bias (EPB) e Energy Performance Preference (EPP)
- preservar a capacidade de ligar/desligar CPU boost em runtime
- não remover um governor só porque ele não é o default do kernel (os governors genéricos ficam como módulos, carregados ao serem escolhidos)

### 32A.3 ACPI platform profile

**Os perfis usam `/sys/firmware/acpi/platform_profile`:**

| Perfil | Valor |
|---|---|
| balanced | balanced |
| balanced-battery | balanced |
| performance | balanced-performance |
| battery | quiet |

Ao parar, os perfis devolvem o `balanced` ao firmware.

**Requisitos:**

- preservar suporte a ACPI platform profile
- preservar os drivers Dell/Alienware/ACPI que fornecem essa interface
- não tratar `platform_profile` como recurso cosmético: ele participa ativamente da política de energia
- uma troca de `platform_profile` pode fazer o EC do Alienware reprogramar os limites RAPL

### 32A.4 Intel RAPL / powercap

**Os perfis escrevem diretamente em:**

`/sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw`

e também em `/sys/class/powercap/intel-rapl-mmio:0/` (os dois backends recebem os mesmos valores).

O firmware foi alterado pelo usuário para permitir até 157 W de package power (PL2).
O limite de consumo total máximo do laptop é 330 W (capacidade da fonte que veio com ele).

| Perfil | PL1 / long term | Janela do PL1 | PL2 / short term | PL4 / peak |
|---|---:|---:|---:|---:|
| balanced | 55 W | 64 s | 86 W | 160 W |
| balanced-battery | 24 W | 28 s | 48 W | 72 W |
| performance | 117 W | 128 s | 157 W | 330 W |
| battery | 12 W | 16 s | 24 W | 42 W |

**Os limites são escritos de forma que `PL1 <= PL2 <= PL4` valha depois de cada escrita:** os que sobem, de cima para baixo (PL4, PL2, PL1); depois os que descem, de baixo para cima.

**Implementação (`power-policy.bash`):**

- o firmware aplica o `platform_profile` de forma assíncrona: as escritas RAPL esperam 16 s depois da troca, dentro de uma unidade transitória do systemd (`systemd-run`), para o `tuned` não ficar bloqueado
- cada troca de perfil usa um nome de unidade único e um ID de execução: uma execução substituída por uma troca mais nova sai sem escrever, então trocas rápidas não disputam os limites
- a verificação aos 10, 20 e 30 s confere o limite *efetivo* (o menor entre MSR e MMIO) e reescreve se o EC o tiver mudado; no `quiet`, o EC devolve o PL1 do MMIO a 50 W, mas o MSR continua valendo, e o limite efetivo fica certo
- o resultado vai para o journal (`Applied platform profile ...`)

**Observações:**

- o lock de PKG_POWER_LIMIT está desativado no firmware (Package Power Limit MSR Lock: Disabled), então as escritas funcionam
- os logs do `tuned` e do journal são usados para diagnosticar falhas de escrita

**Requisitos:**

- preservar Intel RAPL (MSR e MMIO, `processor_thermal_rapl`)
- preservar o framework `powercap`
- preservar a interface sysfs correspondente
- preservar o backend RAPL adequado à plataforma

### 32A.5 PCI runtime PM e ASPM

**Todos os perfis usam (pelo `alienware-common`):**

`/sys/bus/pci/devices/*/power/control=auto`

Logo, PCI runtime PM deve ser preservado.

**Política ASPM:**

| Perfil | Política |
|---|---|
| balanced | powersave |
| balanced-battery | powersupersave |
| performance | performance |
| battery | powersupersave |

**Requisitos:**

- preservar PCIe ASPM
- preservar alteração de política ASPM em runtime
- não compilar o kernel com ASPM permanentemente desativado
- preservar runtime PM dos dispositivos PCIe

### 32A.6 Áudio HDA e power saving

**Os perfis alteram:**

`/sys/module/snd_hda_intel/parameters/power_save`

| Perfil | Timeout |
|---|---:|
| balanced | 10 s |
| balanced-battery | 10 s |
| performance | 0 s |
| battery | 1 s |

**Motivação registrada:**

- o codec HDMI da NVIDIA apareceu no powertop como um dos maiores consumidores
- suspender o codec economiza energia
- o resume pode produzir um pop audível
- balanced e balanced-battery usam 10 s para reduzir a frequência dos pops
- battery aceita 1 s em favor da autonomia
- performance desativa o power saving do codec

**Requisitos:**

- preservar power management do `snd_hda_intel`
- preservar o parâmetro `power_save`
- preservar runtime PM de HDA Intel/NVIDIA

### 32A.7 Swap, zswap e page-cluster

**Todos os perfis usam (pelo `alienware-common`):**

```ini
vm.swappiness=60
vm.page-cluster=1
```

A justificativa explícita é o uso de `zswap`: readahead grande por page fault tende a ser desperdiçado quando a página volta do pool comprimido em RAM; page-cluster=1 mantém pequena antecipação para páginas rejeitadas pelo `zswap`.

**Requisitos:**

- preservar swap
- preservar `zswap`
- preservar `vm.swappiness`
- preservar `vm.page-cluster`

### 32A.8 Writeback / VM

#### Balanced (padrão do `alienware-common`)

`vm.dirty_writeback_centisecs=500`

#### Balanced-battery

`vm.dirty_writeback_centisecs=1500`

#### Performance

```ini
dirty_bytes=10%
dirty_background_bytes=3%
vm.dirty_writeback_centisecs=500
```

#### Battery

```ini
vm.dirty_writeback_centisecs=1500
vm.dirty_expire_centisecs=6000
```

Em bateria, o objetivo é agrupar writeback em rajadas menos frequentes para deixar o NVMe em idle real por mais tempo. O battery aceita conscientemente uma janela maior de dados ainda não persistidos em caso de crash.

**Requisitos:**

- preservar os sysctls de writeback usados pelos perfis

### 32A.9 NMI watchdog

**Os perfis alternam o NMI watchdog em runtime:**

| Perfil | `kernel.nmi_watchdog` |
|---|---:|
| balanced | 1 |
| balanced-battery | 0 |
| performance | 1 |
| battery | 0 |

**Portanto:**

- o suporte ao NMI watchdog / hard lockup detector deve permanecer compilado
- os perfis de bateria o desligam para economia
- balanced e performance o reativam
- não remover o suporte do kernel apenas para liberar o contador PMU
- deixar o `tuned` decidir o estado em runtime

### 32A.10 USB autosuspend

**Os perfis balanced-battery e battery usam o plugin [usb]:**

`autosuspend=1`

O autosuspend USB havia sido tentado antes por script, mas dependia de `$USB_AUTOSUSPEND` não definida e não funcionava; por isso foi movido para o plugin [usb].

**Requisitos:**

- preservar USB runtime PM
- preservar autosuspend
- manter os drivers reais de áudio USB, HID, webcam, celulares e placas de desenvolvimento compatíveis com esse mecanismo

### 32A.11 Wi-Fi power save

**Os perfis balanced-battery e battery ligam o power save 802.11 por script, porque ele não usa o mesmo tipo de interface sysfs:**

```text
start -> wifi_powersave_on
stop  -> wifi_powersave_restore
```

**Requisitos:**

- preservar power management de `iwlwifi`/cfg80211/mac80211
- preservar a possibilidade de alternar Wi-Fi power save em runtime

### 32A.12 Wake-on-LAN e wakeup de rede

**Nos perfis balanced-battery e battery:**

`/sys/class/net/*/device/power/wakeup=disabled`

**e no Killer E3000 (`enp110s0`):**

`wake_on_lan=d`

**Objetivo:**

- evitar que Wi-Fi/Ethernet permaneçam armados como fontes de wakeup em bateria
- evitar que o Killer E3000 mantenha o PHY ativo à espera de magic packets

**Requisitos:**

- preservar infraestrutura de device wakeup
- preservar suporte de Wake-on-LAN/ethtool no `r8169`/PHY Realtek
- preservar runtime PM das interfaces de rede

O fato de os perfis de bateria desabilitarem WOL não significa que o suporte deva ser removido do kernel; ele precisa existir para poder ser controlado.

### 32A.13 Regra de seleção de menuconfig derivada dos perfis

Os perfis mostram que o kernel deve fornecer mecanismos, enquanto o `tuned` escolhe a política em runtime.

**Portanto:**

Não remover uma funcionalidade do kernel apenas porque um dos perfis a deixa desligada. Se outro perfil a liga ou altera dinamicamente, o suporte deve permanecer compilado. Tudo o que aparece em 32A.2 a 32A.12 e 32A.14 conta como usado.

### 32A.14 dGPU forçada a desligar (alienware-battery)

- depois de aplicar o perfil, uma unidade transitória (`alienware-dgpu`) confere se a dGPU chegou a D3cold
- se não chegou, registra no journal quem a mantém acordada (`journalctl -t alienware-dgpu`): processos com `/dev/nvidia*` ou os nós DRM abertos, e serviços da NVIDIA ativos
- quando é seguro (nenhum usuário), para o `nvidia-persistenced`, remove as funções PCI da dGPU (`/sys/bus/pci/devices/*/remove`) e grava em `/run/tuned/alienware-dgpu-removed` os serviços a religar; ao trocar de perfil, um rescan PCI (`/sys/bus/pci/rescan`) a traz de volta e reinicia o `nvidia-persistenced` e o `nvidia-undervolt`

**Requisitos:** hotplug/remoção de dispositivos PCI pelo sysfs, rescan PCI, PCI runtime PM e D3cold via ACPI.

## 33. Requisitos para escolher opções do menuconfig

### 33.1 O kernel é específico deste Alienware

- Preservar todo hardware real.
- Preservar usos reais.
- Preservar também usos futuros já declarados.
- Remover hardware de outras plataformas/fabricantes inexistentes.
- Não manter drivers “só por precaução” sem uso plausível declarado.
- Não remover infraestrutura base se hardware real depende dela.
- Diferenciar infraestrutura genérica de driver específico.

### 33.2 Preferência por modularização

**Preferência explícita:**

- maximizar m em vez de y

**usar y quando:**

- necessário cedo
- Kconfig exige
- há vantagem real
- core precisa existir antes de consumidores

As decisões de cada subsistema estão nas seções respectivas. Também decidido: NVMe disponível cedo (root), HWMON core y com sensores em m, suporte a shebang (#!) y.

**Resultado no `.myfrag` (2026-11-10), conferido opção por opção no Kconfig do 7.2.15:** toda opção tristate que podia ser módulo sem perder função virou módulo. Além dos itens de 33.3, saíram do kernel para módulos: `FUSE_FS`, `AUTOFS_FS`, `CONFIGFS_FS`, `BINFMT_MISC`, `ACPI_AC`/`_BATTERY`/`_BUTTON`, `USB_SERIAL`, `EXT4_FS`, `SCSI`/`BLK_DEV_SD`, `I2C_DESIGNWARE_*`, `X86_MSR`/`X86_CPUID`, os escalonadores BFQ e Kyber, os governors genéricos do cpufreq, os algoritmos AES, CBC, CTR, CTS, ECDH, MD5, SHA-1, SHA-3, BLAKE2b, xxHash e CRC32c, `HW_RANDOM`, os heaps de dma-buf, `EXTCON`, `DMI_SYSFS`, `PCI_STUB` e `NET_DROP_MONITOR`. A configuração final simulada tem 1879 opções y e 382 m.

**Ficam y (critérios do Kconfig e da seção 0):**

- boot e console (33.3): `DRM`, `DRM_SIMPLEDRM`, `FB`, `EFIVAR_FS`, `BINFMT_SCRIPT`, `FW_LOADER`
- padrões que precisam existir antes de qualquer módulo: `MQ_IOSCHED_DEADLINE` (padrão dos discos USB; o kernel não carrega o escalonador padrão sozinho), `TCP_CONG_CUBIC`, `NET_SCH_FQ_CODEL`
- relógio no boot (`RTC_HCTOSYS`) e registro de crashes desde o início: `RTC_DRV_CMOS`, `EFI_VARS_PSTORE`
- confiabilidade: `ACPI_THERMAL`, `EDAC` e `EDAC_GHES`
- núcleos carregados em todo boot, em que módulo não economiza nada: `HWMON`, `USB`, `HID`, `SERIO`, `INPUT_EVDEV`, `INPUT_LEDS`, `LEDS_CLASS`, `BACKLIGHT_CLASS_DEVICE`, `WATCHDOG_CORE`
- funções que só existem embutidas: `CONNECTOR` (o `PROC_EVENTS` exige y), `UNICODE` (casefold do tmpfs), `CRYPTO_DRBG` (gerador do crypto API), `IKCONFIG` (`/proc/config.gz`, 35 KB)
- todas as outras opções y são selecionadas por opções que precisam ficar embutidas (por exemplo, a criptografia da assinatura de módulos, o `NLS` pelo ACPI e pelo USB) e não podem mudar

### 33.3 Initramfs/UKI

Não assumir que “módulo” significa “indisponível no boot”.

**O usuário usa:**

- `mkinitcpio`
- UKI
- `systemd-boot`

**Como o `mkinitcpio` escolhe os módulos** (lido no código-fonte, commit `68ebfd2` de 2026-10-18):

- `autodetect` lê `DRIVER=` e `MODALIAS=` de todos os `uevent` em `/sys/devices` do kernel em execução, resolve com o `modprobe -R` do kernel alvo e acrescenta o módulo do sistema de arquivos da raiz (`fs-btrfs`). Os hooks seguintes só incluem módulos dessa lista. Por isso a UKI precisa ser gerada com o hardware visível (vale também no chroot da reinstalação).
- Opções embutidas são lidas de `modules.builtin.modinfo` e puladas sem erro: mudar uma opção entre y e m não exige mudar `MODULES` nem os hooks.
- Cada módulo leva junto as dependências (`depends`), os `softdep` e o firmware que declara. `weakdep` não é seguido.
- `MODULES` entra na imagem e é carregado explicitamente no boot (`/etc/modules-load.d/MODULES.conf` no initramfs). Serve para o que nenhum hook inclui.
- `mkinitcpio -M` mostra a lista do autodetect; `mkinitcpio -v` mostra cada módulo adicionado.

**O que cada hook em uso põe na UKI:**

| Hook | Sempre (se o módulo existir) | Só se autodetectado |
|---|---|---|
| `systemd` | `crypto-lzo`, `crypto-lz4` | — |
| `microcode` | só o microcódigo desta CPU (`GenuineIntel.bin`), no cpio inicial | — |
| `keyboard` | `usbhid`, `xhci_pci`, `xhci_hcd`, `ehci`/`ohci`, `thunderbolt` | controladores USB, `drivers/hid`, `serio` (i8042) e `input/keyboard` (atkbd) |
| `block` | `nvme`, `ahci`, `sd_mod`, `usb_storage`, `uas`, `mmc_block`, `virtio_blk`, `virtio_scsi` | `block`, `ata`, `scsi`, `nvme`, MMC, SPI, controladores PCI, MFD, clk, PHY, regulators |
| `sd-encrypt` | `dm-crypt`, `dm-integrity`, `hid-generic`, todos os módulos de `/crypto/` (sem filtro) | `drivers/char/tpm` (`tpm_crb`, `tpm`) |
| `filesystems` | `vfat` (com `nls_ascii` e `nls_cp437`) | fs da raiz (`btrfs`) |

O hook `kms` não está em `HOOKS`: o `i915` não entra na UKI, e a senha do LUKS aparece pelo `simpledrm`.

**Por que o `kms` aumenta tanto a UKI:** o `nvidia` do DKMS (em `updates/dkms`) não entra, porque o hook só inclui `drivers/gpu/drm/`. O que pesa é o firmware: o autodetect resolve o modalias da dGPU também para o `nouveau` (o `modprobe -R` ignora a blacklist) e o da iGPU também para o `xe`. Cada módulo leva todo firmware que declara: o `nouveau`, os firmwares GSP das GPUs NVIDIA; o `xe` e o `i915`, os de GuC/HuC/DMC de várias gerações Intel. Com `DRM_NOUVEAU` e `DRM_XE` desligados (ver 2), sobram o `i915` e o firmware dele. O hook continua dispensável, porque o `simpledrm` já mostra a senha. Para medir: `mkinitcpio -A kms -s -g /tmp/kms.img` e `du` no diretório de build que ele indica.

**`simpledrm` como módulo:** possível (entraria por `MODULES`), mas não compensa. `DRM_SIMPLEDRM=y` obriga `DRM=y`. Como m, o núcleo DRM e o `simpledrm` só mudam do kernel para o initramfs dentro da mesma UKI, e a RAM é a mesma, porque o `i915` e o `nvidia_drm` carregam o núcleo DRM de qualquer forma. O custo é ficar sem imagem entre o início do kernel e o carregamento do módulo, justamente onde aparecem os erros de boot (initramfs que não descomprime, panic cedo). Fica y.

**Consequências para a modularização:**

- Podem ser m sem mudar nada no `mkinitcpio`: `NVME`, `BTRFS_FS`, `DM_CRYPT`, `CRYPTO_AES_NI_INTEL`, `CRYPTO_XTS`, `TCG_TPM`, `TCG_CRB`, `USB_XHCI_PCI`/`USB_XHCI_HCD`, `USB_HID`, `HID_GENERIC`, `SERIO_I8042`, `KEYBOARD_ATKBD`, `VFAT_FS` e as NLS.
- Ficam y, porque são usados antes de o initramfs rodar ou porque nenhum hook inclui o módulo: `BLK_DEV_INITRD` com `RD_ZSTD`, `DEVTMPFS`, `EFI_STUB`, `DRM_SIMPLEDRM` (tela da senha), `EFIVAR_FS` (o systemd monta o efivarfs já no initramfs), `UNIX` (o systemd usa sockets AF_UNIX desde o PID 1), `BINFMT_ELF` e `BINFMT_SCRIPT`.
- `zswap`: o compressor é escolhido numa initcall, antes de o systemd do initramfs carregar o `MODULES`. `CRYPTO_ZSTD` (e `CRYPTO_LZ4`, `CRYPTO_LZO`) já é y na base e fica, então o zstd está disponível na initcall; as entradas de `MODULES` não têm efeito.
- descompressores de initramfs: só `RD_ZSTD` fica (a UKI usa zstd); os outros `RD_*` saem. Se a `COMPRESSION` do mkinitcpio mudar, religar o `RD_*` correspondente, senão a UKI não inicia.
- `CRYPTO_MODULES`: sem ela, o `sd-encrypt` põe na UKI todos os módulos de criptografia, que com modularização máxima são dezenas. A variável não é documentada, mas o `sd-encrypt` a lê da configuração (pode ficar em `/etc/mkinitcpio.conf.d/`); para `aes-xts-plain64`, a lista mínima seria `aesni_intel xts` (as dependências entram sozinhas). Conferir com `mkinitcpio -v` e um boot de teste, com a UKI fallback à mão.
- A UKI fallback (preset sem `autodetect`) inclui todos os módulos de bloco, USB host, HID, input, criptografia e sistemas de arquivos: cresce com a modularização máxima. Verificar o espaço na ESP.
- `MODULES_DECOMPRESS="yes"`: módulos e firmware são descomprimidos e entram na compressão zstd da imagem. O manual indica isso para níveis altos de compressão; com `-1` o ganho é pequeno, e o uso de RAM no início do boot é maior. Com `"no"`, os arquivos já comprimidos vão sem recompressão para o cpio inicial. O firmware do disco continua em zstd de qualquer forma (`FW_LOADER_COMPRESS_ZSTD=y`, ver 31).

### 33.4 Performance

Prioridade alta, mas não acima da segurança.

**Evitar:**

- debug desnecessário (e.g. quando o Kconfig desencoraja)
- test drivers
- simuladores
- tracing não usado (o powertop, usado para ajustar os perfis do tuned, precisa dos eventos de perf e tracepoints)
- trabalho periódico inútil
- mecanismos térmicos/energia desnecessários que reduzam desempenho (exceto quando aumentam a confiabilidade do hardware [reliability])
- drivers guest no host
- qdiscs/classifiers não usados
- drivers grandes de hardware impossível

Mas não sacrificar funcionalidade real por poucos KB.

### 33.5 Segurança

**Preferir configurações que:**

- reduzam superfície de ataque
- evitem raw access desnecessário
- removam interfaces userspace antigas
- removam test/debug sem uso
- evitem flash/firmware raw sem necessidade
- funcionem com Secure Boot

Os casos concretos (GPIO, i2c-dev, SPI, thermal emulation, LIRC, watchdogs) estão nas seções respectivas; `spidev` também fica fora.

**LSMs:** em uso hoje, `capability,landlock,lockdown,yama,bpf`.

**systemd:** a lista oficial de opções do kernel que o systemd exige (seção REQUIREMENTS do README do systemd: cgroup v2, BPF, seccomp, namespaces, entre outras) é referência obrigatória.

**Linhas de disciplina de linha (tty) em uso:** só `n_tty` e `n_null` (2026-11-10): `LDISC_AUTOLOAD` desligado não quebra nada.

**Decisões do `.myfrag` (2026-11-10), pela regra das alavancas de segurança da seção 0:**

- já na base e mantidas: `X86_KERNEL_IBT`, shadow stack, `INIT_STACK_ALL_ZERO`, `INIT_ON_ALLOC_DEFAULT_ON`, `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `SLAB_FREELIST_RANDOM`/`_HARDENED`, `SLAB_BUCKETS`, `RANDOMIZE_KSTACK_OFFSET_DEFAULT`, `STACKPROTECTOR_STRONG`, `SECURITY_DMESG_RESTRICT`, `BPF_UNPRIV_DEFAULT_OFF`, `BPF_JIT_ALWAYS_ON`, `DEFAULT_MMAP_MIN_ADDR=65536`, todas as mitigações de CPU da Intel e as comuns
- ligadas: `INIT_ON_FREE_DEFAULT_ON` (o mais caro; `init_on_free=0` na linha de comando desliga para medir), `ZERO_CALL_USED_REGS`, `SLAB_MERGE_DEFAULT` desligado, `KMALLOC_PARTITION_CACHES`, `PROC_MEM_NO_FORCE`, `MODULE_SIG_FORCE` (18), `SECURITY_LOCKDOWN_LSM_EARLY`, `UBSAN` com `UBSAN_BOUNDS` e `UBSAN_TRAP` (os outros detectores do UBSAN só acham bugs e, com o trap, derrubariam o kernel por comportamentos inofensivos: ficam desligados). O Kconfig avisa que o trap "may destabilize the system", e os módulos do DKMS também são compilados com ele: se o nvidia der oops, usar o `linux` ou o `linux-zen`
- interfaces e acesso bruto removidos: `DEVMEM` (32), `DEVPORT`, `X86_IOPL_IOPERM`, `HIBERNATION_SNAPSHOT_DEV` (`/dev/snapshot`, sem uswsusp), `KEXEC`/`KEXEC_FILE`/`CRASH_DUMP`/`KEXEC_HANDOVER`/`LIVEUPDATE`, `X86_X32_ABI`, `LDISC_AUTOLOAD`, `NVRAM`, `EFI_HANDOVER_PROTOCOL`, `MODULE_FORCE_LOAD`/`_UNLOAD`, `SND_OSSEMUL`; com `EXPERT`: `UID16`, `SGETMASK_SYSCALL`, `X86_VSYSCALL_EMULATION`, `ALLOW_DEV_COREDUMP` (Kconfig: "Say 'N' for more sensitive systems"), `EFI_RUNTIME_MAP`, `FIRMWARE_MEMMAP`, `GPIO_CDEV`
- superfície de ataque reduzida: LSMs compilados fora da lista ativa (`SECURITY_SMACK`, `_TOMOYO`, `_LOADPIN`, `_SAFESETID`, `_IPE`; AppArmor e SELinux ficam por decisão de 31), descompressores de initramfs além do zstd, tabelas de partição além de GPT e MBR (AIX, Mac, BSD, Minix, Solaris, LDM, Karma), protocolos de rede de datacenter/BMC/roteador (DCB, MCTP, NC-SI, MPLS, PSP, switchdev, netkit, SRv6, RPL, IOAM, MRP, CFM), `BSD_PROCESS_ACCT`, `CGROUP_RDMA`, `ACCESSIBILITY`
- em N porque o Kconfig manda: `BUG_ON_DATA_CORRUPTION` e `PANIC_ON_OOPS` ("If unsure, say N"), `PAGE_TABLE_CHECK` ("If unsure say n"), `STRICT_SIGALTSTACK_SIZE` ("Say 'N' unless you want to really enforce"), `IMA` e `EVM`, `SYSFS_SYSCALL`, os `DEBUG_*` de desenvolvimento
- desligadas porque quebrariam usos declarados: `STATIC_USERMODEHELPER` (o modprobe dos módulos sob demanda e o systemd-coredump passariam por um binário intermediário que o Arch não tem), lockdown em integrity/confidentiality (hibernação, 18), `SECURITY_LOADPIN` (só aceitaria módulos e firmware do initramfs), `MODIFY_LDT_SYSCALL` e `X86_16BIT` (Wine, 17), `INTEGRITY_CA_MACHINE_KEYRING` (as MOKs não têm keyUsage, 18), `IO_URING` e `KCMP` (usados; o `KCMP` é exigido pelo systemd e selecionado pelo DRM)
- indisponíveis com GCC: kCFI (o GCC 16.2 não aceita `-fsanitize=kcfi`), `KSTACK_ERASE` (exige o callback de profundidade de pilha do Clang) e `RANDSTRUCT` (quebraria os módulos DKMS com objetos pré-compilados)

**Mecanismos de segurança em uso:** Secure Boot com MOK (18), TPM 2.0 (19), `firewalld`/`nftables` (6), fwupd e ClamAV. Hoje o ClamAV faz varredura sob demanda, mas a varredura em tempo real (`clamonacc`, on-access) pode vir a ser usada: ela depende do fanotify com eventos de permissão (`FANOTIFY` e `FANOTIFY_ACCESS_PERMISSIONS`), então esse suporte deve ser mantido.

### 33.6 Debug

- não manter debug só por existir
- exceção: `DEBUG_INFO_BTF` fica, porque o systemd usa o BPF LSM (ativo, ver 33.5), que exige BTF; casa com o `CONFIG_DEBUG_INFO_COMPRESSED_ZSTD=y` do `.myfrag`
- preservar apenas diagnóstico realmente desejado/provável de ser relevante para esse kernel
- **objetivo do usuário:** conseguir diagnosticar erros causados pelas escolhas de compilação e erros gerais dos programas em uso
- ficam (todos y na configuração do zen): `IKCONFIG` e `IKCONFIG_PROC` (`/proc/config.gz`, para comparar com o zen), `KALLSYMS` e `KALLSYMS_ALL` (nomes de funções nos oops), `PRINTK_TIME`, `DYNAMIC_DEBUG` (mensagens de debug dos drivers ligadas em tempo de execução), `MAGIC_SYSRQ`, pstore (`PSTORE`, `EFI_VARS_PSTORE`, `PSTORE_COMPRESS`), `FTRACE`/`FUNCTION_TRACER`, `KPROBES`/`KPROBE_EVENTS`/`UPROBE_EVENTS`, `PERF_EVENTS`, `BPF_SYSCALL`/`BPF_EVENTS` (bpftrace), `DEBUG_FS` e `COREDUMP` (`coredumpctl`)
- o DWARF (só para decodificar linha de código, drgn completo, `crash`, `perf probe` com variáveis) não é necessário para esse objetivo; decidido: `_STRIP="true"` com o BTF religado pelo `.myfrag`, e um build com `_STRIP="false"` e `_NUKR="false"` só se um bug do kernel precisar ser decodificado
- recomendado: manter o `linux-zen` instalado, com UKI própria, como kernel de referência: um problema que some no zen aponta para as escolhas do linux-tkg
- erros de programas não dependem do debug do kernel: os símbolos dos pacotes do Arch vêm pelo debuginfod
- test/mock/simulator/fault-injection/developer-only normalmente fora
- saem no `.myfrag`: `X86_DECODER_SELFTEST`, `DEBUG_RODATA_TEST`, `DEBUG_SHIRQ`, `RUNTIME_TESTING_MENU`, `FUNCTION_ERROR_INJECTION`, `BLK_ERROR_INJECTION`, `MMIOTRACE` ("If you are not helping to develop drivers, say N"), `USB_XHCI_DBGCAP`/`EARLY_PRINTK_USB_XDBC` e `EARLY_PRINTK_DBGP` (exigem cabo de debug e outro computador), `OVMF_DEBUG_LOG` (só em VM), `MEDIA_TEST_SUPPORT`, `LOCK_EVENT_COUNTS` e `X86_CPA_STATISTICS` (contadores em caminhos quentes que ninguém lê), kdump
- ficam, além dos de cima: os tracers de latência (`HWLAT_TRACER`, `OSNOISE_TRACER`, `TIMERLAT_TRACER`, úteis para diagnosticar xruns), `ACPI_DEBUG`, `PM_DEBUG`, `PROC_KCORE` (perf e drgn), `SLUB_DEBUG` (desligado em runtime), o debug do iwlwifi e o pstore EFI, agora ligado por padrão (8)

### 33.7 Hardware específico > nome genérico

**Basear decisões em:**

- lspci -knnQ
- lsusb
- IDs ACPI
- sysfs
- driver carregado
- ALSA codecs
- hwmon
- DMI
- `/sys/class/watchdog`, ACPI WDAT, SoundWire sysfs, TPM sysfs/ACPI, power_supply sysfs, `lsmod`, `/proc/cpuinfo`
- dispositivos ACPI presentes: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" != 0 ] && echo "$(cat $d/hid 2>/dev/null) ${d##*/}"; done | sort -u`
- driver de cada dispositivo ACPI presente: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" = 0 ] && continue; a=$(readlink $d/driver); b=$(readlink $d/physical_node/driver); echo "${d##*/} acpi:${a##*/} phys:${b##*/}"; done 2>/dev/null | grep -v '^device:\|^ACPI0007\|^LNX'`
- drivers de plataforma com dispositivo ligado (a lista de `/sys/bus/platform/drivers` sozinha mostra todos os drivers registrados, não só os usados): `for d in /sys/bus/platform/drivers/*; do [ -n "$(find "$d" -maxdepth 1 -type l ! -name module)" ] && echo "${d##*/}"; done`
- `modprobed-db`, para registrar os módulos carregados ao longo de semanas
- Outros comandos que possam extrair mais informações sobre o sistema

Não assumir pelo nome.

**Exemplos:**

- Alder Lake pinctrl é correto para Raptor Lake HX
- NVIDIA GPU I2C não é necessário só por haver NVIDIA
- Intel PCH thermal antigo não é necessário só por haver PCH Intel
- Intel USBIO GPIO não é necessário só por ser Intel
- ChromeOS EC não é necessário só porque laptop tem EC
- PMIC drivers não são necessários só por haver bateria
- VirtIO frontend não é necessário só porque o host roda QEMU

Em caso de dúvidas, perguntar ao usuário (fornecer comandos para obter novas informações relevantes); nunca inventar ou assumir hardware.

### 33.8 Host vs guest

O kernel é o host físico Alienware.

**Não habilitar automaticamente:**

- Hyper-V guest
- Xen frontend
- VirtIO frontend
- VMware guest
- KVM guest PTP
- virtual GPIO/I2C/etc.

Esse kernel não será usado em guests.

## 34. Precedência das informações

- Dados medidos mais recentes enviados pelo usuário
- Decisão mais recente do chat
- Decisão anterior do chat
- Inventário/documento anterior
- Conhecimento genérico, somente se o usuário pedir nova recomendação

Nunca deixar um `.myfrag` antigo prevalecer sobre uma decisão posterior explícita.

## 35. Resumo operacional

**Este é um:**

- Alienware m16 R1, BIOS 1.34.0 (1.36.0 analisada, menu escondido idêntico)
- i9-13900HX, 24C/32T, microcódigo 0x137
- 32 GB DDR5
- Intel UHD + RTX 4070 Laptop
- Realtek ALC3254 + Intel/NVIDIA HDMI
- Intel AX211 Wi‑Fi/Bluetooth
- Killer E3000 / `r8169`
- Thunderbolt 4 Maple Ridge
- Realtek RTS525A SD
- ADATA NVMe (o Micron instalado é desconsiderado)
- root Btrfs (zstd:3, sem TRIM) dentro de LUKS2
- swapfile Btrfs 16 GiB + `zswap` (zstd) + hibernação (lz4) + S3
- dGPU com RTD3 (pode desligar); iGPU como padrão
- Secure Boot + MOK + UKI + `mkinitcpio`
- TPM 2.0 CRB
- iTCO watchdog
- webcam UVC
- QEMU/KVM/libvirt + passthrough (GPU, NVMe, USB, TPM físico) + Looking Glass (`kvmfr`) + hugepages + TPM emulado (VM do Windows 10)
- WireGuard/OpenVPN/`firewalld`/`nftables`
- Arduino/ESP32/RPi
- USB serial comum
- interfaces de áudio USB/MIDI
- Canon E4210 via IPP/CUPS/SANE/Avahi
- Xbox/PlayStation/Steam Controller
- Android/iPhone
- armazenamento/rede USB externa
- CPU undervolt via `intel-undervolt`
- GPU adjustments via NVML
- quatro perfis customizados do `tuned` (32A): balanced, balanced-battery, performance e battery

**Prioridades (na ordem da seção 0):**

- preservar usos já declarados
- segurança (todas as alavancas, salvo "If unsure, say N" e usos quebrados)
- performance
- hardware real (remover o ausente)
- modularização
- minimalismo

**Arquivos de build:** `~/.config/frogminer/linux-tkg.cfg`, `~/.config/frogminer/alienware.myfrag` (copiado como arquivo regular para `/opt/linux-tkg/`) e `~/.local/share/modprobed-db/modprobed.db` (357 módulos em 2026-11-09).
