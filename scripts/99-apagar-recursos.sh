#!/usr/bin/env bash
# Apaga TODOS os recursos do SampaTech (o Resource Group inteiro), para parar o custo.
# Use só depois da apresentação e da nota. Não dá para desfazer: banco e imagens somem.
# Uso (na raiz do repositório, no Git Bash): bash scripts/99-apagar-recursos.sh

source "$(dirname "${BASH_SOURCE[0]}")/_comum.sh"

carregar_env
exigir_login

if ! existe az group show --name "$RG"; then
    ok "o $RG não existe. Nada a apagar."
    exit 0
fi

info "Recursos que serão apagados"
az resource list --resource-group "$RG" --query "[].{nome:name, tipo:type}" -o table

echo
read -r -p "Para confirmar, digite o nome do grupo ($RG): " confirmacao
[ "$confirmacao" = "$RG" ] || erro "confirmação diferente. Nada foi apagado."

az group delete --name "$RG" --yes --no-wait
ok "exclusão iniciada (leva alguns minutos). Confira com: az group exists --name $RG"
