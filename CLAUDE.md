# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **Fonte de verdade do produto:** [`.claude/PRD.md`](.claude/PRD.md) (o quê e por quê).
> Este arquivo descreve **como** trabalhar aqui. Em caso de conflito entre este documento e o
> PRD, o PRD vence — e o conflito deve ser corrigido, não contornado.
>
> `CLAUDE.md` é artefato **só do template** (`[t]`): os instaladores o excluem do projeto gerado.

---

## 1. O que é este repositório

`devcontainer-ai-cli` é um **template (esqueleto) de projeto**, não
uma aplicação. Ele entrega uma **imagem Docker e uma estrutura de projeto** para desenvolvimento
com **CLIs de IA** — Claude Code (Anthropic), Codex CLI (OpenAI), Gemini CLI e Antigravity CLI/`agy`
(Google) —, seus gerenciadores de pacote (`uv`, `npm`/Node.js, Bun) e ferramentas de apoio
(edição de texto, rede, Docker-out-of-Docker, `gh`, OpenSpec, monitoramento de tokens), mais um
**instalador de um comando** que materializa um projeto novo a partir dele — e a **trilha de
revisão SDD** (§5.1) que se usa dentro do projeto gerado.

Não há código de aplicação, não há build de software, não há suíte de testes automatizados
(testes dos instaladores estão explicitamente fora de escopo — PRD §9).
O "produto" são: a imagem de desenvolvimento (`.devcontainer/Dockerfile-devcontainer`), os scripts
de bootstrap e build, a configuração do devcontainer e os prompts/subagentes de revisão.

**Idioma:** todo conteúdo do repositório (comentários, mensagens de script, documentação) é em
**português**. Mantenha assim.

---

## 2. Invariante central — paridade de caminho

`PROJECT_FOLDER` (em `.devcontainer/.env`) **=** `workspaceFolder` (em `.devcontainer/devcontainer.json`)
**=** caminho absoluto da pasta do projeto no host.

Essa é a restrição estrutural do produto (PRD §1, RF3): garante que os CLIs de IA enxerguem o mesmo
caminho absoluto no host e dentro do container, preservando configuração, memória e sessões.
Se os dois divergirem, **a instalação é inválida**. Nunca "simplifique" para `/workspace` ou
`/workspaces/${localWorkspaceFolderBasename}`.

O instalador coleta **um** caminho (padrão: a pasta de instalação; ou `--project-folder` /
`INSTALL_PROJECT_FOLDER`) e o grava nos dois arquivos de uma vez — nunca em só um. Caminho
relativo é rejeitado.

Neste repositório-template o valor atual é `/code/pessoal/devcontainer-ai-cli`, em ambos os
arquivos. (O `WORKDIR /workspace` do `Dockerfile-devcontainer` é irrelevante aqui: o compose monta
o projeto em `${PROJECT_FOLDER}` e o devcontainer entra por `workspaceFolder`.)


