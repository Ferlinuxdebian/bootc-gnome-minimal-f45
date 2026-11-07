# Fedora Bootc Imagem Personalizada

Este repositório contém a definição da imagem de sistema operacional baseada em **Fedora 45**, construída com `bootc`. O sistema é imutável, voltado para uso desktop com suporte a drivers Nvidia e interface GNOME.

Além do `bootc`, a imagem utiliza o `bootc-base-imagectl` na etapa de rechunk do build para otimizar o processo de atualização, dividindo a imagem em camadas adicionais e reduzindo o volume de dados transferidos a cada update do bootc.

Para preservar esse reaproveitamento, o `Containerfile` evita `dnf upgrade` completo na imagem final: as atualizações de pacotes vêm da tag flutuante `fedora-bootc:45` e apenas o kernel é atualizado, para manter o módulo akmods da NVIDIA alinhado ao kernel do estágio de build.

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

## Ciclo de Atualização

A imagem é reconstruída automaticamente todos os dias às 03h45 (horário de Brasília).

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

## Criação de ISO de instalação

A ISO de instalação é gerada pelo repositório
[anaconda-webui-bootc-installer](https://github.com/Ferlinuxdebian/anaconda-webui-bootc-installer),
que usa o Anaconda WebUI para instalar esta imagem em disco via `bootc`.

```bash
git clone https://github.com/Ferlinuxdebian/anaconda-webui-bootc-installer.git
cd anaconda-webui-bootc-installer

# Gera a ISO a partir da imagem assinada publicada no GHCR
sudo just build ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
sudo just create-iso
```

Ao término, a ISO estará disponível no diretório atual.
