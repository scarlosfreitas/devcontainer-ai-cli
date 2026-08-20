#!/usr/bin/env pwsh
<#
.SYNOPSIS
  install.ps1 — bootstrap do devcontainer-ai-cli (Windows/PowerShell).

.DESCRIPTION
  Baixa o kit deste repositório, remove o .git do template, pergunta os dados
  do novo projeto (nome), reescreve os arquivos afetados e inicializa um
  repositório git novo para o projeto.

  O nome do devcontainer/container NÃO é perguntado: é derivado do nome do
  projeto (RF2 do PRD).

.EXAMPLE
  # Downloader avulso, totalmente interativo:
  irm https://raw.githubusercontent.com/scarlosfreitas/devcontainer-ai-cli/main/scripts/install.ps1 | iex

.EXAMPLE
  # Não-interativo, via variáveis de ambiente (necessário ao usar "irm | iex",
  # que não aceita parâmetros de linha de comando):
  $env:INSTALL_NAME = "Meu Projeto"
  $env:INSTALL_PROJECT_FOLDER = "/code/meu-projeto"
  $env:INSTALL_YES = "1"
  irm .../install.ps1 | iex

.EXAMPLE
  # Baixado localmente, com parâmetros normais:
  .\install.ps1 -Name "Meu Projeto" -Yes
#>
param(
  [string]$Name = $env:INSTALL_NAME,
  [string]$ProjectFolder = $env:INSTALL_PROJECT_FOLDER,
  [string]$Dir = $(if ($env:INSTALL_DIR) { $env:INSTALL_DIR } else { "." }),
  [string]$RepoUrl = $(if ($env:INSTALL_REPO_URL) { $env:INSTALL_REPO_URL } else { "https://github.com/scarlosfreitas/devcontainer-ai-cli.git" }),
  [string]$Branch = $(if ($env:INSTALL_BRANCH) { $env:INSTALL_BRANCH } else { "main" }),
  [switch]$Yes = [bool]$env:INSTALL_YES,
  [switch]$NoCommit = [bool]$env:INSTALL_NO_COMMIT
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Step($msg) { Write-Host "==> $msg" }
function Write-Warn2($msg) { Write-Warning $msg }
function Fail($msg) { Write-Host "Erro: $msg" -ForegroundColor Red; exit 1 }

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
  Fail "git é obrigatório e não foi encontrado no PATH."
}

