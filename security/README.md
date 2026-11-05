# Segurança e verificação

Esta pasta concentra as chaves e políticas de verificação usadas pelo build e
pelo sistema instalado.

| Arquivo | Função |
| --- | --- |
| `cosign.pub` | Chave **pública** de assinatura da imagem. Você precisa gerá-la (`cosign generate-key-pair`) e fazer commit. |
| `policy.json` | Política do `containers/image` que exige assinatura `sigstoreSigned` para a imagem deste repositório. |
| `registries.d/ghcr.yaml` | Habilita a descoberta das assinaturas `.sig` no GHCR. |
| `keys/RPM-GPG-KEY-slaanesh` | Chave pública do repositório negativo17, usada para validar os RPMs da NVIDIA. |

## O que NUNCA deve entrar aqui

- `cosign.key`
- qualquer chave privada, token ou senha

O `.gitignore` da raiz já bloqueia `*.key`.

## Guia completo

Passo a passo de geração de chaves, secrets do GitHub, primeira migração e
testes de verificação: [`docs/SIGNING.md`](../docs/SIGNING.md).
