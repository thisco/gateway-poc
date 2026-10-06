#!/usr/bin/env bash
# Cenário 07 — Visão de Tooling (Inventário, Tool Calling avançado, Dev Tooling)
#
# Três blocos independentes, cada um com 3 casos:
#   TI-01..03 — Inventário (existe visão unificada? o que uma chave restrita
#               vê em cada plano? visibilidade admin na UI)
#   TC-01..03 — Tool calling avançado (paralelo, erro de tool, streaming)
#   TD-01..03 — Dev tooling (SDK OpenAI, SDK Anthropic, DX de erros de
#               governança)
#
# Notas de execução:
# - TI-01/TI-02 usam a rota nativa Anthropic (/v1/messages) para TC-*, e as
#   5 famílias de endpoint de catálogo já mapeadas pelos cenários 03-06
#   (MCP, agentes, vector stores, skills) + /v1/models — não há endpoint
#   único de inventário no gateway (achado central, ver README §8).
# - O catálogo de vector stores do GATEWAY é `GET /vector_store/list`
#   (LiteLLM-específico) — `GET /v1/vector_stores` (compatível OpenAI)
#   responde 200 mas com `data: []` para o mesmo store, porque aponta para
#   uma tabela/caminho diferente internamente (achado; ver README §8 e o
#   próprio `setup.sh`/`testes.sh` do cenário 04, que usa `vector_store/list`).
# - TC-* usam /v1/messages (rota nativa Anthropic) porque `is_error` em
#   tool_result e o streaming de `tool_use` são conceitos nativos do
#   formato Anthropic — testar via /v1/chat/completions (OpenAI-compatível)
#   não teria como expressar `is_error` do jeito que o SDK real expressa.
# - TD-01/TD-02 chamam os SDKs oficiais de verdade (não apenas curl) a
#   partir de um venv Python isolado em dados/.venv (criado/reusado por
#   este script, NÃO versionado — ver .gitignore) — nenhuma dependência foi
#   adicionada ao repositório em si.
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY (set -a; source poc/.env; set +a)}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EV="$SCRIPT_DIR/evidencias"; mkdir -p "$EV"
DADOS="$SCRIPT_DIR/dados"

fetch_latest_log() { # $1 = call_type a filtrar -> imprime o registro mais recente desse call_type
  local tipo="$1" tentativas=8 i resp
  for i in $(seq 1 "$tentativas"); do
    resp=$(curl -s "$GATEWAY/spend/logs?limit=10" -H "Authorization: Bearer $KEY")
    local hit
    hit=$(echo "$resp" | jq -c --arg t "$tipo" '[.[] | select(.call_type==$t)][0] // empty')
    if [ -n "$hit" ]; then
      echo "$hit"
      return 0
    fi
    sleep 2
  done
  echo "null"
}

# ============================================================================
# BLOCO TI — Inventário
# ============================================================================

echo "== TI-01 — existe uma visão unificada de inventário? (5 famílias de endpoint) =="
MODELOS=$(curl -s "$GATEWAY/v1/models" -H "Authorization: Bearer $KEY" | jq -c '[.data[].id] | length')
MCP=$(curl -s "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $KEY" | jq -c '[.tools[]?.name]')
AGENTES=$(curl -s "$GATEWAY/v1/agents" -H "Authorization: Bearer $KEY" | jq -c '[.[].agent_name]')
VETORES_GATEWAY=$(curl -s "$GATEWAY/vector_store/list" -H "Authorization: Bearer $KEY" | jq -c '[.data[].vector_store_name]')
VETORES_OPENAI_COMPAT=$(curl -s "$GATEWAY/v1/vector_stores" -H "Authorization: Bearer $KEY" | jq -c '.data | length')
SKILLS=$(curl -s "$GATEWAY/v1/skills?beta=true" -H "Authorization: Bearer $KEY" | jq -c '.data | length')

cat <<EOF | tee "$EV/TI-01.json"
{
  "endpoint_modelos": "GET /v1/models",
  "n_modelos": $MODELOS,
  "endpoint_mcp": "GET /mcp-rest/tools/list",
  "tools_mcp": $MCP,
  "endpoint_agentes": "GET /v1/agents",
  "agentes": $AGENTES,
  "endpoint_vetores_gateway": "GET /vector_store/list",
  "vetores_gateway": $VETORES_GATEWAY,
  "endpoint_vetores_openai_compat": "GET /v1/vector_stores",
  "n_vetores_openai_compat_MESMO_STORE": $VETORES_OPENAI_COMPAT,
  "endpoint_skills": "GET /v1/skills?beta=true",
  "n_skills": $SKILLS,
  "achado": "5 famílias de endpoint distintas (prefixos e formatos diferentes: /v1/models, /mcp-rest/tools/list, /v1/agents, /vector_store/list, /v1/skills), nenhum endpoint único de inventário; e /v1/vector_stores (compatível OpenAI) diverge de /vector_store/list para o MESMO store (0 vs. 1) — ver README §8"
}
EOF

