#!/usr/bin/env bash
set -euo pipefail

# Executado automaticamente pelo Dev Containers logo após a criação do
# container (ver "postCreateCommand" em devcontainer.json). Use este arquivo
# para instalações/configurações que devem acontecer sempre que o container
# for (re)criado.
#
# Plugins/MCPs não são instalados automaticamente — veja scripts/plugins.sh
# para o catálogo e instale manualmente o que precisar.

echo "postCreate: iniciando setup do container..."

# Raiz do projeto = pasta pai deste script (independe do workspaceFolder
# configurado no devcontainer.json, que já mudou de nome antes).
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Credenciais git + GH_TOKEN via token (regenerado a cada recriação do container) ----
# $ROOT_DIR/.devcontainer/.env (com GIT_USERNAME/GIT_TOKKEN e .git/config) é
# bind mount do host e sobrevive a rebuilds; /home/app é filesystem do
# container e é descartado a cada rebuild. credential.helper=store já está
# configurado em $ROOT_DIR/.git/config (persiste), mas o arquivo
# ~/.git-credentials com o token em si precisa ser recriado aqui, assim como
# o export do GH_TOKEN (usado pela gh CLI) em ~/.bashrc.
DEVCONTAINER_ENV="$ROOT_DIR/.devcontainer/.env"
if [ -f "$DEVCONTAINER_ENV" ]; then
    set -a
    # shellcheck disable=SC1091
    source "$DEVCONTAINER_ENV"
    set +a
    if [ -n "${GIT_USERNAME:-}" ] && [ -n "${GIT_TOKKEN:-}" ]; then
        echo "postCreate: configurando credenciais git via token..."
        # url-encode mínimo (usuário costuma ser um e-mail, com '@'/':'/'%')
        enc_user="${GIT_USERNAME//%/%25}"
        enc_user="${enc_user//@/%40}"
        enc_user="${enc_user//:/%3A}"
        enc_token="${GIT_TOKKEN//%/%25}"
        printf 'https://%s:%s@github.com\n' "$enc_user" "$enc_token" > ~/.git-credentials
        chmod 600 ~/.git-credentials
    else
        echo "postCreate: GIT_USERNAME / GIT_TOKKEN não definidos em .devcontainer/.env, pulando credenciais git."
    fi

    if [ -n "${GIT_TOKKEN:-}" ]; then
        echo "postCreate: configurando GH_TOKEN para a gh CLI..."
        cat > ~/.gh_token_env <<EOF
export GH_TOKEN="${GIT_TOKKEN}"
EOF
        chmod 600 ~/.gh_token_env
        if ! grep -qF '~/.gh_token_env' ~/.bashrc 2>/dev/null; then
            {
                echo ''
                echo '# GH_TOKEN para a gh CLI (gerado pelo postCreate.sh a partir do .devcontainer/.env)'
                echo '[ -f ~/.gh_token_env ] && source ~/.gh_token_env'
            } >> ~/.bashrc
        fi
    else
        echo "postCreate: GIT_TOKKEN não definido em .devcontainer/.env, pulando GH_TOKEN."
    fi
else
    echo "postCreate: $DEVCONTAINER_ENV não encontrado, pulando credenciais git."
fi

# Alias para Antigravity CLI com --dangerously-skip-permissions
if ! grep -qF "alias agy+=" ~/.bashrc 2>/dev/null; then
    echo "postCreate: configurando alias 'agy+' no ~/.bashrc..."
    {
        echo ''
        echo '# Alias Antigravity (sem checagem de permissões)'
        echo "alias agy+='agy --dangerously-skip-permissions'"
    } >> ~/.bashrc
fi

echo "postCreate: concluído."
