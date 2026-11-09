# Assinar a imagem e ativar a verificação no bootc

Este guia vai do zero até a máquina recusar qualquer atualização sem assinatura
válida. São 7 passos, na ordem. Se você nunca assinou uma imagem, comece pelo
passo 1 e não pule nenhum.

**O que vai acontecer no final:** o GitHub Actions assina a imagem com uma chave
privada guardada em segredo, e a sua máquina passa a usar a chave pública para
aceitar somente imagens assinadas por você.

- Imagem deste projeto: `ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45`
- Chave pública no repositório: `security/cosign.pub`
- Chave privada: **nunca** entra no repositório
- Opção do bootc usada no primeiro switch: `--enforce-container-sigpolicy`

---

## Antes de começar

Você precisa de:

- o repositório clonado (`cd ~/Projetos/bootc-gnome-minimal-f45`);
- `git`, `cosign` e `podman` instalados na sua máquina;
- acesso de escrita ao repositório no GitHub e ao pacote no GHCR;
- a senha da chave privada guardada em um gerenciador de senhas.

Fedora:

```bash
sudo dnf install cosign podman git jq
```

> `jq` é opcional; só é usado para ler a política de forma mais legível.

---

## Passo 1 — Gerar o par de chaves (só na primeira vez)

A chave privada assina. A pública verifica. Elas são um par: se a pública não
for a mesma do repositório, a verificação falha.

Se você **já tem** `~/cosign-bootc/cosign.key` e a senha dela, pule para o
passo 2. Gere uma chave nova apenas se for a primeira vez ou se perdeu a antiga.

```bash
mkdir -p ~/cosign-bootc
cd ~/cosign-bootc
cosign generate-key-pair
```

O comando pede uma senha. Use uma senha forte e **guarde-a**; sem ela a chave
privada não assina nada.

Serão criados:

| Arquivo | O que é | Onde guardar |
| --- | --- | --- |
| `~/cosign-bootc/cosign.key` | chave privada | backup seguro, fora do repositório |
| `~/cosign-bootc/cosign.pub` | chave pública | dentro de `security/cosign.pub` |

Proteja a chave privada e faça backup dela e da senha:

```bash
chmod 600 ~/cosign-bootc/cosign.key
```

Agora copie a pública para o repositório e envie para o GitHub:

```bash
cd ~/Projetos/bootc-gnome-minimal-f45
install -m644 ~/cosign-bootc/cosign.pub security/cosign.pub

git add security/cosign.pub
git commit -m "security: atualiza chave pública do cosign"
git push origin main
```

Confira que a pública é realmente o par da privada:

```bash
cosign public-key --key ~/cosign-bootc/cosign.key | diff - security/cosign.pub \
  && echo "OK: chave pública confere"
```

> O `.gitignore` já bloqueia `*.key`, então a privada não é commitada por
> acidente. O build também falha de propósito se `security/cosign.pub` não
> existir.

---

## Passo 2 — Cadastrar a chave privada no GitHub

O workflow precisa da chave privada para assinar. Ela fica em **Secrets**, nunca
no código.

No GitHub, abra o repositório e vá em:

**Settings → Secrets and variables → Actions → New repository secret**

Crie exatamente estes dois secrets:

| Nome | Valor |
| --- | --- |
| `COSIGN_PRIVATE_KEY` | conteúdo completo do arquivo `~/cosign-bootc/cosign.key` |
| `COSIGN_PASSWORD` | a senha que você digitou ao gerar a chave |

Para `COSIGN_PRIVATE_KEY`, abra o arquivo e cole tudo, incluindo as linhas
`-----BEGIN ENCRYPTED COSIGN PRIVATE KEY-----` e
`-----END ENCRYPTED COSIGN PRIVATE KEY-----`.

Se preferir usar a CLI `gh` (execute dentro do repositório):

```bash
gh secret set COSIGN_PRIVATE_KEY < ~/cosign-bootc/cosign.key
gh secret set COSIGN_PASSWORD
```

No segundo comando o `gh` pergunta o valor; cole a senha no prompt.

> Não use a tela **SSH and GPG keys** da conta. Ela serve para autenticar no Git
> e assinar commits, não para o cosign.

---

## Passo 3 — Rodar o build que assina

O build acontece no GitHub Actions. Ele só assina depois de publicar a imagem.

Envie a alteração (se ainda não enviou) ou rode manualmente:

1. Abra **Actions** no repositório.
2. Escolha **Build, Push e Assinatura da Imagem Bootc**.
3. Clique em **Run workflow** → **Run workflow**.

Se preferir a CLI:

```bash
gh workflow run build-image.yml
gh run watch
```

O workflow faz, nesta ordem:

1. constrói a imagem;
2. publica a tag de versão (`45-AAAAMMDD-HHMM`);
3. captura o **digest** real do push;
4. assina **o digest** com a chave privada (nunca a tag);
5. verifica a assinatura como teste de CI e só então move `latest`, `main` e
   `sha-*` para o digest assinado.

