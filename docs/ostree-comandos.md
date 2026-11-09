# OSTree — comandos úteis

Esta é uma referência rápida dos comandos `ostree` usados para inspecionar,
limpar e alternar implantações em sistemas com backend OSTree, como Fedora
Atomic e imagens bootc que usam esse backend.

> [!IMPORTANT]
> Em um sistema bootc, prefira os comandos `bootc` para o dia a dia:
> `bootc status`, `bootc upgrade`, `bootc rollback` e `bootc switch`. Os
> comandos `ostree admin` continuam úteis para diagnóstico e recuperação, mas
> mexem diretamente nas implantações e podem remover a opção de rollback.

## Antes de começar

- Execute comandos que alteram o sistema com `sudo`.
- A implantação atual é a de índice `0`; as anteriores aparecem como `1`, `2`
  etc.
- Um *deployment* (implantação) é uma versão inicializável do sistema. O
  OSTree mantém mais de uma para permitir rollback.
- `prune`, `cleanup` e `undeploy` liberam espaço, mas podem apagar a versão
  para a qual você voltaria. Faça `pin` antes de limpar.

## Ver as implantações instaladas

```bash
sudo ostree admin status
```

A saída mostra o stateroot, o ref, o commit e as implantações disponíveis. Para
uma visão mais detalhada em JSON:

```bash
sudo ostree admin status --json | jq .
```

Para ver apenas os índices:

```bash
ostree admin status --json | jq '.deployments[].index'
```

> [!TIP]
> No bootc, `bootc status` é mais direto e mostra a imagem, a tag e o digest em
> uso. Use `ostree admin status` quando precisar do índice da implantação para
> `pin`, `set-default` ou `undeploy`.

## Limpeza de objetos e implantações

```bash
# Remove objetos do repositório que não são referenciados por nenhum ref
sudo ostree prune --refs-only

# Remove implantações antigas e objetos não usados
sudo ostree admin cleanup
```

O `prune` trabalha no repositório de objetos; o `admin cleanup` remove
implantações que não estão mais referenciadas. Nenhum dos dois remove a
implantação atual.

> [!WARNING]
> Se você precisa manter uma versão antiga para rollback, fixe-a com
> `ostree admin pin <índice>` antes de rodar qualquer limpeza.

## Definir a implantação padrão

```bash
sudo ostree admin set-default <índice>
```

Isso define qual implantação será inicializada por padrão no próximo boot. Não
é a mesma coisa que `bootc rollback`: o rollback do bootc alterna para a imagem
anterior de forma explícita e é o comando recomendado no dia a dia.

## Pinar e despinar uma implantação

Pinar protege a implantação da limpeza automática e cria uma entrada permanente
no menu do GRUB:

```bash
# Fixar a implantação de índice 0
sudo ostree admin pin 0

# Remover o pin
sudo ostree admin pin --unpin 0
```

Use isso antes de atualizar para manter um ponto de restauração conhecido. Para
listar os pins atuais, consulte `ostree admin status`.

## Remover uma implantação

```bash
sudo ostree admin undeploy <índice>
```

Remove a implantação indicada. A implantação em uso não pode ser removida; use
um índice de uma versão antiga. Confirme duas vezes antes de executar: se você
remover a última versão anterior, perde o rollback.

## Desbloquear `/usr` temporariamente

```bash
sudo ostree admin unlock --hotfix
```

Isso torna `/usr` gravável para instalar ou alterar pacotes sem reconstruir a
imagem. As alterações sobrevivem ao reboot, mas **não** sobrevivem a um
`bootc upgrade`/`rpm-ostree update`: a próxima atualização substitui `/usr` pela
imagem nova.

> [!WARNING]
> Use apenas para teste ou recuperação. Para uma mudança permanente, adicione o
> pacote ao `Containerfile` e reconstrua a imagem. Em sistemas bootc, alterações
> locais em `/usr` também podem marcar a implantação como incompatível e fazer
> o `bootc upgrade` recusar a atualização.

## Listar imagens e refs disponíveis

```bash
ostree remote refs fedora
```

Lista as refs publicadas pelo remote `fedora` (por exemplo, diferentes releases
e variantes). Em bootc, a troca de imagem normalmente é feita por tag/digest de
container com `bootc switch`, não por ref OSTree.

## Voltar para um commit anterior na mesma release

Esse fluxo é útil em sistemas rpm-ostree/Fedora Atomic. Ele baixa metadados de
commits antigos, mostra o histórico e permite fazer deploy de um commit
específico:

```bash
# Baixa metadados dos últimos 10 commits da ref
sudo ostree pull --commit-metadata-only --depth=10 \
  fedora:fedora/44/x86_64/silverblue

# Mostra o histórico de commits
ostree log fedora:fedora/44/x86_64/silverblue

# Faz deploy do commit escolhido
sudo rpm-ostree deploy <commit>
```

Ajuste `44` para a release que você usa. Em um sistema bootc, prefira
`bootc switch <imagem>:<tag>` ou `bootc switch <imagem>@<digest>`; veja a seção
abaixo.

## No bootc: equivalentes recomendados

| Tarefa | Comando recomendado |
| --- | --- |
| Ver a imagem atual | `bootc status` |
| Verificar atualização | `sudo bootc upgrade --check` |
| Atualizar | `sudo bootc upgrade` |
| Reverter para a anterior | `sudo bootc rollback` |
| Trocar de imagem/tag | `sudo bootc switch ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest` |
| Ver o que mudou entre versões | `rpm-ostree db diff` |

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `ostree admin status` mostra vários deployments | É o comportamento normal: um por versão instalada. | Use `bootc status` para ver qual está em uso. |
| Falta espaço em `/` | Implantações antigas e objetos acumulados. | Pin a versão desejada e rode `ostree admin cleanup` / `ostree prune --refs-only`. |
| O rollback desapareceu | `cleanup` ou `undeploy` removeu a implantação anterior. | Não há como recuperar sem baixar a imagem de novo; evite limpar sem pin. |
| `bootc upgrade` recusa a atualização | Há modificações locais ou uma implantação incompatível. | Verifique `rpm-ostree status` e considere `rpm-ostree reset`; veja [`rpm-ostree.md`](rpm-ostree.md). |
| Alteração em `/usr` sumiu após atualizar | `/usr` é imutável e pertence à imagem. | Reconstrua a imagem com a mudança no `Containerfile`. |

## Referências

- [`ostree admin` — documentação upstream](https://ostreedev.github.io/ostree/)
- [Relação entre bootc e rpm-ostree](https://bootc.dev/bootc/bootc-relationships.7.html)
- [`rpm-ostree.md`](rpm-ostree.md)
- [`SIGNING.md`](SIGNING.md)
