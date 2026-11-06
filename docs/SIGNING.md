# Assinatura e verificação da imagem

A imagem é assinada no CI com [cosign](https://docs.sigstore.dev/cosign/) e o
sistema instalado passa a **rejeitar atualizações sem assinatura válida**.

## Estrutura de segurança

| Caminho | Função |
| --- | --- |
| `security/cosign.pub` | Chave pública usada pelo CI e embutida na imagem |
| `security/policy.json` | Política que exige assinatura do seu repositório |
| `security/registries.d/ghcr.yaml` | Descoberta das assinaturas `.sig` no GHCR |
| `security/keys/RPM-GPG-KEY-slaanesh` | Chave pública dos RPMs do negativo17 |
| `security/README.md` | Resumo dos arquivos desta pasta |
| `docs/SIGNING.md` | Este guia |

As configurações do sistema ficam em `config/` (`config/nvidia/`,
`config/packages/`, `config/system/`, `config/systemd/` e `config/flatpak/`).
O `Containerfile` copia `config/` e `security/` para `/run/build-inputs/` e
instala cada arquivo no destino final.

> `security/cosign.pub` é obrigatório. Se ele não existir, o build falha com a
> mensagem `ERRO: crie security/cosign.pub com 'cosign generate-key-pair'`.

## 1. Gerar o par de chaves (uma única vez)

```bash
cosign generate-key-pair
```

Isso cria `cosign.key` (privada) e `cosign.pub` (pública).

- Mova a **pública** para `security/cosign.pub` e faça commit dela.
- A **privada** nunca deve entrar no repositório. Ela vai apenas para os
  secrets do GitHub.

O `.gitignore` e o `.dockerignore` já bloqueiam `*.key`, então a chave privada
não é commitada nem enviada ao builder.

## 2. Configurar os secrets no GitHub

Em **Settings → Secrets and variables → Actions → New repository secret**
(é a aba **Secrets**, não **Variables**):

| Secret | Valor |
| --- | --- |
| `COSIGN_PRIVATE_KEY` | conteúdo completo do arquivo `cosign.key` |
| `COSIGN_PASSWORD` | a senha informada ao gerar a chave |

Não use a página **SSH and GPG keys** da conta: ela serve para autenticação do
Git e assinatura de commits, não para o cosign.

## 3. Como o build assina

1. A imagem é publicada com a tag de versão (`45-AAAAAMMDD-HHMM`).
2. O digest real do push é capturado com `podman push --digestfile`.
3. `cosign sign` assina **o digest** (nunca a tag).
4. `cosign verify --key security/cosign.pub` roda como gate: se a assinatura
   não for válida, o workflow falha.
5. Só então as tags móveis (`latest`, `main`, `sha-*`) são publicadas.

> A Action `cosign-installer` está fixada por SHA de commit porque ela manipula
> a chave privada. O cosign está fixado em `v2.4.3` para gerar a assinatura no
> formato de anexo `.sig`, que é o formato que o bootc descobre através de
> `use-sigstore-attachments: true`.

As configurações finais são copiadas depois dos passos pesados (NVIDIA e
GNOME), então alterar `config/system/locale.conf` ou `security/policy.json` não
invalida o cache desses passos.

## 4. Como o sistema verifica

O `Containerfile` instala os arquivos de `security/` nos caminhos abaixo:

| Arquivo no repo | Destino na imagem | Função |
| --- | --- | --- |
| `security/cosign.pub` | `/etc/pki/containers/bootc-gnome.pub` | chave pública confiável |
| `security/policy.json` | `/etc/containers/policy.json` | exige assinatura para o seu repositório |
| `security/registries.d/ghcr.yaml` | `/etc/containers/registries.d/ghcr.yaml` | habilita descoberta das assinaturas `.sig` |

A regra do seu repositório usa `signedIdentity: matchRepository`, o que impede
reaproveitar a assinatura de outra imagem (tag substitution).

O `default` da policy é `reject`: qualquer registry que não esteja na lista
explícita é recusado. Hoje estão liberados (sem verificação de assinatura)
`docker.io`, `registry.fedoraproject.org`, `quay.io` e `ghcr.io` para não
quebrar `podman`/`toolbox`/`distrobox`. Ajuste a lista conforme o seu uso.

## 5. Verificar a imagem que está rodando

O `bootc status` mostra o digest da imagem em execução, mas o formato do texto
muda entre versões. Para não depender do rótulo, extraia o primeiro `sha256:`
da saída e verifique **pelo digest** (nunca pela tag, que pode ser movida):

```bash
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45
DIG=$(sudo bootc status | grep -oE 'sha256:[0-9a-f]{64}' | head -1)

echo "DIG=[$DIG]"
[ -n "$DIG" ] || { echo "não consegui extrair o digest"; exit 1; }

cosign verify --key ~/cosign.pub "$IMG@$DIG" \
  && echo "OK: assinatura válida para $DIG"
```

O `DIG` precisa ser igual ao digest mostrado em `bootc status`, e o JSON da
verificação deve trazer `"docker-manifest-digest"` com esse mesmo valor.

Confira também que a chave embutida no sistema é a mesma do repositório:

```bash
sha256sum /etc/pki/containers/bootc-gnome.pub ~/cosign.pub
```

E que a policy ativa aponta para ela:

```bash
jq '.default, .transports.docker["ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45"]' \
  /etc/containers/policy.json
```

> O prefixo `ostree-unverified-registry:` que aparece no `rpm-ostree status`
> é só o nome do transporte OCI. O bootc **sempre** aplica a policy de
> containers; a prova é o teste negativo recusar um digest sem assinatura.

## 6. Primeira migração para a imagem assinada

A policy vale a partir do sistema **que está rodando**. Uma máquina que ainda
está na imagem antiga não tem a policy nova, então valide a assinatura na mão
antes do primeiro switch:

```bash
cosign verify --key security/cosign.pub \
  ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest

sudo bootc switch ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
sudo systemctl reboot
```

Depois do reboot, o sistema já carrega a policy nova e todos os
`sudo bootc upgrade` seguintes verificam a assinatura automaticamente.

Se quiser garantir já no primeiro switch (copiando a policy para o host atual):

```bash
sudo install -Dm644 security/policy.json /etc/containers/policy.json
sudo install -Dm644 security/registries.d/ghcr.yaml /etc/containers/registries.d/ghcr.yaml
sudo install -Dm644 security/cosign.pub /etc/pki/containers/bootc-gnome.pub

sudo bootc switch --enforce-container-sigpolicy \
  ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
sudo systemctl reboot
```

O `--enforce-container-sigpolicy` exige que a policy **não** tenha
`default: insecureAcceptAnything`; por isso o `default` deste projeto é
`reject`.

Teste negativo (deve ser recusado):

```bash
sudo bootc switch --enforce-container-sigpolicy \
  ghcr.io/usuario/qualquer-imagem-sem-assinatura:latest
```

## 7. Chave GPG do repositório negativo17

A chave pública fica versionada em `security/keys/RPM-GPG-KEY-slaanesh` e o
`Containerfile`:

- confere o SHA-256 fixo do arquivo da chave;
- importa a chave no rpmdb antes de instalar qualquer pacote do repositório;
- roda `rpmkeys --checksig` em cada pacote baixado **antes** de instalar;
- instala com `rpm -vi --nodeps` (sem `--nosignature`), mantendo o comportamento
  de não puxar dependências de compilação para a imagem final.

Fingerprint da chave:

```
0C5D 0F47 0484 AE2F C40A  9B65 97F3 0089 93E8 909B
```

A lista de pacotes NVIDIA instalados na imagem final fica em
`config/nvidia/nvidia_packages`. O `--nodeps` continua sendo usado de propósito;
se quiser dependências checadas, instale essa lista antes e remova o
`--nodeps` — o `rpm` não baixa nada, apenas valida o que já está presente.

## 8. Checklist rápido

- [ ] `security/cosign.pub` commitado (e é o par de `~/cosign.key`).
- [ ] Secrets `COSIGN_PRIVATE_KEY` e `COSIGN_PASSWORD` criados.
- [ ] Workflow novo em `.github/workflows/build-image.yml` enviado para `main`.
- [ ] Build com as etapas `Assinar a imagem pelo digest` e
      `Verificar a assinatura (gate de CI)` verdes.
- [ ] `cosign verify --key security/cosign.pub ...:latest` retorna `Verified OK`.
- [ ] `cosign verify` pelo digest mostrado no `bootc status` retorna `Verified OK`.
- [ ] Primeiro `bootc switch` feito e máquina reiniciada na imagem assinada.
- [ ] Teste negativo recusado com `A signature was required, but no signature exists`.
- [ ] Backup de `~/cosign.key` e da senha guardado fora do repositório.
