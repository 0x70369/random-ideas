# Digitalização de CDs/DVDs (música, álbuns, shows) — Arch Linux

Procedimento completo: identificação da mídia → extração para FLAC → metadados/organização com MusicBrainz Picard → conversão para Opus.

**Ambiente:** Arch Linux, leitor óptico USB em `/dev/sr0`, área de trabalho em tmpfs montada em `/temp`.

**Sobre mídia gravável (CD-R/DVD-R/DVD+R/RW):** as ferramentas classificam pelo *conteúdo* do disco, não pela gravabilidade — um CD-R de áudio já aparece como `CD-DA`, e um DVD-R/+R/RW como `DVD-R`/`DVD+R`/`DVD-RW` (em vez de `DVD-ROM`), tratados abaixo do mesmo jeito que `DVD-ROM`. A única diferença prática real é que mídia *gravada* (ao contrário de pressada de fábrica) pode ter as pastas `VIDEO_TS`/`AUDIO_TS` e os arquivos `.VOB` em minúsculas, dependendo do software usado para gravar — os comandos abaixo assumem maiúsculas (padrão), então se `ls`/ffmpeg não encontrarem nada, tente de novo com `find -iname` (veja a caixa de aviso no Caso B).

**Scripts prontos:** cada etapa abaixo também existe como um script Bash independente (`00-install-dependencies.bash` a `04-convert-to-opus.bash`), já com esses casos de borda tratados e com pontos de decisão interativos onde o julgamento humano é necessário. Este documento continua valendo como referência do *porquê* de cada comando.

**Árvore final de arquivos:**
```
Artista(s)/Álbum - Ano/[Disco N/]NN - Título.opus
```
- `Various Artists` no lugar do artista quando o álbum tiver múltiplos artistas (os artistas individuais ficam nos metadados de cada faixa).
- `Disco N` só existe em álbuns com mais de um disco.
- Ano = ano de lançamento oficial, quando disponível.

---

## 0. Pacotes necessários (instalar uma vez)

```bash
sudo pacman -S --needed libcdio cdparanoia flac ffmpeg libdvdcss dvdbackup \
                        lsdvd ogmtools \
                        picard chromaprint opus-tools
```

Para DVD-Audio (AUDIO_TS), via AUR (ex.: `paru`):
```bash
paru -S libdvd-audio
```
Se falhar (suporte a MLP é fraco e o projeto está parado desde 2017), alternativa proprietária/paga: `dvdae-bin` (AUR).

---

## 1. Identificar o tipo de mídia

Com o disco no drive:

```bash
cd-info --dvd /dev/sr0
```

Leia a linha `Disc mode is listed as:`

| Saída | Significado | Próximo passo |
|---|---|---|
| `CD-DA` | CD de áudio (pressado ou CD-R) | Caso A |
| `DVD-ROM`, `DVD-R`, `DVD-RW`, `DVD+R`, `DVD+RW`, `DVD-RAM` | DVD (pressado ou gravado) — falta saber se é Vídeo ou Audio | ver abaixo |

Se `cd-info` falhar (drive ocupado por automount):
```bash
udevadm info --query=property --name=/dev/sr0 | grep ID_CDROM_MEDIA
```

**Só se for DVD**, descubra o tipo real:
```bash
mkdir -p /temp/disc && sudo mount -o ro /dev/sr0 /temp/disc
ls /temp/disc
sudo umount /temp/disc
```
- `VIDEO_TS` com arquivos → **Caso B** (DVD-Vídeo — a maioria dos shows).
- `AUDIO_TS` com arquivos → **Caso C** (DVD-Audio — raro).
- Ambos com conteúdo (híbrido) → use o `AUDIO_TS` (é lossless).

---

## 2. Extrair para FLAC

### Caso A — CD-DA

```bash
mkdir -p /temp/rip && cd /temp/rip
cdparanoia -B -d /dev/sr0
ls *.wav | xargs -P"$(nproc)" -I{} flac --best --delete-input-file {}
```
- `-B` = um arquivo por faixa.
- `cdparanoia` não paraleliza (gargalo é o drive girando o disco); a conversão WAV→FLAC sim, um processo por núcleo.

**Sobre os gaps:** o silêncio entre faixas (pregap) é gravado, por convenção de todo ripper, colado no **fim da faixa anterior**. Cortá-lo é destrutivo (perde cauda de reverb/aplauso em discos ao vivo ou gapless). Se ainda assim quiser eliminar apenas o silêncio final:
```bash
for f in *.flac; do
  ffmpeg -i "$f" -af "areverse,silenceremove=start_periods=1:start_threshold=-60dB,areverse" "cut-$f"
done
```
Teste em um disco antes de aplicar em toda a coleção.

### Caso B — DVD-Vídeo (shows)

```bash
sudo dvdbackup -i /dev/sr0 -M -o /temp
```
Isso cria `/temp/<NOME_DO_DISCO>/VIDEO_TS/`.

