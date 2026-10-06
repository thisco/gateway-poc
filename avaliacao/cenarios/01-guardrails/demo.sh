#!/usr/bin/env bash
# Demo ao vivo — Cenário 01: Guardrails (Presidio auto-hospedado)
#
# Ritmo de apresentação (não confundir com testes.sh, que é para
# reprodução/evidência dos 5 casos GR-01..GR-05): aqui só os 2 casos de
# maior impacto — GR-01 (mascaramento isolado, via apply_guardrail) e
# GR-03 (o mesmo guardrail protegendo uma chamada real de chat).
#
# DEMO_AUTO=1 pula os "ENTER para continuar" (usado na validação e no
# ensaio sem plateia — ver avaliacao/demo-completa.sh).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 01 — Guardrails (Presidio auto-hospedado)"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
check_container poc-presidio-analyzer "docker compose --profile guardrails up -d"
check_container poc-presidio-anonymizer "docker compose --profile guardrails up -d"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

# ---------------------------------------------------------------------------
banner "CPF sintético é mascarado antes de sair do ambiente" \
  "Pilar P5/P6 — minimização de PII na borda, via um endpoint isolado do guardrail (sem precisar de um modelo real)."
mostrar_comando 'POST /guardrails/apply_guardrail  {"guardrail_name":"mascara-pii","text":"Meu CPF é 529.982.247-25, pode cadastrar?"}'
esperar_enter
RESP=$(curl -s "$GATEWAY/guardrails/apply_guardrail" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"guardrail_name": "mascara-pii", "text": "Meu CPF é 529.982.247-25, pode cadastrar?", "language": "en"}')
echo "$RESP" | jq -c '{response_text: (.response_text // .text // .)}'
if echo "$RESP" | grep -q '<BR_CPF>'; then
  concluir "CPF nunca chega ao provedor em claro — mascarado para <BR_CPF> pelo Presidio auto-hospedado (reconhecedor ad-hoc)."
else
  falha "resultado inesperado — CPF não apareceu mascarado; ver testes.sh GR-01 e evidencias/GR-01.json"
fi

# ---------------------------------------------------------------------------
banner "O mesmo guardrail protege uma chamada real de chat" \
  "Pilar P5 (guardrails mandatórios herdados) + princípio 4 (runtime enforcement) — o controle roda no gateway, não na aplicação cliente."
mostrar_comando 'POST /v1/chat/completions  {"model":"local-qwen","guardrails":["mascara-pii"],"messages":[...CPF...]}'
esperar_enter
RESP=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"local-qwen","guardrails":["mascara-pii"],
       "messages":[{"role":"user","content":"Repita exatamente: meu CPF é 529.982.247-25"}]}')
echo "$RESP" | jq -c '{content: .choices[0].message.content}'
concluir "A entrada chegou mascarada ao Ollama (mode pre_call, antes de qualquer chamada ao modelo) — confirme em guardrail_information no spend log / UI de Logs."

apontar_ui "http://localhost:4000/ui/logs → clique na chamada acima (model ollama_chat/qwen2.5:0.5b) → \"Guardrails & Policy Compliance\" → Request Lifecycle mostra \"Pre-call guardrail: mascara-pii — PASSED\". Ou repita ao vivo pelo Playground: roteiro-playground.md deste cenário."
apontar_slide "Slide 19"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 01. Gateway saudável.${C_RESET}"
