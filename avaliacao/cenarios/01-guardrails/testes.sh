#!/usr/bin/env bash
# Cenário 01 — Guardrails (Presidio auto-hospedado)
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
EV="$(dirname "$0")/evidencias"; mkdir -p "$EV"

caso() { # $1=id  $2=descrição  (payload via stdin)  → salva evidência e resume
  local id="$1" desc="$2"
  echo "== $id — $desc"
  curl -s "$GATEWAY/guardrails/apply_guardrail" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d @- | tee "$EV/$id.json" | jq -c '{response_text: (.response_text // .text // .), error: .error}'
}

# GR-01: mascaramento de CPF na entrada
caso GR-01 "CPF é mascarado pelo guardrail" <<'EOF'
{"guardrail_name": "mascara-pii", "text": "Meu CPF é 529.982.247-25, pode cadastrar?", "language": "en"}
EOF

# GR-02: mascaramento de e-mail (entidade nativa)
caso GR-02 "E-mail é mascarado" <<'EOF'
{"guardrail_name": "mascara-pii", "text": "Escreva para fulano@example.gov.br com o resultado."}
EOF

# GR-03: enforcement no fluxo real de chat (pre_call por request)
echo "== GR-03 — guardrail aplicado em chat completion"
curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"local-qwen","guardrails":["mascara-pii"],
       "messages":[{"role":"user","content":"Repita exatamente: meu CPF é 529.982.247-25"}]}' \
  | tee "$EV/GR-03.json" | jq -c '{content: .choices[0].message.content}'

# GR-04: modo logging_only não altera a resposta
echo "== GR-04 — logging_only observa sem bloquear"
curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"simulado","guardrails":["mascara-pii-log"],
       "messages":[{"role":"user","content":"Meu CPF é 529.982.247-25"}]}' \
  | tee "$EV/GR-04.json" | jq -c '{content: .choices[0].message.content}'

# GR-05: frase neutra não é alterada (controle de falso-positivo)
caso GR-05 "Frase sem PII passa intacta" <<'EOF'
{"guardrail_name": "mascara-pii", "text": "Qual a capital do Brasil?"}
EOF
