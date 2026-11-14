#!/usr/bin/env bash
# Release, stage "Produção": smoke test depois do deploy.
# "Verde" na tarefa de deploy não prova que a API subiu (lição da CP6). Este script prova:
#   1. /health/live = 200 → o processo da API está no ar;
#   2. /health      = 200 → a API conecta no Azure SQL (503 se o banco cair);
#   3. /swagger     = 200 → a documentação está publicada (Swagger__Enabled=true).
# Uso: API_URL=http://<dns>:8080 bash smoke-test.sh

set -euo pipefail

erro() { echo "##vso[task.logissue type=error]$*"; exit 1; }

API_URL="${API_URL:-${1:-}}"
[ -n "$API_URL" ] && [[ "$API_URL" != '$('* ]] || erro "API_URL não informada."
TENTATIVAS="${TENTATIVAS:-36}"   # 36 x 5 s = 3 min: o container leva de 1 a 2 min para subir
INTERVALO="${INTERVALO:-5}"

# Espera um endpoint responder 200, tentando de novo até o limite.
esperar_200() {
    local caminho="$1" codigo=""
    for ((i = 1; i <= TENTATIVAS; i++)); do
        codigo="$(curl -s -o /tmp/resposta.txt -w '%{http_code}' --max-time 10 "$API_URL$caminho" || true)"
        if [ "$codigo" = "200" ]; then
            echo "    $caminho → 200 (tentativa $i)"
            return 0
        fi
        echo "    $caminho → ${codigo:-sem resposta} (tentativa $i/$TENTATIVAS)"
        sleep "$INTERVALO"
    done
    echo "    última resposta: $(head -c 300 /tmp/resposta.txt 2>/dev/null || true)"
    return 1
}

echo "==> Smoke test em $API_URL"
esperar_200 /health/live || erro "a API não subiu: /health/live não respondeu 200."
esperar_200 /health || erro "a API subiu, mas não conecta no banco: /health não respondeu 200."
echo "    resposta do /health: $(cat /tmp/resposta.txt)"
esperar_200 /swagger/index.html || erro "o Swagger não está publicado (confira Swagger__Enabled)."
echo "==> Smoke test aprovado"
