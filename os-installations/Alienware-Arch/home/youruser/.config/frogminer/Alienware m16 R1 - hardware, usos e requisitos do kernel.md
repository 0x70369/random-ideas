# Alienware m16 R1 — Hardware, usos e requisitos para configuração do kernel

Última atualização do documento: 2026-11-12

Este documento descreve o sistema como ele deve ficar (Arch Linux reinstalado com os scripts do repositório e o kernel `linux-tkg` com o fragmento `alienware.myfrag`). Os números de seção são citados nos comentários do fragmento.

## 0. Regras Máximas

- O kernel sendo configurado aqui será usado exclusivamente nesse laptop. Ele não será usado nem em outros computadores, nem em VMs guests desse laptop.
- Em caso de dúvidas, sempre olhar a documentação online oficial dos projetos/programas/aplicações usados pelo usuário.
- Preservar infraestrutura de debugging que realisticamente poderia ser usada nesse kernel. O que o Kconfig disser que não vale a pena deve ser removido.
- O Kconfig oficial é a autoridade máxima e deve ser sempre consultado. Caso o usuário queira algo que vai contra a recomendação do Kconfig, comente e deixe o usuário escolher.
- A performance e eficiência máximas são o objetivo desse kernel, mas jamais ao custo da segurança do sistema.
- Todas as alavancas de segurança do Kconfig ficam ligadas, exceto as que o Kconfig manda deixar em N na dúvida ("If unsure, say N" ou equivalente) e as que quebrariam um uso declarado (os casos estão em 33.5).
- O que cobrir hardware não existente nesse laptop deve ser removido.
- Tudo que puder ser modularizado deve ser, salvo se for algo essencial para iniciar o sistema ou for extremamente comum (como suporte para scripts com #!).
- Se o usuário modularizar algo que não deveria ser, explicar e deixá-lo escolher.
- Tudo que estiver em uso no laptop deve ser mantido: driver ligado a um dispositivo, módulo carregado ou interface usada por algum programa. A única exceção declarada é o SSD Micron (ver 8). Módulos que carregam só porque outra opção da configuração os exige, sem dispositivo deste laptop, não contam como em uso.
- Se o Kconfig mostrar que uma opção a desligar é selecionada por outra que fica ligada ("Selected by"), respeitar a dependência e avisar o usuário.

## 1. Identificação geral

- Modelo: Alienware m16 R1 (Dell / Alienware), SKU / Platform ID 0BFB
- Placa-mãe: Dell 00DK46, rev. A00
- Service Tag: 80S9K34
- BIOS 1.36.0 (2026-10-22), instalada em 2026-11-11 no lugar da 1.34.0. O menu escondido é idêntico byte a byte ao da 1.34.0; mudam o Intel ME (16.1.40.2765 → 16.1.42.2872), o pacote do EC (1.15.0 → 1.16.0), os drivers de rede do BIOS Connect e módulos de segurança (criptografia, TPM, variáveis e WMI da Dell). O microcódigo embutido continua 0x133
- Sistema: Arch Linux com KDE Plasma
- Boot: `systemd-boot` com UKIs, via shim (18)
- Kernels: `linux-tkg` (o customizado) e, como reserva, `linux` e `linux-zen`, todos com os DKMS `nvidia` (615.78.08) e `looking-glass` (B7)

## 1A. Firmware: configurações que afetam o kernel

Alteradas pelo usuário no menu escondido (Smokeless UMAF) ou conferidas nos padrões. Ver a Seção 7 da página da wiki para caminhos e offsets.

Um reset do firmware (carregar os padrões) volta todas as alteradas abaixo ao valor da Dell, e uma atualização da BIOS volta parte delas: depois de qualquer um dos dois, conferir a lista inteira (a seção 7 da wiki serve de checklist). O reset de 2026-11-12 desfez todas, e elas foram refeitas.

**Alteradas:**

- ACPI S3 Support: Enabled (a Dell entrega Disabled) → o sono S3 (`deep`) existe e é usado
- UnderVolt Protection: Disabled e OverClocking Feature: Enabled → permitem o undervolt por MSR do `intel-undervolt`
- Legacy Game Compatibility Mode: Enabled → Scroll Lock alterna o standby dos E-cores; também ativa teclado/mouse PS/2 nas Platform Settings
- WDT Enable: Enabled (watchdog do OC, usado pelo XTU no Windows)
- BIST: Enabled (autoteste da CPU a cada reset)
- REFRESH_2X_MODE: Enabled for WARM or HOT (refresh da RAM dobra quando ela esquenta)
- Native ASPM (ACPI Settings, `Setup` offset `0x12`): Enabled (a Dell entrega Disabled) → o firmware entrega o controle do ASPM ao kernel pelo `_OSC`, e as políticas dos perfis do tuned (32A.5) passam a valer
- D3 Setting for Storage (ACPI Settings, `Setup` offset `0xAB2`): D3Cold (a Dell entrega D3Hot) → no s2idle, o NVMe pode perder a energia por completo; sem efeito no S3
- EC CS Debug Light (ACPI Settings, `Setup` offset `0x32`; padrão Disabled): Enabled → a luz do Caps Lock acende quando o EC entra no modo de economia de energia. Por isso a luz do Caps Lock não serve sozinha para saber se o sistema travou ou se a tecla está ativa
- Advanced Error Reporting do PCI Express Root Port 25 (Thunderbolt, `PchSetup` offset `0x283`): Enabled (a Dell entrega Disabled) → erros de PCIe no link do Thunderbolt passam a ser reportados ao kernel
- Tcc Offset Lock Enable: Enabled (a 1.36.0 veio com Disabled)
- DTBT RTD3 CLKREQ Delay value (ACPI D3Cold settings, `Setup` offset `0x985`): 200 ms (a Dell entrega 0) → espera depois de mudar o CLKREQ ao religar o controlador do Thunderbolt, contra a falha de 7
- RFI Mitigation (Connectivity Configuration): Enabled (a Dell entrega Disabled) → o `iwlwifi` pode pedir ao controlador de memória um pequeno desvio na frequência da DDR quando ela interfere no canal Wi-Fi em uso
- Disable Fast PKG C State Ramp for IA Domain e for GT Domain (Power & Performance > CPU VR Settings > Acoustic Noise Settings, `CpuSetup` offsets `0x1FD` e `0x1FE`): TRUE (padrão FALSE) → os reguladores de tensão sobem devagar ao sair dos estados de repouso profundos do pacote, contra o coil whine
- Config TDP (Power & Performance): Nominal (o nível do boot) com PL1 55 W e PL2 86 W, os mesmos do `alienware-balanced` (a Dell entrega 165/165 W); Level 1 com 157/157 W; Level 2 indefinido. No Linux, os perfis do tuned reescrevem os limites (32A.4)
- Thermal Device (B0:D4:F0) (System Agent (SA) Configuration, `SaSetup` offset `0x7C`): Enabled (padrão Disabled) → expõe o `00:04.0` (`proc_thermal_pci`) e com ele o `intel-rapl-mmio`, que o tuned escreve; sem ele, o limite MMIO do firmware limitaria a CPU
- Cpu CrashLog (Device 10) (System Agent (SA) Configuration, `SaSetup` offset `0xF6`): Enabled (padrão Disabled) → registro do estado da CPU em erros graves de hardware, que sobrevive ao reboot (32A.16)
- DeepSx Power Policies (PCH-IO Configuration, `PchSetup` offset `0x4`): Enabled in S4-S5 (padrão Disabled) → hibernado ou desligado, o chipset corta a energia de standby, e o laptop só acorda pelo botão de energia
- EFI Network (PCH-IO Configuration, `Setup` offset `0x49`): Disabled (a Dell entrega Onboard NIC & WiFi) → sem pilha de rede no firmware; sem boot pela rede nem BIOS Connect, e o fwupd continua atualizando o firmware
- LPM S0i2.1 (`PchSetup` offset `0x14`): Enabled (a Dell entrega Disabled); só afeta o s2idle, sem efeito com o S3
- Power Limit 2: 157 W (a opção fica escondida no setup da 1.36.0; no Linux o tuned define o PL2); multiplicador máximo 54x nos P-cores e 39x nos E-cores (clusters); BCLK 100,00 MHz; iGPU até 1650 MHz; IccMax 215 A (IA) e 30 A (GT)

**Mantidas nos padrões porque o sistema depende delas:**

- VMX e VT-d: Enabled (KVM e passthrough)
- Above 4GB MMIO e Resizable BAR (Auto): necessários ao `NVreg_EnableResizableBar=1`
- ACS em cada root port: Enabled → a dGPU fica no próprio grupo IOMMU sem o patch de ACS override
- ACPI D3Cold Support: Enabled → necessário para a dGPU desligar por completo (RTD3)
- Package Power Limit MSR Lock: Disabled → o `tuned` consegue escrever os limites RAPL em runtime
- Tcc Activation Offset: 0, com o Tcc Offset Lock (acima) → o throttling começa no Tjmax de 100 °C, e o `tjoffset` do `intel-undervolt` é ignorado
- PROCHOT Lock (`CpuSetup` offset `0x7D`) e Bi-directional PROCHOT#: Enabled → a CPU reduz a velocidade quando o EC sinaliza superaquecimento de outra parte (GPU, reguladores), e o sistema não consegue desligar essa resposta pelo MSR
- Platform Debug Consent (`SiSetup` offset `0x1`): Disabled → sem Intel DCI nem Trace Hub (debug da CPU por USB, abaixo do sistema e do Secure Boot)
- Intel Dynamic Tuning Technology, INT3400 Device e Processor Thermal Device (SA Thermal Device): Enabled → `int3400 thermal`, `proc_thermal_pci` e os sensores `int3403` (22); Charger, Power e Battery Participant desligados
- Enable TCO Timer (`PchSetup` offset `0x11`): Disabled → sem tabela WDAT e sem o timer ACPI do chipset; o `iTCO_wdt` funciona assim mesmo (20)
- System Time and Alarm Source: ACPI Time and Alarm Device, com o RTC antigo também presente → `acpi-tad` e `rtc_cmos` (`/dev/rtc0`, usado para acordar na hora marcada)
- HID Event Filter Driver: Enabled → `INTC1070` (`intel-hid`)
- Pseudo G3: Enabled (padrão da Intel Disabled) e Charging Method: Normal Charging → desligado e na bateria, o EC corta quase toda a energia; carga sem o modo rápido, que desgasta mais a bateria (30)

**No menu F2 (Dell):**

- Hybrid Graphics: ativado (sem ele a dGPU controla todas as telas e nunca desliga)
- Discrete Graphics Controller Direct Output Mode: ativado (para a menor latência entre a dGPU e monitores externos); com um monitor externo ligado, a dGPU fica acordada

## 1B. Linha de comando do kernel

Montada a partir de `/etc/cmdline.d/` e embutida na UKI; vale para os três kernels. Um arquivo por linha:

```text
root.conf          root=/dev/mapper/root rootfstype=btrfs rootflags=subvol=/Arch/@
sd-encrypt.conf    rd.luks.name=<UUID do LUKS>=root rd.luks.options=password-echo=no,tries=2,timeout=60s
hibernation.conf   hibernate.compressor=lz4
zswap.conf         zswap.enabled=1 zswap.shrinker_enabled=1 zswap.compressor=zstd zswap.max_pool_percent=23 zswap.accept_threshold_percent=90
iommu.conf         intel_iommu=on
audio.conf         threadirqs
pstore.conf        efi_pstore.pstore_disable=0
miscellaneous.conf loglevel=7
```

- hibernação sem `resume=`: ao hibernar, o systemd grava o dispositivo e o offset do swapfile (calculado também para btrfs) na variável EFI `HibernateLocation`, e o `systemd-hibernate-resume-generator` do initramfs a lê e retoma depois que o `sd-encrypt` abre a raiz. Recriar o swapfile não exige mudar nada. Exige o efivarfs no initramfs (`EFIVAR_FS=y`, 33.3)
- `hibernate.compressor=lz4`: lz4 descomprime mais rápido que o lzo padrão. No `linux-tkg` o lz4 já é o padrão (`HIBERNATION_COMP_LZ4`), e o parâmetro só tem efeito no `linux` e no `linux-zen`
- zswap: compressor zstd (maior taxa de compressão; o uso de memória é alto com a VM e o build em tmpfs) e pool de 23%. O 7.2 não tem mais escolha de zpool (o zsmalloc é o único alocador). No `linux-tkg` o zswap já fica ligado e com zstd por padrão
- `intel_iommu=on`: liga o IOMMU (duas unidades, `dmar0` e `dmar1`, endereços de 39 bits). Redundante no `linux-tkg` (`INTEL_IOMMU_DEFAULT_ON=y`)
- `threadirqs`: handlers de interrupção em threads, para áudio de baixa latência
- `efi_pstore.pstore_disable=0`: liga o backend EFI do pstore no `linux` e no `linux-zen`, cuja configuração o desliga por padrão; redundante no `linux-tkg`
- sysctl relacionado: `kernel.sysrq = 1` (`/etc/sysctl.d/sysrq.conf`, ver 33.6)

## 2. CPU e plataforma

- CPU: Intel Core i9-13900HX (Raptor Lake-HX), 24 cores / 32 threads: 8 P-cores com SMT e 16 E-cores
- `NR_CPUS`=32
- Endereçamento: 39 bits físicos, 48 bits virtuais (sem `la57`: paginação de 5 níveis não tem uso aqui)
- Microcódigo 0x137, carregado cedo pelo pacote `intel-ucode` (hook `microcode` do `mkinitcpio`), mais novo que o 0x133 embutido na BIOS
- Sem Total Memory Encryption (sem a flag `tme`)
- Sem SGX, TDX e RDT/resctrl (sem as flags `sgx`, `rdt_a`, `cat_l2`, `cat_l3`, `cqm_llc` e `mba`): `X86_SGX`, `INTEL_TDX_HOST` e `X86_CPU_RESCTRL` saem
- `intel_pstate` em modo `active`, com `hwp` e `hwp_epp`: o Turbo Boost Max 3.0 (`INTEL_TURBO_MAX_3`), que só serve sem HWP, sai

**Flags relevantes de `/proc/cpuinfo`:**

`vmx ept ept_ad vnmi x2apic tsc_deadline_timer hwp hwp_notify hwp_act_window hwp_epp hwp_pkg_req hfi ibt user_shstk split_lock_detect intel_pt arch_lbr pku ospke umip waitpkg avx2 avx_vnni sha_ni gfni vaes vpclmulqdq movdiri movdir64b serialize fsrm clwb rdpid md_clear flush_l1d arch_capabilities ibrs_enhanced`

- `ibt` e `user_shstk`: CET disponível (IBT no kernel, shadow stack para userspace)
- `hwp*` e `hfi`: Intel P-state com HWP/EPP e Intel HFI
- Não há AVX-512.

**Vulnerabilidades que o kernel reporta (`bugs`):**

`spectre_v1 spectre_v2 spec_store_bypass swapgs eibrs_pbrsb rfds bhi spectre_v2_user vmscape`

As mitigações dessas permanecem (segurança acima de performance). As que não aparecem na lista não afetam esta CPU.

Diversos drivers do kernel cobrem Raptor Lake HX com nomes que ainda contêm Alder Lake (por exemplo, `PINCTRL_ALDERLAKE`, `SND_SOC_SOF_ALDERLAKE` e o firmware DMC `adls`).

### Dispositivos ACPI

Só os presentes (`status` diferente de 0). A tabela ACPI também descreve vários dispositivos ausentes, que não contam.

- Plataforma: `PNP0C09` (EC), `PNP0C14` (12 blocos WMI), `PNP0C0A` (bateria), `ACPI0003` (AC), `PNP0C0D` (tampa), `PNP0C0E` (botão de sono), `ACPI000C` (processor aggregator), `ACPI000E` (time and alarm, `acpi-tad`), `PNP0B00` (RTC), `PNP0103` (HPET), `PNP0A08` (raiz PCIe), `PNP0C02` (recursos da placa-mãe)
- Processadores: 64 objetos `ACPI0007` para 32 threads (o firmware declara objetos a mais)
- Intel: `INTC1085` (pinctrl Raptor Lake, `alderlake-pinctrl`), `INTC1070` (`intel-hid`), `INTC6001` (TPM CRB, `tpm_crb_acpi`), `INT33A1` (PEP, `intel_pmc_core`)
- DPTF: `INTC10A0` (`int3400 thermal`) e seis participantes `INTC1046` (`int3403 thermal`)
- Dell: `DLLK0BFB` (teclado PS/2, `i8042 kbd`) e `DLL0BFB` (porta auxiliar PS/2, `i8042 aux`)
- Touchpad: `VEN_06CB` (Synaptics), `i2c_hid_acpi`
- USB-C: `USBC000` (UCSI, `ucsi_acpi`)
- Sem driver ligado nem no kernel do Arch, que tem quase todos os drivers, então não pedem nada: `INT340E`, `INTC109C`, `NVDA0820` (o driver da NVIDIA pode usá-lo por métodos ACPI, sem se ligar a ele) e `PRP00001` (2 instâncias). `PNP0000`, `PNP0100`, `PNP0103`, `PNP0A08` e `PNP0C02` são tratados pelo núcleo do kernel.
- Ausentes, portanto sem uso: os sensores de câmera MIPI (`OVTI01AS`, `INT33BE`, `SONY362A`, `SONY488A`) e os dispositivos de câmera `INT3471`/`INT3472`/`INT3474` (a webcam real é USB, então IPU e drivers de sensor MIPI ficam fora); os monitores de energia Microchip `MCHP1930`/`MCHP1940` (PAC193x/PAC194x); `DELL0029`, `DELL0033`, `DELLABC6`, `TXNW3643`, `INT3420`, `INT33E1`, `INT3519`, `INT3533`, `INTC1001`, `INTC1092`, `INTC10A3`; e o `PNP0C0C` (o botão de energia usa o evento fixo do ACPI)

### Drivers de plataforma em uso

`ac`, `acpi-battery`, `acpi-button`, `acpi-ec`, `acpi-tad`, `acpi-wmi`, `alarmtimer`, `alderlake-pinctrl`, `dell-smbios`, `dmic-codec`, `hid_sensor_custom`, `i2c_designware`, `i8042`, `idma64`, `int3400 thermal`, `int3403 thermal`, `intel-hid`, `intel_pmc_core`, `intel_rapl_msr`, `iTCO_wdt`, `pcspkr`, `processor_aggregator`, `rtc_cmos`, `rtsx_pci_sdmmc`, `skl_hda_dsp_generic`, `tpm_crb_acpi`, `ucsi_acpi`

- `pcspkr` (bipe do PC speaker) está ligado, então fica
- o laptop não tem nenhuma UART (sem `PNP0501`, sem `ttySN ... is a 16550A` no dmesg): `SERIAL_8250` sai; os adaptadores USB serial (13) não dependem dele
- `dcdbas` não é um driver de plataforma, mas é usado pelo `dell_smbios` (backend SMM)
- `efi-framebuffer`/`simple-framebuffer` somem quando o `i915` assume a tela, mas são necessários no início do boot (33.3)
- `coretemp` não é driver de plataforma, mas está em uso (23)

### Módulos em uso

Levantados com `lsmod` no kernel do Arch e reunidos no `modprobed.db` (31). Todos ficam, exceto os da lista "Desligar" abaixo. Agrupados:

- CPU, energia e telemetria: `coretemp`, `intel_cstate`, `intel_uncore`, `intel_uncore_frequency`, `rapl`, `intel_rapl_msr`, `intel_rapl_common`, `x86_pkg_temp_thermal`, `intel_powerclamp`, `intel_tcc_cooling`, `acpi_pad`, `intel_pmc_core`, `intel_pmc_ssram_telemetry`, `intel_pmc_pwrm_telemetry`, `intel_vsec`, `pmt_telemetry`, `pmt_discovery`, `pmt_class`
- DPTF: `int3400_thermal`, `int3403_thermal`, `int340x_thermal_zone`, `acpi_thermal_rel`, `processor_thermal_device_pci` e seus submódulos (`rapl`, `rfim`, `mbox`, `power_floor`, `wt_hint`, `wt_req`, `soc_slider`, `platform_temperature_control`)
- Dell/Alienware/WMI: `wmi`, `wmi_bmof`, `alienware_wmi`, `dell_wmi`, `dell_wmi_descriptor`, `dell_wmi_ddv`, `dell_wmi_sysman`, `dell_smbios`, `dcdbas`, `dell_smm_hwmon`, `nvidia_wmi_ec_backlight`, `intel_hid`, `sparse_keymap`, `video`
- Gráficos: `i915`, `nvidia`, `nvidia_modeset`, `nvidia_drm`, `nvidia_uvm`, `drm_display_helper`, `ttm`, `cec`, `i2c_algo_bit`
- Áudio: `snd_sof_pci_intel_tgl` e a pilha SOF, `snd_soc_skl_hda_dsp`, `snd_hda_intel`, `snd_hda_codec_alc269`, `snd_hda_codec_intelhdmi`, `snd_hda_codec_nvhdmi`, `snd_seq`, `snd_seq_dummy`, `snd_hrtimer`, `snd_ctl_led`
- Rede: `iwlmvm`, `iwlwifi`, `mac80211`, `cfg80211`, `r8169`, `realtek`, `ax88179_178a`, `usbnet`, `mii`, `ptp`
- Bluetooth: `btusb`, `btintel`, `bluetooth`, `bnep`, `rfcomm`
- Netfilter (firewalld): `nf_tables`, `nft_ct`, `nft_fib_inet`/`ipv4`/`ipv6`, `nft_reject_inet`/`ipv4`, `nft_masq`, `nft_chain_nat`, `nf_conntrack` com os helpers `ftp`, `tftp`, `irc`, `sip`, `h323`, `pptp`, `sane`, `netbios_ns` e os `nf_nat` correspondentes
- Armazenamento: `nvme`, `nvme_core`, `dm_crypt`, `dm_integrity`, `dm_mod`, `trusted`, `encrypted_keys`, `uas`, `usb_storage`, `sg`, `vfat`, `fat`, `rtsx_pci`, `rtsx_pci_sdmmc`, `mmc_core`, `mmc_block`
- Flash SPI: `spi_intel_pci`, `spi_intel`, `spi_nor`, `mtd` (27)
- Criptografia: `aesni_intel`, `gf128mul`, `ccm`, `af_alg`, `algif_hash`, `algif_skcipher`, `crypto_user`
- Virtualização: `kvm_intel`, `kvm`, `irqbypass`, `vfio_pci`, `vfio_pci_core`, `vfio_iommu_type1`, `vfio`, `iommufd`
- Entrada e sensores: `i2c_hid_acpi`, `i2c_hid`, `hid_multitouch`, `intel_ish_ipc`, `intel_ishtp`, `intel_ishtp_hid`, `hid_sensor_hub`, `hid_sensor_custom`, `psmouse`, `serio_raw`, `mousedev`, `joydev`, `mac_hid`, `pcspkr`
- I2C/SMBus: `i2c_i801`, `i2c_smbus`, `i2c_mux`, `i2c_dev`, `intel_lpss_pci`, `intel_lpss`, `idma64`, `spd5118`
- Webcam: `uvcvideo`, `videodev`, `videobuf2_*`, `mc`
- USB-C/Thunderbolt: `thunderbolt`, `typec`, `typec_ucsi`, `ucsi_acpi`, `roles`
- Outros: `mei_me`, `mei_hdcp`, `mei_pxp`, `iTCO_wdt`, `intel_pmc_bxt`, `pinctrl_alderlake`, `acpi_tad`

Usos declarados que não aparecem no `lsmod` a todo momento (VPN/TUN, WireGuard, bridge e `vhost_net` do libvirt, `uinput`, controles, USB serial, MIDI USB e outros) continuam valendo.

**Desligar** (carregam no kernel do Arch só porque a configuração os puxa, sem hardware deste laptop):

- `BT_HCIBTUSB_RTL`, `BT_HCIBTUSB_BCM` e `BT_HCIBTUSB_MTK` (e com eles `btrtl`, `btbcm` e `btmtk`): o Bluetooth interno é Intel (`btintel`); só fariam falta com um adaptador USB externo dessas marcas
- `DRM_XE` (e com ele `drm_gpusvm_helper`, `drm_gpuvm`, `gpu_sched`): a iGPU Raptor Lake é atendida pelo `i915`; nela o `xe` só funciona forçado (`force_probe`). O HMM do `nvidia-uvm` sai junto (4)
- `DRM_NOUVEAU`: a dGPU usa o driver `nvidia` (o `nvidia-utils` põe o `nouveau` na blacklist)
- `SND_SOC_INTEL_AVS`: driver alternativo de DSP Intel; o áudio usa o SOF
- `SND_SOC_SOF_INTEL_SOUNDWIRE` e `SOUNDWIRE` (e com eles `soundwire_intel`, `soundwire_cadence`, `soundwire_bus`): não há dispositivo SoundWire; nada que fica ligado seleciona o `SOUNDWIRE`, e SOF, HDA e SDCA continuam funcionando
- `NVME_HOST_AUTH` (`nvme_auth`, `nvme_keyring`: autenticação do NVMe over Fabrics), `TRUSTED_KEYS_TEE`/`TEE` (as chaves confiáveis usam só o TPM), `MACVLAN`/`MACVTAP` (`tap`; as VMs usam bridge e `tun`, 16)

### PCI completo do laptop

A listagem abaixo é a referência para IDs e drivers; as seções seguintes só citam o endereço de cada dispositivo. A linha "Kernel modules" lista os candidatos do kernel do Arch, inclusive os que saem (`xe`, `nouveau`, `snd_soc_avs`, `ie31200_edac`, `shpchp`).

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

- 32 GB DDR5: 2 × 16 GB SK hynix `HMCG78AGBSA095N` (código JEDEC `80AD`), DDR5-5600, a 5600 MT/s
- Pentes sem ECC: o `ie31200_edac` (candidato do host bridge) não tem o que reportar e sai
- Refresh 2x quando a RAM esquenta, configurado no firmware (REFRESH_2X_MODE)
- Compilação de kernel em tmpfs (`/tmp/kernel-build`, 42 GiB), portanto RAM/swap importam ao fluxo de build

## 4. GPUs

### iGPU Intel

- `00:02.0` [8086:a788], driver `i915`
- GPU padrão do sistema

### Tela interna

- `eDP-1`, 2560×1600, com modos de 60,01 Hz e 240,02 Hz (o preferido); escala 1,25 no Plasma
- sem VRR, HDR nem gama de cor ampla (KScreen: "incapable")
- sem PSR (Panel Self Refresh): o `i915_edp_psr_status` e o `eDP-1/i915_psr_sink_status` do debugfs respondem "Dispositivo inexistente", o que o `i915` faz quando o painel não declara suporte a PSR. Sem PSR, a iGPU lê o framebuffer e manda imagem ao painel em todo quadro, mesmo com a tela parada, o que limita os estados de repouso do pacote (32A.15)
- brilho controlado pelo `nvidia_wmi_ec_backlight`

### dGPU NVIDIA

- `01:00.0` [10de:2860], GeForce RTX 4070 Laptop (AD106M), driver `nvidia`
- 8 GB de VRAM (8188 MiB utilizáveis); limite de potência padrão de 90 W, máximo de 140 W, mínimo de 5 W

**Uso:**

- Driver: `nvidia-open-dkms` do Arch, compilado via DKMS para cada kernel e assinado com a MOK
- Passthrough da dGPU para VMs possível; por padrão ela fica no host (o `vfio.conf` está todo comentado)
- Ajustes/undervolt da GPU via NVML API (32)
- OpenCL (`opencl-nvidia`), que usa o `nvidia_uvm`; nenhum pacote CUDA

**Gerenciamento de energia (a dGPU desliga por completo, RTD3):**

```text
options nvidia NVreg_RegistryDwords="OverrideMaxPerf=0x1" NVreg_UseKernelSuspendNotifiers=1 NVreg_TemporaryFilePath="/var/tmp" NVreg_DynamicPowerManagement=0x02 NVreg_EnableResizableBar=1 NVreg_EnableGpuFirmwareLogs=1
```

- `NVreg_DynamicPowerManagement=0x02`: RTD3 fine-grained; a dGPU chega a D3cold
- regras udev põem `power/control=auto` nas funções VGA/3D da NVIDIA ao serem adicionadas/ligadas ao driver, e `on` ao serem desligadas
- `nvidia-persistenced` roda sem `--uvm-persistence-mode` (o modo UVM desativaria o RTD3)
- `nvidia-powerd` (Dynamic Boost) e os serviços `nvidia-suspend`/`-resume`/`-hibernate` ativos
- a iGPU é a GPU padrão para Vulkan e VA-API (`LIBVA_DRIVER_NAME` não é definido globalmente); a NVIDIA é usada sob demanda com `prime-run`
- vídeo: VA-API no Firefox e nos navegadores Chromium; QSV/VPL (`intel-media-driver`/oneVPL) também
- com o Direct Output Mode ativado, um monitor externo mantém a dGPU acordada
- o perfil `alienware-battery` força o desligamento se ela continuar acordada (32A.14)
- verificação: `/sys/bus/pci/devices/0000:01:00.0/power/runtime_status` = `suspended` (ler pela NVML, como o btop faz, a acorda)

**Requisitos ao kernel:** PCI runtime PM, D3cold via ACPI, suspend/hibernate, e o que o `nvidia-open-dkms` exigir para compilar (DRM/KMS). O `nvidia` exige também `NUMA`, `MEMORY_HOTPLUG`, `ZONE_DEVICE` e `DEVICE_PRIVATE`, que ficam.

**HMM do `nvidia-uvm`:** ele só compila com HMM (CUDA acessando memória alocada com `malloc` comum) se `HMM_MIRROR` e `DEVICE_PRIVATE` estiverem ligados. `HMM_MIRROR` não tem pergunta própria no Kconfig, e nesta configuração só o `DRM_XE` (pelo `DRM_GPUSVM`) o seleciona. Com o `xe` fora, o HMM sai; OpenCL, NVENC/NVDEC, Vulkan, NVML e PRIME não o usam. Se um dia precisar dele, `CONFIG_DRM_XE=m` o devolve (o `xe` compila, mas não se liga à iGPU sem `force_probe`).

## 5. Áudio

### Controladores

- Intel `00:1f.3` [8086:7a50], driver `sof-audio-pci-intel-tgl`, habilitado pelo `SND_SOC_SOF_ALDERLAKE` (o `pci-tgl.c` lista o RPL-S nessa opção; `SND_SOC_SOF_TIGERLAKE` sai)
- HDMI da NVIDIA `01:00.1` [10de:22bd], driver `snd_hda_intel`

### ALSA

```text
0 [NVidia]: HDA-Intel - HDA NVidia
1 [sofhdadsp]: sof-hda-dsp - sof-hda-dsp
              Alienware-Alienwarem16R1-00DK46
```

### Codecs

- Analógico/interno principal: Realtek ALC3254, atendido pelo `snd_hda_codec_alc269` (família ALC269); os outros codecs Realtek (ALC260, 262, 268, 662, 680, 861, 861-VD, 880, 882) e os HDMI ATI, NVIDIA MCP e Tegra saem (exige `EXPERT`, 31)
- HDMI/DP Intel: Intel Raptor Lake HDMI
- HDMI/DP NVIDIA: NVIDIA GPU a6 HDMI/DP
- Sem dispositivo SoundWire, sem módulos nem dispositivos I2C Cirrus/CS35/CS40/CS42/CS47/Madera/Arizona/Wolfson: esses MFDs saem. Smart amplifiers de outros menus de áudio devem ser avaliados separadamente; não extrapolar a remoção para todo driver Cirrus/TI sem verificação
- O laptop tem entrada P3, usada regularmente; dispositivos de som via USB também são usados

### Usos de áudio

- PipeWire para tudo, incluindo ALSA, PulseAudio e JACK
- baixa latência e máxima qualidade sonora
- `threadirqs` (1B)
- limites do usuário: `LimitRTPRIO=98` e `LimitMEMLOCK=infinity`, além do pacote `realtime-privileges` (grupo `realtime`)
- gravação de instrumentos musicais, interfaces de áudio USB, Ardour

**Preservar:**

- USB Audio Class e USB MIDI
- ALSA sequencer (`SND_SEQUENCER`), usado pelo PipeWire para o MIDI
- HDA Intel/Realtek, HDMI/DP Intel e NVIDIA
- áudio Bluetooth

## 6. Rede

### Wi‑Fi

- `00:14.3` [8086:7a70], subsystem Rivet Networks [1a56:1672], driver `iwlwifi`
- Killer Wi-Fi 6E AX1675i 160 MHz (211NGW), a versão Killer do AX211 (CNVi): RF GF, firmware `so-a0-gf-a0-89.ucode` com o `iwlmvm`
- Preservar `iwlwifi` e o que for necessário para ele; remover famílias Wi‑Fi inexistentes e drivers Intel Wi‑Fi antigos
- Menus `WLAN_VENDOR_*`: só o Intel fica

### Bluetooth

- AX211, USB (`8087:0033`): o frontend Intel PCIe (`BT_INTEL_PCIE`, Lunar Lake em diante) sai
- Preservar HCI USB

**Usos:** controles Xbox, PlayStation e Steam Controller, áudio Bluetooth e outros periféricos Bluetooth.

### Ethernet

- `6e:00.0` Killer E3000 2.5GbE [10ec:3000], driver `r8169`, interface `enp110s0`; PHY Realtek, com o hwmon do PHY mantido
- ASPM desligado no link (root port #3, `00:1c.0`), inclusive L1.1/L1.2: o `r8169` desliga o ASPM deste chip (RTL8125) por causa de travamentos conhecidos. Ligar o L1.2 não reduziu o consumo (32A.15), então fica assim
- Menus `NET_VENDOR_*`: só o Realtek fica

### Software/rede

- WireGuard e OpenVPN
- NetworkManager (com wpa_supplicant), inclusive hotspot Wi-Fi (`ipv4.method shared`): modo AP no `iwlwifi`, NAT/masquerade e o `dnsmasq` do NetworkManager
- Extensões de privacidade do IPv6
- DNS over TLS via systemd-resolved
- mDNS: o systemd-resolved só resolve (`MulticastDNS=resolve`), e o Avahi responde
- `firewalld` via `nftables`
- LocalSend
- redes QEMU/libvirt, TUN/TAP
- USB networking: Raspberry Pi, Arduino e ESP32 via USB/rede, iPhone USB Ethernet (`ipheth`), Android

### QoS

- `fq_codel` como qdisc padrão (`NET_SCH_FQ_CODEL=m`, `DEFAULT_FQ_CODEL`; o sysctl `net.core.default_qdisc` do systemd carrega o módulo no boot). O linux-tkg trocaria o padrão para o CAKE; o fragmento o devolve ao fq_codel
- FQ e CAKE como módulos
- ingress / flower / matchall / gact / mirred mantidos
- os demais qdiscs/classifiers/actions saem
- TCP: CUBIC embutido e padrão (o padrão precisa ser embutido); Westwood+, Vegas, YeAH e BBR como módulos

## 7. USB-A, USB-C e Thunderbolt

### Controladores

- xHCI principal `00:14.0` [8086:7a60], USB 3.2 Gen 2x2 (20 Gb/s), driver `xhci_hcd`
- Thunderbolt 4 Maple Ridge: bridges `02:00.0` e `03:00.0`–`03:03.0` [8086:1136], NHI `04:00.0` [8086:1137] (driver `thunderbolt`), xHCI `38:00.0` [8086:1138] (`xhci_pci`)

### Dispositivos USB

**Internos:**

- `0d62:d2b0` Darfon, teclado interno, `usbhid` (também envia as teclas de macro, 11)
- `187c:0551` Alienware AW-ELC, controlador da iluminação RGB, `usbhid`. Nenhum programa o controla no Linux: o brilho muda pelo Fn+F7 (fraco, forte e desligado), e as cores foram gravadas nele pelo AlienFX-Tools no Windows. Ele não aparece em `/sys/class/leds/`, então o tuned não consegue controlá-lo
- `0bda:555d` Realtek, webcam, `uvcvideo` (a interface 4, "Application Specific", fica sem driver)
- `8087:0033` Intel AX211 Bluetooth, `btusb`

Autosuspend: Bluetooth e webcam ficam com `power/control=auto`; o teclado interno e o AW-ELC ficam com `on` (o `autosuspend=1` do tuned não os muda). Forçar o autosuspend deles não reduziu o consumo (32A.15).

**Externos usados:**

- `152d:0583` JMicron JMS583, ponte USB para NVMe (SSD externo), `uas`
- `0b95:1790` ASIX AX88179, Ethernet USB, `ax88179_178a`
- `30fa:1440` mouse gamer, `usbhid`

**Problema conhecido:** com a política ASPM `powersupersave` (os links do Thunderbolt são os únicos com L0s ligado nela), acordar o NHI (`04:00.0`) e o xHCI (`38:00.0`) do Thunderbolt em runtime, por exemplo com um `lspci -vvv`, pode deixá-los mortos (`not ready 1023ms after resume; giving up`, `HC died`, aviso em `drivers/thunderbolt/nhi.c:142`, `failed to send driver ready to ICM`) até reiniciar. Causa ainda não confirmada. No firmware (PCI Express Root Port 25), o link do Thunderbolt vem com ASPM só L1, sem L1 Substates, com Hot Plug ligado e Advanced Error Reporting desligado: o L0s que o kernel liga no `powersupersave` é algo que o firmware não configura nesse link, e erros de PCIe nele não são reportados (o AER desse port foi ligado no firmware, 1A). Em ACPI D3Cold settings, o firmware deixa o controlador do Thunderbolt desligar em runtime (DTBT RTD3 Enable e DTBT RTD3 CLKREQ Enable ligados, TBT Power-off delay = 5000 ms): é esse caminho de desligar e religar que falha. O DTBT RTD3 CLKREQ Delay value foi de 0 para 200 ms em 2026-11-11 (1A), junto com o AER; se a falha continuar, o próximo teste é desligar o L0s dos links e depois o DTBT RTD3 CLKREQ, medindo o consumo antes e depois.

**Preservar:**

- Thunderbolt 4, USB-C, USB Power Delivery / UCSI (`thunderbolt`, `ucsi_acpi`, `typec_ucsi`, `typec`)
- DisplayPort Alt Mode
- monitores via USB-C/HDMI/miniDP
- docks/hubs e dispositivos Thunderbolt

## 8. Armazenamento interno

### NVMe ADATA

- `6d:00.0` [1cc1:5766], ADATA XPG LEGEND 710 de 2 TB, driver `nvme`
- Um SSD Micron 2450 de 512 GB também está instalado (`6f:00.0`), mas é desconsiderado: não será usado

### Root / partições

- ESP FAT32 em `/boot`, de 253 MB, compartilhada com o Windows; guarda os `vmlinuz-*` e as UKIs dos três kernels (cerca de 100 MB livres)
- root em LUKS2 + Btrfs (`/dev/mapper/root`), sem discard: TRIM totalmente desativado, nem `discard` nem `fstrim.timer`
- LUKS2: cifra `aes-xts-plain64` com chave de 512 bits (AES-256 em XTS), setores de 512 bytes, PBKDF `argon2id`. O kernel precisa de dm-crypt, dm-integrity (o hook `sd-encrypt` o exige), XTS e AES com AES-NI no initramfs; o argon2id roda no `cryptsetup`
- todos os subvolumes montados com `relatime,nodiscard,compress=zstd:3`
- Btrfs com checksum `crc32c` e as features `mixed_backref`, `big_metadata`, `extended_iref`, `skinny_metadata`, `no_holes` e `compress_zstd`; nenhum dado em lzo

**Subvolumes:** os do Arch ficam dentro do diretório comum `Arch/` (não é subvolume); os compartilháveis ficam no nível superior.

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

**tmpfs:** `/tmp`, `/temp` e `/tmp/kernel-build` (42 GiB) com `huge=within_size` (THP em shmem) e `usrquota` (quotas de tmpfs).

**Sistemas de arquivos das mídias externas:**

- exFAT
- NTFS: o udisks2 tenta primeiro o `ntfs3` (`ntfs_drivers=ntfs3,ntfs`), que fica; no fallback e no `mount -t ntfs`, o helper `/usr/bin/mount.ntfs` aponta para o `ntfs-3g`. O driver NTFS novo do kernel (`NTFS_FS=m`, com `NTFS_DEBUG`) fica compilado, mas só é usado se pedido explicitamente
- FAT (pendrives de colegas; `vfat` com as codepages e charsets usados, como cp437 e utf8)
- imagens ISO (ISO 9660 com Joliet e Rock Ridge, UDF, montadas por loop)

**Sistemas de arquivos montados:** `btrfs`, `vfat`, `tmpfs`, `hugetlbfs`, `fuse.portal` (portal de documentos do Flatpak), `autofs` (automount do systemd), `efivarfs`, `pstore`, `cgroup2`, `bpf`, `configfs`, `debugfs`, `tracefs`, `securityfs`, `mqueue`, além de `proc`, `sysfs`, `devtmpfs` e `devpts`.

**FUSE é essencial:** dependem dele o `ntfs-3g`, as AppImages (GearLever), o `ifuse` (iPhone) e o portal de documentos do Flatpak.

**Windows:** partição NTFS (apelidada de Bosta11), sem entrada no fstab, montada com `ntfs-3g`; a ESP é a mesma do Arch. O BitLocker usa o TPM físico (19).

**initramfs (`mkinitcpio`):** os arquivos de `/etc/mkinitcpio.conf.d/` se sobrepõem ao `/etc/mkinitcpio.conf`:

```text
HOOKS=(base systemd autodetect microcode modconf keyboard sd-vconsole block sd-encrypt filesystems fsck)
MODULES=(zstd lz4)
COMPRESSION="zstd"
COMPRESSION_OPTIONS=(-19 --long -v)
MODULES_DECOMPRESS="yes"
```

- o hook `systemd` substitui o `udev`; `sd-encrypt` abre o LUKS
- sem o hook `kms` (33.3)
- `zstd` e `lz4` estão em `MODULES` pelo zswap e pela hibernação; como `CRYPTO_ZSTD`, `CRYPTO_LZ4` e `CRYPTO_LZO` são embutidos nos três kernels, as entradas não têm efeito (33.3)
- o mkinitcpio já acrescenta `-T0` às opções do zstd; com `MODULES_DECOMPRESS`, módulos e firmware entram descomprimidos e são comprimidos junto com a imagem
- o kernel próprio só tem o descompressor zstd de initramfs (33.3)

**Escalonador de E/S:** `/etc/udev/rules.d/60-ioschedulers.rules` pede o `mq-deadline` para discos USB e cartões SD (`sd[a-z]*`, `mmcblk[0-9]*`); o NVMe fica com `none`. No `linux-tkg` o mq-deadline é módulo, e o kernel só o carrega quando alguém escreve em `queue/scheduler`.

### Swap / hibernação

- Swapfile Btrfs de 16 GiB em `/.swap/swapfile`
- hibernado (S4) ou desligado, o laptop só acorda pelo botão de energia: o DeepSx corta a energia de standby do chipset (1A)
- hibernação comprimida com lz4, localizada pelo systemd pela `HibernateLocation` (1B); `zswap` com zstd
- `HibernateMode=platform`; sono com `MemorySleepMode=deep` e `SuspendState=mem` (S3 ativado no firmware)
- `systemd-oomd` ativo: mata processos por pressão de memória (`ManagedOOMMemoryPressureLimit=70%` nas sessões de usuário) e por uso de swap; depende do PSI e do controlador de memória do cgroup v2
- `zram` não é necessário com swapfile + `zswap`
- pstore com backend EFI ligado (1B; padrão do Kconfig no `linux-tkg`) e `systemd-pstore.service` habilitado: cada crash grava alguns KB na NVRAM, e o serviço os move para `/var/lib/systemd/pstore` e os apaga da NVRAM (`/etc/systemd/pstore.conf` nos padrões)

### Armazenamento externo

- SSDs/HDDs/pendrives externos; um SSD externo com LUKS + Btrfs + subvolumes, onde discard não é permitido pelo usuário
- SSD e HDD SATA via adaptador USB-SATA. Um deles, o SanDisk SSD PLUS 240 GB, é o disco da VM Faltir-win10 (`/dev/disk/by-id/ata-SanDisk_SSD_PLUS_240GB_184027805329`). O nome `ata-` vem do udev, que lê a identificação ATA pelo adaptador (`uas`/`usb-storage` + `sd_mod`): o laptop não tem controladora SATA, então o `ATA` (libata) sai sem afetá-lo

**Preservar:** USB Mass Storage, UAS, SCSI disk e SCSI generic. Não remover suporte externo só porque os discos internos são NVMe.

### Política NVMe

- NVMe é crítico; disponível cedo (raiz)
- APST ligado nos dois NVMe e ASPM L1 com L1.1/L1.2 nos dois links; o Micron, mesmo sem uso, não impede os estados de repouso. Não alterar latência/APST sem necessidade
- preservar NVMe hwmon

## 9. Leitor SD

- `6c:00.0` Realtek RTS525A [10ec:525a], driver `rtsx_pci`
- Preservar `rtsx_pci`, `rtsx_pci_sdmmc` e `mmc_block` (necessário para ler um cartão). O leitor não é eMMC: `RPMB` sai

## 10. Webcam

- Webcam integrada, Realtek `0bda:555d`, usada pelo usuário

**Preservar:** media camera, media USB, UVC e os input events do UVC.

## 11. Teclado, mouse, touchpad e HID

### Teclado interno

- O teclado interno é USB: Darfon `0d62:d2b0`, `usbhid`
- O controlador i8042/PS2 também está ativo, com teclado (`DLLK0BFB`) e porta auxiliar (`DLL0BFB`) ligados ao `i8042` (o Legacy Game Compatibility Mode do firmware ativa teclado/mouse PS/2). Manter `i8042` e `atkbd`
- As teclas de macro chegam pelo mesmo dispositivo USB HID: um arquivo hwdb mapeia os usages `0xc0051`–`0xc0055` para `macro1`–`macro5`
- Não confundir teclado USB com drivers de teclados embarcados do submenu Keyboards
- Protocolos PS/2 de touchpads de outros fabricantes (ALPS, BYD, Cypress, Elantech, FocalTech, Lifebook, Logitech PS/2, Sentelic, Touchkit, Trackpoint) saem; os Synaptics do `psmouse` ficam, por ser o fabricante do touchpad
- `INPUT_TOUCHSCREEN` e `INPUT_TABLET` saem: não há tela sensível ao toque nem mesa digitalizadora

### Touchpad

O touchpad é o `VEN_06CB` (Synaptics), ligado ao `i2c_hid_acpi`:

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

Mouses e teclados USB: Logitech K230, Logitech M280/M320/M275, Logitech Unifying Receiver (C52B), mouse gamer Dazz GMO3000, teclado Dell KB216p e outros HID USB/receptores sem fio.

**Preservar:** HID genérico, USB HID, Logitech HID, DJ e HID++, periféricos com RGB.

## 12. Gamepads

**Uso:**

- Xbox 360 e One
- PlayStation 3 e 4/5
- Steam Controller
- Gamepads third-party (inclusive com adaptadores USB sem fio, além do Bluetooth)
- Volantes: o usuário ainda não tem um, então `LOGIWHEELS_FF` e `HID_PID` ficam desligados; ao comprar um, religar o driver da marca e carregar o módulo antes do próximo build. O manche Logitech G940 sai

**Preservar:**

- `xpad`, com force feedback e LED Guide
- `hid-playstation`, com force feedback
- `hid-steam`
- `hid-sony`, `hid-nintendo`, `hid-microsoft` (controles Xbox por Bluetooth) e `hid-logitech`
- Bluetooth HIDP
- USB HID genérico
- `uinput`: o Steam Input cria controles virtuais por `/dev/uinput`

Não confundir gamepads com Remote Controller/LIRC/IR: saem `LIRC`, `RC_CORE` e o repasse de controle remoto pelo HDMI-CEC (`MEDIA_CEC_RC`); o CEC do `i915` fica.

## 13. Arduino, ESP32 e Raspberry Pi

**Usa:** Arduino, ESP32 e Raspberry Pi, por USB serial e USB networking.

**Preservar:** CDC ACM, CH341/CH340, CP210x, FTDI SIO, PL2303 e USB serial generic.

```text
Arduino -> CDC ACM / CH340 / FTDI
ESP32   -> CP210x / CH340 / CDC ACM
RPi     -> USB serial e/ou USB networking
```

### Não confundir

- `SPI_CH341` não é necessário só por usar CH340/CH341 serial
- FTDI MPSSE GPIO só é necessário com uso deliberado de FT232H/FT2232H em MPSSE para GPIO/JTAG/SPI
- GPIO/SPI/I2C/1-Wire do host não devem ser habilitados só porque existem nas placas externas; um sensor ligado ao ESP32 é controlado pelo ESP32
- Os adaptadores USB serial não usam o driver 8250

### USB networking

**Preservar:** Raspberry Pi USB gadget/network, CDC Ethernet, CDC NCM, RNDIS host, ASIX AX88179, Realtek RTL8152/8153, iPhone (`ipheth`) e Android USB Ethernet. O `cdc_subset` (adaptadores USB antigos) sai.

## 14. Telefones

- Conecta Android e iPhone/iOS: preservar o USB networking correspondente
- Não habilitar modems WWAN: o laptop não tem hardware WWAN

## 15. Impressora e scanner

- Canon E4210, pela rede: `ipps://248FC3000000.local:631/ipp/print` (CUPS, descoberta pelo mDNS do Avahi), com SANE
- IPP-USB não é usado; `USB_PRINTER` fica como módulo para uma impressora USB eventual
- preservar multicast/mDNS

## 16. Virtualização

**Usa:**

- QEMU, KVM e libvirt; SPICE via socket Unix
- passthrough de GPU com Looking Glass B7 e o módulo `kvmfr` (fora da árvore, via DKMS e assinado com a MOK; `static_size_mb=256`)
- passthrough de NVMe e de USB
- TPM: a VM do Windows 11 (a instalação bare metal, usada também como VM) recebe o TPM físico pelo `/dev/tpmrm0`; a VM do Windows 10 usa TPM emulado (`swtpm`)
- discos físicos em VM, inclusive um disco virtual montado com device-mapper (`dm-linear`) sobre as partições do Windows físico, com imagens em loop (`loop max_part=15`)
- pasta compartilhada com `virtiofsd` (memória da VM compartilhada)
- CPU isolation por hook do libvirt, via cgroups (`AllowedCPUs` do systemd): vCPUs nos P-cores 8–15, emulador nos 16–17, iothread nos 18–19; o host fica com 0–7 e 20–31
- hugepages dinâmicas: `vm.nr_overcommit_hugepages=8192` (16 GiB), com compactação de memória antes de a VM iniciar (`/proc/sys/vm/compact_memory`); HVO ligado por padrão
- virtualização aninhada: `kvm_intel nested=1`
- dummy HDMI/miniDP
- IOMMU ligado (1B)
- discos das VMs com `io="native"` (Linux AIO), `cache="none"`, `discard="unmap"` e iothreads
- VMs: `archlinux`, `Bosta10`, `Bosta11-bare-metal` (disco `/dev/mapper/windows-VM`) e `Faltir-win10` (SSD SATA por USB, 8). Todas com rede `type='network'` na rede `default` (NAT, bridge `virbr0` com STP), placa `virtio` e vídeo `virtio-vga-gl`; nenhuma usa macvtap (`type='direct'`)

**Opções:** ficam `KVM_INTEL`, `KVM_HYPERV` (enlightenments Hyper-V das VMs Windows), `VFIO_PCI`, `VHOST_NET`, `TUN`, `BRIDGE`; saem `KVM_AMD`, `KVM_XEN` (emulação de Xen para guests), `KVM_INTEL_TDX` e `MACVLAN`/`MACVTAP`.

**Preservar:** KVM Intel, IOMMU, VFIO/VFIO PCI e passthrough, TUN/TAP, device-mapper e loop, hugetlbfs e compactação de memória, Linux AIO, bridge com nftables e `vhost_net`, cpusets do cgroup v2.

**Regra crucial:** o kernel é o host físico, não o guest. Não habilitar frontends VirtIO/Xen/Hyper-V/VMware só porque o host roda VMs. O sistema não usa Xen.

## 17. Jogos

**Usos:** Steam, Proton, Wine, emulação, controles (12), NVIDIA, VM de jogos com passthrough.

- o sandbox do Steam (pressure-vessel), o Flatpak (`bubblewrap` sem setuid) e o sandbox dos navegadores Chromium (como o Helium) precisam de user namespaces sem privilégio: `USER_NS=y` e, no linux-tkg, `USER_NS_UNPRIVILEGED=y` (opção do patch `0001-add-sysctl-to-disallow-unprivileged-CLONE_NEWUSER`, ligada por padrão)
- `ntsync` (`CONFIG_NTSYNC=m`, usado pelo Proton recente); no `linux-tkg.cfg`, o `_ntsync="false"` só se refere ao patch para kernels antigos
- o Wine precisa de `MODIFY_LDT_SYSCALL` e `X86_16BIT`, que ficam mesmo sendo interfaces antigas; o 32 bits (`IA32_EMULATION`) fica pelo Steam
- a emulação da página vsyscall sai (`X86_VSYSCALL_EMULATION`): só binários estáticos de glibc anteriores a 2011 a usam

**Requisitos:** evitar latência e overhead desnecessários; preservar periféricos e HDMI/miniDP/USB-C.

## 18. Secure Boot, UKI e assinatura

- Secure Boot ativo, com as chaves padrão do laptop: PK, KEK e db/dbx não foram alteradas (db/dbx são atualizadas pelo fwupd)
- MOKs próprias assinam os binários do sistema, via shim em `EFI/systemd/` (com cópia em `EFI/arch/` para o fwupd), instalado pelos scripts do repositório (`shim-setup.sh`, `systemd-boot-setup-shim.sh`); a entrada de boot do firmware aponta para `\EFI\systemd\shimx64.efi`
- `systemd-boot`, assinado com a MOK por um hook do pacman
- UKIs geradas pelo `mkinitcpio`; os hooks `kernel-sbsign` e `uki-sbsign` assinam o kernel e a UKI com a MOK. Cada kernel tem um preset com `default_uki` e sem fallback; o do `linux-tkg` (`/etc/mkinitcpio.d/linux-tkg.preset`) é uma cópia do `linux-zen.preset` com o nome trocado, criada antes de instalar o pacote (senão o hook de instalação cria um preset do template, que gera initramfs em vez de UKI)
- Os módulos DKMS (`nvidia-open-dkms`, `kvmfr`) são assinados pelo DKMS com a MOK de assinatura de módulos (`custom-moks.conf`, "Mr. Robot Alienware Machine Owner Key - Module Signing"), não com a chave de módulos do kernel. O kernel confia nela pelo keyring `.machine`, carregado da `MokListRT` (`mokutil --trust-mok` ativo)
- `/proc/sys/kernel/tainted` esperado: 4100 = 4096 (módulos de fora da árvore, o DKMS) + 4 (escrita em MSR pelo `intel-undervolt`). O bit 13 (8192, módulo sem assinatura) não pode aparecer
- MOKs: `MOK.crt` e `MOK-module-signing.crt` têm `CA:TRUE` e nenhum keyUsage. Por isso `INTEGRITY_CA_MACHINE_KEYRING` fica desligado: com ele, só entram no `.machine` as MOKs com `CA:TRUE` e `keyCertSign`, as duas iriam para o keyring da plataforma (que não vale para módulos), e o nvidia e o kvmfr deixariam de carregar
- A `MokListRT` tem também `Red Hat, Inc.: fedoraca`, `grub` e `MultiOS-USB`. Com a confiança na MOK ativa, o kernel aceita módulos assinados por qualquer uma delas, e o shim inicia o que elas assinarem. Remover as que não forem usadas (`mokutil --export`, `mokutil --delete MOK-000N.der` e confirmar no MokManager); manter `MultiOS-USB` e `grub` se o pendrive do MultiOS-USB for iniciado com Secure Boot
- O fwupd atualiza o firmware por cápsulas UEFI (ESRT, efivarfs) e assina o próprio binário EFI com a MOK
- Chaves MOK em `/root/secureboot/keys/` (guardar antes de reinstalar)

**Assinatura de módulos no kernel:**

- `MODULE_SIG=y`, `MODULE_SIG_ALL=y`, SHA-512
- `MODULE_SIG_FORCE=y`: módulo sem assinatura válida não carrega. Se a assinatura do DKMS falhar, o nvidia não carrega: o `linux` e o `linux-zen` ficam como reserva
- sem `MODULE_FORCE_LOAD` nem `MODULE_FORCE_UNLOAD`
- o PKGBUILD do linux-tkg usa `options=('!strip')`, e o `INSTALL_MOD_STRIP=1` do `_STRIP="true"` age antes da assinatura no `modules_install`: as assinaturas continuam válidas

Não quebrar Secure Boot ao modularizar drivers de boot.

**Lockdown:** com o lockdown em modo integrity, comum junto do Secure Boot, o kernel desativa a hibernação. Como a hibernação é usada, fica `LOCK_DOWN_KERNEL_FORCE_NONE`, com `SECURITY_LOCKDOWN_LSM_EARLY=y` (sem efeito enquanto o lockdown estiver em none). Com o lockdown em none, o `kexec_load` deixaria o root iniciar um kernel não assinado, passando por cima do Secure Boot: kexec e kdump saem (33.5).

**Tela no boot:** a senha do LUKS (`sd-encrypt`) aparece antes de o driver da GPU carregar, pelo framebuffer do UEFI (`simple-framebuffer` via `simpledrm`, 33.3).

## 19. TPM 2.0

```text
driver: /sys/bus/platform/drivers/tpm_crb_acpi
TPM version: 2
device: /sys/devices/platform/INTC6001:00
DRIVER=tpm_crb_acpi
MODALIAS=acpi:INTC6001:MSFT0101:
```

- ACPI/EFI: SSDT Tpm2Tabl, tabela TPM2 Dell, TPMFinalLog, TPMEventLog
- o systemd faz o TPM PCR Barrier no initrd, as medições de PCR, a do Machine ID e o Early TPM SRK Setup
- interface real: CRB. `TCG_TIS` e `TCG_TIS_CORE` (TIS/FIFO/SPI/I2C) saem
- `TCG_TPM=m` e `TCG_CRB=m`: o hook `sd-encrypt` põe `tpm_crb` e `tpm` na UKI (filtrados pelo autodetect, 33.3); `MODULES` não é necessário
- o `/dev/tpmrm0` (resource manager do kernel) é passado à VM do Windows 11 bare metal (16)
- o TPM físico é usado pelo systemd (medições, `systemd-creds`, usado no script do hotspot) e pelo BitLocker do Windows

## 20. Watchdog

```text
/dev/watchdog
/dev/watchdog0

identity: iTCO_wdt
driver: /sys/bus/platform/drivers/iTCO_wdt
Found a Intel PCH TCO device, Version=6, TCOBASE=0x0400, heartbeat=30 sec, nowayout=0
```

- watchdog real: Intel TCO (`iTCO_wdt`, com o `intel_pmc_bxt`); fica
- ACPI WDAT ausente: o firmware só a publica com o Enable TCO Timer ligado, e ele fica desligado (1A); o `iTCO_wdt` não depende dela
- softdog e pretimeout desnecessários; `nowayout=0` desejado

### NMI watchdog

- detector de hard lockup por um contador da PMU (`NMI watchdog: Enabled. Permanently consumes one hw-PMU counter.`), diferente do iTCO
- os perfis do `tuned` o ligam e desligam em runtime, então o suporte fica compilado (32A.9)

## 21. Intel Integrated Sensor Hub

- `00:12.0` [8086:7a78], driver `intel_ish_ipc`, com `intel_ishtp` e `intel_ishtp_hid` (sensores `hid_sensor_hub`/`hid_sensor_custom`); preservar o caminho

## 22. DPTF / thermal Intel

- `00:04.0` [8086:a71d], driver `proc_thermal_pci` (módulo `processor_thermal_device_pci`)

**Preservar:** INT340X / processor thermal, package temperature thermal, coretemp, Intel HFI, TCC cooling do Raptor Lake, thermal hwmon.

**Decisões:**

- drivers Bay Trail/Broxton e o Intel PCH Thermal Reporting antigo não correspondem ao hardware
- `intel_powerclamp` está em uso, então fica
- governor térmico principal: step_wise
- Tjmax 100 °C, sem offset: o Tcc Offset Lock do firmware trava o registro, então ferramentas do sistema não alteram o ponto de throttling
- sem thermal emulation
- não há ventoinha ACPI (`PNP0C0B` ou `INTC1048`): as ventoinhas vêm do Dell SMM e do WMI (23). `ACPI_FAN` fica como módulo só porque o `INT340X_THERMAL` o seleciona
- `ACPI_THERMAL` embutido (o Kconfig o chama de "HIGHLY recommended"; como módulo, as zonas térmicas do firmware só valeriam depois do prompt do LUKS)
- thermald desabilitado (32)
- zona térmica ACPI genérica (Platform Thermal Configuration do firmware, nos padrões): ponto crítico em 119 °C (o kernel desliga o sistema), pontos passivos desligados (o kernel não reduz a velocidade da CPU por ela; o throttling vem do TCC aos 100 °C) e pontos ativos sem efeito, por falta de ventoinha ACPI

## 23. HWMON

| Fonte | Driver | O que expõe |
|---|---|---|
| CPU | `coretemp` | pacote e cada núcleo (Tjmax 100 °C) |
| Dell SMM | `dell_smm_hwmon` | 4 ventoinhas, 9 temperaturas e controle PWM manual das ventoinhas |
| Dell DDV (WMI) | `dell_wmi_ddv` | as mesmas ventoinhas e temperaturas do Dell SMM, com nomes (CPU, Video, Ambient, SODIMM) |
| Alienware WMI | `alienware_wmi` | ventoinhas de CPU e GPU, temperaturas de CPU e GPU |
| RAM | `spd5118` | os dois pentes DDR5, no SMBus do I801 (endereços `0x50` e `0x52`) |
| NVMe | NVMe hwmon | o ADATA (`6d:00.0`) e o Micron desconsiderado (`6f:00.0`) |
| Wi-Fi | `iwlwifi` | temperatura do AX211 |
| Ethernet | Realtek PHY hwmon | temperatura do PHY |
| Energia | power_supply hwmon | bateria `BAT0` e as duas portas USB-C (UCSI) |

- todos ficam, inclusive o `dell_wmi_ddv` e o hwmon do `alienware_wmi`, que repetem dados do `dell_smm_hwmon`; `HWMON` core como módulo
- `/proc/i8k` legado (`I8K`) sai

## 24. Dell/Alienware WMI

- `dell_wmi`, `alienware_wmi`, `dell_smbios` (com o `dcdbas`), `dell_wmi_sysman` (configurações da BIOS pelo `firmware-attributes`), `dell_wmi_ddv` (sensores, 23), `nvidia_wmi_ec_backlight` (brilho)
- o `alienware_wmi` fornece o `platform_profile` usado pelos perfis do tuned (32A.3)
- GUIDs WMI: o WMAX do Alienware (`A70591CE-…`) e o do Dell SMBIOS (`A80593CE-…`), entre outros. O GUID do Alienware legado (`A90597CE-…`, AlienFX) não existe: `ALIENWARE_WMI_LEGACY` sai, `ALIENWARE_WMI_WMAX` fica

## 25. Intel MEI

- `00:16.0` CSME HECI #1 [8086:7a68], driver `mei_me`, com `mei_hdcp` e `mei_pxp`; fica
- o watchdog iAMT (`MEI_WDT`) e outros dispositivos MEI especializados saem

## 26. I2C

- core I2C embutido (ACPI I2C OpRegion, touchpad, Intel LPSS, dispositivos internos enumerados)
- I801: `00:1f.4` [8086:7a23], driver `i801_smbus`; `I2C_I801` fica
- DesignWare: o Intel LPSS usa o DesignWare Platform (`i2c_designware.0` e `.1`); `I2C_DESIGNWARE_CORE` e `I2C_DESIGNWARE_PLATFORM` como módulos. `I2C_DESIGNWARE_PCI` e o semáforo do Bay Trail saem
- i2c-dev: `I2C_CHARDEV` fica, porque o `i2c_dev` é carregado pelo `/usr/lib/modules-load.d/` dos pacotes `i2c-tools`, `ddcutil` (DDC/CI, brilho de monitores externos) e `fwupd`
- I2C mux: o core `I2C_MUX` é selecionado por dependência e fica; os muxes específicos saem
- `I2C_SLAVE` sai

## 27. SPI

- flash SPI do PCH: o controlador `00:1f.5` usa o `spi_intel_pci`, com `spi_intel`, `spi_nor` e `mtd`; ficam. O driver só permite leitura da flash por padrão (parâmetro `writeable` desligado)
- `SPI_INTEL_PLATFORM` (variante de plataforma, sem dispositivo aqui), `spidev` e `SPI_CH341` ficam fora

## 28. Pinctrl / GPIO

- Raptor Lake HX usa o Intel Alder Lake pinctrl: `PINCTRL_INTEL` e `PINCTRL_ALDERLAKE` (não o Tiger Lake)
- GPIO userspace desnecessário: `GPIO_CDEV` (e com ele a ABI v1) sai pelo bloco 8 do `.myfrag` (`EXPERT`); `GPIO_SYSFS` desligado. Se o core GPIO estiver forçado, não quebrar dependências para removê-lo
- Arduino/ESP32/RPi via USB não justificam GPIO no host

## 29. Regulators / PMIC

- `intel-undervolt` e NVML não dependem de `CONFIG_REGULATOR`; o framework é para PMICs geridos pelo kernel, que não existem aqui
- reguladores Maxim/TI/Richtek/NXP/MediaTek saem
- `REGULATOR` / fixed voltage regulator é selecionado por dependência: não forçar N enquanto essa dependência não for identificada

## 30. Bateria / power supply

- bateria `BAT0`: DELL 70N2F3B (fabricante SMP), Li-poly, fabricada em 2023-12-26; capacidade de projeto ~84,28 Wh (7393 mAh × 11,4 V), ~71% de saúde
- driver: bateria ACPI (`acpi-battery`, `PNP0C0A`); SBS não é usado
- a bateria informa `current_now`, `voltage_now` e `charge_now`, não `power_now`: a potência é o produto dos dois primeiros (µA × µV = 10⁻¹² W), e a média de um período sai da variação do `charge_now`
- fontes de energia: `AC` (driver `ac`) e duas portas USB-C (`ucsi-source-psy-USBC000:001` e `:002`, driver `ucsi_acpi`)

**Preservar:** power supply class, bateria ACPI, AC adapter, power supply hwmon. Drivers de fuel gauge/charger específicos saem.

## 31. linux-tkg e build

**Arquivos:**

- `~/.config/frogminer/linux-tkg.cfg` (configuração externa do tkg)
- `~/.config/frogminer/alienware.myfrag`, copiado como arquivo regular para `/opt/linux-tkg/` com `install -m644` a cada mudança: o tkg só aplica arquivos *regulares* terminados em `.myfrag` dentro do diretório dele (`find "$_where"/ -type f -name "*.myfrag"`), e um symlink é ignorado sem aviso. Nenhum outro `.myfrag` pode ficar em `/opt/linux-tkg/`
- `~/.local/share/modprobed-db/modprobed.db` (357 módulos)
- repositório do tkg em `/opt/linux-tkg`; build em tmpfs (`/tmp/kernel-build`, 42 GiB), 5–6 min no perfil de performance com ~7 GiB de RAM

**`linux-tkg.cfg`:**

- `_custom_pkgbase="linux-tkg"`: pacotes `linux-tkg` e `linux-tkg-headers`, imagem `/boot/vmlinuz-linux-tkg`, preset `linux-tkg.preset` (18)
- versão: a estável mais recente da série escolhida na hora do build (`_version` vazio: o script pergunta; `"7.2-latest"` ou uma tag como `"v7.2.15"` fixam a escolha). As séries 7.2 e 7.3 são mantidas pelo linux-tkg
- base: com `_distro="Arch"` e `_configfile` vazio, o tkg parte do `linux-tkg-config/7.2/config.x86_64`, que é a configuração do `linux` do Arch
- escalonador BORE (`_bore_min_base_slice_ns=2000000`)
- GCC (o `_lto_mode` só vale para clang, então o LTO fica desligado); `-O3` (`_compileroptlevel=2`); `-march=native` (`_processor_opt=native`, posto no Makefile pelo tkg e mantido para o DKMS)
- `_tickless=2` → tickless-idle (`NO_HZ_IDLE`); 1000 Hz; 32 CPUs
- NUKR; MGLRU ligado; `_zenify` e `_glitched_base` ligados
- `_STRIP="true"`: remove o DWARF dos módulos (`INSTALL_MOD_STRIP=1`, que mantém a seção `.BTF`) e do `vmlinux` dos headers. O tkg também liga `DEBUG_INFO_NONE`, que desligaria o BTF; o fragmento religa o debug
- `_irq_threading="false"` (a threading de IRQs vem do `threadirqs`); `_acs_override="false"` (o ACS do firmware já isola a dGPU)
- debug, ftrace e NUMA não são desativados pelo tkg (`_debugdisable`, `_ftracedisable`, `_numadisable` = false); `_kernel_on_diet` desligado; `PREEMPT_RT` desligado
- `_modprobeddb="true"`, com `_modprobeddb_db_path=~/.local/share/modprobed-db/modprobed.db`
- `_menunconfig="1"` (abre o `menuconfig` a cada build), `_diffconfig="true"` e `_diffconfig_name="menuconfig-diff.txt"`
- sem efeito no 7.2: `_fsync_backport`, `_fsync_legacy`, `_zfsfix`, `_ntsync` (o `CONFIG_NTSYNC` fica ligado, 17), `_random_trust_cpu`, `_aggressive_ondemand`, `_install_after_building` e as opções de LLVM
- compilador: GCC 16.2.1, sem `-fsanitize=kcfi`; `-fzero-call-used-regs` suportado

**Ordem do build (`linux-tkg-config/prepare`):** base `config.x86_64` → `make localmodconfig` com o banco → ajustes do próprio tkg (`DEBUG_INFO_NONE` do `_STRIP`, `NR_CPUS`, tickless, `MAXSMP` desligado, `SYSFB_SIMPLEFB` desligado, CAKE como qdisc padrão etc.) → cada `*.myfrag` por `merge_config.sh -m`, em ordem alfabética → `olddefconfig` → `menuconfig` → `diffconfig`. O fragmento é aplicado depois dos ajustes do tkg e prevalece sobre eles.

- o `localmodconfig` desliga as opções m cujo módulo não está no banco e não mexe nas y; o que ele derrubar por engano volta pelo fragmento
- o `diffconfig` grava em `$_where/menuconfig-diff.txt` só as mudanças daquele `menuconfig`, e esse arquivo **não** é reaplicado no build seguinte: toda escolha feita no `menuconfig` que deva ficar precisa ir para o fragmento. O nome gerado não pode terminar em `.myfrag`, senão seria aplicado automaticamente

**`modprobed.db`:** o banco só tem o que foi carregado como módulo no kernel em uso. Módulos de uso raro precisam ser carregados ao menos uma vez antes do build, senão somem. Além do coletado pelo `modprobed-db`, o banco recebeu à mão os módulos do inventário: codepages NLS, `nbd`, `ntsync`, `mmc_block`, seriais USB (`cdc_acm`, `usbserial`, `ch341`, `cp210x`, `ftdi_sio`, `pl2303`), `rndis_host`, `r8152`, gamepads (`xpad`, `hid_playstation`, `led_class_multicolor`, `hid_sony`, `hid_steam`, `hid_nintendo`, `hid_logitech`), `hidp`, áudio USB e MIDI (`snd_usb_audio`, `snd_usbmidi_lib`, `snd_rawmidi`, `snd_ump`, `snd_seq_midi`, `snd_seq_midi_event`), qdiscs e classificadores (`sch_fq`, `sch_cake`, `sch_fq_codel`, `sch_ingress`, `cls_flower`, `cls_matchall`, `act_gact`, `act_mirred`) e os que são embutidos na base e o fragmento passa a m (`tpm`, `tpm_crb`, `btrfs`, `fuse`, `xts`, `msr`, `usbhid`, `hid_generic`, `xhci_*`, `i8042`, `atkbd`, `serio`, `libps2`, `sd_mod`, `scsi_mod`, `autofs4`, `configfs`, `ac`, `battery`, `button`, `i2c_designware_*`). O `modprobed-db store` só acrescenta, então eles ficam. Os módulos da NVIDIA (DKMS) não precisam estar no banco.

**Requisitos do fluxo de build e boot:**

- DKMS a compilar para cada kernel: `nvidia` e `looking-glass` (`kvmfr`); conferir com `dkms status`
- o `linux-firmware` do Arch é comprimido em zstd: o kernel precisa carregar firmware zstd (`FW_LOADER_COMPRESS_ZSTD`), senão Wi-Fi, Bluetooth, iGPU (GuC/HuC/DMC), áudio (SOF) e Ethernet param
- módulos comprimidos em zstd (`MODULE_COMPRESS_ZSTD`), combinando com o `MODULES_DECOMPRESS` do `mkinitcpio`
- kernels de reserva: `linux` e `linux-zen`, porque versões novas do kernel às vezes quebram o `nvidia-open-dkms` por um tempo. O `linux-zen` também serve de referência: um problema que some nele aponta para as escolhas do linux-tkg

**Mantidos da base (configuração do `linux` do Arch):**

- assinatura e keyrings: `INTEGRITY_MACHINE_KEYRING`, `INTEGRITY_PLATFORM_KEYRING`, `SECONDARY_TRUSTED_KEYRING`, `LOAD_UEFI_KEYS` (o kernel confia na MOK para os módulos DKMS)
- LSMs: `CONFIG_LSM="landlock,lockdown,yama,integrity,bpf"`, `BPF_LSM=y`; `SECURITY_APPARMOR`, `SECURITY_SELINUX` e `SCHED_CLASS_EXT` (sched_ext) compilados sem uso ativo, mantidos
- sistema: `PSI`, `USER_NS`, `CPUSETS`, `AIO`, `IO_URING`, `FANOTIFY_ACCESS_PERMISSIONS`, `IRQ_FORCED_THREADING`
- memória: `HUGETLBFS`, `COMPACTION`, `LRU_GEN_ENABLED`, `TMPFS_QUOTA`, `ZSWAP_DEFAULT_ON`, `ZSWAP_SHRINKER_DEFAULT_ON`, `ZSWAP_COMPRESSOR_DEFAULT_ZSTD` com `CRYPTO_ZSTD=y`; `COMPACT_UNEVICTABLE_DEFAULT=1` (o padrão do `linux`, que favorece as páginas grandes; se o áudio tiver xruns, testar `vm.compact_unevictable_allowed=0` por sysctl)
- escalonamento: `PREEMPT=y` com `PREEMPT_DYNAMIC` (modo `full`, com `lazy` disponível)
- boot: `EFI_STUB`, `EFI_ESRT`, `RD_ZSTD`, `KERNEL_ZSTD`
- CPU: `X86_KERNEL_IBT`, `X86_USER_SHADOW_STACK`, todas as mitigações Intel

**Fragmento `alienware.myfrag`:** cada linha comentada com a seção deste documento que a justifica. Validado por simulação no código-fonte do 7.2.15 (base → `localmodconfig` com o banco real → ajustes do tkg → fragmento → `olddefconfig`, e também por cima do `kernelconfig.new` de um build real); toda linha fica com o valor pedido. Blocos:

1. debug: religa o BTF (`DEBUG_INFO_DWARF5`, `_BTF`, `_BTF_MODULES`, `_COMPRESSED_ZSTD`) e tira testes, injeção de falhas, `MMIOTRACE`, debug por xHCI/EHCI, `OVMF_DEBUG_LOG`, kexec/kdump/Live Update e contadores de debug em caminhos quentes (`LOCK_EVENT_COUNTS`, `X86_CPA_STATISTICS`); liga o backend EFI do pstore
2. CPU e papel de host: só Intel (sem AMD, mitigações exclusivas de AMD, IOMMU AMD), sem SGX/TDX/RDT, sem `INTEL_TURBO_MAX_3`, sem plataformas Intel embarcadas, sem papel de guest (`HYPERVISOR_GUEST`, Hyper-V, frontends VirtIO, `REMOTEPROC`), `INTEL_IOMMU_DEFAULT_ON`, `HIBERNATION_COMP_LZ4`, sem ABI x32, sem `ioperm`/`iopl`, `/dev/mem`, `/dev/port` e `/dev/snapshot`, sem EFI handover
3. os itens "Desligar" da seção 2
4. hardware ausente: SATA, AGP, VESA, EHCI/OHCI/UHCI, UART 8250, PMICs, touchscreen, TV/rádio/câmeras de plataforma, IR, NVMe multipath/auth, DAX, zonados, HBAs, SR-IOV e outros recursos PCI de servidor, NPU, infraestrutura de SoC, RAS de servidor, flash NAND, eMMC
5. segurança (33.5): LSMs sem uso, descompressores de initramfs além do zstd, tabelas de partição além de GPT/MBR, protocolos de datacenter, endurecimento
6. embutido → módulo (33.2)
7. rede de segurança: os módulos de uso raro declarados, como m, para o caso de o banco não os ter
8. `EXPERT=y` e o que só sai com ele: suporte a CPUs AMD/Hygon/Centaur/Zhaoxin, protocolos PS/2, `GPIO_CDEV`, `UID16`, `SGETMASK_SYSCALL`, emulação vsyscall, mapas de memória do firmware, console VGA e codecs HD-audio ausentes. Ligar o `EXPERT` não muda nenhuma outra opção, e o aviso dele no Kconfig não é um "If unsure, say N"
9. escolhas do usuário no `menuconfig` e correções:
   - `DM_INTEGRITY=m` (exigido pelo hook `sd-encrypt`; o `localmodconfig` o tirava) e `SYSFB_SIMPLEFB=y` (o tkg o desliga, o que deixaria o simpledrm sem framebuffer e o prompt do LUKS invisível)
   - TCP: CUBIC embutido e padrão; Westwood+, Vegas, YeAH e BBR como módulos
   - `X86_NATIVE_CPU` (redundante com o `_processor_opt=native`, sem efeito colateral)
   - `DPM_WATCHDOG`: se um driver travar o suspend ou o resume, avisa aos 60 s e dá panic aos 120 s (gravado no pstore)
   - THP em `madvise` (os programas que pedem, como o QEMU, continuam usando); HVO ligado por padrão
   - `FIRMWARE_EDID`; SOF só `ALDERLAKE` (5); `USB_PRINTER=m` (15); gatilhos de LED de MTD e CPU fora, de câmera como módulo
   - `ALLOW_DEV_COREDUMP=y`: coredumps de firmware do iwlwifi e do i915 para depuração (só root lê, e o dump some em 5 minutos)
   - `RUST_BITMAP_HARDENED` e `DEBUG_NMI_SELFTEST` (os dois com "If unsure, say N", escolhidos pelo usuário; custo desprezível)
   - `CRYPTO_SELFTESTS` (sem FULL): testa cada algoritmo do crypto API no registro e bloqueia implementações com defeito
   - `CRYPTO_HW` fora (aceleradores QAT, CCP, Padlock e afins não existem; AES-NI e SHA-NI ficam em outra seção do Kconfig)
   - kmemleak compilado e desligado (`DEBUG_KMEMLEAK_DEFAULT_OFF`): liga com `kmemleak=on` na linha de comando
   - UBSAN: detectores de bounds, shift, divisão por zero, bool e enum, sem `UBSAN_TRAP` (33.5)
   - menus `NET_VENDOR_*` e `WLAN_VENDOR_*` desligados, exceto Realtek (Ethernet) e Intel (Wi-Fi)
   - `ACPI_EC_DEBUGFS` e `USB_STORAGE_DEBUG` ficam fora: o primeiro permite escritas no EC que podem travá-lo a ponto de exigir tirar a bateria; o segundo grava uma mensagem no journal por comando enviado a um pendrive, sem como desligar

**Ficam de propósito:** `NUMA` (o linux-tkg avisa que desligá-lo quebra CUDA/NVENC), `MEMORY_HOTPLUG`/`ZONE_DEVICE`/`DEVICE_PRIVATE` (nvidia), `PCI_P2PDMA` (o `VFIO_PCI_DMABUF` depende dele), governors do cpufreq e térmicos (32A), `ACPI_DEBUG`, os tracers de latência (`HWLAT`, `OSNOISE`, `TIMERLAT`, úteis para xruns), `PROC_KCORE` (perf/drgn), o debug do iwlwifi.

## 32. Undervolt / power tuning

### CPU

- `intel-undervolt`, por MSR; o firmware só aceita o undervolt porque o UnderVolt Protection está desativado
- offsets: CPU −100 mV, GPU −70 mV, CPU Cache −100 mV, System Agent −70 mV, Analog I/O −70 mV; reaplicados pelo daemon a cada 60 min
- `X86_MSR` como módulo: o `intel-undervolt` roda `/sbin/modprobe msr` antes de usá-lo; não precisa de `modules-load.d`
- a configuração (`/etc/intel-undervolt.conf`) só tem as linhas `undervolt`, mais `daemon undervolt`, `daemon power` e `daemon tjoffset` sem valores de `power` nem `tjoffset`: nada usa o `/dev/mem`, que o `intel-undervolt` só abre para limites de potência e Tjunction por MMIO. Os limites de potência vêm do tuned pelo powercap (32A.4). `DEVMEM` sai; religar se um dia usar `power` ou `tjoffset` no `intel-undervolt`
- não confundir com o regulator framework

### GPU

- ajustes via NVML API, com o driver NVIDIA (sem regulator framework)
- `nvidia-undervolt.service` (oneshot, depois do `nvidia-persistenced`): clocks travados entre 210 e 2175 MHz e offsets de clock por P-state (P0 +300, P3 +255, P4 +240, P5 +225, P8 +180 MHz)
- o `nvidia-persistenced` mantém esses ajustes enquanto o driver estiver carregado

### Ferramentas

- `tuned` e `tuned-ppd`
- powertop e turbostat (usados para ajustar os perfis do tuned)
- `nvidia-powerd` (Dynamic Boost), ativo; só tem efeito na tomada
- thermald desabilitado (`systemctl disable --now thermald`): no modo `--adaptive` do serviço do pacote, ele aplica os limites das tabelas do DPTF por cima dos perfis (o PL1 ia a 165 W no MSR e no MMIO, ou a 55 W, em vez dos 12 W do `alienware-battery`) e não traz ganho em repouso

Ao remover governors/thermal facilities, considerar se uma ferramenta depende deles.

## 32A. Perfis customizados do tuned

O laptop possui quatro perfis customizados do `tuned`, mais um conjunto comum (`alienware-common`) que todos incluem. Ao escolher opções do kernel, preservar as interfaces que esses perfis manipulam dinamicamente.

### 32A.1 Perfis e objetivos

#### alienware-common

- não é selecionado sozinho; reúne os sysctls e o PCI runtime PM comuns
- `power-policy.bash`, ao lado dele, tem o código compartilhado: platform profile, RAPL, Wi-Fi e dGPU (32A.4 e 32A.14)

#### alienware-balanced

- perfil cotidiano padrão em AC; objetivo: equilíbrio geral

#### alienware-balanced-battery

- uso leve em bateria (o uso típico do usuário fora da tomada)
- herda o `alienware-balanced` e puxa para a economia: EPB `balance-power`, limites RAPL menores, ASPM `powersupersave`, USB autosuspend, Wi-Fi power save, sem wakeup de rede e sem NMI watchdog

#### alienware-performance

- exclusivo para AC; objetivo: desempenho determinístico com maior consumo
- usa `platform_profile`=balanced-performance, e não performance, porque no Alienware o perfil performance corresponde ao AWCC Overdrive e fixa as ventoinhas no máximo
- usa o governor `powersave` com EPP `balance_performance`, e não o governor `performance`: com este, o `intel_pstate` força a EPP em `performance`, a CPU nunca descansa e os reguladores de tensão produzem coil whine audível

#### alienware-battery

- exclusivo para bateria; objetivo: maximizar autonomia, mais rígido que o balanced-battery: boost desligado, platform profile `quiet` e a dGPU forçada a desligar (32A.14)

### 32A.2 CPUFreq, Intel P-state, EPB/EPP e boost

| Perfil | Governor | EPB | EPP | Boost |
|---|---|---|---|---|
| balanced | powersave | normal | balance_power | ligado |
| balanced-battery | powersave | balance-power | balance_power | ligado |
| performance | powersave | performance | balance_performance | ligado |
| battery | powersave | power | power | desligado |

**Requisitos ao kernel:**

- CPU frequency scaling e Intel P-state em modo ativo, com HWP; nesse modo, `powersave` e `performance` são políticas do próprio `intel_pstate`
- interfaces de EPB e EPP
- ligar/desligar o boost em runtime
- não remover um governor só porque ele não é o padrão (os genéricos ficam como módulos, carregados ao serem escolhidos)

### 32A.3 ACPI platform profile

| Perfil | `/sys/firmware/acpi/platform_profile` |
|---|---|
| balanced | balanced |
| balanced-battery | balanced |
| performance | balanced-performance |
| battery | quiet |

Ao parar, os perfis devolvem o `balanced` ao firmware. Uma troca de `platform_profile` pode fazer o EC reprogramar os limites RAPL.

**Requisitos:** ACPI platform profile e os drivers Dell/Alienware/ACPI que o fornecem. Ele participa ativamente da política de energia.

### 32A.4 Intel RAPL / powercap

Os perfis escrevem em `/sys/class/powercap/intel-rapl:0/constraint_*_power_limit_uw` e em `/sys/class/powercap/intel-rapl-mmio:0/` (os dois backends recebem os mesmos valores).

O firmware permite até 157 W de package power (PL2). O limite de consumo total do laptop é 330 W (capacidade da fonte).

| Perfil | PL1 / long term | Janela do PL1 | PL2 / short term | PL4 / peak |
|---|---:|---:|---:|---:|
| balanced | 55 W | 64 s | 86 W | 160 W |
| balanced-battery | 24 W | 28 s | 48 W | 72 W |
| performance | 117 W | 128 s | 157 W | 330 W |
| battery | 12 W | 16 s | 24 W | 42 W |

Os limites são escritos de forma que `PL1 <= PL2 <= PL4` valha depois de cada escrita: os que sobem, de cima para baixo (PL4, PL2, PL1); depois os que descem, de baixo para cima.

**Implementação (`power-policy.bash`):**

- o firmware aplica o `platform_profile` de forma assíncrona: as escritas RAPL esperam 16 s depois da troca, dentro de uma unidade transitória do systemd (`systemd-run`), para o `tuned` não ficar bloqueado
- cada troca de perfil usa um nome de unidade único e um ID de execução: uma execução substituída por uma troca mais nova sai sem escrever
- a verificação aos 10, 20 e 30 s confere o limite *efetivo* (o menor entre MSR e MMIO) e reescreve se o EC o tiver mudado; no `quiet`, o EC devolve o PL1 do MMIO a 50 W, mas o MSR continua valendo, e o limite efetivo fica certo
- o resultado vai para o journal (`Applied platform profile ...`)
- o lock de PKG_POWER_LIMIT está desativado no firmware, então as escritas funcionam

**Requisitos:** Intel RAPL (MSR e MMIO, `processor_thermal_rapl`), o framework `powercap` e a interface sysfs.

### 32A.5 PCI runtime PM e ASPM

Todos os perfis usam (pelo `alienware-common`) `/sys/bus/pci/devices/*/power/control=auto`.

| Perfil | Política ASPM |
|---|---|
| balanced | powersave |
| balanced-battery | powersupersave |
| performance | performance |
| battery | powersupersave |

**Requisitos:** PCI runtime PM e PCIe ASPM com troca de política em runtime; não compilar o kernel com ASPM permanentemente desativado.

### 32A.6 Áudio HDA e power saving

Os perfis alteram `/sys/module/snd_hda_intel/parameters/power_save`:

| Perfil | Timeout |
|---|---:|
| balanced | 10 s |
| balanced-battery | 10 s |
| performance | 0 s |
| battery | 1 s |

O codec HDMI da NVIDIA aparece no powertop como um dos maiores consumidores, e suspender o codec economiza energia, mas o resume pode produzir um pop audível: balanced e balanced-battery usam 10 s para reduzir os pops, battery aceita 1 s, performance desativa.

**Requisitos:** power management do `snd_hda_intel`, o parâmetro `power_save` e o runtime PM de HDA Intel/NVIDIA.

### 32A.7 Swap, zswap e page-cluster

Todos os perfis usam (pelo `alienware-common`):

```ini
vm.swappiness=60
vm.page-cluster=1
```

Com o `zswap`, readahead grande por page fault tende a ser desperdiçado quando a página volta do pool comprimido em RAM; page-cluster=1 mantém pequena antecipação para páginas rejeitadas pelo `zswap`.

**Requisitos:** swap, `zswap`, `vm.swappiness` e `vm.page-cluster`.

### 32A.8 Writeback / VM

| Perfil | Sysctls |
|---|---|
| balanced (padrão do `alienware-common`) | `vm.dirty_writeback_centisecs=500` |
| balanced-battery | `vm.dirty_writeback_centisecs=1500` |
| performance | `dirty_bytes=10%`, `dirty_background_bytes=3%`, `vm.dirty_writeback_centisecs=500` |
| battery | `vm.dirty_writeback_centisecs=1500`, `vm.dirty_expire_centisecs=6000` |

Em bateria, o writeback é agrupado em rajadas menos frequentes para deixar o NVMe em idle real por mais tempo; o battery aceita uma janela maior de dados ainda não persistidos em caso de crash.

### 32A.9 NMI watchdog

| Perfil | `kernel.nmi_watchdog` |
|---|---:|
| balanced | 1 |
| balanced-battery | 0 |
| performance | 1 |
| battery | 0 |

O suporte ao NMI watchdog / hard lockup detector fica compilado, e o `tuned` decide o estado em runtime. Enquanto o travamento de 32A.16 é investigado, os perfis de bateria também usam 1.

### 32A.10 USB autosuspend

Os perfis balanced-battery e battery usam o plugin `[usb]` com `autosuspend=1`.

**Requisitos:** USB runtime PM e autosuspend, com os drivers reais de áudio USB, HID, webcam, celulares e placas de desenvolvimento compatíveis com esse mecanismo.

### 32A.11 Wi-Fi power save

Os perfis balanced-battery e battery ligam o power save 802.11 por script (`wifi_powersave_on` ao iniciar, `wifi_powersave_restore` ao parar), porque ele não tem interface sysfs.

**Requisitos:** power management do `iwlwifi`/cfg80211/mac80211, alternável em runtime.

### 32A.12 Wake-on-LAN e wakeup de rede

Nos perfis balanced-battery e battery: `/sys/class/net/*/device/power/wakeup=disabled` e, no Killer E3000 (`enp110s0`), `wake_on_lan=d`. Assim Wi-Fi e Ethernet não ficam armados como fontes de wakeup em bateria, e o PHY do E3000 não fica ativo à espera de magic packets.

**Requisitos:** infraestrutura de device wakeup, Wake-on-LAN/ethtool no `r8169`/PHY Realtek e runtime PM das interfaces de rede. Os perfis precisam do suporte para poder desligá-lo.

### 32A.13 Regra de seleção de menuconfig derivada dos perfis

O kernel fornece mecanismos, e o `tuned` escolhe a política em runtime. Não remover uma funcionalidade só porque um dos perfis a deixa desligada: se outro perfil a liga ou altera, o suporte fica compilado. Tudo o que aparece em 32A.2 a 32A.12 e 32A.14 conta como usado.

### 32A.14 dGPU forçada a desligar (alienware-battery)

- depois de aplicar o perfil, uma unidade transitória (`alienware-dgpu`) confere se a dGPU chegou a D3cold
- se não chegou, registra no journal quem a mantém acordada (`journalctl -t alienware-dgpu`): processos com `/dev/nvidia*` ou os nós DRM abertos, e serviços da NVIDIA ativos
- quando é seguro (nenhum usuário), para o `nvidia-persistenced`, remove as funções PCI da dGPU (`/sys/bus/pci/devices/*/remove`) e grava em `/run/tuned/alienware-dgpu-removed` os serviços a religar; ao trocar de perfil, um rescan PCI (`/sys/bus/pci/rescan`) a traz de volta e reinicia o `nvidia-persistenced` e o `nvidia-undervolt`

**Requisitos:** hotplug/remoção de dispositivos PCI pelo sysfs, rescan PCI, PCI runtime PM e D3cold via ACPI.

### 32A.15 Consumo em bateria

Com o `alienware-battery`, brilho em 20%, tela a 60 Hz e a tela ligada, a bateria fornece ~17–18 W, dos quais o pacote gasta só ~4,6–4,9 W. O resto vem da plataforma (tela, chipset, memória, SSDs, Wi-Fi, iluminação, perdas de conversão).

- o pacote fica em PC2/PC3; PC6/PC8 quase não acontecem e PC10 nunca, porque o painel sem PSR (4) mantém a leitura do framebuffer ativa. Com a tela ligada, os ajustes do lado do processador estão no limite
- núcleos: P-cores 85–97% em CC7, E-cores 96–99% em CC6
- LTR que limitam o pacote (`intel_pmc_core`, `ltr_show`): Wi-Fi (CNV) 102 µs, xHCI 46 µs, `SOUTHPORT_F` 30,7 µs
- testados e sem ganho mensurável, portanto fora dos perfis: autosuspend do teclado interno e do AW-ELC; L1/L1.2 no Ethernet
- iluminação do teclado: desligada 16,75 W, nível fraco 17,18 W (+0,4 W), nível forte 17,62 W (+0,9 W). Na bateria, desligá-la rende uns 3% (fraco) a 5% (forte) de autonomia
- ferramentas de medição: `turbostat`, os contadores do `intel_pmc_core` (`package_cstate_show`, `ltr_show`) e a média de potência pela variação do `charge_now` da bateria (30)

### 32A.16 Travamento em investigação

Um travamento completo (tela parada, Ctrl+Alt+F sem resposta, nada gravado no journal) aconteceu logo depois de um `tuned-adm profile alienware-battery` com o thermald ligado e a sessão bloqueada. A causa não foi identificada; com o thermald desabilitado e a sessão desbloqueada, a mesma troca não travou. Captura montada até a causa aparecer (arquivos temporários, a apagar depois):

- `kernel.nmi_watchdog=1` também nos perfis de bateria (32A.9)
- `/etc/sysctl.d/90-debug-travamento.conf`: `kernel.hardlockup_panic=1`, `kernel.softlockup_panic=1`, `kernel.panic=10` (o lockup vira panic, gravado no pstore, e o sistema reinicia em 10 s)
- `/etc/systemd/journald.conf.d/90-debug-sync.conf`: `SyncIntervalSec=10s`
- pstore EFI e `systemd-pstore` (8), `DPM_WATCHDOG` no `linux-tkg` (31) e SysRq completo (33.6)
- crashlog da CPU: ligado no firmware (1A) e lido pelo `intel_pmt_crashlog` (`CONFIG_INTEL_PMT_CRASHLOG=m` no fragmento), em `/sys/class/intel_pmt/crashlog*`

## 33. Requisitos para escolher opções do menuconfig

### 33.1 O kernel é específico deste Alienware

- Preservar todo hardware real, os usos reais e os usos futuros já declarados
- Remover hardware de outras plataformas/fabricantes inexistentes
- Não manter drivers "só por precaução" sem uso plausível declarado
- Não remover infraestrutura base se hardware real depende dela
- Diferenciar infraestrutura genérica de driver específico

### 33.2 Preferência por modularização

Maximizar m em vez de y. Usar y quando for necessário cedo, o Kconfig exigir, houver vantagem real ou o core precisar existir antes dos consumidores. As decisões de cada subsistema estão nas seções respectivas.

**Módulos no `linux-tkg`** (toda opção tristate que pode ser módulo sem perder função), além dos de 33.3:

- `FUSE_FS`, `AUTOFS_FS`, `CONFIGFS_FS`, `BINFMT_MISC`, `EXT4_FS`, `NTFS_FS`, `UNICODE`
- `ACPI_AC`/`_BATTERY`/`_BUTTON`, `ACPI_FAN`
- `USB`, `USB_SERIAL`, `HID`, `SERIO`, `INPUT_EVDEV`, `INPUT_LEDS`, `LEDS_CLASS`, `BACKLIGHT_CLASS_DEVICE`, `HWMON`, `WATCHDOG_CORE`, `EDAC`/`EDAC_GHES`, `EXTCON`, `DMI_SYSFS`, `PCI_STUB`, `HW_RANDOM`, os heaps de dma-buf
- `SCSI`/`BLK_DEV_SD`, `I2C_DESIGNWARE_*`, `X86_MSR`/`X86_CPUID`
- escalonadores de E/S `MQ_IOSCHED_DEADLINE` (8), BFQ e Kyber; os governors genéricos do cpufreq
- rede: `PACKET`, `PACKET_DIAG`, `UNIX_DIAG`, `NET_SCH_FQ_CODEL` (6), `NET_DROP_MONITOR`, `CONNECTOR` (o `PROC_EVENTS` some, e nenhum programa o usa)
- criptografia: AES, CBC, CTR, CTS, ECDH, MD5, SHA-1, SHA-3, BLAKE2b, xxHash, CRC32c, `CRYPTO_DRBG`, `CRYPTO_JITTERENTROPY`, `CRYPTO_PCRYPT`, `CRYPTO_LZ4HC`. O KDE Wallet, o gnome-keyring, o GPG e afins criptografam no userspace e não dependem deles
- `IKCONFIG` (com `IKCONFIG_PROC`) e `IKHEADERS`

**Ficam y:** `BINFMT_SCRIPT` e `BINFMT_ELF`, `FW_LOADER`, `EFI_VARS_PSTORE` (crashes desde o boot), `TCP_CONG_CUBIC` (padrão do TCP), `EFIVAR_FS` (33.3), `DRM`/`DRM_SIMPLEDRM`/`FB` (33.3), `ACPI_THERMAL` (22), `RTC_DRV_CMOS` (relógio certo desde o boot pelo `RTC_HCTOSYS`, inclusive no journal do initramfs), `NVME` disponível cedo, o core I2C (26), e as opções selecionadas por outras que precisam ficar embutidas (por exemplo, a criptografia da assinatura de módulos, o `NLS` pelo ACPI e pelo USB).

### 33.3 Initramfs/UKI

Módulo não significa indisponível no boot. O usuário usa `mkinitcpio`, UKI e `systemd-boot`.

**Como o `mkinitcpio` escolhe os módulos** (lido no código-fonte, commit `68ebfd2` de 2026-10-18):

- `autodetect` lê `DRIVER=` e `MODALIAS=` de todos os `uevent` em `/sys/devices` do kernel em execução, resolve com o `modprobe -R` do kernel alvo e acrescenta o módulo do sistema de arquivos da raiz (`fs-btrfs`). Os hooks seguintes só incluem módulos dessa lista. Por isso a UKI precisa ser gerada com o hardware visível (vale também no chroot da reinstalação)
- opções embutidas são lidas de `modules.builtin.modinfo` e puladas sem erro: mudar uma opção entre y e m não exige mudar `MODULES` nem os hooks, salvo o que nenhum hook inclui
- cada módulo leva junto as dependências (`depends`), os `softdep` e o firmware que declara; `weakdep` não é seguido
- `MODULES` entra na imagem e é carregado explicitamente no boot (`/etc/modules-load.d/MODULES.conf` no initramfs). Serve para o que nenhum hook inclui
- `mkinitcpio -M` mostra a lista do autodetect; `mkinitcpio -v` mostra cada módulo adicionado

**O que cada hook em uso põe na UKI:**

| Hook | Sempre (se o módulo existir) | Só se autodetectado |
|---|---|---|
| `systemd` | `crypto-lzo`, `crypto-lz4` | — |
| `microcode` | só o microcódigo desta CPU (`GenuineIntel.bin`), no cpio inicial | — |
| `keyboard` | `usbhid`, `xhci_pci`, `xhci_hcd`, `ehci`/`ohci`, `thunderbolt` | controladores USB, `drivers/hid`, `serio` (i8042) e `input/keyboard` (atkbd) |
| `block` | `nvme`, `ahci`, `sd_mod`, `usb_storage`, `uas`, `mmc_block`, `virtio_blk`, `virtio_scsi` | `block`, `ata`, `scsi`, `nvme`, MMC, SPI, controladores PCI, MFD, clk, PHY, regulators |
| `sd-encrypt` | `dm-crypt`, `dm-integrity`, `hid-generic`, todos os módulos de `/crypto/` (sem filtro) | `drivers/char/tpm` (`tpm_crb`, `tpm`) |
| `filesystems` | `vfat` (com `nls_ascii` e `nls_cp437`) | fs da raiz (`btrfs`) |

**Sem o hook `kms`:** o `i915` não entra na UKI, e a senha do LUKS aparece pelo `simpledrm`. O `kms` aumentaria muito a UKI por causa do firmware: o autodetect resolveria o modalias da dGPU também para o `nouveau` (o `modprobe -R` ignora a blacklist) e o da iGPU também para o `xe`, e cada módulo leva todo firmware que declara. Com `DRM_NOUVEAU` e `DRM_XE` desligados, sobraria o `i915` e o firmware dele, ainda dispensável. Para medir: `mkinitcpio -A kms -s -g /tmp/kms.img` e `du` no diretório de build que ele indica.

**Tela desde o início do boot:** `DRM`, `DRM_SIMPLEDRM` e `FB` ficam embutidos. Como módulos não economizariam nada (o `i915` e o `nvidia_drm` carregam o núcleo DRM em todo boot), deixariam a tela preta até o initramfs, escondendo erros e panics do início do boot, e fariam o prompt do LUKS depender do `MODULES`. O `simpledrm` precisa do `SYSFB_SIMPLEFB=y`, que o tkg desliga e o fragmento religa.

**Consequências para a modularização:**

- podem ser m sem mudar nada no `mkinitcpio`: `NVME`, `BTRFS_FS`, `DM_CRYPT`, `DM_INTEGRITY`, `CRYPTO_AES_NI_INTEL`, `CRYPTO_XTS`, `TCG_TPM`, `TCG_CRB`, `USB_XHCI_PCI`/`USB_XHCI_HCD`, `USB_HID`, `HID_GENERIC`, `SERIO_I8042`, `KEYBOARD_ATKBD`, `VFAT_FS` e as NLS
- ficam y, porque são usados antes de o initramfs rodar ou porque nenhum hook inclui o módulo: `BLK_DEV_INITRD` com `RD_ZSTD`, `DEVTMPFS`, `EFI_STUB`, `DRM_SIMPLEDRM` (tela da senha), `EFIVAR_FS` (o systemd do initramfs lê a `HibernateLocation`, 1B), `UNIX` (o systemd usa sockets AF_UNIX desde o PID 1), `BINFMT_ELF` e `BINFMT_SCRIPT`
- `zswap`: o compressor é escolhido numa initcall, antes de o systemd do initramfs carregar o `MODULES`. `CRYPTO_ZSTD` (e `CRYPTO_LZ4`, `CRYPTO_LZO`) é y na base e fica; as entradas de `MODULES` não têm efeito
- descompressores de initramfs: só `RD_ZSTD` (a UKI usa zstd); os outros `RD_*` saem. Se a `COMPRESSION` do mkinitcpio mudar, religar o `RD_*` correspondente, senão a UKI não inicia
- `CRYPTO_MODULES`: sem ela, o `sd-encrypt` põe na UKI todos os módulos de criptografia, que com modularização máxima são dezenas. A variável não é documentada, mas o `sd-encrypt` a lê da configuração (pode ficar em `/etc/mkinitcpio.conf.d/`); para `aes-xts-plain64`, a lista mínima seria `aesni_intel xts`. Conferir com `mkinitcpio -v` e um boot de teste, com outro kernel à mão
- sem UKI fallback (preset sem `autodetect`): ela incluiria todos os módulos de bloco, USB host, HID, input, criptografia e sistemas de arquivos, e cresceria com a modularização. Os outros dois kernels fazem esse papel, e a ESP compartilhada com o Windows não tem espaço para mais uma UKI
- `MODULES_DECOMPRESS="yes"`: módulos e firmware são descomprimidos e entram na compressão zstd da imagem, o que reduz a UKI com o nível 19. O firmware no disco continua em zstd (`FW_LOADER_COMPRESS_ZSTD=y`)

### 33.4 Performance

Prioridade alta, mas não acima da segurança. Evitar:

- debug desnecessário (quando o Kconfig desencoraja), test drivers e simuladores
- tracing não usado (o powertop precisa dos eventos de perf e tracepoints)
- trabalho periódico inútil
- mecanismos térmicos/energia desnecessários que reduzam desempenho (exceto quando aumentam a confiabilidade do hardware)
- drivers guest no host, qdiscs/classifiers não usados, drivers grandes de hardware impossível

Mas não sacrificar funcionalidade real por poucos KB.

### 33.5 Segurança

**Preferir configurações que:** reduzam superfície de ataque, evitem raw access e flash/firmware raw desnecessários, removam interfaces userspace antigas e test/debug sem uso, e funcionem com Secure Boot. Os casos concretos (GPIO, i2c-dev, SPI, thermal emulation, LIRC, watchdogs) estão nas seções respectivas.

**LSMs ativos:** `capability,landlock,lockdown,yama,bpf`.

**systemd:** a seção REQUIREMENTS do README do systemd (cgroup v2, BPF, seccomp, namespaces, entre outras) é referência obrigatória.

**Disciplinas de linha (tty) em uso:** só `n_tty` e `n_null`: `LDISC_AUTOLOAD` desligado não quebra nada.

**Decisões do fragmento, pela regra das alavancas de segurança da seção 0:**

- da base, mantidas: `X86_KERNEL_IBT`, shadow stack, `INIT_STACK_ALL_ZERO`, `INIT_ON_ALLOC_DEFAULT_ON`, `HARDENED_USERCOPY`, `FORTIFY_SOURCE`, `SLAB_FREELIST_RANDOM`/`_HARDENED`, `SLAB_BUCKETS`, `RANDOMIZE_KSTACK_OFFSET_DEFAULT`, `STACKPROTECTOR_STRONG`, `SECURITY_DMESG_RESTRICT`, `BPF_UNPRIV_DEFAULT_OFF`, `BPF_JIT_ALWAYS_ON`, `DEFAULT_MMAP_MIN_ADDR=65536`, todas as mitigações de CPU da Intel e as comuns
- ligadas: `INIT_ON_FREE_DEFAULT_ON` (o mais caro; `init_on_free=0` na linha de comando desliga para medir), `ZERO_CALL_USED_REGS`, `SLAB_MERGE_DEFAULT` desligado, `KMALLOC_PARTITION_CACHES`, `PROC_MEM_NO_FORCE`, `MODULE_SIG_FORCE` (18), `SECURITY_LOCKDOWN_LSM_EARLY`
- UBSAN: `UBSAN_BOUNDS`, `UBSAN_SHIFT`, `UBSAN_DIV_ZERO`, `UBSAN_BOOL` e `UBSAN_ENUM`, sem `UBSAN_TRAP` (escolha do usuário): todos só avisam no dmesg (`UBSAN: ...`), inclusive nos módulos do DKMS, compilados com as mesmas flags. Sem o trap, um acesso fora dos limites de um array não é bloqueado; com ele, comportamentos inofensivos derrubariam o kernel ou o nvidia
- interfaces e acesso bruto removidos: `DEVMEM` (32), `DEVPORT`, `X86_IOPL_IOPERM`, `HIBERNATION_SNAPSHOT_DEV` (`/dev/snapshot`, sem uswsusp), `KEXEC`/`KEXEC_FILE`/`CRASH_DUMP`/`KEXEC_HANDOVER`/`LIVEUPDATE`, `X86_X32_ABI`, `LDISC_AUTOLOAD`, `NVRAM`, `EFI_HANDOVER_PROTOCOL`, `MODULE_FORCE_LOAD`/`_UNLOAD`, `SND_OSSEMUL`, `ACPI_EC_DEBUGFS`; com `EXPERT`: `UID16`, `SGETMASK_SYSCALL`, `X86_VSYSCALL_EMULATION`, `EFI_RUNTIME_MAP`, `FIRMWARE_MEMMAP`, `GPIO_CDEV`
- superfície de ataque reduzida: LSMs compilados fora da lista ativa (`SECURITY_SMACK`, `_TOMOYO`, `_LOADPIN`, `_SAFESETID`, `_IPE`; AppArmor e SELinux ficam), descompressores de initramfs além do zstd, tabelas de partição além de GPT e MBR (AIX, Mac, BSD, Minix, Solaris, LDM, Karma), protocolos de rede de datacenter/BMC/roteador (DCB, MCTP, NC-SI, MPLS, PSP, switchdev, netkit, SRv6, RPL, IOAM, MRP, CFM), `BSD_PROCESS_ACCT`, `CGROUP_RDMA`, `ACCESSIBILITY`
- em N porque o Kconfig manda: `BUG_ON_DATA_CORRUPTION` e `PANIC_ON_OOPS` ("If unsure, say N"), `PAGE_TABLE_CHECK` ("If unsure say n"), `STRICT_SIGALTSTACK_SIZE` ("Say 'N' unless you want to really enforce"), `IMA` e `EVM`, `SYSFS_SYSCALL`, os `DEBUG_*` de desenvolvimento
- ligada por decisão do usuário apesar do Kconfig ("Say 'N' for more sensitive systems"): `ALLOW_DEV_COREDUMP` (31)
- desligadas porque quebrariam usos declarados: `STATIC_USERMODEHELPER` (o modprobe dos módulos sob demanda e o systemd-coredump passariam por um binário intermediário que o Arch não tem), lockdown em integrity/confidentiality (hibernação, 18), `SECURITY_LOADPIN` (só aceitaria módulos e firmware do initramfs), `MODIFY_LDT_SYSCALL` e `X86_16BIT` (Wine, 17), `INTEGRITY_CA_MACHINE_KEYRING` (as MOKs não têm keyUsage, 18), `IO_URING` e `KCMP` (usados; o `KCMP` é exigido pelo systemd e selecionado pelo DRM)
- indisponíveis com GCC: kCFI (o GCC 16.2 não aceita `-fsanitize=kcfi`), `KSTACK_ERASE` (exige o callback de profundidade de pilha do Clang) e `RANDSTRUCT` (quebraria os módulos DKMS com objetos pré-compilados)

**Mecanismos de segurança em uso:** Secure Boot com MOK (18), TPM 2.0 (19), `firewalld`/`nftables` (6), fwupd e ClamAV. O ClamAV faz varredura sob demanda, mas a varredura em tempo real (`clamonacc`) pode vir a ser usada: ela depende de `FANOTIFY` e `FANOTIFY_ACCESS_PERMISSIONS`, que ficam.

### 33.6 Debug

- **objetivo do usuário:** diagnosticar erros causados pelas escolhas de compilação e erros gerais dos programas em uso. Não manter debug só por existir
- ficam: `IKCONFIG`/`IKCONFIG_PROC` (`/proc/config.gz`, para comparar com o zen), `KALLSYMS`/`KALLSYMS_ALL` (nomes de funções nos oops), `PRINTK_TIME`, `DYNAMIC_DEBUG`, `MAGIC_SYSRQ`, pstore (`PSTORE`, `EFI_VARS_PSTORE` com o backend ligado, `PSTORE_COMPRESS`), `FTRACE`/`FUNCTION_TRACER`, `KPROBES`/`KPROBE_EVENTS`/`UPROBE_EVENTS`, `PERF_EVENTS`, `BPF_SYSCALL`/`BPF_EVENTS` (bpftrace), `DEBUG_FS`, `COREDUMP` (`coredumpctl`), os tracers de latência (`HWLAT_TRACER`, `OSNOISE_TRACER`, `TIMERLAT_TRACER`), `ACPI_DEBUG`, `PM_DEBUG`, `PROC_KCORE` (perf e drgn), `SLUB_DEBUG` (desligado em runtime), o debug do iwlwifi, `DPM_WATCHDOG`, `DEBUG_NMI_SELFTEST`, kmemleak desligado por padrão e o UBSAN (33.5)
- `DEBUG_INFO_BTF` fica porque o systemd usa o BPF LSM, que exige BTF; com `DEBUG_INFO_COMPRESSED_ZSTD`. O DWARF (decodificar linha de código, drgn completo, `crash`, `perf probe` com variáveis) não é necessário: `_STRIP="true"` com o BTF religado pelo fragmento, e um build com `_STRIP="false"` e `_NUKR="false"` só se um bug do kernel precisar ser decodificado
- erros de programas não dependem do debug do kernel: os símbolos dos pacotes do Arch vêm pelo debuginfod
- saem: `X86_DECODER_SELFTEST`, `DEBUG_RODATA_TEST`, `DEBUG_SHIRQ`, `RUNTIME_TESTING_MENU`, `FUNCTION_ERROR_INJECTION`, `BLK_ERROR_INJECTION`, `MMIOTRACE` ("If you are not helping to develop drivers, say N"), `USB_XHCI_DBGCAP`/`EARLY_PRINTK_USB_XDBC` e `EARLY_PRINTK_DBGP` (exigem cabo de debug e outro computador), `OVMF_DEBUG_LOG` (só em VM), `MEDIA_TEST_SUPPORT`, `LOCK_EVENT_COUNTS` e `X86_CPA_STATISTICS` (contadores em caminhos quentes que ninguém lê), `USB_STORAGE_DEBUG`, kdump
- Magic SysRq com todas as funções (`kernel.sysrq = 1` em `/etc/sysctl.d/sysrq.conf`; o padrão do systemd libera só o sync), para recuperar travamentos com REISUB

### 33.7 Hardware específico > nome genérico

**Basear decisões em:**

- `lspci -knnQ`, `lsusb`, IDs ACPI, sysfs, driver carregado, codecs ALSA, hwmon, DMI
- `/sys/class/watchdog`, ACPI WDAT, SoundWire sysfs, TPM sysfs/ACPI, power_supply sysfs, `lsmod`, `/proc/cpuinfo`
- dispositivos ACPI presentes: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" != 0 ] && echo "$(cat $d/hid 2>/dev/null) ${d##*/}"; done | sort -u`
- driver de cada dispositivo ACPI presente: `for d in /sys/bus/acpi/devices/*; do [ "$(cat $d/status 2>/dev/null || echo 15)" = 0 ] && continue; a=$(readlink $d/driver); b=$(readlink $d/physical_node/driver); echo "${d##*/} acpi:${a##*/} phys:${b##*/}"; done 2>/dev/null | grep -v '^device:\|^ACPI0007\|^LNX'`
- drivers de plataforma com dispositivo ligado (a lista de `/sys/bus/platform/drivers` sozinha mostra todos os drivers registrados): `for d in /sys/bus/platform/drivers/*; do [ -n "$(find "$d" -maxdepth 1 -type l ! -name module)" ] && echo "${d##*/}"; done`
- programas que usam um protocolo netlink (por exemplo, o connector, protocolo 11): `awk 'NR>1 && $2==11 {print $3}' /proc/net/netlink | sort -u` (só `0` significa só o kernel)
- `modprobed-db`, para registrar os módulos carregados ao longo de semanas
- outros comandos que possam extrair mais informações sobre o sistema

Não assumir pelo nome. Exemplos:

- Alder Lake pinctrl é correto para Raptor Lake HX
- NVIDIA GPU I2C não é necessário só por haver NVIDIA
- Intel PCH thermal antigo não é necessário só por haver PCH Intel
- Intel USBIO GPIO não é necessário só por ser Intel
- ChromeOS EC não é necessário só porque o laptop tem EC
- PMIC drivers não são necessários só por haver bateria
- VirtIO frontend não é necessário só porque o host roda QEMU

Em caso de dúvidas, perguntar ao usuário (fornecer comandos para obter novas informações); nunca inventar ou assumir hardware.

### 33.8 Host vs guest

O kernel é o host físico Alienware e não será usado em guests. Não habilitar: Hyper-V guest, Xen frontend, VirtIO frontend, VMware guest, KVM guest PTP, GPIO/I2C virtuais.

## 34. Precedência das informações

- Dados medidos mais recentes enviados pelo usuário
- Decisão mais recente do chat
- Decisão anterior do chat
- Este documento
- Conhecimento genérico, somente se o usuário pedir nova recomendação

Nunca deixar um `.myfrag` antigo prevalecer sobre uma decisão posterior explícita.

## 35. Resumo operacional

**Este é um:**

- Alienware m16 R1, BIOS 1.36.0
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
- swapfile Btrfs 16 GiB + `zswap` (zstd) + hibernação (lz4, sem `resume=`) + S3
- dGPU com RTD3 (pode desligar); iGPU como padrão
- Secure Boot + shim + MOK + UKI + `mkinitcpio`
- TPM 2.0 CRB
- iTCO watchdog
- webcam UVC
- QEMU/KVM/libvirt + passthrough (GPU, NVMe, USB, TPM físico) + Looking Glass (`kvmfr`) + hugepages + TPM emulado (VM do Windows 10)
- WireGuard/OpenVPN/`firewalld`/`nftables`
- Arduino/ESP32/RPi e USB serial comum
- interfaces de áudio USB/MIDI
- Canon E4210 via IPP/CUPS/SANE/Avahi
- Xbox/PlayStation/Steam Controller
- Android/iPhone
- armazenamento/rede USB externa
- CPU undervolt via `intel-undervolt`; GPU ajustada via NVML
- quatro perfis customizados do `tuned` (32A): balanced, balanced-battery, performance e battery; thermald desabilitado

**Prioridades (na ordem da seção 0):**

- preservar usos já declarados
- segurança (todas as alavancas, salvo "If unsure, say N" e usos quebrados)
- performance
- hardware real (remover o ausente)
- modularização
- minimalismo
