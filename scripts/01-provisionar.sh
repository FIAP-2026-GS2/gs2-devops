#!/usr/bin/env bash
# Cria a infraestrutura do SampaTech na Azure:
#   Resource Group → Azure SQL (servidor, firewall e banco) → ACR → ACI.
# Pode rodar de novo: o que já existe é mantido, e só o que falta é criado.
# Pré-requisitos: az login e o scripts/.env preenchido (copie do .env.example).
# Uso (na raiz do repositório, no Git Bash): bash scripts/01-provisionar.sh
#
# As tabelas NÃO são criadas aqui: quem aplica o scripts/script-bd.sql é a Release,
# antes de cada deploy (o script é idempotente). O ACI nasce com uma imagem
# provisória, e a Release troca pela imagem da API que o CI enviou ao ACR.

source "$(dirname "${BASH_SOURCE[0]}")/_comum.sh"

carregar_env
exigir_login

info "Registrando os resource providers (só na primeira vez demora)"
for ns in Microsoft.Sql Microsoft.ContainerRegistry Microsoft.ContainerInstance; do
    az provider register --namespace "$ns" --wait --only-show-errors
    ok "$ns"
done

info "Resource Group $RG ($AZ_LOCATION)"
if existe az group show --name "$RG"; then
    rg_loc="$(az_tsv group show --name "$RG" --query location)"
    [ "$rg_loc" = "$AZ_LOCATION" ] \
        || erro "o $RG já existe em $rg_loc. Apague (bash scripts/99-apagar-recursos.sh) ou use AZ_LOCATION=$rg_loc."
    ok "já existe"
else
    az group create --name "$RG" --location "$AZ_LOCATION" --tags "${TAGS[@]}" -o none
    ok "criado"
fi

info "Servidor Azure SQL $SQL_SERVER"
if existe az sql server show --name "$SQL_SERVER" --resource-group "$RG"; then
    ok "já existe"
else
    az sql server create --name "$SQL_SERVER" --resource-group "$RG" --location "$AZ_LOCATION" \
        --admin-user "$SQL_ADMIN_USER" --admin-password "$SQL_ADMIN_PASSWORD" \
        --minimal-tls-version 1.2 --tags "${TAGS[@]}" -o none
    ok "criado"
fi

info "Firewall do SQL"
# 0.0.0.0 é a regra especial "Allow Azure services": libera o ACI e os agentes
# hospedados do Azure DevOps (a Release aplica o DDL de dentro da Azure).
az sql server firewall-rule create --resource-group "$RG" --server "$SQL_SERVER" \
    --name AllowAzureServices --start-ip-address 0.0.0.0 --end-ip-address 0.0.0.0 -o none
ok "AllowAzureServices"

# O seu IP, para os SELECTs do vídeo (Query Editor do portal ou VS Code).
ip="${CLIENT_IP:-$(curl -fsS --max-time 10 https://api.ipify.org || true)}"
if [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    az sql server firewall-rule create --resource-group "$RG" --server "$SQL_SERVER" \
        --name ClienteLocal --start-ip-address "$ip" --end-ip-address "$ip" -o none
    ok "ClienteLocal ($ip)"
else
    echo "    aviso: não descobri o seu IP. Preencha CLIENT_IP no .env e rode de novo,"
    echo "    ou libere o IP pelo Query Editor do portal quando ele pedir."
fi

info "Banco $SQL_DB (Basic, 5 DTUs, backup local)"
if existe az sql db show --name "$SQL_DB" --server "$SQL_SERVER" --resource-group "$RG"; then
    ok "já existe"
else
    az sql db create --name "$SQL_DB" --server "$SQL_SERVER" --resource-group "$RG" \
        --service-objective Basic --backup-storage-redundancy Local \
        --tags "${TAGS[@]}" -o none
    ok "criado"
fi

info "Azure Container Registry $ACR (Basic)"
if existe az acr show --name "$ACR" --resource-group "$RG"; then
    ok "já existe"
else
    # admin-enabled: o ACI precisa de usuário e senha para puxar a imagem. A Release
    # lê essa senha na hora do deploy (az acr credential show): ela não fica guardada em lugar nenhum.
    az acr create --name "$ACR" --resource-group "$RG" --location "$AZ_LOCATION" \
        --sku Basic --admin-enabled true --tags "${TAGS[@]}" -o none
    ok "criado"
fi

info "Azure Container Instance $ACI (imagem provisória)"
if existe az container show --name "$ACI" --resource-group "$RG"; then
    ok "já existe"
else
    # Imagem pública de exemplo da Microsoft, só para o recurso e o DNS existirem.
    # A primeira Release recria o container com a imagem da API, na porta 8080.
    # 0,5 vCPU e 1 GB: o ACI cobra por segundo de CPU e memória, e a API cabe nisso
    # (metade do custo de 1 vCPU e 1,5 GB; o crédito da assinatura de estudante é limitado).
    az container create --name "$ACI" --resource-group "$RG" --location "$AZ_LOCATION" \
        --image mcr.microsoft.com/azuredocs/aci-helloworld:latest --os-type Linux \
        --cpu 0.5 --memory 1 --ports 80 --ip-address Public --dns-name-label "$ACI_DNS" \
        --restart-policy Always --tags "${TAGS[@]}" -o none
    ok "criado"
fi

info "Resumo (valores sem segredo, para o Variable Group da Release)"
printf '    %-22s %s\n' \
    "AZ_RESOURCE_GROUP" "$RG" \
    "AZ_LOCATION" "$AZ_LOCATION" \
    "ACR_NAME" "$ACR" \
    "ACR_LOGIN_SERVER" "$(az_tsv acr show --name "$ACR" --query loginServer)" \
    "ACI_NAME" "$ACI" \
    "ACI_DNS_LABEL" "$ACI_DNS" \
    "SQL_SERVER_FQDN" "$(az_tsv sql server show --name "$SQL_SERVER" --resource-group "$RG" --query fullyQualifiedDomainName)" \
    "SQL_DATABASE" "$SQL_DB"
echo
echo "    URL do ACI: http://$(az_tsv container show --name "$ACI" --resource-group "$RG" --query ipAddress.fqdn)"
echo "    (até a primeira Release, ela mostra a página de exemplo da Microsoft)"
