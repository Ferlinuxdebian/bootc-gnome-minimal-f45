# Instalador Anaconda (GTK)

Este documento descreve como gerar uma ISO live do Fedora 45 com o instalador
**Anaconda GTK** (legado) para instalar a imagem bootc deste projeto. A ISO é
produzida com a ferramenta unificada `image-builder`, no formato
`bootc-generic-iso`.

> [!NOTE]
> O projeto `bootc-image-builder` foi descontinuado em favor do `image-builder`.
> Para o instalador novo, baseado em WebUI/Cockpit, veja
> [`instalador-anaconda-webui.md`](instalador-anaconda-webui.md). O GTK continua
> útil para compatibilidade, automação e ambientes em que a WebUI não é
> desejada.

## Como funciona

A ISO gerada não contém o sistema inteiro: ela contém um ambiente live com o
Anaconda e um kickstart padrão que aponta para a imagem bootc que será
instalada. Durante a instalação, o Anaconda baixa a imagem do registry e a
grava no disco usando o `bootc`.

O fluxo é:

1. criar um `Containerfile` que instala o Anaconda e os utilitários de ISO;
2. construir esse container como uma imagem local;
3. pedir ao `image-builder` para transformar esse container em ISO;
4. iniciar a ISO em uma máquina virtual ou física;
5. concluir o assistente do Anaconda;
6. reiniciar no sistema instalado.

## Pré-requisitos

- Fedora 45 no host de build (ou versão compatível).
- `podman` instalado, com suporte a heredocs no `Containerfile` (os blocos
  `COPY <<EOT` usam esse recurso).
- `image-builder` instalado. Consulte a documentação do osbuild para o pacote
  da sua distribuição; em Fedora, normalmente está disponível nos repositórios
  oficiais.
- Espaço em disco para a imagem do container e para a ISO (alguns GB).
- Acesso ao GHCR, caso a imagem de destino seja privada.
- `sudo`, pois o build e a geração da ISO precisam de root.

## Containerfile

Salve o conteúdo abaixo em um arquivo chamado `Containerfile`. Ele é uma
adaptação do exemplo oficial do osbuild para Fedora 45.

```dockerfile
FROM quay.io/fedora/fedora-bootc:45

# Imagem que o Anaconda vai instalar e usar nas atualizações seguintes.
# Pode ser sobrescrita no build com --build-arg CONTAINER_NAME=...
ARG CONTAINER_NAME=localhost/my-bootc-image:latest

# Ferramentas do instalador e da mídia live.
RUN dnf5 install -qy \
    anaconda \
    anaconda-install-img-deps \
    anaconda-dracut \
    dracut-config-generic \
    dracut-network \
    net-tools \
    grub2-efi-x64-cdboot \
    plymouth \
    default-fonts-core-sans \
    default-fonts-other-sans \
    google-noto-sans-cjk-fonts \
    xorrisofs \
    squashfs-tools \
    jq && \
    dnf5 clean all

# Copia os binários EFI para o local esperado pelo image-builder.
RUN mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi

# Menu de boot da ISO.
RUN mkdir -p /usr/lib/image-builder/bootc
COPY <<EOT /usr/lib/image-builder/bootc/iso.yaml
label: "Custom-Fedora-Installer"
grub2:
  entries:
    - name: "Install Fedora (bootc)"
      linux: "/images/pxeboot/vmlinuz inst.stage2=hd:LABEL=Custom-Fedora-Installer console=tty0 inst.graphical selinux=0 rhgb quiet"
      initrd: "/images/pxeboot/initrd.img"
EOT

# Ativa o modo de instalação bootc no Anaconda. O kickstart abaixo define
# a imagem de origem (source) e a imagem usada nas atualizações (target).
RUN mkdir -p /usr/share/anaconda && \
    echo "bootc --source-imgref registry:${CONTAINER_NAME} --target-imgref ${CONTAINER_NAME}" > /usr/share/anaconda/interactive-defaults.ks

# Ajustes mínimos do ambiente do Anaconda (normalmente feitos pelo lorax).
RUN echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >> /etc/passwd && \
    echo "install::14438:0:99999:7:::" >> /etc/shadow && \
    passwd -d root

RUN mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives && \
    mv /usr/share/dnf5/repos.d /etc/anaconda.repos.d && \
    ln -s /lib/systemd/system/anaconda.target /etc/systemd/system/default.target && \
    rm -v /usr/lib/systemd/system-generators/systemd-gpt-auto-generator

RUN ln -s /usr/lib/systemd/system/anaconda-shell@.service /usr/lib/systemd/system/autovt@.service

RUN mkdir -p /usr/lib/systemd/logind.conf.d
COPY <<EOT /usr/lib/systemd/logind.conf.d/anaconda-shell.conf
[Login]
ReserveVT=2
EOT

# Gera um initramfs com o módulo do Anaconda e o kernel da imagem.
RUN mkdir -p "$(realpath /root)" && \
    kernel=$(kernel-install list --json pretty | jq -r '.[] | select(.has_kernel == true) | .version') && \
    DRACUT_NO_XATTR=1 dracut --force -v --zstd --reproducible --no-hostonly \
        --add "anaconda" \
        "/usr/lib/modules/${kernel}/initramfs.img" "${kernel}"

# Permite que o root use PipeWire durante a instalação.
RUN mkdir -p /etc/systemd/user/pipewire.service.d/
COPY <<EOT /etc/systemd/user/pipewire.service.d/allowroot.conf
[Unit]
ConditionUser=
EOT

RUN mkdir -p /etc/systemd/user/pipewire.socket.d/
COPY <<EOT /etc/systemd/user/pipewire.socket.d/allowroot.conf
[Unit]
ConditionUser=
EOT
```

