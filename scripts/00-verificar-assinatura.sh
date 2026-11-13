#!/usr/bin/env bash
# Fase 0: confere a assinatura ANTES de criar qualquer recurso. Só lê, não cria nada.
#   1. qual assinatura e qual usuário estão ativos;
#   2. se o usuário tem o papel Owner (necessário para criar a service connection no Azure DevOps);
#   3. quais regiões a policy da assinatura permite;
#   4. em quais dessas regiões o Azure SQL aceita criar servidor, e se ACR e ACI existem nelas;
#   5. se os resource providers usados estão registrados.
# Uso (na raiz do repositório, no Git Bash): bash scripts/00-verificar-assinatura.sh

source "$(dirname "${BASH_SOURCE[0]}")/_comum.sh"

info "1. Assinatura ativa"
az account show --query "{assinatura:name, id:id, estado:state}" -o table
SUB_ID="$(az_tsv account show --query id)"

info "2. Papéis do seu usuário na assinatura (precisa aparecer Owner)"
USER_ID="$(az_tsv ad signed-in-user show --query id)"
az role assignment list --assignee "$USER_ID" --scope "/subscriptions/$SUB_ID" \
    --include-inherited --query "[].roleDefinitionName" -o tsv | tr -d '\r' | sort -u | sed 's/^/    /'

info "3. Regiões permitidas pela policy"
REGIOES="$(az_tsv policy assignment list \
    --query "[].parameters.listOfAllowedLocations.value[]" | sort -u)"
if [ -z "$REGIOES" ]; then
    echo "    Nenhuma policy de regiões encontrada. Testando uma lista de candidatas."
    REGIOES="brazilsouth centralus eastus eastus2 southcentralus westus2 mexicocentral"
else
    echo "$REGIOES" | sed 's/^/    /'
fi

info "4. Disponibilidade por região"
# Nomes das regiões onde ACR e ACI existem (em minúsculas e sem espaço, como "eastus2").
normalizar() { tr -d '\r' | tr '[:upper:]' '[:lower:]' | tr -d ' '; }
ACR_REGIOES="$(az_tsv provider show -n Microsoft.ContainerRegistry \
    --query "resourceTypes[?resourceType=='registries'].locations[]" | normalizar)"
ACI_REGIOES="$(az_tsv provider show -n Microsoft.ContainerInstance \
    --query "resourceTypes[?resourceType=='containerGroups'].locations[]" | normalizar)"

printf '    %-16s %-12s %-5s %-5s\n' "REGIÃO" "AZURE SQL" "ACR" "ACI"
for r in $REGIOES; do
    # "Available" = aceita criar servidor; "Visible" = existe, mas recusa novos servidores.
    sql="$(az_tsv rest --method get \
        --url "https://management.azure.com/subscriptions/$SUB_ID/providers/Microsoft.Sql/locations/$r/capabilities?api-version=2021-11-01" \
        --query status 2>/dev/null || echo "erro")"
    acr="não"; grep -qx "$r" <<<"$ACR_REGIOES" && acr="sim"
    aci="não"; grep -qx "$r" <<<"$ACI_REGIOES" && aci="sim"
    printf '    %-16s %-12s %-5s %-5s\n' "$r" "$sql" "$acr" "$aci"
done

info "5. Resource providers (NotRegistered é normal: o 01-provisionar.sh registra)"
for ns in Microsoft.Sql Microsoft.ContainerRegistry Microsoft.ContainerInstance; do
    printf '    %-30s %s\n' "$ns" "$(az_tsv provider show -n "$ns" --query registrationState)"
done

info "Pronto. Escolha uma região com Azure SQL 'Available', ACR 'sim' e ACI 'sim' e coloque em AZ_LOCATION no scripts/.env."