> **Se `VIDEO_TS` não existir com esse nome exato** (comum em DVD-R/+R gravados com software menos rigoroso): ache o nome real com `find /temp/<NOME_DO_DISCO> -maxdepth 1 -iname VIDEO_TS`, e use o caminho retornado no lugar de `VIDEO_TS` em todos os comandos abaixo. O mesmo vale para os arquivos `.VOB` — troque `ls -lh .../VTS_*.VOB` por `find .../VIDEO_TS -iname 'VTS_*.VOB'` se a busca normal não achar nada.

**Sobre `ffmpeg -f dvdvideo`:** esse demuxer (baseado em `libdvdnav`/`libdvdread`) documenta que "seeking não é suportado" e, na prática, pode falhar em ler até o primeiro capítulo de uma pasta `VIDEO_TS` comum, com erros de leitura de bloco corrompidos. É um recurso recente (2024) do ffmpeg e ainda instável para esse uso. Por isso o fluxo abaixo usa `lsdvd`/`dvdxchap` só para **ler** metadados (que funciona bem, é a mesma biblioteca só que sem navegação) e extrai o áudio direto dos arquivos `.VOB` do título — que são MPEG-PS puro, sem precisar de biblioteca de DVD nenhuma.

Veja os títulos, capítulos e faixas de áudio disponíveis:
```bash
lsdvd -a "/temp/<NOME_DO_DISCO>"
```
Escolha a faixa de áudio por qualidade: `lpcm` (lossless) > `dts`/`ac3` (lossy), desempatando por bitrate/canais. Depois, veja os `.VOB` do título (geralmente `VTS_NN_*.VOB` com o mesmo número `NN` do título):
```bash
ls -lh "/temp/<NOME_DO_DISCO>/VIDEO_TS"/VTS_*.VOB
```

Extraia o título inteiro como um único FLAC, concatenando seus `.VOB` (ajuste `NN` e o índice da faixa de áudio):
```bash
ffmpeg -i "concat:/temp/<NOME_DO_DISCO>/VIDEO_TS/VTS_NN_1.VOB|/temp/<NOME_DO_DISCO>/VIDEO_TS/VTS_NN_2.VOB" \
  -map 0:a:0 -vn -c:a flac /temp/rip/whole-title.flac
```

Pegue os tempos exatos de cada capítulo com `dvdxchap` (mesma biblioteca de leitura do `lsdvd`, sem os problemas do demuxer `dvdvideo`):
```bash
dvdxchap -t 3 "/temp/<NOME_DO_DISCO>"
# CHAPTER01=00:00:00.000
# CHAPTER02=00:04:12.240
# ...
```

E corte o FLAC único em um arquivo por capítulo, usando esses tempos como `-ss`/`-to`:
```bash
ffmpeg -ss 00:00:00.000 -to 00:04:12.240 -i /temp/rip/whole-title.flac -c:a flac /temp/rip/01.flac
ffmpeg -ss 00:04:12.240                  -i /temp/rip/whole-title.flac -c:a flac /temp/rip/02.flac
# (sem -to no último capítulo, para ir até o fim)
```
Não vale a pena paralelizar esse fluxo — cada corte depende do arquivo único gerado antes dele.

**Nota:** se a única faixa disponível for AC3/DTS, a origem já é lossy; o FLAC apenas guarda o decodificado sem adicionar perda, mas não recupera o que já foi descartado no disco.

### Caso C — DVD-Audio (AUDIO_TS)

> Mesmo aviso do Caso B: se `AUDIO_TS` não existir com esse nome exato em mídia gravada, ache o nome real com `find /temp/disc -maxdepth 1 -iname AUDIO_TS` e use esse caminho no lugar de `AUDIO_TS` abaixo.

```bash
sudo mount -o ro /dev/sr0 /temp/disc
dvda-debug-info -A /temp/disc/AUDIO_TS      # lista títulos e faixas
mkdir -p /temp/rip && cd /temp/rip
dvda2wav -A /temp/disc/AUDIO_TS
ls *.wav | xargs -P"$(nproc)" -I{} flac --best --delete-input-file {}
sudo umount /temp/disc
```

---

## 3. Metadados e organização (MusicBrainz Picard)

### 3.1 Configurar uma vez (Editar ▸ Opções)

**Naming ▸ File Naming Script Editor** — cole:
```
$if($eq(%albumartist%,Various Artists),Various Artists,%albumartist%)/%album% - $if2($left(%originaldate%,4),$left(%date%,4))/$if($gt(%totaldiscs%,1),Disco %discnumber%/,)$num(%tracknumber%,2) - %title%
```

**File Naming (tela principal):**
- ✅ Rename files when saving
- ✅ Move files when saving → Destination directory: `/temp/final`
- ✅ Delete empty directories
- ❌ Replace non-ASCII characters (deixar desmarcado, preserva acentos)

**Cover Art:**
- ✅ Embed cover images into tags
- ✅ Embed only a single front image

Clique **Make It So**.

### 3.2 Fluxo de trabalho, álbum por álbum