### O que cada bloco faz

| Bloco | Explicação |
| --- | --- |
| `ARG CONTAINER_NAME` | Define a imagem bootc que será instalada e usada nas atualizações. É gravada no kickstart. |
| `dnf5 install ...` | Instala o Anaconda, o dracut, o GRUB EFI e as ferramentas para montar a ISO (`xorrisofs`, `squashfs-tools`). |
| `cp -ra /usr/lib/efi/*/*/EFI` | O `image-builder` espera os binários EFI em `/boot/efi/EFI`. |
| `iso.yaml` | Define o rótulo da ISO e a entrada do GRUB. O `inst.stage2=hd:LABEL=...` precisa apontar para o mesmo rótulo. |
| `interactive-defaults.ks` | Ativa o modo bootc do Anaconda com `--source-imgref` e `--target-imgref`. |
| Usuário `install` e `passwd -d root` | O Anaconda live roda sem senha de root; é o comportamento esperado do instalador. |
| `mv ... /etc/anaconda.repos.d` | Ajusta o caminho dos repositórios para o formato usado pelo Anaconda. |
| `default.target = anaconda.target` | Faz o ambiente live iniciar diretamente no instalador. |
| `ReserveVT=2` | Reserva um console extra para o shell do Anaconda. |
| `dracut --add anaconda` | Inclui o módulo do Anaconda no initramfs. |
| `allowroot.conf` | Remove a restrição de usuário do PipeWire para o root durante a instalação. |

> [!NOTE]
> `inst.graphical` abre a interface GTK. `selinux=0` desativa o SELinux apenas
> no ambiente live do instalador; o sistema instalado continua com o SELinux da
> imagem. `rhgb quiet` só esconde mensagens de boot.

## Passo 1 — Construir a imagem do instalador

No diretório onde está o `Containerfile`:

```bash
sudo podman build -t localhost/bootc-generic-iso-f45:latest \
  --build-arg CONTAINER_NAME=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest \
  -f Containerfile .
```

Troque `CONTAINER_NAME` pela tag ou pelo digest que você quer instalar. Para
este projeto, a tag `:latest` é a mais prática; para uma instalação
reprodutível, use um digest `@sha256:...`.

## Passo 2 — Gerar a ISO

```bash
sudo image-builder build \
  --bootc-ref localhost/bootc-generic-iso-f45:latest \
  --bootc-default-fs ext4 \
  bootc-generic-iso
```

O que cada argumento faz:

| Argumento | Função |
| --- | --- |
| `--bootc-ref localhost/bootc-generic-iso-f45:latest` | Container que contém o Anaconda e as configurações da ISO (o que você acabou de construir). |
| `--bootc-default-fs ext4` | Sistema de arquivos padrão que o instalador usará na raiz. Use `btrfs` se quiser o layout BTRFS. |
| `bootc-generic-iso` | Tipo de imagem. Em versões mais antigas do `image-builder`, o mesmo tipo pode aparecer como `generic-iso`. |