Você sabe que deu certo quando os passos **Assinar a imagem pelo digest**,
**Verificar a assinatura (gate de CI)** e **Verificar assinatura da tag latest**
ficam verdes.

> Se você acabou de criar os secrets, o build precisa ser rodado de novo para
> enxergá-los. Alterar só arquivos em `docs/` não dispara o workflow; use
> **Run workflow**.

---

## Passo 4 — Verificar a assinatura no seu terminal

Antes de mexer na máquina, confirme que a imagem publicada está assinada com a
sua chave pública:

```bash
cd ~/Projetos/bootc-gnome-minimal-f45
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45

cosign verify --key security/cosign.pub "${IMG}:latest" >/dev/null \
  && echo "OK: assinatura válida em :latest"
```

O comando não precisa de `sudo`. Se ele terminar com `OK`, a assinatura existe e
confere. Sem o `>/dev/null`, o cosign mostra um JSON com os dados da verificação;
o importante é o código de saída ser `0`.

Para ver os detalhes:

```bash
cosign verify --key security/cosign.pub "${IMG}:latest" | jq .
```

> Verifique sempre pelo **digest** quando for algo crítico. Tags podem ser
> movidas; o digest não muda.

---

## Passo 5 — Preparar a máquina atual para o primeiro switch

Esta etapa só é necessária **na primeira migração**. Se a máquina já roda uma
imagem construída com estes arquivos de segurança, pule para o passo 6.

O motivo: a política de assinatura que vale é a do sistema que está rodando
agora. Uma máquina na imagem antiga ainda não tem a política nova. Copie os três
arquivos antes do switch:

```bash
cd ~/Projetos/bootc-gnome-minimal-f45

# Guarde a política atual, se existir
sudo test -f /etc/containers/policy.json && \
  sudo cp -a /etc/containers/policy.json "/etc/containers/policy.json.bak.$(date +%F)"

# Instale a política, a descoberta de assinaturas e a chave pública
sudo install -Dm644 security/policy.json /etc/containers/policy.json
sudo install -Dm644 security/registries.d/ghcr.yaml /etc/containers/registries.d/ghcr.yaml
sudo install -Dm644 security/cosign.pub /etc/pki/containers/bootc-gnome.pub
```

Confira o resultado:

```bash
sudo jq '.default, .transports.docker["ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45"]' \
  /etc/containers/policy.json
```

O esperado é `"type": "reject"` no `default` e a regra do seu repositório com
`"type": "sigstoreSigned"`. Confira também que a chave instalada é a mesma do
repositório:

```bash
sha256sum /etc/pki/containers/bootc-gnome.pub security/cosign.pub
```

Os dois hashes devem ser iguais.

---

## Passo 6 — Fazer o switch com verificação obrigatória

Agora sim. O comando abaixo baixa a imagem e **verifica a assinatura antes de
gravar o novo deployment**:

```bash
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45

sudo bootc switch --enforce-container-sigpolicy "${IMG}:latest"
```

O nome completo da opção é `--enforce-container-sigpolicy` (o “container” do
título é essa opção).

- Se a assinatura estiver válida, o bootc prepara a troca e avisa que a imagem
  será usada no próximo boot.
- Se a imagem não estiver assinada (ou a chave não bater), o comando **falha e
  não altera nada**.
- A opção exige que a política não tenha `default: insecureAcceptAnything`; por
  isso o `default` deste projeto é `reject`.

Reinicie para entrar na imagem nova:

```bash
sudo systemctl reboot
```

> Se algo der errado, a imagem anterior continua disponível. Dá para voltar com
> `sudo bootc rollback` e reiniciar.

---

## Passo 7 — Confirmar que o sistema está verificando

Depois do reboot, confirme que a máquina está na imagem certa:

```bash
bootc status
```

A saída mostra a imagem em execução e o digest. Verifique a assinatura **pelo
digest** mostrado:

```bash
cd ~/Projetos/bootc-gnome-minimal-f45
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45
DIG=$(sudo bootc status | grep -oE 'sha256:[0-9a-f]{64}' | head -1)

echo "DIG=[$DIG]"
[ -n "$DIG" ] || { echo "não consegui extrair o digest"; exit 1; }

cosign verify --key security/cosign.pub "${IMG}@${DIG}" >/dev/null \
  && echo "OK: assinatura válida para $DIG"
```

Confirme também que a chave e a política embutidas no sistema são as novas:

```bash
sudo sha256sum /etc/pki/containers/bootc-gnome.pub security/cosign.pub
sudo jq -r '.default[0].type' /etc/containers/policy.json
```

Esperado: hashes iguais e `reject`.

A partir daqui, as atualizações são verificadas automaticamente:

```bash
sudo bootc upgrade --check
sudo bootc upgrade
```

Se a imagem nova não estiver assinada, o `bootc upgrade` recusa a atualização e
mantém o sistema como está.

---

## Teste negativo (opcional, mas recomendado)

Prove que uma chave errada é recusada. Isso não altera a máquina:

```bash
cd ~/Projetos/bootc-gnome-minimal-f45
IMG=ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45

COSIGN_PASSWORD=chave-falsa-123 cosign generate-key-pair --output-key-prefix /tmp/chave-falsa

cosign verify --key /tmp/chave-falsa.pub "${IMG}:latest" >/dev/null \
  && echo "ERRO: aceitou uma chave errada" \
  || echo "OK: chave errada recusada"

rm -f /tmp/chave-falsa.key /tmp/chave-falsa.pub
```

O esperado é `OK: chave errada recusada`.

> Para testar o bootc recusando uma imagem sem assinatura, seria preciso
> publicar uma tag de teste sem assinar no seu repositório. Não faça isso na
> `latest`: o teste com a chave falsa já prova que a verificação está ativa.

---

## Se der erro

| Mensagem / sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `A signature was required, but no signature exists` | a imagem não foi assinada ou a descoberta `.sig` não está ativa | confira o workflow e o arquivo `/etc/containers/registries.d/ghcr.yaml` |
| `no matching signatures` no `cosign verify` | a pública não é o par da privada usada no CI | refaça o passo 1 e atualize `COSIGN_PRIVATE_KEY` e `security/cosign.pub` |
| `ERRO: crie security/cosign.pub` no build | a chave pública não foi commitada | faça o commit de `security/cosign.pub` |
| `unauthorized` ao baixar do GHCR | pacote privado ou falta login | torne o pacote público ou rode `podman login ghcr.io` na máquina |
| `--enforce-container-sigpolicy` recusa a política | `default` está como `insecureAcceptAnything` | copie `security/policy.json` para `/etc/containers/policy.json` |
| `bootc switch` conclui, mas continua na imagem antiga | o reboot ainda não foi feito | reinicie e confira `bootc status` |
| `unexpected argument '--enforce-container-sigpolicy'` | versão antiga do bootc | atualize o bootc (`sudo dnf upgrade bootc`) e tente de novo |
| Workflow falha ao assinar | secret ausente, senha errada ou chave inválida | confira os dois secrets e rode o workflow de novo |

---

## Referência rápida

### Arquivos e destinos

| Arquivo no repositório | Destino na imagem | Função |
| --- | --- | --- |
| `security/cosign.pub` | `/etc/pki/containers/bootc-gnome.pub` | chave pública confiável |
| `security/policy.json` | `/etc/containers/policy.json` | exige assinatura do seu repositório |
| `security/registries.d/ghcr.yaml` | `/etc/containers/registries.d/ghcr.yaml` | encontra as assinaturas `.sig` no GHCR |

A regra usa `signedIdentity: matchRepository`, então a assinatura de outra
imagem não pode ser reaproveitada. O `default` é `reject`; por isso qualquer
registry fora da lista é recusado. Hoje `docker.io`, `registry.fedoraproject.org`,
`quay.io` e `ghcr.io` estão liberados sem verificação para não quebrar
`podman`, `toolbox` e `distrobox`. Ajuste em `security/policy.json` se mudar o
seu uso.

### Checklist

- [ ] `cosign generate-key-pair` feito e senha guardada.
- [ ] `security/cosign.pub` commitado.
- [ ] Secrets `COSIGN_PRIVATE_KEY` e `COSIGN_PASSWORD` criados.
- [ ] Workflow **Build, Push e Assinatura da Imagem Bootc** verde.
- [ ] `cosign verify --key security/cosign.pub ...:latest` retorna código `0`.
- [ ] Política, `registries.d/ghcr.yaml` e chave copiados para a máquina atual.
- [ ] `sudo bootc switch --enforce-container-sigpolicy ...:latest` concluído.
- [ ] Máquina reiniciada e `bootc status` mostrando a imagem nova.
- [ ] `cosign verify` pelo digest do `bootc status` retorna código `0`.
- [ ] Teste com chave falsa recusado.
- [ ] Backup de `~/cosign-bootc/cosign.key` e da senha guardado fora do repositório.

### Trocar a chave no futuro

Se precisar gerar uma chave nova, a máquina que já está com a política antiga
não confia na chave nova. Faça nesta ordem:

1. gere o novo par e atualize `security/cosign.pub`;
2. atualize `COSIGN_PRIVATE_KEY` e `COSIGN_PASSWORD` nos secrets;
3. rode o workflow para publicar uma imagem assinada com a chave nova;
4. em cada máquina, instale a nova pública em
   `/etc/pki/containers/bootc-gnome.pub` **antes** do switch;
5. faça o switch e reinicie.