function Read-HostOrDefault([string]$Message, [string]$Default) {
  # Read-Host lança erro em hosts não interativos (ex.: pipelines de CI); nesse
  # caso caímos no valor padrão em vez de travar o script.
  try {
    $value = Read-Host "$Message [$Default]"
  } catch {
    Write-Warn2 "terminal não interativo; usando padrão para `"$Message`": $Default"
    return $Default
  }
  if ([string]::IsNullOrWhiteSpace($value)) { return $Default } else { return $value }
}

function Prompt-Default([string]$Current, [string]$Message, [string]$Default) {
  if (-not [string]::IsNullOrWhiteSpace($Current)) { return $Current }
  if ($Yes) { return $Default }
  return Read-HostOrDefault -Message $Message -Default $Default
}

function Slugify([string]$Text) {
  $normalized = $Text.ToLowerInvariant().Normalize([System.Text.NormalizationForm]::FormD)
  $sb = New-Object System.Text.StringBuilder
  foreach ($ch in $normalized.ToCharArray()) {
    $cat = [System.Globalization.CharUnicodeInfo]::GetUnicodeCategory($ch)
    if ($cat -ne [System.Globalization.UnicodeCategory]::NonSpacingMark) { [void]$sb.Append($ch) }
  }
  $slug = [System.Text.RegularExpressions.Regex]::Replace($sb.ToString(), '[^a-z0-9]+', '-')
  return $slug.Trim('-')
}

# --- diretório de destino -------------------------------------------------

New-Item -ItemType Directory -Force -Path $Dir | Out-Null
$Dir = (Resolve-Path $Dir).Path

$existing = Get-ChildItem -Force -Path $Dir -ErrorAction SilentlyContinue
if ($existing) {
  if ($Yes) {
    Write-Warn2 "diretório '$Dir' não está vazio; prosseguindo (-Yes)."
  } else {
    $reply = $null
    try { $reply = Read-Host "Diretório '$Dir' não está vazio. Continuar mesmo assim? [y/N]" }
    catch { Fail "diretório '$Dir' não está vazio. Rode novamente com -Yes para prosseguir." }
    # Cast explícito para string: "$null -notmatch ..." não retorna $false como se
    # esperaria (é um caso especial do operador -match/-notmatch em PowerShell) e
    # deixaria essa checagem de segurança passar aberta em modo não interativo.
    if ([string]$reply -notmatch '^[Yy]') { Fail "cancelado pelo usuário." }
  }
}

# --- baixa o kit e remove o .git do template ------------------------------

$TmpDir = Join-Path ([System.IO.Path]::GetTempPath()) ("devcontainer-ai-cli-" + [System.Guid]::NewGuid().ToString("N"))

try {
  Write-Step "baixando o kit ($RepoUrl, branch $Branch)..."
  git clone --quiet --depth 1 --branch $Branch $RepoUrl $TmpDir
  if ($LASTEXITCODE -ne 0) { Fail "falha ao clonar $RepoUrl (branch $Branch)." }
  Remove-Item -Recurse -Force (Join-Path $TmpDir ".git")

  Write-Step "copiando arquivos para '$Dir'..."
  # Lista FECHADA do RF6: só estes itens vão para o projeto gerado. O que não
  # estiver aqui (README.md, CLAUDE.md, .claude/PRD.md, .claude/settings.local.json,
  # .agents/skills/, ...) fica só no template.
  $dirItems = @('.claude', '.devcontainer', 'prompts', 'scripts')
  $fileItems = @('.gitignore', 'skills-lock.json')
  # scripts/ vai item a item, pulando os instaladores: install.sh e install.ps1
  # materializam um projeto novo a partir do template e não têm função dentro
  # do projeto gerado.
  $scriptsExclude = @('install.sh', 'install.ps1')

  # valida tudo antes de copiar qualquer coisa, para não deixar o destino pela metade
  foreach ($d in $dirItems) {
    if (-not (Test-Path (Join-Path $TmpDir $d))) { Fail "item obrigatório ausente no template: $d/" }
  }
  foreach ($f in $fileItems) {
    if (-not (Test-Path (Join-Path $TmpDir $f))) { Fail "item obrigatório ausente no template: $f" }
  }

  foreach ($d in $dirItems) {
    $dest = Join-Path $Dir $d
    New-Item -ItemType Directory -Force -Path $dest | Out-Null
    if ($d -eq 'scripts') {
      Copy-Item -Path (Join-Path (Join-Path $TmpDir $d) '*') -Destination $dest -Recurse -Force -Exclude $scriptsExclude
    } else {
      Copy-Item -Path (Join-Path (Join-Path $TmpDir $d) '*') -Destination $dest -Recurse -Force
    }
  }
  foreach ($f in $fileItems) {
    Copy-Item -Path (Join-Path $TmpDir $f) -Destination (Join-Path $Dir $f) -Force
  }

  # .claude/ é copiado exceto estes dois: o PRD.md é o do template (produto
  # devcontainer-ai-cli), não faz sentido no projeto novo, e não é substituído
  # por nenhum esqueleto — o usuário escreve o seu (prompts/1-create-prd.md).
  # O settings.local.json do template desativaria skills no projeto novo.
  Remove-Item -Force -ErrorAction SilentlyContinue `
    -Path (Join-Path $Dir '.claude/PRD.md'), (Join-Path $Dir '.claude/settings.local.json')

  # .claude/skills/ é um conjunto de symlinks para .agents/skills/, que NÃO é
  # copiado (RF10: as skills são materializadas sob demanda no projeto novo).
  # Sem isso o projeto nasceria com links quebrados.
  # (Detecção de link quebrado varia entre versões do PowerShell; como .agents/
  # nunca é copiado, todos esses links são quebrados por construção.)
  $skillsDir = Join-Path $Dir '.claude/skills'
  if ((Test-Path $skillsDir) -and -not (Test-Path (Join-Path $Dir '.agents'))) {
    Remove-Item -Force -Recurse -ErrorAction SilentlyContinue $skillsDir
  }
} finally {
  Remove-Item -Recurse -Force -ErrorAction SilentlyContinue $TmpDir
}

Set-Location $Dir

# --- coleta de dados do novo projeto --------------------------------------

$DefaultName = Split-Path -Leaf $Dir
$Name = Prompt-Default -Current $Name -Message "Nome do projeto" -Default $DefaultName

# RF3: o mesmo caminho absoluto no host e dentro do container. O padrão é a
# pasta de instalação; o usuário pode informar outro valor, mas ele será usado
# nos DOIS lugares (PROJECT_FOLDER e workspaceFolder), nunca em só um.
# O caminho vai para dentro do container (Linux), então usamos "/" mesmo quando
# o host é Windows.
$DefaultFolder = ($Dir -replace '\\', '/')
$ProjectFolder = Prompt-Default -Current $ProjectFolder -Message "Caminho do projeto no host e no container" -Default $DefaultFolder
$ProjectFolder = ($ProjectFolder -replace '\\', '/').TrimEnd()

# RF2: o nome do container é derivado do nome do projeto, não perguntado.
$ContainerSlug = Slugify $Name
if ([string]::IsNullOrWhiteSpace($ContainerSlug)) { $ContainerSlug = Slugify $DefaultName }
if ([string]::IsNullOrWhiteSpace($ContainerSlug)) { Fail "não foi possível derivar um nome de container a partir de '$Name'." }

# --- reescreve devcontainer.json -------------------------------------------

Write-Step "atualizando .devcontainer/devcontainer.json..."
# Reescrita por linha (em vez de ConvertFrom-Json/ConvertTo-Json): o arquivo é
# JSONC, e o round-trip pelo parser apagaria os comentários e reordenaria as
# chaves. Tudo que vier depois de "name": / "workspaceFolder": é substituído,
# sem depender do valor que veio do template.
function Escape-Json([string]$Text) { return $Text.Replace('\', '\\').Replace('"', '\"') }

$dcPath = Join-Path $Dir ".devcontainer/devcontainer.json"
$nameJson = Escape-Json $Name
$folderJson = Escape-Json $ProjectFolder

$seenName = $false
$seenFolder = $false
$dcOut = foreach ($line in (Get-Content -Path $dcPath)) {
  if (-not $seenName -and $line -match '^\s*"name"\s*:') {
    $seenName = $true
    "  `"name`": `"$nameJson`","
    continue
  }
  if (-not $seenFolder -and $line -match '^\s*"workspaceFolder"\s*:') {
    $seenFolder = $true
    "  `"workspaceFolder`": `"$folderJson`","
    continue
  }
  $line
}
if (-not $seenName) { Fail "chave `"name`" não encontrada em devcontainer.json." }
if (-not $seenFolder) { Fail "chave `"workspaceFolder`" não encontrada em devcontainer.json." }
($dcOut -join "`n") + "`n" | Set-Content -Path $dcPath -Encoding utf8 -NoNewline

# --- gera o .env a partir do .env.example ----------------------------------

Write-Step "gerando .devcontainer/.env..."
$envExamplePath = Join-Path $Dir ".devcontainer/.env.example"
$envPath = Join-Path $Dir ".devcontainer/.env"
# PROJECT_FOLDER precisa ser idêntico ao workspaceFolder acima (RF3): o
# docker-compose monta o projeto nesse caminho dentro do container.
# DOCKER_IMAGE_NAME e DOCKER_IMAGE_TAG não são tocados: permanecem os valores
# de .env.example (a imagem é construída/publicada à parte, não por projeto).
$seenEnvFolder = $false
$envLines = Get-Content -Path $envExamplePath | ForEach-Object {
  if ($_ -match '^CONTAINER_NAME=') { "CONTAINER_NAME=$ContainerSlug" }
  elseif ($_ -match '^PROJECT_FOLDER=') { $seenEnvFolder = $true; "PROJECT_FOLDER=$ProjectFolder" }
  else { $_ }
}
if (-not $seenEnvFolder) { $envLines += "PROJECT_FOLDER=$ProjectFolder" }
($envLines -join "`n") + "`n" | Set-Content -Path $envPath -Encoding utf8 -NoNewline

# Nada a gerar aqui: a lista fechada do RF6 não inclui .claude/PRD.md — o
# projeto novo nasce sem PRD, a ser escrito pelo usuário (ver prompts/1-create-prd.md).
# Os itens que só fazem sentido no template nunca chegam ao projeto gerado —
# incluindo scripts/install.sh e scripts/install.ps1, que ficam de fora da cópia.

# --- git init ------------------------------------------------------------------

Write-Step "inicializando repositório git..."
git init --quiet
if ($LASTEXITCODE -ne 0) { Fail "git init falhou." }
if (-not $NoCommit) {
  git add -A
  git commit --quiet -m "chore: bootstrap a partir do template devcontainer-ai-cli"
}

# --- resumo ----------------------------------------------------------------------

Write-Host ""
Write-Step "projeto '$Name' criado em '$Dir'."
Write-Host "  container:      $ContainerSlug"
Write-Host "  PROJECT_FOLDER: $ProjectFolder (igual ao workspaceFolder)"
Write-Host "Próximos passos:"
Write-Host "  1. Copie .env.example para .env (GIT_USERNAME/GIT_EMAIL/GIT_NAME) e"
Write-Host "     preencha GIT_TOKKEN em .devcontainer/.env."
Write-Host "  2. Construa a imagem (scripts/build-image-devcontainer.sh via WSL/Git Bash, ou 'docker build')"
Write-Host "     ou publique-a em um registry."
Write-Host "  3. Abra a pasta no VS Code."
Write-Host "  4. Ctrl+Shift+P -> Dev Containers: Reopen in Container."
Write-Host "  5. Faça login nos CLIs de IA que for usar (claude, codex, gemini, agy)."
Write-Host "  6. Escreva .claude/PRD.md (ver prompts/1-create-prd.md)."
