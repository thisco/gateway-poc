#!/usr/bin/env bash
# Demo ao vivo — Cenário 02: Guardrail Policies
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 4
# casos PO-01..PO-04): aqui só os 2 de maior impacto — PO-02 (herança
# resolvida: protecao-total herda de protecao-base) e PO-04 (a policy
# disparando os guardrails numa chamada real, sem o cliente escolher
# guardrails um a um).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 02 — Guardrail Policies"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
check_container poc-presidio-analyzer "docker compose --profile guardrails up -d  (PO-04 dispara o guardrail mascara-pii)"
check_container poc-presidio-anonymizer "docker compose --profile guardrails up -d"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

# ---------------------------------------------------------------------------
banner "A policy \"protecao-total\" herda a proteção da \"protecao-base\"" \
  "Pilar P5/P10 — herança de guardrails por perfil de risco, definida em config.yaml versionado (política como código)."
mostrar_comando 'GET /policy/info/protecao-total'
esperar_enter
RESP=$(curl -s "$GATEWAY/policy/info/protecao-total" -H "Authorization: Bearer $KEY")
echo "$RESP" | jq -c '{inherit, guardrails, resolved_guardrails, inheritance_chain}'
concluir "resolved_guardrails une o guardrail próprio (mascara-pii) com o herdado de protecao-base (mascara-pii-log) — herança funcionando de verdade, não só na intenção do yaml."

# ---------------------------------------------------------------------------
banner "A policy é invocada numa chamada real — sem o cliente escolher guardrails" \
  "Pilar P5 (herdado por perfil) + P7 (cliente não é confiável por padrão) — o chamador só referencia a policy, não decide qual guardrail rodar."
mostrar_comando 'POST /v1/chat/completions  {"model":"simulado","policies":["protecao-total"],"messages":[...CPF...]}'
esperar_enter
RESP=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"simulado","policies":["protecao-total"],
       "messages":[{"role":"user","content":"Meu CPF é 529.982.247-25"}]}')
echo "$RESP" | jq -c '{content: .choices[0].message.content}'
concluir "os guardrails resolvidos da policy (mascara-pii + mascara-pii-log) rodaram nesta chamada — confirme applied_guardrails na UI de Logs."

apontar_ui "http://localhost:4000/ui/logs → clique na chamada acima (model openai/simulado) → Metadata → applied_guardrails: [\"mascara-pii\",\"mascara-pii-log\"]. Ou repita ao vivo pelo Playground: roteiro-playground.md deste cenário (aba Policies do chat)."
apontar_slide "Slide 20"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 02. Gateway saudável.${C_RESET}"
