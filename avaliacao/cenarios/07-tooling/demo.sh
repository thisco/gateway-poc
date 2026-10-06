#!/usr/bin/env bash
# Demo ao vivo — Cenário 07: Visão de Tooling
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 9
# casos TI-01..03/TC-01..03/TD-01..03): aqui só os 3 de maior impacto,
# escolhidos pelo controlador — TI-01 (a divergência real entre as duas
# rotas de vector stores, prova ao vivo de que "inventário" ainda não é
# confiável), TC-01 (2 tool_use paralelas no mesmo turno, mecanismo básico
# de qualquer agente real) e TD-03 (os dois erros de governança que mais
# geram chamado de suporte, lado a lado).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 07 — Visão de Tooling"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

# ---------------------------------------------------------------------------
banner "Duas rotas, um só recurso, dois resultados diferentes" \
  "Pilar P3 — /vector_store/list e /v1/vector_stores deveriam descrever o MESMO catálogo; uma mostra o store real, a outra mostra uma lista vazia."
mostrar_comando 'GET /vector_store/list   x   GET /v1/vector_stores'
esperar_enter
GW_LIST=$(curl -s "$GATEWAY/vector_store/list" -H "Authorization: Bearer $KEY" | jq -c '[.data[].vector_store_name]')
COMPAT_LIST=$(curl -s "$GATEWAY/v1/vector_stores" -H "Authorization: Bearer $KEY" | jq -c '.data')
echo "  /vector_store/list      -> $GW_LIST"
echo "  /v1/vector_stores       -> $COMPAT_LIST"
if [ "$GW_LIST" != "[]" ] && [ "$COMPAT_LIST" = "[]" ]; then
  concluir "o mesmo store (base-governanca) existe e funciona (cenário 04), mas some na rota 'compatível OpenAI' — quem audita por essa rota concluiria, errado, que não há vector store nenhum."
else
  falha "resultado inesperado — ver testes.sh TI-01 e evidencias/TI-01.json"
fi

# ---------------------------------------------------------------------------
banner "Duas tools, um só turno: paralelismo real de tool calling" \
  "Pilar P4/P5 — qualquer agente de produção precisa disparar mais de uma ação por turno; o gateway preserva os 2 tool_use sem misturar nem descartar nenhum."
mostrar_comando 'POST /v1/messages  {"model":"fronteira-haiku","tools":[consulta_clima],"messages":[".. Brasília E Recife, no mesmo turno .."]}'
esperar_enter
TOOL_CLIMA='{"name":"consulta_clima","description":"Consulta o clima atual de uma cidade brasileira.","input_schema":{"type":"object","properties":{"cidade":{"type":"string"}},"required":["cidade"]}}'
RESP=$(curl -s "$GATEWAY/v1/messages" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":500,\"tools\":[$TOOL_CLIMA],\"messages\":[{\"role\":\"user\",\"content\":\"Preciso saber o clima agora em Brasília e em Recife. Chame a ferramenta consulta_clima duas vezes, uma para cada cidade, no mesmo turno, antes de responder.\"}]}")
echo "$RESP" | jq -c '{n_tool_use: [.content[] | select(.type=="tool_use")] | length, cidades: [.content[] | select(.type=="tool_use") | .input.cidade]}'
if echo "$RESP" | jq -e '[.content[] | select(.type=="tool_use")] | length == 2' >/dev/null 2>&1; then
  concluir "2 tool_use reais no mesmo turno, uma por cidade — o mecanismo básico de qualquer agente multi-ação através do gateway."
else
  falha "resultado inesperado — ver testes.sh TC-01 e evidencias/TC-01.json"
fi

# ---------------------------------------------------------------------------
banner "Os 2 erros de governança que mais geram chamado de suporte" \
  "Pilar P2/P12 — modelo fora do perfil (403) e orçamento estourado (429): as duas mensagens são claras o bastante para o desenvolvedor se autoatender?"
mostrar_comando 'POST /key/generate {"models":["simulado"],"max_budget":0.001}  →  chamar fronteira-haiku (403)  →  estourar o budget em simulado (429)'
esperar_enter
CHAVE=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["simulado"],"max_budget":0.001,"key_alias":"demo07-td03"}' | jq -r '.key')
echo "  -- modelo fora do perfil --"
curl -s "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"model":"fronteira-haiku","messages":[{"role":"user","content":"oi"}]}' | jq -c '.error.message'
curl -s "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"model":"simulado","messages":[{"role":"user","content":"oi"}]}' >/dev/null
sleep 1
echo "  -- orçamento estourado --"
RESP2=$(curl -s "$GATEWAY/v1/chat/completions" -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"model":"simulado","messages":[{"role":"user","content":"oi de novo"}]}')
echo "$RESP2" | jq -c '.error.message'
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE\"]}" >/dev/null
if echo "$RESP2" | grep -q 'budget_exceeded'; then
  concluir "as duas mensagens nomeiam a causa exata (modelo permitido / custo atual x teto) com o código HTTP semanticamente certo (403/429) — acionáveis sem abrir chamado, com uma ressalva de polimento (ver README §8, achado 4)."
else
  falha "resultado inesperado — ver testes.sh TD-03 e evidencias/TD-03b-budget-excedido.json"
fi

apontar_ui "http://localhost:4000/ui/vector-stores → aba \"Manage Vector Stores\" mostrando \"No vector stores\" ao vivo. Depois http://localhost:4000/ui/logs → chamada de TC-02 (erro de tool) no mesmo log das chamadas de chat. Roteiro completo: roteiro-playground.md deste cenário."
apontar_slide "Slide 25"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 07. Gateway saudável.${C_RESET}"
