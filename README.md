# Fedora Bootc Imagem Personalizada

Este repositório contém a definição da imagem de sistema operacional baseada em **Fedora 45**, construída com `bootc`. O sistema é imutável, voltado para uso desktop com suporte a drivers Nvidia e interface GNOME.

Além do `bootc`, a imagem utiliza o [chunkah](https://github.com/coreos/chunkah) para otimizar o processo de atualização, dividindo a imagem em camadas adicionais e reduzindo o volume de dados transferidos a cada update do bootc.

## Arquitetura do Projeto

- **Base:** [fedora-bootc](https://quay.io/repository/fedora/fedora-bootc) (Imagem OCI inicializável Oficial do projeto Fedora)
- **Interface:** GNOME Shell
- **Drivers:** Nvidia via repositório Negativo17, incluídos na imagem
- **Automação:** GitHub Actions com build diário às 03h45 (horário de Brasília)

## Estrutura de Arquivos

```text
.
├── Containerfile                 # build da imagem
├── config/
│   ├── nvidia/                   # driver NVIDIA (kargs, modprobe, pacotes)
│   ├── packages/                 # listas de pacotes do sistema e do desktop
│   ├── system/                   # locale, vconsole e zram
│   ├── systemd/                  # unidades systemd
│   └── flatpak/                  # Flatpaks pré-instalados
├── security/                     # chaves e política de assinatura
├── docs/                         # documentação
└── .github/workflows/            # build automático
```

| Arquivo | Função |
|---|---|
| `Containerfile` | Instruções de build da imagem (instalação de pacotes e drivers) |
| `config/packages/pacotes_desktop` | Lista de pacotes relacionados à interface gráfica (GNOME, Plasma e afins) |
| `config/packages/pacotes_necessarios` | Lista de pacotes essenciais ao sistema, acrescida de pacotes de escolha pessoal |
| `.github/workflows` | Arquivo `.yml` responsável pelo build automático via GitHub Actions |
| `config/nvidia/10-nvidia-args.toml` | Parâmetros para colocar o driver `nouveau` no blacklist |
| `config/nvidia/nvidia-power.conf` | Ajustes de gerenciamento de energia do driver NVIDIA |
| `config/nvidia/nvidia_packages` | Pacotes do driver NVIDIA instalados na imagem final |
| `config/systemd/post-install.service` | Serviço systemd que executa o pós-instalação no primeiro boot |
| `config/system/vconsole.conf` | Configuração do TTY para pt-BR |
| `config/system/locale.conf` | Configuração de localidade do sistema para pt-BR |
| `config/system/zram-generator.conf` | Configura o zram com tamanho igual ao da RAM, usando o algoritmo de compressão zstd |
| `config/flatpak/flatpaks.preinstall` | Lista de Flatpaks instalados no primeiro boot |
| `security/policy.json` | Política que exige assinatura da imagem para atualizações |
| `security/registries.d/ghcr.yaml` | Descoberta das assinaturas cosign no GHCR |
| `security/cosign.pub` | Chave pública usada para verificar a assinatura da imagem |
| `security/keys/RPM-GPG-KEY-slaanesh` | Chave pública do repositório negativo17 |
| `docs/SIGNING.md` | Guia de assinatura e verificação |
| `config.toml` | Arquivo de kickstart do Anaconda para geração de ISO (local, não versionado) |

## Ciclo de Atualização

A imagem é reconstruída automaticamente todos os dias às 03h45. Uma notificação via Telegram (integração com o BotFather) é enviada ao final de cada build, indicando sucesso ou falha.

![Notificação Telegram](https://i.imgur.com/5Ip7A1N.png)

### Atualização manual

```bash
# Verificar se há nova imagem disponível
sudo bootc upgrade --check

# Aplicar a atualização
sudo bootc upgrade

# Após reiniciar, verificar o que mudou
rpm-ostree db diff

# Reiniciar para ativar a nova imagem
sudo reboot
```

## Comandos de Manutenção

```bash
# Ver a versão atual da imagem
bootc status

# Reverter para a imagem anterior
sudo bootc rollback

# Migrar para esta imagem (primeira utilização)
sudo bootc switch ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
```

## Segurança e assinatura

A imagem é assinada com cosign no GitHub Actions e o sistema instalado verifica
a assinatura antes de aplicar atualizações. As chaves e políticas ficam em
`security/` e o passo a passo está em [`docs/SIGNING.md`](docs/SIGNING.md).

## Criação de ISO Personalizada

### Build da imagem local

```bash
# baixar os arquivos do projeto
git clone https://github.com/Ferlinuxdebian/bootc-gnome-minimal-f45.git
cd bootc-gnome-minimal-f45
mkdir output

# build do projeto com o buildah
sudo buildah build \
    --skip-unused-stages=false \
    --security-opt=label=disable \
    -t "bootc-gnome-minimal" \
    -f Containerfile \
    -v $(pwd):/run/src \
    .
```

### Geração da ISO de instalação

```bash
sudo podman run \
    --rm \
    -it \
    --privileged \
    --pull=newer \
    --security-opt label=type:unconfined_t \
    -v ./output:/output \
    -v ./config.toml:/config.toml:ro \
    -v /var/lib/containers/storage:/var/lib/containers/storage \
    quay.io/centos-bootc/bootc-image-builder:latest \
    --type anaconda-iso \
    --rootfs btrfs \
    localhost/bootc-gnome-minimal
```

Após a conclusão, o arquivo `output/bootiso/install.iso` estará disponível para uso na instalação do sistema.
