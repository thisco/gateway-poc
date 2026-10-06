#!/usr/bin/env bash
# Cenário 03 — MCP Gateway
#
# Nota de execução: o rascunho original do brief presumia um campo de
# permissão por chave chamado `allowed_mcp_servers` em /key/generate.
# Conferido no Swagger real (http://localhost:4000/openapi.json) da imagem
# ghcr.io/berriai/litellm:main-stable: não existe `allowed_mcp_servers` no
# schema `GenerateKeyRequest` — o campo real é `object_permission.mcp_servers`
# (lista de nomes de servidor), dentro do objeto `LiteLLM_ObjectPermissionBase`.
# O script usa `object_permission: {mcp_servers: [...]}` em MC-04.
#
# Também: POST /mcp-rest/tools/call exige `server_id` no corpo (um hash
# gerado pelo gateway, não o nome do servidor) — não documentado no Swagger
# (requestBody vazio no schema), descoberto por tentativa e confirmado no
# código-fonte do container (rest_endpoints.py). O script resolve o
# server_id do servidor "deepwiki" dinamicamente via GET /v1/mcp/server
# antes de MC-02, em vez de hardcodar o hash.
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
EV="$(dirname "$0")/evidencias"; mkdir -p "$EV"

# MC-01: gateway lista tools do servidor registrado
echo "== MC-01 — listar tools via gateway"
curl -s "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $KEY" \
  | tee "$EV/MC-01.json" | jq -c '[.tools[]?.name] // .'

# MC-02: chamada de tool passa pelo gateway (proxy + auditoria)
# server_id resolvido dinamicamente (ver nota de execução acima).
echo "== MC-02 — chamar tool via gateway"
SERVER_ID=$(curl -s "$GATEWAY/v1/mcp/server" -H "Authorization: Bearer $KEY" \
  | jq -r '.[] | select(.server_name=="deepwiki") | .server_id')
echo "server_id(deepwiki)=$SERVER_ID"

TENTATIVAS=3
MC02_OK=0
for i in $(seq 1 "$TENTATIVAS"); do
  RESP=$(curl -s "$GATEWAY/mcp-rest/tools/call" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"name\":\"read_wiki_structure\",\"server_id\":\"$SERVER_ID\",\"arguments\":{\"repoName\":\"BerriAI/litellm\"}}")
  if echo "$RESP" | jq -e '.content != null and (.isError // false) == false' >/dev/null 2>&1; then
    MC02_OK=1
    break
  fi
  echo "tentativa $i falhou, retentando..." >&2
done
echo "$RESP" | tee "$EV/MC-02.json" | jq -c '{ok: (.content != null and (.isError // false) == false), error: .error, isError}'
if [ "$MC02_OK" -eq 0 ]; then
  echo "AVISO: MC-02 não confirmou sucesso após $TENTATIVAS tentativas — ver $EV/MC-02.json (possível instabilidade do serviço externo deepwiki)." >&2
fi

# MC-03: chave restrita SEM permissão MCP não acessa tools
echo "== MC-03 — chave sem permissão MCP"
CHAVE=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
curl -s "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $CHAVE" \
  | tee "$EV/MC-03.json" | jq -c '.'

# MC-04: permissão de MCP por chave (object_permission.mcp_servers — ver nota de execução)
echo "== MC-04 — chave com permissão explícita ao servidor deepwiki"
CHAVE_MCP=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"models":["simulado"],"object_permission":{"mcp_servers":["deepwiki"]}}' | jq -r '.key')
curl -s "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $CHAVE_MCP" \
  | tee "$EV/MC-04.json" | jq -c '[.tools[]?.name] // .'
