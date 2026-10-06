#!/usr/bin/env bash
# Cenário 06 — Agentes (A2A) e Tool Calling
#
# Notas de execução (ver README §3 para o detalhe completo):
# - Agente A2A local "eco-governanca" é registrado no config.yaml (bloco
#   `agents:`), apontando para http://agente-eco:9000/ (container próprio,
#   profile "agents" no docker-compose). Implementação HTTP mínima própria
#   (stdlib Python, sem a2a-sdk — a2a-sdk exige Python >=3.10 e, mesmo assim,
#   sua API pública mudou de forma incompatível entre a versão testada
#   localmente e a que roda dentro do próprio container do gateway; ver nota
#   em dados/agente-eco/server.py).
# - Para agentes declarados via config.yaml, o LiteLLM NÃO busca o agent card
#   do upstream — ele serve `agent_card_params` diretamente, só reescrevendo
#   `url` para apontar ao proxy (confirmado lendo
#   litellm/proxy/agent_endpoints/a2a_endpoints.py:get_agent_card dentro do
#   container). Por isso o agente local não precisa nem implementar
#   .well-known/agent-card.json para o cenário funcionar (ele implementa
#   mesmo assim, como bônus).
# - `object_permission.agents` (schema real, conferido no /openapi.json) usa
#   o `agent_id` (hash gerado no registro), NÃO o `agent_name` do config —
#   mesmo padrão de pegadinha já visto com `server_id` no cenário 03 (MCP).
# - `cost_per_query` em `litellm_params` do agente habilita rastreio de custo
#   por invocação A2A (AG-04) — suportado nesta build, não é gap.
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
EV="$(dirname "$0")/evidencias"; mkdir -p "$EV"

# O log de auditoria é gravado de forma assíncrona (mais perceptível em
# chamadas A2A, que adiam o log até o post_call_success_hook terminar —
# ver litellm/proxy/agent_endpoints/a2a_endpoints.py). fetch_spend_log faz
# polling em vez de um sleep fixo.
fetch_spend_log() { # $1=request_id -> imprime o JSON (array) em stdout
  local req_id="$1" tentativas=10 i resp
  for i in $(seq 1 "$tentativas"); do
    resp=$(curl -s "$GATEWAY/spend/logs?request_id=$req_id" -H "Authorization: Bearer $KEY")
    if [ "$(echo "$resp" | jq 'length')" -gt 0 ] 2>/dev/null; then
      echo "$resp"
      return 0
    fi
    sleep 2
  done
  echo "$resp"
}

TOOL_DEF='{"type":"function","function":{"name":"consulta_politica","description":"Consulta a regra de politica de governanca de IA aplicavel a um tema.","parameters":{"type":"object","properties":{"tema":{"type":"string","description":"Tema da politica a consultar"}},"required":["tema"]}}}'

# --- resolve agent_id do agente registrado (config.yaml -> agent_name: eco-governanca) ---
AGENT_ID=$(curl -s "$GATEWAY/v1/agents" -H "Authorization: Bearer $KEY" \
  | jq -r '.[] | select(.agent_name=="eco-governanca") | .agent_id')
echo "agent_id(eco-governanca)=$AGENT_ID"

# ============================================================
# AG-01: obter agent card via gateway
# ============================================================
echo "== AG-01 — agent card via gateway"
curl -s "$GATEWAY/a2a/$AGENT_ID/.well-known/agent-card.json" -H "Authorization: Bearer $KEY" \
  | tee "$EV/AG-01.json" | jq -c '{name, url, protocolVersion, skills: [.skills[]?.id]}'

# ============================================================
# AG-02: invocar o agente via gateway (A2A message/send)
# ============================================================
echo "== AG-02 — invocar agente via gateway"
AG02_REQ_ID="ag02-$(date +%s)"
curl -s "$GATEWAY/a2a/$AGENT_ID/message/send" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"jsonrpc\":\"2.0\",\"id\":\"$AG02_REQ_ID\",\"method\":\"message/send\",\"params\":{\"message\":{\"role\":\"user\",\"messageId\":\"m1\",\"parts\":[{\"kind\":\"text\",\"text\":\"Quais sao as regras de politica de governanca de IA?\"}]}}}" \
  | tee "$EV/AG-02.json" | jq -c '{text: .result.parts[0].text, error}'

echo "-- AG-02: confirmação no log unificado (/spend/logs) --"
fetch_spend_log "$AG02_REQ_ID" | tee "$EV/AG-02-spend-log.json" \
  | jq -c '.[0] | {call_type, api_key, model, spend, startTime, endTime}'

# ============================================================
# AG-03: chave sem permissão de agente tenta invocar
# ============================================================
echo "== AG-03 — chave sem object_permission.agents (default)"
CHAVE_SEM_PERM=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/a2a/$AGENT_ID/.well-known/agent-card.json" \
  -H "Authorization: Bearer $CHAVE_SEM_PERM" | tee "$EV/AG-03.json"