1. **Arquivo ▸ Adicionar pasta** → `/temp/rip/<esse álbum>` (um álbum de cada vez).
2. Clique **Cluster**.
3. Clique **Scan** (fingerprint via AcoustID). Funciona bem para lançamentos comerciais de estúdio.
4. **Se não achar** (comum em shows/bootlegs fora do MusicBrainz): busque manualmente por artista/título no painel direito e arraste o cluster para cima do resultado.
5. Confira a lista de faixas à direita contra a extraída à esquerda — é aqui que se verifica se a ordem dos capítulos do DVD bate com a numeração oficial.
6. Confira a capa na aba **Cover Art**.
7. `Ctrl+S` — o Picard move e renomeia para `/temp/final/...`.

---

## 4. Converter para Opus

```bash
find /temp/final -type f -iname '*.flac' -print0 |
  xargs -0 -P"$(nproc)" -I{} bash -c '
    f="$1"
    channels="$(metaflac --show-channels "$f" 2>/dev/null | tail -n1 | tr -cd "0-9")"
    if ! [[ "$channels" =~ ^[0-9]+$ ]] || [[ "$channels" -lt 1 ]]; then
        echo "Failed: $f (metaflac did not return a clean channel count: [$channels])" >&2
        exit 0
    fi
    bitrate=$(( channels * 256 ))
    out="${f%.flac}.opus"
    errfile="$(mktemp)"
    if opusenc --bitrate "$bitrate" "$f" "$out" >"$errfile" 2>&1; then
        rm -- "$f"
    else
        echo "Failed: $f (channels=$channels bitrate=$bitrate) -- full output below:" >&2
        cat "$errfile" >&2
    fi
    rm -f "$errfile"
  ' _ {}
```

**Por quê:**
- `channels=$(... | tail -n1 | tr -cd "0-9")` e a validação com `[[ "$channels" =~ ^[0-9]+$ ]]`: na primeira versão deste fluxo, um `channels` vazio ou não-numérico virava um `--bitrate` inválido, e o `opusenc` falhava silenciosamente (imprimia sua tela de ajuda) sem dizer por quê. Isso já aconteceu na prática — vale manter a validação.
- `errfile="$(mktemp)"` **por processo**: uma primeira tentativa de capturar o erro usou um nome de arquivo fixo (`opusenc-error.tmp`), e com vários processos em paralelo escrevendo no mesmo arquivo ao mesmo tempo, um pisava no outro. `mktemp` gera um arquivo exclusivo por invocação.
- `br=$(( ch * 256 ))`: o teto técnico do `opusenc` é 256 kbit/s **por canal**, mas o parâmetro `--bitrate` espera o valor **total** — por isso multiplicamos pelo número de canais (2 em estéreo → 512; 6 em 5.1 → 1536).
- VBR é o modo padrão (não precisa especificar) — dá mais qualidade por bit que CBR, sem teto artificial de tamanho.
- Complexidade (`--comp`) já é 10 (máxima) por padrão.
- Nenhuma flag `--discard-comments`/`--discard-pictures` é usada: por padrão o `opusenc` já copia os comentários Vorbis (artista, álbum, faixa, ano) e a capa embutida do FLAC de entrada.
- `if opusenc ...; then rm -- "$f"; else ...`: só apaga o FLAC se a conversão terminou sem erro.
- `-P"$(nproc)"`: um processo por núcleo — é aqui que a CPU é de fato o gargalo, ao contrário da extração (gargalo é o drive óptico).

Ao final, `/temp/final` contém só os `.opus` na árvore `Artista(s)/Álbum - Ano/[Disco N/]NN - Título.opus`, pronta para mover para fora do tmpfs.

---

## Apêndice A — Lossless vs. lossy (áudio de CD/DVD)

**Lossless:**
| Formato | Onde aparece |
|---|---|
| PCM / LPCM | CD-DA, DVD-Vídeo, DVD-Audio |
| MLP | DVD-Audio |
| FLAC | gerado por nós, não nativo de disco |

**Lossy:**
| Formato | Onde aparece |
|---|---|
| DTS (núcleo clássico, DTS-ES, DTS 96/24) | DVD-Vídeo, DVD-Audio |
| Dolby Digital / AC-3 | DVD-Vídeo |
| MPEG-1/2 Audio Layer 2 | DVD-Vídeo (comum em discos europeus) |

(DTS-HD Master Audio, Dolby TrueHD e DTS-HD High Resolution só existem em Blu-ray/HD DVD — não se aplicam a um leitor de CD/DVD comum.)

## Apêndice B — Onde multithreading ajuda

| Etapa | Paraleliza? | Motivo |
|---|---|---|
| `cdparanoia` | Não | Gargalo é o drive girando o disco |
| `dvdbackup` | Não | Gargalo é I/O do drive |
| Extração do título em DVD-Vídeo (`concat` de VOBs) | Não vale a pena | Cada corte de capítulo depende do arquivo único gerado antes |
| `dvda2wav` | Não | Ferramenta single-thread |
| `flac` (WAV→FLAC) | Sim, por arquivo | Cada faixa é independente |
| Picard (Scan) | Já é paralelo internamente | — |
| `opusenc` (FLAC→Opus) | Sim, por arquivo | Maior uso real de CPU do fluxo inteiro |
