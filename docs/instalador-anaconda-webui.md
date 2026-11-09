# Instalador Anaconda (Web UI)

Este documento descreve como gerar uma ISO live do Fedora 45 com o novo
instalador **Anaconda WebUI** para instalar a imagem bootc deste projeto. A
interface é servida pelo Cockpit e exibida em um navegador em modo quiosque
(Wayland), usando `gnome-kiosk`.

> [!NOTE]
> O projeto `bootc-image-builder` foi descontinuado em favor do `image-builder`.
> Esta ISO usa o tipo `bootc-generic-iso` do `image-builder`. Para o instalador
> legado GTK, veja [`instalador-anaconda-gtk.md`](instalador-anaconda-gtk.md).

## WebUI ou GTK?

| Característica | WebUI (este guia) | GTK (legado) |
| --- | --- | --- |
| Interface | Navegador + Cockpit, em Wayland | Aplicativo GTK |
| Estado | Instalador novo e recomendado | Mantido para compatibilidade |
| Pacotes principais | `anaconda-webui`, `cockpit-ws`, `cockpit-bridge`, `firefox`, `gnome-kiosk` | `anaconda` com interface GTK |
| Argumento de boot | `inst.webui` | `inst.graphical` |
| Uso típico | Instalação moderna em desktop/VM | Automação, ambientes antigos ou sem Wayland |

Os dois caminhos geram uma ISO que instala a mesma imagem bootc; a diferença
está na experiência do instalador e nos pacotes embarcados.

## Como funciona

1. O `Containerfile` cria uma imagem baseada em `fedora-bootc:45` com o
   Anaconda, o Cockpit e o navegador.
2. O `image-builder` transforma essa imagem em uma ISO live.
3. Ao iniciar a ISO, o GRUB passa `inst.webui` ao kernel.
4. O Anaconda WebUI abre em um navegador local; o kickstart aponta para a
   imagem bootc que será instalada.
5. Ao concluir, o Anaconda grava a imagem no disco com o `bootc`.

## Pré-requisitos

- Fedora 45 no host de build (ou versão compatível).
- `podman` com suporte a heredocs no `Containerfile` (os blocos `COPY <<EOT`
  usam esse recurso).
- `image-builder` instalado.
- Espaço em disco para a imagem do container e para a ISO.
- Acesso ao GHCR, caso a imagem de destino seja privada.
- `sudo`.

## Containerfile

Salve o conteúdo em um arquivo chamado `Containerfile`:

```dockerfile
FROM quay.io/fedora/fedora-bootc:45

# Imagem que o Anaconda vai instalar e usar nas atualizações seguintes.
# Pode ser sobrescrita no build com --build-arg CONTAINER_NAME=...
ARG CONTAINER_NAME=quay.io/fedora/fedora-bootc:45

# Pacotes do instalador e do ambiente WebUI.
RUN dnf install -qy \
    anaconda \
    anaconda-install-img-deps \
    anaconda-dracut \
    dracut-config-generic \
    dracut-network \
    net-tools \
    grub2-efi-x64-cdboot \
    plymouth \
    cockpit-ws \
    cockpit-bridge \
    anaconda-webui \
    firefox \
    gnome-kiosk \
    mesa-dri-drivers \
    default-fonts-core-sans \
    jq

# Ferramentas necessárias para gerar a ISO.
RUN dnf install -qy \
    xorrisofs \
    squashfs-tools

RUN dnf clean all

# Copia os binários EFI para o local esperado pelo image-builder.
RUN mkdir -p /boot/efi && cp -ra /usr/lib/efi/*/*/EFI /boot/efi

# Menu de boot da ISO.
RUN mkdir -p /usr/lib/image-builder/bootc

# inst.webui inicia o Anaconda WebUI em vez da interface GTK.
RUN cat <<EOF > /usr/lib/image-builder/bootc/iso.yaml
label: "Fedora-bootc-Installer"
grub2:
  timeout: 5
  entries:
    - name: "Install Fedora (bootc WebUI Wayland Local)"
      linux: \${kernelpath} \${root} inst.webui
      initrd: \${initrdpath}
EOF

# Define a imagem de origem e a imagem usada nas atualizações.
# Usa RUN (e não COPY) porque o shell expande ${CONTAINER_NAME} no build.
RUN mkdir -p /usr/share/anaconda && \
    echo "bootc --source-imgref registry:${CONTAINER_NAME} --target-imgref ${CONTAINER_NAME}" > /usr/share/anaconda/interactive-defaults.ks

# Ajustes mínimos do ambiente do Anaconda (normalmente feitos pelo lorax).
RUN echo "install:x:0:0:root:/root:/usr/libexec/anaconda/run-anaconda" >> /etc/passwd && \
    echo "install::14438:0:99999:7:::" >> /etc/shadow && \
    passwd -d root

RUN mv /usr/share/anaconda/list-harddrives-stub /usr/bin/list-harddrives && \
    mv /etc/yum.repos.d /etc/anaconda.repos.d && \
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
| `ARG CONTAINER_NAME` | Imagem bootc de destino; é gravada no kickstart e usada nas atualizações. |
| `cockpit-ws`, `cockpit-bridge` | Servidor e ponte do Cockpit, que hospedam a interface WebUI. |
| `anaconda-webui` | Módulo do Anaconda que fornece a interface web. |
| `firefox` + `gnome-kiosk` | Navegador em modo quiosque para exibir a WebUI localmente. |
| `mesa-dri-drivers` | Drivers gráficos para o ambiente Wayland. |
| `iso.yaml` | Label da ISO e entrada do GRUB com `inst.webui`. |
| `interactive-defaults.ks` | Ativa o modo bootc com `--source-imgref` e `--target-imgref`. |
| `passwd -d root` | O ambiente live do Anaconda roda sem senha de root. |
| `default.target = anaconda.target` | Inicia diretamente no instalador. |
| `dracut --add anaconda` | Inclui o módulo do Anaconda no initramfs. |

> [!NOTE]
> O exemplo oficial do osbuild usa `cage` como compositor. Esta versão usa
> `gnome-kiosk`, o compositor de quiosque do GNOME. Se a interface não abrir,
> teste trocar `gnome-kiosk` por `cage` no `Containerfile`.
>
> Em Fedora 45, `dnf` aponta para o DNF5. Se o seu ambiente usar apenas
> `dnf5`, ajuste os comandos ou use o binário explicitamente.
>
> O caminho `/etc/yum.repos.d` pode variar conforme a imagem base. Se o diretório
> não existir, use o caminho presente na imagem (por exemplo
> `/usr/share/dnf5/repos.d`, como no exemplo GTK).

## Passo 1 — Construir a imagem do instalador

```bash
sudo podman build -t localhost/bootc-generic-iso-f45:latest \
  --build-arg CONTAINER_NAME=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest \
  -f Containerfile .
