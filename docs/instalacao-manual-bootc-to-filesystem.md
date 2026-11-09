# Instalação manual com `bootc install to-filesystem`

Este guia mostra como instalar a imagem deste projeto em um disco já preparado
manualmente, usando BTRFS com os subvolumes `root` e `home`. É o caminho
indicado quando você quer controle sobre o particionamento — por exemplo, para
usar LUKS, RAID, um layout BTRFS específico ou automatizar a instalação.

> [!NOTE]
> Para a maioria dos casos, a instalação pela ISO com o Anaconda é mais simples.
> Use este guia quando precisar de um layout diferente do padrão da ISO. Veja
> também [`instalador-anaconda-webui.md`](instalador-anaconda-webui.md) e
> [`instalador-anaconda-gtk.md`](instalador-anaconda-gtk.md).

## Como o processo funciona

O `bootc install to-filesystem` não particiona nem formata o disco: ele recebe
um sistema de arquivos **já montado e vazio** e grava a imagem nele. O fluxo é:

1. particionar e formatar o disco;
2. montar a raiz, `/boot` e `/boot/efi` em `/mnt`;
3. rodar o container da imagem e executar o `bootc install to-filesystem`;
4. montar a instalação recém-criada para ajustar o `/etc/fstab`;
5. finalizar e desmontar;
6. reiniciar no sistema instalado.

O `--skip-finalize` é usado de propósito no passo 3: ele deixa a instalação
gravável para que o `/etc/fstab` seja ajustado antes da finalização.

## Layout que será criado

| Ordem | Exemplo SATA/virtio | Exemplo NVMe | Tamanho sugerido | Tipo | Ponto de montagem |
| --- | --- | --- | --- | --- | --- |
| 1 | `/dev/sda1` | `/dev/nvme0n1p1` | 512 MB – 1 GB | `vfat` (EFI System) | `/boot/efi` |
| 2 | `/dev/sda2` | `/dev/nvme0n1p2` | 1 GB | `ext4` | `/boot` |
| 3 | `/dev/sda3` | `/dev/nvme0n1p3` | restante do disco | `btrfs` | `/` (`subvol=root`) e `/var/home` (`subvol=home`) |

> [!IMPORTANT]
> A numeração muda conforme o tipo de disco:
>
> - **SATA, USB e virtio** (`/dev/sda`, `/dev/vdb`): as partições são
>   `/dev/sda1`, `/dev/sda2`, `/dev/sda3`.
> - **NVMe** (`/dev/nvme0n1`) e **MMC/SD** (`/dev/mmcblk0`): existe um `p`
>   antes do número: `/dev/nvme0n1p1`, `/dev/nvme0n1p2`, `/dev/nvme0n1p3`.
>
> Não remova o `p` em NVMe/MMC e não o adicione em SATA/USB/virtio.

O `/var` não precisa de uma entrada própria: o bootc transforma `/var` em um
bind do estado persistente da implantação automaticamente. No sistema
instalado, `/home` é um link simbólico para `/var/home` — por isso o subvolume
`home` é montado em `/var/home`.

## Pré-requisitos

- Um ambiente live ou de resgate Linux com `podman` e `bootc` instalados.
- Acesso de root.
- Espaço e rede suficientes para baixar a imagem do GHCR.
- Backup de qualquer dado no disco de destino. **O disco será apagado.**

Em um live Fedora, instale as ferramentas necessárias:

```bash
sudo dnf install -y podman bootc btrfs-progs dosfstools e2fsprogs util-linux
```

> [!WARNING]
> Confirme o nome do disco com `lsblk` antes de qualquer comando. Um nome
> errado destrói o disco errado. Este guia usa `/dev/nvme0n1` e `/dev/sda` como
> exemplos; no seu computador o disco pode ser `/dev/vdb`, `/dev/sdb`,
> `/dev/mmcblk0` etc.

Se a imagem for privada no GHCR, faça login no ambiente live:

```bash
sudo podman login ghcr.io
```