**Lista fechada do RF6** — o projeto gerado recebe **apenas**: `.claude/` (exceto
`settings.local.json`, `PRD.md`), `.devcontainer/`, `prompts/`,
`scripts/` (exceto `install.sh`, `install.ps1`), `.gitignore`,
`skills-lock.json`. Nada além disso —
em especial, `.claude/PRD.md` **não** é regerado como esqueleto; o projeto nasce sem PRD. Ao mexer
nos instaladores, verifique essa lista: ela é implementada como cópia item a item (nunca "copia tudo
e apaga depois") e é validada por inteiro **antes** de a primeira cópia acontecer, para não deixar o
destino pela metade.

---

## 4. Comandos

Não há `make`, `npm test` ou pipeline. O que se roda aqui:

```bash
bash scripts/install.sh --help          # bootstrap; ver flags
bash scripts/clean.sh                   # remove container/volumes (preserva o volume "vscode")
bash scripts/clean.sh -y                # sem confirmação
bash .devcontainer/postCreate.sh        # idempotente; roda sozinho no create do container
bash scripts/build-image-devcontainer.sh          # builda a imagem baixando do GitHub (padrão); necessário antes do 1º "Reopen in Container"
bash scripts/build-image-devcontainer.sh --local  # builda a partir do .devcontainer/.env e Dockerfile-devcontainer locais
bash scripts/build-image-devcontainer.sh --local --no-cache   # flags desconhecidas são repassadas ao docker build
```

Validação manual do ambiente (critérios de aceite do PRD §10):

```bash
whoami            # app
locale            # C.UTF-8
for c in node npm uv bun git gh sudo docker nano ping ccusage claude-usage openspec claude codex gemini agy; do command -v $c; done
```

---

## 5. Convenções ao editar

**Instaladores (`install.sh` / `install.ps1`)** — os dois são a mesma especificação em dois idiomas:
**toda mudança em um exige a mudança equivalente no outro**. Ambos devem: abortar em pasta não vazia
sem `--yes`/`-Yes`, funcionar sem TTY, clonar com `--depth 1`, apagar o `.git` do template,
respeitar a lista fechada do RF6, gravar `PROJECT_FOLDER`/`workspaceFolder` com o `pwd` da
instalação, derivar `CONTAINER_NAME` do nome do projeto normalizado e rodar `git init` (+ commit,
salvo `--no-commit`). `DOCKER_IMAGE_NAME`/`DOCKER_IMAGE_TAG` **não** são reescritos pelo instalador:
o projeto gerado herda os valores de `.env.example` como estão — a imagem é construída/publicada à
parte (`scripts/build-image-devcontainer.sh`), não uma por projeto. Nenhum dos dois gera
`.claude/PRD.md`: o `.claude/PRD.md` do template é removido junto com `settings.local.json`, e não é
substituído por nada.

Normalização do nome (RF2): espaços → `-`, tudo minúsculo (a `slugify` também remove acentos e
outros caracteres inválidos em nome de container). `Meu Projeto Novo` → `meu-projeto-novo`, usado
também como nome do container. **Não existe pergunta, flag nem variável para o nome do container** —
não reintroduza `--container`/`INSTALL_CONTAINER`.

Reescrita do `devcontainer.json`: é feita **linha a linha**, substituindo tudo que vier depois de
`"name":` e `"workspaceFolder":`, sem casar o valor antigo, e abortando se qualquer uma das duas
chaves não existir. O arquivo é **JSONC** — não passe por `ConvertFrom-Json`/`jq`, que apagam os
comentários. Os valores entram pelo ambiente (`ENVIRON` no awk), nunca por `awk -v`, que
reprocessaria os escapes. Não existe pergunta, flag nem variável para a descrição do projeto — o
instalador não escreve `"description":`; não reintroduza `--description`/`INSTALL_DESCRIPTION`.

Os diretórios de config (`/home/app/.claude`, `.gemini`, `.codex`, `.agents`) são pré-criados com
dono `app:app` **antes** do `USER app`, para que os bind mounts do `devcontainer.json` (RF8) herdem
a permissão certa na primeira subida. Não há nenhum `RUN` depois do `USER app` hoje — só `WORKDIR`.
**Cuidado com `USER` e `$HOME` durante o build** continua valendo como princípio geral para
ferramentas *futuras*: se um instalador novo não suportar redirecionar seu diretório de destino, ele
volta a precisar do padrão antigo (rodar como usuário `app`, com `ENV PATH` declarado antes).
`arch=amd64` é fixo (Chrome e `gh`); multiarquitetura está fora de escopo. O cliente Docker
(`docker-ce-cli`/`docker-compose-plugin`) é só o cliente — o comentário do Dockerfile assume um
mount de `/var/run/docker.sock` que **não existe** hoje em `devcontainer.json` (pendência, §6); não
assuma DooD funcional sem checar isso primeiro.

**`devcontainer.json`** — o bloco `GIT_CONFIG_*` com `VALUE_0` **vazio** é intencional:
`credential.helper` é cumulativo, e o valor vazio zera a lista injetada pela extensão Dev Containers
antes de definir `store`. Junto com `dev.containers.copyGitConfig: false`, é o que faz `git push`
funcionar no container. Não "limpe" isso. O arquivo usa comentários (JSONC) — preserve-os. Os quatro
mounts (`~/.claude`, `~/.gemini`, `~/.codex`, `~/.agents`) seguem o mesmo padrão: qualquer CLI de IA
novo que entrar na imagem (RF7) precisa **de um par** — o mount aqui e o `mkdir`/`chown` prévio no
Dockerfile —, senão perde config/credenciais a cada rebuild (RF8) ou sobe como root sem permissão de
escrita.

**`scripts/build-image-devcontainer.sh` (RF13)** — builda `.devcontainer/Dockerfile-devcontainer`
fora do `docker-compose`, em dois modos:

* **Padrão (remoto)** — clona `REPO_URL`/`BRANCH` (default: `devcontainer-ai-cli`/`main`) num
  diretório temporário e lê `DOCKER_IMAGE_NAME`/`DOCKER_IMAGE_TAG` de `.devcontainer/.env.example`
  ali dentro. Existe para funcionar como downloader avulso (`curl | bash`, igual ao `install.sh`),
  sem exigir um clone local do projeto.
* **`--local`** — usa `.devcontainer/.env` e `.devcontainer/Dockerfile-devcontainer` do próprio
  projeto onde o script está (resolvido pelo caminho do script, mesmo padrão de `clean.sh`), para
  testar mudanças no Dockerfile antes de publicá-las.

Em ambos os modos, o valor lido é `DOCKER_IMAGE_NAME`/`DOCKER_IMAGE_TAG` — as **mesmas** variáveis
que o `docker-compose.yml` já usa para `image:`, não campos novos. Qualquer opção não reconhecida
(`--local`, `--repo-url`, `--branch`, `-h`) é repassada ao `docker build` (ex.: `--no-cache`).
Não há um segundo Dockerfile na raiz: já se cogitou isso (imagem multiestágio separada) e foi
descartado, porque quase tudo instalado no `Dockerfile-devcontainer` é pacote `apt`/`npm` — não há
alvo de build pesado para "copiar só os binários", e replicar o ferramental num segundo arquivo só
criaria dessincronia para manter.

**`postCreate.sh`** — precisa ser idempotente: rodar duas vezes não pode duplicar linha no
`~/.bashrc` (hoje via `grep -qF`), e `.env` ausente/incompleto deve pular o passo com mensagem e
**sair com sucesso**. A raiz do projeto é resolvida pelo caminho do próprio script, nunca pelo nome
da pasta.

---

## 5.2 `prompts/` — o roteiro

Numerados na ordem de uso, executados **dentro do projeto gerado**, não aqui:

| Arquivo | Papel |
|---|---|
| `1-create-prd.md` | Escreve o PRD do projeto novo (o template não entrega esqueleto) |
| `2-create-claude.md` | Gera o `CLAUDE.md` do projeto a partir do PRD + `./references` |
| `3-create-agents.md` | Gera os subagentes da camada 2 — **variante Blazor/.NET** |
| `4-create-readme.md` | Gera o README do projeto |
| `5-new-feature-script.md` | **Variante agnóstica de stack** do `3-create-agents.md` (`review-code` no lugar de `review-blazor`); o nome do arquivo não corresponde ao conteúdo |
| `6-final-review.md` | Aciona a revisão consolidada da camada 2 |

`3-create-agents.md` e `5-new-feature-script.md` são hoje quase idênticos (diferem só no
especialista de framework) e `6-final-review.md` se espelha na lista de especialistas dos dois —
**mudança em um exige a mudança equivalente nos outros**, como acontece com os instaladores.