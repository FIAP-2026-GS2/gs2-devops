#!/usr/bin/env bash
# Release, stage "Produção": publica no ACI a imagem que o CI enviou ao ACR.
# Roda dentro da tarefa "Azure CLI" da Release (já logada na assinatura pela service connection).
#
# Variáveis de ambiente (vêm do Variable Group vg-sampatech-release):
#   comuns : AZ_RESOURCE_GROUP ACR_NAME ACI_NAME ACI_DNS_LABEL SQL_SERVER_FQDN SQL_DATABASE
#            SQL_ADMIN_USER AUTH_ADMIN_USERNAME
#   secretas (mapeadas uma a uma na tarefa): SQL_ADMIN_PASSWORD JWT_KEY AUTH_ADMIN_PASSWORD_HASH
#   do artefato: IMAGE_FILE (caminho do imagem.txt publicado pelo CI)
# Saída: a variável API_URL, usada pelo smoke test na tarefa seguinte.

set -euo pipefail

erro() { echo "##vso[task.logissue type=error]$*"; exit 1; }

# Trava antes de mexer no container (lição da Sprint 4): uma variável secreta que não foi
# mapeada chega ao script como o texto literal "$(NOME)", e a API cairia ao iniciar.
for nome in AZ_RESOURCE_GROUP ACR_NAME ACI_NAME ACI_DNS_LABEL SQL_SERVER_FQDN SQL_DATABASE \
            SQL_ADMIN_USER SQL_ADMIN_PASSWORD JWT_KEY AUTH_ADMIN_USERNAME AUTH_ADMIN_PASSWORD_HASH IMAGE_FILE; do
    valor="${!nome:-}"
    if [ -z "$valor" ] || [[ "$valor" == '$('* ]]; then
        erro "a variável $nome está vazia ou não foi mapeada na tarefa. Nada foi alterado no ACI."
    fi
done
[ "${#JWT_KEY}" -ge 32 ] || erro "JWT_KEY precisa ter 32 ou mais caracteres. Nada foi alterado no ACI."
[ -f "$IMAGE_FILE" ] || erro "artefato da imagem não encontrado em $IMAGE_FILE."

echo "==> Imagem a publicar"
IMAGE_REF="$(tr -d '\r\n' < "$IMAGE_FILE")"                     # ex.: sampatech-api:41
ACR_SERVER="$(az acr show --name "$ACR_NAME" --query loginServer -o tsv)"
IMAGE="$ACR_SERVER/$IMAGE_REF"
az acr repository show --name "$ACR_NAME" --image "$IMAGE_REF" -o none \
    || erro "a imagem $IMAGE_REF não existe no ACR."
echo "    $IMAGE"

echo "==> Credenciais do ACR (lidas agora, não ficam guardadas)"
ACR_USER="$(az acr credential show --name "$ACR_NAME" --query username -o tsv)"
ACR_PASS="$(az acr credential show --name "$ACR_NAME" --query 'passwords[0].value' -o tsv)"
echo "##vso[task.setsecret]$ACR_PASS"                            # esconde a senha nos logs

# A connection string é montada aqui, na hora do deploy: ela nunca existe no repositório.
CONN="Server=tcp:${SQL_SERVER_FQDN},1433;Initial Catalog=${SQL_DATABASE};User ID=${SQL_ADMIN_USER};Password=${SQL_ADMIN_PASSWORD};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

# O ACI não deixa trocar a porta de um container existente (a imagem provisória usa a 80).
# Recriar é o jeito previsível: o DNS continua o mesmo, só o IP pode mudar.
if az container show --resource-group "$AZ_RESOURCE_GROUP" --name "$ACI_NAME" -o none 2>/dev/null; then
    echo "==> Removendo o container anterior"
    az container delete --resource-group "$AZ_RESOURCE_GROUP" --name "$ACI_NAME" --yes -o none
fi

echo "==> Criando o container com a nova imagem"
# --environment-variables: valores comuns, visíveis no portal.
# --secure-environment-variables: segredos, que o portal e o "az container show" não mostram.
az container create \
    --resource-group "$AZ_RESOURCE_GROUP" --name "$ACI_NAME" \
    --image "$IMAGE" --os-type Linux --cpu 0.5 --memory 1 \
    --ports 8080 --ip-address Public --dns-name-label "$ACI_DNS_LABEL" \
    --restart-policy Always \
    --registry-login-server "$ACR_SERVER" --registry-username "$ACR_USER" --registry-password "$ACR_PASS" \
    --environment-variables \
        ASPNETCORE_ENVIRONMENT=Production \
        Swagger__Enabled=true \
        "Auth__Users__0__Username=$AUTH_ADMIN_USERNAME" \
        Auth__Users__0__Role=ADMIN \
    --secure-environment-variables \
        "ConnectionStrings__DefaultConnection=$CONN" \
        "Jwt__Key=$JWT_KEY" \
        "Auth__Users__0__PasswordHash=$AUTH_ADMIN_PASSWORD_HASH" \
    -o none

FQDN="$(az container show --resource-group "$AZ_RESOURCE_GROUP" --name "$ACI_NAME" --query ipAddress.fqdn -o tsv)"
API_URL="http://$FQDN:8080"
echo "##vso[task.setvariable variable=API_URL]$API_URL"
echo "==> Publicado: $API_URL (Swagger em $API_URL/swagger)"
