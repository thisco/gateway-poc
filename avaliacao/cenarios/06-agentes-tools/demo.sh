#!/usr/bin/env bash
# Demo ao vivo — Cenário 06: Agentes (A2A) e Tool Calling
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 7
# casos AG-01..AG-04 + TL-01..TL-03): aqui só os 2 casos de maior
# impacto, escolhidos pelo controlador — AG-03 (allow-by-default de
# agentes, o oposto do deny-by-default do MCP) e TL-03 (guardrail
# mascarando PII dentro do ARGUMENTO ESTRUTURADO de uma tool call).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 06 — Agentes (A2A) e Tool Calling"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
check_container poc-agente-eco "docker compose --profile agents up -d agente-eco  (e depois: docker compose up -d --force-recreate gateway)"
KEY="$LITELLM_MASTER_KEY"
AGENT_ID=$(curl -s "$GATEWAY/v1/agents" -H "Authorization: Bearer $KEY" \
  | jq -r '.[] | select(.agent_name=="eco-governanca") | .agent_id')
if [ -z "$AGENT_ID" ]; then
  echo "${C_RED}ERRO: agente 'eco-governanca' não está registrado no gateway.${C_RESET}" >&2
  echo "  Confira o bloco agents: em poc/gateway/config.yaml e recrie o gateway (docker compose up -d --force-recreate gateway)." >&2
  exit 1
fi
pre_checagens_ok

# ---------------------------------------------------------------------------
banner "Allow-by-default: chave sem permissão de agente invoca mesmo assim" \
  "Pilar P1/P5/P7 — diferente do MCP (cenário 03, fechado por padrão), agentes A2A nascem ABERTOS; há um campo de restrição (object_permission.agents), mas exige hardening explícito."
mostrar_comando 'POST /key/generate {"models":["simulado"]}   →   GET /a2a/{agent_id}/.well-known/agent-card.json  (com a nova chave)'
esperar_enter
CHAVE_SEM_PERM=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
RESP=$(curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/a2a/$AGENT_ID/.well-known/agent-card.json" \
  -H "Authorization: Bearer $CHAVE_SEM_PERM")
echo "$RESP" | jq -c '.name // .' 2>/dev/null || echo "$RESP"
if echo "$RESP" | grep -q '"name"'; then
  concluir "a chave SEM object_permission.agents conseguiu o card normalmente — allow-by-default confirmado ao vivo (contrasta com o deny-by-default do MC-03, cenário 03)."
else
  falha "resultado inesperado — ver testes.sh AG-03 e evidencias/AG-03.json"
fi

# ---------------------------------------------------------------------------
banner "Guardrail mascara CPF dentro do ARGUMENTO de uma tool call" \
  "Pilar P5 — tool args são um canal de vazamento tão real quanto o texto da conversa; o modelo nunca chega a ver o CPF de verdade."
mostrar_comando 'POST /v1/chat/completions  {"model":"fronteira-haiku","guardrails":["mascara-pii"],"tool_choice":{"function":{"name":"consulta_politica"}},"messages":[...CPF 529.982.247-25...]}'
esperar_enter
TOOL_DEF='{"type":"function","function":{"name":"consulta_politica","description":"Consulta a regra de politica de governanca de IA aplicavel a um tema.","parameters":{"type":"object","properties":{"tema":{"type":"string"}},"required":["tema"]}}}'
RESP=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":400,\"guardrails\":[\"mascara-pii\"],\"tools\":[$TOOL_DEF],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"consulta_politica\"}},\"messages\":[{\"role\":\"user\",\"content\":\"Registre uma consulta de politica para o titular de CPF 529.982.247-25. Chame a ferramenta consulta_politica com o argumento tema igual exatamente ao CPF do titular: 529.982.247-25\"}]}")
echo "$RESP" | jq -c '{tool_call_arguments: .choices[0].message.tool_calls[0].function.arguments}'
if echo "$RESP" | grep -q '<BR_CPF>'; then
  concluir "o argumento da tool veio mascarado (<BR_CPF>), não o CPF real — o modelo nunca viu o dado em claro (guardrail pre_call antes de qualquer geração)."
else
  falha "resultado inesperado — ver testes.sh TL-03 e evidencias/TL-03.json"
fi

apontar_ui "http://localhost:4000/ui/agents mostra eco-governanca catalogado (P3). Depois http://localhost:4000/ui/logs → badges \"Agent\" e \"LLM\" lado a lado na mesma tabela. Roteiro completo: roteiro-playground.md deste cenário."
apontar_slide "Slide 24"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 06. Gateway saudável.${C_RESET}"