echo
echo "== TI-02 — o que uma chave restrita (sem nenhum object_permission) enxerga em cada plano =="
CHAVE_TI02=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["simulado"],"key_alias":"ti02-sem-permissao"}' | jq -r '.key')
echo "chave_sem_permissao=$CHAVE_TI02"

TI02_MCP=$(curl -s -w '\n%{http_code}' "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $CHAVE_TI02")
TI02_VETORES=$(curl -s -w '\n%{http_code}' "$GATEWAY/vector_store/list" -H "Authorization: Bearer $CHAVE_TI02")
TI02_AGENTES=$(curl -s -w '\n%{http_code}' "$GATEWAY/v1/agents" -H "Authorization: Bearer $CHAVE_TI02")
TI02_SKILLS=$(curl -s -w '\n%{http_code}' "$GATEWAY/v1/skills?beta=true" -H "Authorization: Bearer $CHAVE_TI02")
TI02_MODELOS=$(curl -s -w '\n%{http_code}' "$GATEWAY/v1/models" -H "Authorization: Bearer $CHAVE_TI02")

cat <<EOF | tee "$EV/TI-02.json"
{
  "chave": "$CHAVE_TI02 (models: [simulado], sem object_permission)",
  "mcp_tools_list": $(echo "$TI02_MCP" | head -1 | jq -c '{tools_visiveis: ((.tools // []) | length), erro: .error}' 2>/dev/null || echo "\"$TI02_MCP\""),
  "mcp_http_status": "$(echo "$TI02_MCP" | tail -1)",
  "vector_store_list_visiveis": $(echo "$TI02_VETORES" | head -1 | jq -c '.data | length' 2>/dev/null || echo null),
  "vector_store_http_status": "$(echo "$TI02_VETORES" | tail -1)",
  "agentes_visiveis": $(echo "$TI02_AGENTES" | head -1 | jq -c 'length' 2>/dev/null || echo null),
  "agentes_http_status": "$(echo "$TI02_AGENTES" | tail -1)",
  "skills_visiveis": $(echo "$TI02_SKILLS" | head -1 | jq -c '.data | length' 2>/dev/null || echo null),
  "skills_http_status": "$(echo "$TI02_SKILLS" | tail -1)",
  "modelos_visiveis": $(echo "$TI02_MODELOS" | head -1 | jq -c '.data | length' 2>/dev/null || echo null),
  "modelos_http_status": "$(echo "$TI02_MODELOS" | tail -1)"
}
EOF
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_TI02\"]}" | jq -c '{deleted: .deleted_keys}'

echo
echo "== TI-03 — visibilidade admin nas telas da UI (prints já capturados via Playwright) =="
echo "Ver evidencias/TI-03-*.png (Models, MCP Servers, Agents, Vector Stores, Skills, ReDoc) — README §8 analisa cada print."

# ============================================================================
# BLOCO TC — Tool calling avançado (via /v1/messages, rota nativa Anthropic)
# ============================================================================

TOOL_CLIMA='{"name":"consulta_clima","description":"Consulta o clima atual de uma cidade brasileira.","input_schema":{"type":"object","properties":{"cidade":{"type":"string","description":"Nome da cidade"}},"required":["cidade"]}}'

echo
echo "== TC-01 — tools paralelas: 2+ tool_use no mesmo turno =="
TC01_RESP=$(curl -s "$GATEWAY/v1/messages" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":500,\"tools\":[$TOOL_CLIMA],\"messages\":[{\"role\":\"user\",\"content\":\"Preciso saber o clima agora em Brasília e em Recife. Chame a ferramenta consulta_clima duas vezes, uma para cada cidade, no mesmo turno, antes de responder.\"}]}")
echo "$TC01_RESP" | tee "$EV/TC-01.json" \
  | jq -c '{n_tool_use: [.content[] | select(.type=="tool_use")] | length, cidades: [.content[] | select(.type=="tool_use") | .input.cidade], stop_reason}'

