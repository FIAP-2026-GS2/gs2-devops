#!/usr/bin/env bash
# Funções e nomes compartilhados pelos scripts de infraestrutura.
# Não rode este arquivo direto: os outros scripts carregam ele com "source".

set -euo pipefail

# No Git Bash, impede que "/subscriptions/..." vire um caminho do Windows.
export MSYS_NO_PATHCONV=1

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info() { printf '\n==> %s\n' "$*"; }
ok()   { printf '    ok: %s\n' "$*"; }
erro() { printf '\nERRO: %s\n' "$*" >&2; exit 1; }

# A Azure CLI no Windows devolve o -o tsv com \r no fim da linha. O tr remove.
az_tsv() { az "$@" -o tsv | tr -d '\r'; }

# Confere o login e, se pedido, troca para a assinatura do .env.
exigir_login() {
    az account show >/dev/null 2>&1 || erro "você não está logado. Rode: az login"
    if [ -n "${AZ_SUBSCRIPTION_ID:-}" ]; then
        az account set --subscription "$AZ_SUBSCRIPTION_ID"
    fi
    ok "assinatura: $(az_tsv account show --query name)"
}

# Lê o scripts/.env (removendo \r, caso ele tenha sido salvo no Bloco de Notas),
# valida os campos e monta os nomes dos recursos.
carregar_env() {
    local env_file="$SCRIPTS_DIR/.env"
    [ -f "$env_file" ] || erro "crie o scripts/.env a partir do scripts/.env.example."

    set -a
    # shellcheck disable=SC1090
    source <(tr -d '\r' < "$env_file")
    set +a

    [ -n "${AZ_LOCATION:-}" ] || erro "preencha AZ_LOCATION no scripts/.env."
    [[ "${NAME_SUFFIX:-}" =~ ^[a-z0-9]{3,10}$ ]] \
        || erro "NAME_SUFFIX precisa ter de 3 a 10 letras minúsculas ou números."
    [ -n "${SQL_ADMIN_USER:-}" ] || erro "preencha SQL_ADMIN_USER no scripts/.env."
    case "${SQL_ADMIN_USER,,}" in
        admin|sa|root|administrator) erro "o Azure SQL recusa o usuário '$SQL_ADMIN_USER'." ;;
    esac
    [ "${#SQL_ADMIN_PASSWORD}" -ge 12 ] || erro "SQL_ADMIN_PASSWORD precisa de 12 ou mais caracteres."

    # Padrão de nomes: <tipo>-sampatech[-sufixo]. O ACR não aceita hífen.
    RG="rg-sampatech"
    SQL_SERVER="sql-sampatech-${NAME_SUFFIX}"
    SQL_DB="SampaTech"
    ACR="acrsampatech${NAME_SUFFIX}"
    ACI="aci-sampatech-api"
    ACI_DNS="sampatech-${NAME_SUFFIX}"
    TAGS=(projeto=sampatech disciplina=devops entrega=gs-2026-2)
}

# Verdadeiro se o comando "az ... show" encontrar o recurso.
existe() { "$@" --only-show-errors >/dev/null 2>&1; }
