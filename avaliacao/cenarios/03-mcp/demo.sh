#!/usr/bin/env bash
# Demo ao vivo — Cenário 03: MCP Gateway
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 4
# casos MC-01..MC-04): aqui só os 2 de maior impacto — MC-02 (chamada de
# tool real através do gateway, com auditoria unificada) e MC-03
# (deny-by-default ao vivo: chave sem permissão MCP é bloqueada).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
#
# Observação: MC-02 depende do servidor MCP público deepwiki
# (https://mcp.deepwiki.com/mcp) — se a internet estiver instável, o
# resultado pode variar; não é falha do gateway (ver nota em testes.sh).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 03 — MCP Gateway"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

SERVER_ID=$(curl -s "$GATEWAY/v1/mcp/server" -H "Authorization: Bearer $KEY" \
  | jq -r '.[] | select(.server_name=="deepwiki") | .server_id')
if [ -z "$SERVER_ID" ]; then
  echo "${C_RED}ERRO: servidor MCP 'deepwiki' não está registrado no gateway.${C_RESET}" >&2
  echo "  Confira o bloco mcp_servers: em poc/gateway/config.yaml e reinicie o gateway." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
banner "Uma chamada de tool passa pelo gateway — não direto ao servidor MCP" \
  "Pilar P1 (identidade do chamador preservada) + P4 (trilha de auditoria unificada com o log de LLM)."
mostrar_comando "POST /mcp-rest/tools/call  {\"name\":\"read_wiki_structure\",\"server_id\":\"$SERVER_ID\",\"arguments\":{\"repoName\":\"BerriAI/litellm\"}}"
esperar_enter
RESP=$(curl -s "$GATEWAY/mcp-rest/tools/call" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"name\":\"read_wiki_structure\",\"server_id\":\"$SERVER_ID\",\"arguments\":{\"repoName\":\"BerriAI/litellm\"}}")
echo "$RESP" | jq -c '{ok: (.content != null and (.isError // false) == false), isError}'
if echo "$RESP" | jq -e '.content != null and (.isError // false) == false' >/dev/null 2>&1; then
  concluir "a chamada de tool foi proxied pelo gateway e volta a aparecer no MESMO log unificado (/spend/logs, call_type: call_mcp_tool) das chamadas de chat."
else
  falha "deepwiki não respondeu como esperado agora (serviço externo público) — resultado documentado em evidencias/MC-02.json; não é falha do gateway."
fi

# ---------------------------------------------------------------------------
banner "Deny-by-default: chave sem permissão MCP é bloqueada, ao vivo" \
  "Pilar P1/P5/P7 — diferente de guardrails/policies (que nascem desligados), MCP nasce FECHADO por chave: é o único recurso com esse comportamento sem nenhuma config extra."
mostrar_comando 'POST /key/generate {"models":["simulado"]}   →   GET /mcp-rest/tools/list  (com a nova chave)'
esperar_enter
CHAVE=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
RESP=$(curl -s "$GATEWAY/mcp-rest/tools/list" -H "Authorization: Bearer $CHAVE")
echo "$RESP" | jq -c '.'
if echo "$RESP" | grep -q 'access_denied'; then
  concluir "acesso negado por padrão (access_denied) — a chave só listaria tools do deepwiki se ganhasse object_permission.mcp_servers explicitamente (ver MC-04 em testes.sh)."
else
  falha "resultado inesperado — chave sem permissão não foi bloqueada; ver testes.sh MC-03 e evidencias/MC-03.json"
fi

apontar_ui "http://localhost:4000/ui/mcp-servers → card \"deepwiki\" (Healthy). Depois http://localhost:4000/ui/logs → linha com Call Type: call_mcp_tool, lado a lado com as chamadas de chat. Roteiro completo: roteiro-playground.md deste cenário."
apontar_slide "Slide 21"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 03. Gateway saudável.${C_RESET}"