echo
echo "== TC-02 — tool_result com is_error:true -> recuperação do modelo + log =="
ID1=$(echo "$TC01_RESP" | jq -r '.content[0].id')
ID2=$(echo "$TC01_RESP" | jq -r '.content[1].id')
CIDADE1=$(echo "$TC01_RESP" | jq -r '.content[0].input.cidade')
ASSIST_CONTENT=$(echo "$TC01_RESP" | jq -c '.content')
TC02_RESP=$(curl -s "$GATEWAY/v1/messages" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":500,\"tools\":[$TOOL_CLIMA],\"messages\":[
    {\"role\":\"user\",\"content\":\"Preciso saber o clima agora em Brasília e em Recife. Chame a ferramenta consulta_clima duas vezes, uma para cada cidade, no mesmo turno, antes de responder.\"},
    {\"role\":\"assistant\",\"content\":$ASSIST_CONTENT},
    {\"role\":\"user\",\"content\":[
       {\"type\":\"tool_result\",\"tool_use_id\":\"$ID1\",\"is_error\":true,\"content\":\"Erro: serviço de clima indisponível para $CIDADE1 no momento (timeout upstream).\"},
       {\"type\":\"tool_result\",\"tool_use_id\":\"$ID2\",\"content\":\"29C, ensolarado, umidade 70%.\"}
    ]}
  ]}")
echo "$TC02_RESP" | tee "$EV/TC-02.json" | jq -c '{stop_reason, texto: .content[0].text}'
echo "-- TC-02: confirmação no log de auditoria (call_type anthropic_messages mais recente) --"
fetch_latest_log "anthropic_messages" | tee "$EV/TC-02-spend-log.json" | jq -c '{call_type, model, spend, startTime}'

echo
echo "== TC-03 — streaming com tools: chunks de tool_use no SSE =="
curl -s "$GATEWAY/v1/messages" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":300,\"stream\":true,\"tools\":[$TOOL_CLIMA],\"messages\":[{\"role\":\"user\",\"content\":\"Qual o clima em Brasília agora? Use a ferramenta.\"}]}" \
  > "$EV/TC-03-stream.txt"
N_EVENTOS=$(grep -c '^event:' "$EV/TC-03-stream.txt")
TIPO_BLOCO=$(grep -A1 'content_block_start' "$EV/TC-03-stream.txt" | grep '^data:' | sed -E 's/^data: //' | jq -r '.content_block.type')
NOME_TOOL=$(grep -A1 'content_block_start' "$EV/TC-03-stream.txt" | grep '^data:' | sed -E 's/^data: //' | jq -r '.content_block.name')
N_INPUT_DELTAS=$(grep '"partial_json"' "$EV/TC-03-stream.txt" | wc -l | tr -d ' ')
echo "{\"n_eventos_sse\": $N_EVENTOS, \"content_block_start_type\": \"$TIPO_BLOCO\", \"tool_chamada\": \"$NOME_TOOL\", \"n_input_json_delta_chunks\": $N_INPUT_DELTAS}" | tee "$EV/TC-03.json"

# ============================================================================
# BLOCO TD — Dev tooling
# ============================================================================

echo
echo "== TD-01/TD-02 — preparando venv Python isolado (dados/.venv, não versionado) =="
if [ ! -d "$DADOS/.venv" ]; then
  python3 -m venv "$DADOS/.venv"
fi
# shellcheck source=/dev/null
source "$DADOS/.venv/bin/activate"
pip install -q --upgrade pip >/dev/null
pip install -q openai anthropic >/dev/null
echo "openai=$(python -c 'import openai; print(openai.__version__)') anthropic=$(python -c 'import anthropic; print(anthropic.__version__)')"

echo
echo "== TD-01 — SDK OpenAI oficial -> base_url $GATEWAY/v1 (chave virtual restrita) =="
CHAVE_TD01=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["fronteira-haiku"],"max_budget":1.0,"key_alias":"td01-openai-sdk"}' | jq -r '.key')
echo "chave_td01=$CHAVE_TD01"
GATEWAY="$GATEWAY" API_KEY="$CHAVE_TD01" MODEL="fronteira-haiku" \
  python "$DADOS/td01_openai_sdk.py" | tee "$EV/TD-01.json"
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_TD01\"]}" | jq -c '{deleted: .deleted_keys}'

echo
echo "== TD-02 — SDK Anthropic oficial -> base_url $GATEWAY (rota nativa /v1/messages) =="
CHAVE_TD02=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["fronteira-haiku"],"max_budget":1.0,"key_alias":"td02-anthropic-sdk"}' | jq -r '.key')
echo "chave_td02=$CHAVE_TD02"
GATEWAY="$GATEWAY" API_KEY="$CHAVE_TD02" MODEL="fronteira-haiku" \
  python "$DADOS/td02_anthropic_sdk.py" | tee "$EV/TD-02.json"
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_TD02\"]}" | jq -c '{deleted: .deleted_keys}'
deactivate

echo
echo "== TD-03 — DX de erros de governança: modelo fora do perfil (403) + budget estourado (429) =="
CHAVE_TD03=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["simulado"],"max_budget":0.001,"key_alias":"td03-erros-governanca"}' | jq -r '.key')
echo "chave_td03=$CHAVE_TD03"

echo "-- TD-03a: modelo fora do perfil da chave --"
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE_TD03" -H "Content-Type: application/json" \
  -d '{"model":"fronteira-haiku","messages":[{"role":"user","content":"oi"}]}' | tee "$EV/TD-03a-modelo-nao-permitido.json"

echo "-- TD-03b: chamada 1 dentro do perfil (gasta o budget de US\$0,001, modelo simulado tem custo fictício alto) --"
curl -s "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE_TD03" -H "Content-Type: application/json" \
  -d '{"model":"simulado","messages":[{"role":"user","content":"oi"}]}' | jq -c '{id, model}'
sleep 2
echo "-- TD-03b: chamada 2, budget já estourado --"
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE_TD03" -H "Content-Type: application/json" \
  -d '{"model":"simulado","messages":[{"role":"user","content":"oi de novo"}]}' | tee "$EV/TD-03b-budget-excedido.json"

curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_TD03\"]}" | jq -c '{deleted: .deleted_keys}'

echo
echo "== fim =="
