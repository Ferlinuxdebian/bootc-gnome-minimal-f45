# rpm-ostree — referência de comandos

O `rpm-ostree` é a ferramenta histórica para gerenciar sistemas OSTree com
pacotes RPM, como o Fedora Atomic/Silverblue. Em sistemas bootc, ele compartilha
o mesmo backend OSTree, mas **não é o fluxo recomendado** para adicionar
pacotes: a imagem deve ser reconstruída com o `Containerfile`.

> [!IMPORTANT]
> Em um sistema bootc, instalar pacotes com `rpm-ostree install` cria uma
> "modificação local" na implantação. O `bootc upgrade` passa a recusar a
> atualização com um erro do tipo *Deployment contains local rpm-ostree
> modifications*. Use `sudo rpm-ostree reset` para remover as modificações ou,
> melhor, adicione o pacote à imagem e faça um novo build.

## Como o modelo funciona

- A imagem base é somente leitura e vem do registry.
- O `rpm-ostree` pode aplicar camadas locais (pacotes instalados, overrides,
  kargs) por cima da imagem.
- Essas camadas são reaplicadas a cada nova implantação no modelo rpm-ostree
  clássico.
- No bootc, o objetivo é que a imagem inteira seja versionada e atualizada como
  container; camadas locais quebram essa lógica.

## Ver o estado do sistema

```bash
rpm-ostree status
```

Para mais detalhes (commits, camadas, origem):

```bash
rpm-ostree -v status
```

No bootc, o comando equivalente é:

```bash
bootc status
```

## Resetar as modificações locais

```bash
sudo rpm-ostree reset
```

O `reset` devolve o sistema à composição da imagem base:

- remove pacotes instalados manualmente com `rpm-ostree install`;
- restaura pacotes da base removidos com `override remove`;
- remove substituições feitas com `override replace`.

Ele **não** apaga arquivos em `/home` nem configurações em `/etc`.

Exemplo de saída:

```text
Staging deployment... done
Freed: 2,6 MB (pkgcache branches: 1)
Added:
  tree-2.2.1-2.fc43.x86_64
Changes queued for next boot. Run "systemctl reboot" to start a reboot
```

> [!NOTE]
> O `reset` é a saída de emergência quando uma modificação local está impedindo
> o `bootc upgrade`. Se você usa bootc, o ideal é nunca precisar dele: mantenha
> os pacotes no `Containerfile`.

## Substituir um pacote da imagem base

O `override replace` troca um pacote já instalado por outro RPM, que pode ser
mais novo, mais antigo ou de outra origem. Ele **não** funciona como `dnf swap`:
o pacote precisa existir na imagem.

```bash
# A partir de uma URL
sudo rpm-ostree override replace https://exemplo.com/pacote.rpm

# A partir de um arquivo local
sudo rpm-ostree override replace ./pacote.rpm

# Para desfazer a substituição de um pacote
sudo rpm-ostree override reset nome-do-pacote
```

## Remover um pacote da imagem base

```bash
sudo rpm-ostree override remove tree
```

Para desfazer:

```bash
sudo rpm-ostree override reset tree
```

## Instalar e remover pacotes em camadas

```bash
sudo rpm-ostree install mousepad
sudo rpm-ostree uninstall mousepad
```

Em bootc, o equivalente correto é adicionar `mousepad` à lista de pacotes e
reconstruir a imagem. Veja `config/packages/pacotes_necessarios` e
`config/packages/pacotes_desktop` neste repositório.

## Atualizar metadados de pacotes

```bash
rpm-ostree refresh-md
```

Equivale a atualizar o cache de metadados do DNF antes de uma operação. Em
sistemas bootc, as atualizações vêm da imagem, então esse comando raramente é
necessário.

## Cancelar uma operação em andamento

```bash
rpm-ostree cancel
```

Interrompe uma transação em execução (por exemplo, um upgrade que ainda está
baixando ou aplicando camadas).

## Comparar commits e listar pacotes

```bash
# Diferença de pacotes entre a implantação atual e a anterior
rpm-ostree db diff

# Diferença entre commits específicos
rpm-ostree db diff <commit-antigo> <commit-novo>

# Listar os pacotes de um commit
rpm-ostree db list <commit>

# Detalhes de um pacote específico
rpm-ostree db list <commit> nome_do_pacote
```

Para listar os pacotes do sistema em uso, `rpm -qa` costuma ser mais simples e
direto.