> [!NOTE]
> Este projeto define `rootflags=compress=zstd:1` em
> `config/nvidia/10-nvidia-args.toml`, uma opção do BTRFS. Se for instalar em
> ext4, remova esse argumento da imagem ou reconstrua-a sem ele; um `rootflags`
> incompatível pode impedir a montagem da raiz. Para seguir o layout BTRFS do
> [guia de instalação manual](instalacao-manual-bootc-to-filesystem.md), use
> `--bootc-default-fs btrfs`.

Ao final, o `image-builder` cria um diretório no diretório atual com a ISO
gerada. O caminho exato aparece na saída do comando.

## Passo 3 — Testar e usar a ISO

Para testar em uma máquina virtual:

```bash
qemu-system-x86_64 \
  -m 4096 -enable-kvm -cpu host \
  -boot d \
  -cdrom /caminho/para/imagem.iso \
  -drive file=teste.qcow2,if=virtio,format=qcow2
```

Para gravar em um pendrive (confira o dispositivo com `lsblk` antes):

```bash
sudo dd if=/caminho/para/imagem.iso of=/dev/sdX bs=8M status=progress oflag=sync
```

Depois de iniciar a ISO:

1. escolha **Install Fedora (bootc)** no GRUB;
2. siga o assistente do Anaconda (idioma, disco, usuário);
3. o Anaconda baixa a imagem definida em `CONTAINER_NAME` e a grava no disco;
4. ao terminar, reinicie e remova a mídia.

> [!WARNING]
> A instalação apaga o disco escolhido. Faça backup e confira o dispositivo de
> destino antes de continuar.

## Instalação offline (opcional)

Por padrão, o Anaconda precisa de rede para baixar a imagem. Para uma instalação
offline, inclua a imagem no armazenamento local do instalador e mude o kickstart
para usar `containers-storage:`:

```dockerfile
COPY <<EOT /usr/share/anaconda/interactive-defaults.ks
bootc --source-imgref containers-storage:ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest --target-imgref ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
EOT
```

E gere a ISO com o payload embutido:

```bash
sudo image-builder build \
  --bootc-ref localhost/bootc-generic-iso-f45:latest \
  --bootc-installer-payload-ref ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest \
  --bootc-default-fs ext4 \
  bootc-generic-iso
```

O `--bootc-installer-payload-ref` copia a imagem para o armazenamento do
instalador, evitando o download durante a instalação.

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| A ISO não inicia | Firmware/BIOS configurado para o modo errado ou ISO corrompida. | Teste em UEFI e em BIOS legado; baixe/grave novamente e confira o checksum. |
| O GRUB não encontra o `stage2` | O rótulo em `inst.stage2=hd:LABEL=...` não é igual ao `label` do `iso.yaml`. | Use exatamente o mesmo texto nos dois lugares. |
| O Anaconda não encontra a imagem | Rede, autenticação no GHCR ou `CONTAINER_NAME` errado. | Confira a tag, faça login no registry e teste `podman pull` no host. |
| A instalação aborta sem detalhes | Falta de espaço, rede ou política de assinatura. | Use `inst.nokill` nos argumentos do kernel para manter o ambiente vivo e ver os logs. |
| A interface GTK não abre | Driver de vídeo ou parâmetros de boot inadequados. | Teste com `console=tty0` e, em VM, use `-vga std` ou virtio. |
| O sistema instalado não inicia | Layout de disco ou carregador incompatível. | Verifique o `bootc status` pelo live e consulte [`instalacao-manual-bootc-to-filesystem.md`](instalacao-manual-bootc-to-filesystem.md). |
| Aviso sobre `systemd-remount-fs.service` | Comportamento conhecido de instalações bootc via Anaconda. | Nesta imagem o serviço já é mascarado no `Containerfile`; se aparecer, confira a versão da imagem. |

## Referências

- [Documentação oficial de ISOs bootc do image-builder](https://osbuild.org/docs/developer-guide/projects/image-builder/advanced/bootc/isos/)
- [Exemplo de Anaconda GTK no repositório do image-builder](https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/60-iso-anaconda-gtk.md)
- [Instalador Anaconda (Web UI)](instalador-anaconda-webui.md)
- [Assinatura e verificação da imagem](SIGNING.md)
