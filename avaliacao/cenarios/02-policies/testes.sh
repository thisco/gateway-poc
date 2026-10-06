#!/usr/bin/env bash
# Cenário 02 — Guardrail Policies
#
# Nota de execução: o rascunho original do brief presumia endpoints
# /policies e /policies/{nome}/attach. Conferido no Swagger real
# (http://localhost:4000/openapi.json) da imagem ghcr.io/berriai/litellm:main-stable
# (v1.100.0): o endpoint de listagem é GET /policies/list; o de leitura
# com herança resolvida é GET /policy/info/{policy_name} (GET /policies/{id}
# só enxerga policies criadas via API, não as definidas em config.yaml);
# anexação por time é POST /policies/attachments, mas só aceita policies
# "definition_location: db" — por isso PO-03 primeiro recria a policy via
# POST /policies antes de anexar. O parâmetro de request `policies` em
# /v1/chat/completions NÃO está documentado, mas existe e funciona nesta
# build (confirmado abaixo em PO-04).
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
EV="$(dirname "$0")/evidencias"; mkdir -p "$EV"

# PO-01: policies definidas no config.yaml aparecem na API de gestão
echo "== PO-01 — listar policies (GET /policies/list)"
curl -s "$GATEWAY/policies/list" -H "Authorization: Bearer $KEY" \
  | tee "$EV/PO-01.json" | jq -c '{total_count, nomes: [.policies[].policy_name]}'

# PO-02: herança — protecao-total resolve os guardrails da base + o próprio
echo "== PO-02 — herança de policy (GET /policy/info/protecao-total)"
curl -s "$GATEWAY/policy/info/protecao-total" -H "Authorization: Bearer $KEY" \
  | tee "$EV/PO-02.json" | jq -c '{inherit, guardrails, resolved_guardrails, inheritance_chain}'

# PO-03: anexar policy a um time (teste de licença Enterprise)
echo "== PO-03 — anexação por time (teste de licença)"
TEAM=$(curl -s "$GATEWAY/team/new" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" \
  -d '{"team_alias":"avaliacao-policies"}' | jq -r '.team_id')
echo "team_id=$TEAM"
# Anexação exige policy "db" (as definidas só em config.yaml não são
# encontradas por /policies/attachments) — recria a policy via API,
# espelhando o mesmo conteúdo já definido no config.yaml.
curl -s "$GATEWAY/policies" -X POST -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"policy_name":"protecao-total","inherit":"protecao-base","guardrails_add":["mascara-pii"]}' \
  | jq -c '{policy_id, definition_location}'
curl -s "$GATEWAY/policies/attachments" -X POST \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"policy_name":"protecao-total","teams":["avaliacao-policies"]}' \
  | tee "$EV/PO-03.json" | jq -c '.'

# PO-04: policy invocada em chamada real (parâmetro `policies` por request)
echo "== PO-04 — policy aplicada em chat"
curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"model":"simulado","policies":["protecao-total"],
       "messages":[{"role":"user","content":"Meu CPF é 529.982.247-25"}]}' \
  | tee "$EV/PO-04.json" | jq -c '{content: .choices[0].message.content, error: .error}'