echo "-- AG-03 (bônus): object_permission.agents com agent_name NÃO funciona (é agent_id) --"
CHAVE_NOME=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"],"object_permission":{"agents":["eco-governanca"]}}' | jq -r '.key')
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/a2a/$AGENT_ID/.well-known/agent-card.json" \
  -H "Authorization: Bearer $CHAVE_NOME" | tee "$EV/AG-03-bonus-nome.json"

echo "-- AG-03 (bônus): object_permission.agents com agent_id FUNCIONA --"
CHAVE_ID=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d "{\"models\":[\"simulado\"],\"object_permission\":{\"agents\":[\"$AGENT_ID\"]}}" | jq -r '.key')
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/a2a/$AGENT_ID/.well-known/agent-card.json" \
  -H "Authorization: Bearer $CHAVE_ID" | tee "$EV/AG-03-bonus-id.json"

# ============================================================
# AG-04: custo/limite aplicado à invocação de agente
# ============================================================
echo "== AG-04 — custo por invocação (litellm_params.cost_per_query no config)"
fetch_spend_log "$AG02_REQ_ID" | tee "$EV/AG-04.json" | jq -c '.[0] | {spend, total_tokens, model}'

# ============================================================
# TL-01: function calling completo via gateway (fronteira-haiku)
# ============================================================
echo "== TL-01 — passo 1: definição de tool -> tool_use"
TL01_STEP1=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":400,\"tools\":[$TOOL_DEF],\"tool_choice\":\"auto\",\"messages\":[{\"role\":\"user\",\"content\":\"Preciso saber a politica sobre uso de dados pessoais (PII) em prompts enviados a modelos de IA. Use a ferramenta disponivel para consultar antes de responder.\"}]}")
echo "$TL01_STEP1" | tee "$EV/TL-01-step1-tool_use.json" \
  | jq -c '{tool_call: .choices[0].message.tool_calls[0], finish_reason: .choices[0].finish_reason}'

TOOL_ID=$(echo "$TL01_STEP1" | jq -r '.choices[0].message.tool_calls[0].id')
TOOL_ARGS=$(echo "$TL01_STEP1" | jq -c '.choices[0].message.tool_calls[0].function.arguments')
ASSISTANT_CONTENT=$(echo "$TL01_STEP1" | jq -c '.choices[0].message.content // ""')

echo "== TL-01 — passo 2: tool_result -> resposta final"
TL01_STEP2=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":400,\"tools\":[$TOOL_DEF],\"messages\":[
    {\"role\":\"user\",\"content\":\"Preciso saber a politica sobre uso de dados pessoais (PII) em prompts enviados a modelos de IA. Use a ferramenta disponivel para consultar antes de responder.\"},
    {\"role\":\"assistant\",\"content\":$ASSISTANT_CONTENT,\"tool_calls\":[{\"id\":\"$TOOL_ID\",\"type\":\"function\",\"function\":{\"name\":\"consulta_politica\",\"arguments\":$TOOL_ARGS}}]},
    {\"role\":\"tool\",\"tool_call_id\":\"$TOOL_ID\",\"content\":\"Regra: dados pessoais (PII) devem ser mascarados pelo guardrail mascara-pii (Presidio) antes de sair do ambiente soberano; nenhum PII deve ser enviado a provedores externos sem mascaramento previo.\"}
  ]}")
TL01_REQ_ID=$(echo "$TL01_STEP2" | jq -r '.id')
echo "$TL01_STEP2" | tee "$EV/TL-01-step2-resposta_final.json" \
  | jq -c '{content: .choices[0].message.content, finish_reason: .choices[0].finish_reason}'

# ============================================================
# TL-02: auditoria do tool calling nos spend logs
# ============================================================
echo "== TL-02 — auditoria do round-trip de tool calling (spend logs)"
fetch_spend_log "$TL01_REQ_ID" | tee "$EV/TL-02.json" \
  | jq -c '.[0] | {call_type, model, spend, applied_guardrails: .metadata.applied_guardrails, messages_stored: (.messages != {} and .messages != null), response_stored: (.response != {} and .response != null)}'

# ============================================================
# TL-03: guardrail mascara-pii sobre argumento de tool (CPF sintético)
# ============================================================
echo "== TL-03 — CPF sintético em argumento de tool, guardrail mascara-pii ativo"
TL03_RESP=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":400,\"guardrails\":[\"mascara-pii\"],\"tools\":[$TOOL_DEF],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"consulta_politica\"}},\"messages\":[{\"role\":\"user\",\"content\":\"Registre uma consulta de politica para o titular de CPF 529.982.247-25. Chame a ferramenta consulta_politica com o argumento tema igual exatamente ao CPF do titular: 529.982.247-25\"}]}")
TL03_REQ_ID=$(echo "$TL03_RESP" | jq -r '.id')
echo "$TL03_RESP" | tee "$EV/TL-03.json" \
  | jq -c '{tool_call_arguments: .choices[0].message.tool_calls[0].function.arguments}'

echo "-- TL-03: guardrail_information no log de auditoria --"
fetch_spend_log "$TL03_REQ_ID" | tee "$EV/TL-03-spend-log.json" \
  | jq -c '.[0].metadata | {applied_guardrails, guardrail_information}'

echo "== fim =="