## Cancelar um deployment pendente

Se você rodou uma atualização mas ainda não reiniciou, é possível descartar o
deployment pendente e continuar na imagem atual:

```bash
sudo rpm-ostree cleanup -p
```

O `-p` significa *pending*: remove apenas implantações pendentes. Para limpar
outros tipos de estado, consulte `rpm-ostree cleanup --help`.

## Alterar argumentos do kernel

```bash
# Adicionar
sudo rpm-ostree kargs --append="vconsole.keymap=br"

# Remover
sudo rpm-ostree kargs --delete="vconsole.keymap=br"

# Substituir um argumento existente
sudo rpm-ostree kargs --replace="vconsole.keymap=br"
```

No bootc, os argumentos também podem ser definidos na imagem em
`/usr/lib/bootc/kargs.d/` (este projeto usa
`config/nvidia/10-nvidia-args.toml`). Alterações com `rpm-ostree kargs` são
locais da máquina e criam uma nova implantação.

## Executar programas sem reiniciar

Após `rpm-ostree install`, as mudanças ficam pendentes até o reboot. Para testar
o programa imediatamente, use `apply-live`:

```bash
sudo rpm-ostree install mousepad
sudo rpm-ostree apply-live
mousepad
```

Ou instale já aplicando em tempo real:

```bash
sudo rpm-ostree install -A mousepad
mousepad
```

> [!NOTE]
> O `apply-live` não funciona para tudo: kernel, drivers, systemd e outros
> componentes de baixo nível continuam exigindo reboot. Use apenas para testar
> aplicativos.

## Listar refs e fazer rebase

Em sistemas rpm-ostree clássicos:

```bash
ostree remote refs fedora
sudo rpm-ostree rebase fedora:fedora/44/x86_64/silverblue
```

Em bootc, o equivalente é trocar a imagem de container:

```bash
sudo bootc switch ghcr.io/ferlinuxdebian/bootc-gnome-minimal-f45:latest
```

## Pinar uma imagem

Pinar impede que uma implantação seja removida pela limpeza automática:

```bash
# Ver os índices
ostree admin status

# Fixar a implantação 0 (atual)
sudo ostree admin pin 0

# Desfazer
sudo ostree admin pin --unpin 0
```

Use antes de uma atualização importante para manter um ponto de restauração
permanente no GRUB. Veja também [`ostree-comandos.md`](ostree-comandos.md).

## Equivalência bootc × rpm-ostree

| Tarefa | rpm-ostree | bootc |
| --- | --- | --- |
| Ver status | `rpm-ostree status` | `bootc status` |
| Atualizar | `rpm-ostree upgrade` | `bootc upgrade` |
| Reverter | `rpm-ostree rollback` | `bootc rollback` |
| Trocar imagem | `rpm-ostree rebase` | `bootc switch` |
| Instalar pacote | `rpm-ostree install` | Adicionar ao `Containerfile` e rebuildar |
| Remover pacote | `rpm-ostree uninstall` | Remover do `Containerfile` e rebuildar |
| Alterar kargs | `rpm-ostree kargs` | `kargs.d` na imagem ou `rpm-ostree kargs` local |

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
| --- | --- | --- |
| `bootc upgrade` recusa com "local rpm-ostree modifications" | Há camadas ou overrides locais. | `sudo rpm-ostree reset`; se precisar do pacote, adicione à imagem. |
| `override replace` não encontra o pacote | O pacote não está instalado na base. | Use `rpm-ostree install` ou um build da imagem; `replace` só troca o que existe. |
| `apply-live` não reflete a mudança | O componente exige reboot (kernel, systemd etc.). | Reinicie para ativar a nova implantação. |
| `refresh-md` falha | Repositórios offline ou cache inconsistente. | Verifique a rede e os arquivos em `/etc/yum.repos.d`; em bootc, prefira atualizar pela imagem. |
| Espaço insuficiente após várias camadas | Objetos e implantações antigas acumulados. | `rpm-ostree cleanup`, `ostree admin cleanup` e `ostree prune --refs-only`. |

## Referências

- [rpm-ostree — documentação upstream](https://coreos.github.io/rpm-ostree/)
- [Relação entre bootc e rpm-ostree](https://bootc.dev/bootc/bootc-relationships.7.html)
- [`ostree-comandos.md`](ostree-comandos.md)
- [`SIGNING.md`](SIGNING.md)