## Passo 1 — Identificar o disco e criar as partições

Liste os discos e identifique o **disco inteiro** (sem número de partição):

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Exemplos de nome do disco:

| Tipo de disco | Nome do disco | Nome das partições |
| --- | --- | --- |
| SATA, USB ou virtio | `/dev/sda`, `/dev/vdb` | `/dev/sda1`, `/dev/sda2`, `/dev/vdb1` etc. |
| NVMe | `/dev/nvme0n1` | `/dev/nvme0n1p1`, `/dev/nvme0n1p2` etc. |
| MMC/SD | `/dev/mmcblk0` | `/dev/mmcblk0p1`, `/dev/mmcblk0p2` etc. |

Defina as variáveis de acordo com o seu disco. Para **NVMe**:

```bash
# Troque pelo disco NVMe detectado no lsblk
DISK=/dev/nvme0n1
ESP=${DISK}p1
BOOT=${DISK}p2
ROOT=${DISK}p3
```

Para **SATA, USB ou virtio**:

```bash
# Troque /dev/sda pelo seu disco (por exemplo, /dev/vdb)
DISK=/dev/sda
ESP=${DISK}1
BOOT=${DISK}2
ROOT=${DISK}3
```

> [!IMPORTANT]
> Em NVMe e MMC existe um `p` antes do número da partição
> (`/dev/nvme0n1p1`). Em SATA, USB e virtio não existe
> (`/dev/sda1`). Use a variante que corresponde ao seu disco.

Crie a tabela **GPT** e três partições:

```bash
sudo cfdisk "$DISK"
```

No `cfdisk`:

1. **EFI System** — 512 MB a 1 GB.
2. **Linux filesystem** — 1 GB, para o `/boot`.
3. **Linux filesystem** — o restante do disco, para o BTRFS.

Grave a tabela e saia do `cfdisk`. Confira se as variáveis apontam para as
partições corretas:

```bash
echo "ESP=$ESP"
echo "BOOT=$BOOT"
echo "ROOT=$ROOT"
lsblk -o NAME,SIZE,TYPE,FSTYPE "$DISK"
```

## Passo 2 — Formatar e criar os subvolumes BTRFS

Formate as três partições:

```bash
sudo mkfs.vfat -F 32 -n ESP "$ESP"
sudo mkfs.ext4 -L boot "$BOOT"
sudo mkfs.btrfs -L root "$ROOT"
```

Monte o BTRFS temporariamente e crie os subvolumes `root` e `home`:

```bash
sudo mkdir -p /mnt
sudo mount "$ROOT" /mnt
sudo btrfs subvolume create /mnt/root /mnt/home
sudo umount /mnt
```

> [!TIP]
> Se quiser conferir os subvolumes criados, monte novamente com
> `sudo mount "$ROOT" /mnt` e rode `sudo btrfs subvolume list /mnt`.

## Passo 3 — Montar a estrutura em `/mnt`

Monte o subvolume `root` com compressão zstd, depois `/boot` e `/boot/efi`:

```bash
# Raiz do sistema (subvolume root)
sudo mount -o subvol=root,compress=zstd:1 "$ROOT" /mnt

# /boot em ext4
sudo mount --mkdir "$BOOT" /mnt/boot

# ESP em vfat
sudo mount --mkdir "$ESP" /mnt/boot/efi
```

Confira o resultado:

```bash
findmnt -R /mnt
```

Devem aparecer três montagens: `/mnt`, `/mnt/boot` e `/mnt/boot/efi`.

## Passo 4 — Gravar a imagem com `bootc install to-filesystem`

Descubra os UUIDs que serão usados no `/etc/fstab` e no carregador de boot:

```bash
BOOT_UUID=$(sudo blkid -s UUID -o value "$BOOT")
ROOT_UUID=$(sudo blkid -s UUID -o value "$ROOT")
ESP_UUID=$(sudo blkid -s UUID -o value "$ESP")

echo "BOOT_UUID=$BOOT_UUID"
echo "ROOT_UUID=$ROOT_UUID"
echo "ESP_UUID=$ESP_UUID"
```