```

Use uma tag ou um digest da imagem de destino. A tag `:latest` é prática para
testes; o digest é o ideal para builds reproduzíveis.

## Passo 2 — Gerar a ISO

```bash
sudo image-builder build \
  --bootc-ref localhost/bootc-generic-iso-f45:latest \
  --bootc-default-fs ext4 \
  bootc-generic-iso
```

| Argumento | Função |
| --- | --- |
| `--bootc-ref` | Container do instalador (o que você acabou de construir). |
| `--bootc-default-fs` | Sistema de arquivos padrão da raiz (`ext4`, `btrfs`, etc.). |
| `bootc-generic-iso` | Tipo de imagem; em versões antigas pode ser `generic-iso`. |

> [!NOTE]
> Este projeto define `rootflags=compress=zstd:1` em
> `config/nvidia/10-nvidia-args.toml`, uma opção do BTRFS. Se for instalar em
> ext4, remova esse argumento da imagem ou reconstrua-a sem ele; um `rootflags`
> incompatível pode impedir a montagem da raiz. Para o layout BTRFS do
> [guia de instalação manual](instalacao-manual-bootc-to-filesystem.md), use
> `--bootc-default-fs btrfs`.

A ISO é criada em um novo diretório no diretório atual; o caminho aparece na
saída do `image-builder`.

## Passo 3 — Testar e usar a ISO

Teste em uma VM:

```bash
qemu-system-x86_64 \
  -m 4096 -enable-kvm -cpu host \
  -boot d \
  -cdrom /caminho/para/imagem.iso \
  -drive file=teste.qcow2,if=virtio,format=qcow2
```

Grave em um pendrive (confira o dispositivo com `lsblk`):

```bash
sudo dd if=/caminho/para/imagem.iso of=/dev/sdX bs=8M status=progress oflag=sync
```

No boot:

1. escolha **Install Fedora (bootc WebUI Wayland Local)**;
2. a interface WebUI abre automaticamente no navegador quiosque;
3. siga o assistente (idioma, disco, usuário);
4. aguarde o download e a gravação da imagem;
5. reinicie e remova a mídia.

> [!WARNING]
> A instalação apaga o disco escolhido. Faça backup e confira o dispositivo de
> destino.

## Instalação offline (opcional)

Para instalar sem baixar a imagem durante o assistente, embuta o payload na ISO
e use `containers-storage:` no kickstart:

```dockerfile
COPY <<EOT /usr/share/anaconda/interactive-defaults.ks
bootc --source-imgref containers-storage:ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest --target-imgref ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
EOT
```

```bash
sudo image-builder build \
  --bootc-ref localhost/bootc-generic-iso-f45:latest \
  --bootc-installer-payload-ref ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest \
  --bootc-default-fs ext4 \
  bootc-generic-iso
```

O `--bootc-installer-payload-ref` copia a imagem para o armazenamento local do
instalador, então o Anaconda não precisa baixá-la pela rede.

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| A ISO não inicia | Modo de firmware errado ou ISO corrompida. | Teste UEFI e BIOS legado; verifique o checksum e grave novamente. |
| A WebUI não abre | Compositor ou driver gráfico incompatível. | Teste `cage` no lugar de `gnome-kiosk`; em VM, use `-vga std` ou virtio. |
| Fica na tela do GRUB | Entrada ou label incorretos. | Confira o `iso.yaml` e o `inst.stage2`/`label`. |
| O Anaconda não baixa a imagem | Sem rede, sem login no GHCR ou tag errada. | Teste `podman pull` no host e confira o `CONTAINER_NAME`. |
| A instalação para sem mensagem | Falta de espaço ou erro no kickstart. | Adicione `inst.nokill` aos argumentos do kernel e veja os logs no console. |
| O sistema instalado não inicia | Layout de disco ou carregador. | Consulte [`instalacao-manual-bootc-to-filesystem.md`](instalacao-manual-bootc-to-filesystem.md). |
| Aviso de `systemd-remount-fs.service` | Comportamento conhecido do bootc instalado via Anaconda. | Esta imagem mascara o serviço no `Containerfile`; confira a versão instalada. |

## Referências

- [Documentação oficial de ISOs bootc do image-builder](https://osbuild.org/docs/developer-guide/projects/image-builder/advanced/bootc/isos/)
- [Exemplo de Anaconda WebUI no repositório do image-builder](https://github.com/osbuild/image-builder/blob/main/doc/20-advanced/20-bootc/70-iso-anaconda-webui.md)
- [Instalador Anaconda (GTK)](instalador-anaconda-gtk.md)
- [Assinatura e verificação da imagem](SIGNING.md)