Agora rode o container da imagem. O `bootc` é executado **de dentro da própria
imagem** e grava o sistema em `/target` (que é o `/mnt` do host):

```bash
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest

sudo podman run --rm --privileged --pid=host \
  -v /dev:/dev \
  -v /var/lib/containers:/var/lib/containers \
  -v /mnt:/target:rw,z \
  --security-opt label=type:unconfined_t \
  "$IMG" \
  bootc install to-filesystem \
    --skip-finalize \
    --boot-mount-spec="UUID=${BOOT_UUID}" \
    --karg=rootflags=subvol=root,compress=zstd:1 \
    /target/
```

O que cada opção faz:

| Opção | Função |
| --- | --- |
| `--privileged --pid=host` | Permite ao bootc acessar dispositivos e o namespace do host. |
| `-v /dev:/dev` | Expõe os discos ao container. |
| `-v /var/lib/containers:/var/lib/containers` | Dá acesso à imagem que o podman acabou de baixar. |
| `-v /mnt:/target:rw,z` | Monta o destino no container com o rótulo SELinux correto. |
| `--security-opt label=type:unconfined_t` | Evita bloqueios do SELinux durante a escrita no disco. |
| `--boot-mount-spec` | Informa ao bootc qual é a partição de `/boot`. |
| `--karg=rootflags=...` | Garante que o último `rootflags` da linha de comando contenha `subvol=root` e a compressão. |
| `--skip-finalize` | Mantém a instalação gravável para ajustar o `fstab`. |

O `bootc` detecta automaticamente o UUID da raiz e o subvolume em que o destino
está montado, mas a imagem também define argumentos em
`/usr/lib/bootc/kargs.d/` (neste projeto, `config/nvidia/10-nvidia-args.toml`).
Como o kernel usa o **último** `rootflags=` da linha de comando, o `--karg`
acima é explícito e garante que `subvol=root` e `compress=zstd:1` fiquem juntos.
Se você usar outro nome de subvolume, ajuste o valor.

> [!TIP]
> Para exigir assinatura já na instalação, acrescente
> `--enforce-container-sigpolicy` ao `bootc install to-filesystem`. A imagem
> inclui a política e a chave pública, então a instalação falha se a tag não
> estiver assinada corretamente. Veja [`SIGNING.md`](SIGNING.md).

## Passo 5 — Montar a instalação para ajustar o `/etc/fstab`

Crie um diretório e monte a implantação recém-instalada:

```bash
sudo mkdir -p /var/bootc_mount
sudo bootc install mount --sysroot /mnt --latest /var/bootc_mount
```

O `bootc install mount` mostra a raiz como ela ficará no primeiro boot. A raiz
e `/usr` são somente leitura; `/etc` e `/var` são graváveis para que você possa
fazer os ajustes finais.

> [!NOTE]
> Esse comando usa o binário `bootc` do ambiente live, não o do container. Se
> ele não existir, instale com `sudo dnf install bootc`.

## Passo 6 — Escrever o `/etc/fstab`

O `/etc/fstab` define onde `/boot`, `/boot/efi` e o subvolume `home` serão
montados. Use os UUIDs descobertos no passo 4:

```bash
sudo tee /var/bootc_mount/etc/fstab > /dev/null <<EOF
UUID=${ROOT_UUID} / btrfs subvol=root,compress=zstd:1,ro 0 0
UUID=${BOOT_UUID} /boot ext4 ro 1 2
UUID=${ESP_UUID} /boot/efi vfat umask=0077,shortname=winnt 0 2
UUID=${ROOT_UUID} /var/home btrfs subvol=home,compress=zstd:1 0 0
EOF
```

Entenda cada linha:

| Linha | Por que está assim |
| --- | --- |
| `/` com `subvol=root` e `ro` | A raiz do bootc é somente leitura. O `--karg` acima já passa `rootflags=subvol=root`; esta entrada documenta o layout. |
| `/boot` com `ro` | O bootc controla o `/boot`; ele o remonta de forma controlada quando precisa gravar um kernel novo. |
| `/boot/efi` com `umask=0077` | Restringe o acesso à ESP e usa nomes compatíveis com Windows. |
| `/var/home` com `subvol=home` | No sistema, `/home` aponta para `/var/home`; o subvolume `home` fica gravável e comprimido. |

> [!IMPORTANT]
> Não crie uma entrada para `/var` no `fstab`. O bootc mantém `/var` como estado
> persistente da implantação e faz o bind automaticamente. Uma entrada extra
> pode conflitar com esse comportamento.

> [!TIP]
> Se `bootc upgrade` reclamar que `/boot` está somente leitura, troque `ro` por
> `defaults` na linha do `/boot` e rode `sudo systemctl daemon-reload`. A raiz
> deve continuar somente leitura.

## Passo 7 — Finalizar e desmontar

Desmonte a visão usada para editar o `fstab`, rode a finalização e desmonte o
destino:

```bash
sudo umount -R /var/bootc_mount
sudo bootc install finalize /mnt
sudo umount -R /mnt
```

O `bootc install finalize` faz verificações de sanidade, aplica ajustes finais
e prepara a raiz para ser montada somente leitura no boot. Ele é o penúltimo
passo antes de desmontar.

## Passo 8 — Primeiro boot

1. Remova a mídia live (ou altere a ordem de boot na BIOS/UEFI).
2. Inicie pelo disco instalado.
3. No primeiro boot, o `post-install.service` instala os Flatpaks listados em
   `config/flatpak/flatpaks.preinstall`. Isso exige rede e o usuário `fernando`
   existente, conforme a unidade deste projeto.
4. Faça login no GNOME.

Confira a instalação:

```bash
bootc status
findmnt -R /
flatpak list --app
```

O `findmnt` deve mostrar o subvolume `root` em `/`, o `subvol=home` em
`/var/home` e as partições de boot nos lugares certos.

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `Verifying empty rootfs` falha | O `/mnt` não está vazio ou o subvolume errado foi montado. | Desmonte, recrie o subvolume `root` e monte novamente. |
| `No filesystem uuid found` | A partição de destino não foi formatada ou não está montada. | Confira `lsblk` e `findmnt`; formate e monte de novo. |
| O sistema não encontra a raiz no boot | Falta `rootflags=subvol=root` ou o `fstab` está incorreto. | Inicie pelo live, monte a raiz e confira `/proc/cmdline`; garanta um único `rootflags` efetivo com `subvol=root`. |
| O kernel mostra dois `rootflags=` | A imagem define um `rootflags` em `kargs.d` e o bootc adiciona outro. | Passe `--karg=rootflags=subvol=root,compress=zstd:1` (o último vence) ou ajuste o `10-nvidia-args.toml`. |
| `/boot` somente leitura durante `bootc upgrade` | Entrada `ro` no `fstab`. | Troque para `defaults` na linha do `/boot`. |
| O driver NVIDIA não carrega com Secure Boot | Os módulos akmods não estão assinados para o Secure Boot. | Configure MOK/assinatura ou desative o Secure Boot. |
| `bootc install mount: command not found` | O ambiente live não tem o `bootc`. | `sudo dnf install bootc` ou use um live que já o inclua. |
| Erro de assinatura ao instalar | A tag não está assinada ou a política não confere. | Verifique [`SIGNING.md`](SIGNING.md) ou remova `--enforce-container-sigpolicy` para testar. |

## Referências

- [`bootc install to-filesystem`](https://bootc.dev/bootc/bootc-installation.7.html)
- [`bootc install mount`](https://bootc.dev/bootc/man/bootc-install-mount.8.html)
- [Sistema de arquivos do bootc](https://bootc.dev/bootc/bootc-filesystem.7.html)
- [Assinatura e verificação da imagem](SIGNING.md)
