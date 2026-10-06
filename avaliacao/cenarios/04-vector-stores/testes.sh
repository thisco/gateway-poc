#!/usr/bin/env bash
# Cenário 04 — Vector Stores (pgvector soberano)
#
# Nota de execução (ver README §3 para o detalhamento completo): o rascunho
# original do brief presumia um fluxo "OpenAI Files" (POST .../files,
# multipart/JSON) e um custom_llm_provider "pgvector". Conferido no
# código-fonte real do gateway (imagem ghcr.io/berriai/litellm:main-stable)
# e do conector (github.com/BerriAI/litellm-pgvector):
#
#   1. O provedor correto é "pg_vector" (com underscore) — "pgvector" não
#      existe no enum litellm.LlmProviders.
#   2. O gateway NÃO tem transformação de "vector store files" para
#      pg_vector (só para "openai" nativo) — o endpoint OpenAI-compatível
#      POST /v1/vector_stores/{id}/files falha para este provedor. A
#      ingestão real precisa ir direto ao conector:
#      POST {api_base}/v1/vector_stores/{id}/embeddings, com o vetor de
#      embedding já calculado (o conector NÃO gera embedding de ingestão —
#      só da query de busca).
#   3. O vector_store_id não pode ser escolhido: o conector gera um UUID via
#      gen_random_uuid() na criação. Por isso o STORE_ID não é mais fixo
#      neste script — ele é lido de `.store-id`, gravado por `setup.sh`
#      (setup idempotente: extensão vector, migração do schema, ajuste de
#      dimensão do vetor e criação/reuso do store — ver README §3.1). Rode
#      `bash setup.sh` uma vez por ambiente (ou sempre que o db-vectors for
#      recriado) antes deste script.
#   4. Um store carregado só de `vector_store_registry:` (config.yaml, em
#      memória) é apagado por uma rotina de sincronização com o banco de
#      controle do gateway assim que ela roda (ex.: ao chamar
#      GET /vector_store/list) — "legacy behavior" segundo o próprio
#      código-fonte. Por isso o VS-01 abaixo também persiste o store via
#      POST /vector_store/new (grava no Postgres de controle do gateway),
#      não só no config.yaml — sem isso, VS-03/04/05 ficam instáveis depois
#      da primeira chamada de management.
#   5. GET /v1/vector_stores no PRÓPRIO conector (list) quebra com 500
#      ("'str' object has no attribute 'timestamp'") assim que o store já
#      teve alguma atividade (last_active_at preenchido) — bug real do
#      conector (achado, ver README §8). Por isso nem este script nem o
#      `setup.sh` usam esse endpoint para checar se o store já existe.
#
# set -e não é usado de propósito: os casos VS-04/VS-05 têm resultado
# "esperado" que inclui respostas de baixa qualidade (modelo 0.5b) ou acesso
# permitido (achado de gap) — nenhum dos dois é uma falha de script.
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
CONECTOR=${CONECTOR:-http://localhost:8002}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EV="$SCRIPT_DIR/evidencias"; DADOS="$SCRIPT_DIR/dados"; mkdir -p "$EV"

STORE_ID_FILE="$SCRIPT_DIR/.store-id"
if [ -n "${STORE_ID:-}" ]; then
  : # permite override explícito via env (ex.: comparar dois stores)
elif [ -f "$STORE_ID_FILE" ]; then
  STORE_ID=$(cat "$STORE_ID_FILE")
else
  echo "ERRO: $STORE_ID_FILE não existe. Rode 'bash setup.sh' primeiro (cria/reconhece o store e grava o UUID nesse arquivo)." >&2
  exit 1
fi

# VS-01: store soberano (STORE_ID fixo, criado uma vez no conector — ver
# nota de execução item 3) está catalogado/governado no gateway (P3):
# registrado tanto no config.yaml (vector_store_registry, versionado)
# quanto persistido via /vector_store/new (durável, sobrevive à
# sincronização com o banco de controle — ver nota de execução item 4).
echo "== VS-01 — store soberano catalogado no gateway (P3)"
curl -s -X POST "$GATEWAY/vector_store/new" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"vector_store_id\":\"$STORE_ID\",\"custom_llm_provider\":\"pg_vector\",\"vector_store_name\":\"base-governanca\",\"vector_store_description\":\"Base de conhecimento de governança (soberana: pgvector local + embeddings Ollama)\",\"litellm_params\":{\"api_base\":\"http://vector-connector:8000\",\"api_key\":\"$KEY\"}}" \
  > "$EV/VS-01-gateway-persist.json"
curl -s "$GATEWAY/vector_store/list" -H "Authorization: Bearer $KEY" \
  | tee "$EV/VS-01.json" | jq -c '.data[] | {vector_store_id, vector_store_name, custom_llm_provider}'

# VS-02: ingerir o documento de política, uma regra por embedding (R1/R2/R3)
# — cada chunk é embedado pelo modelo governado embedding-nomic (via
# gateway) e o vetor resultante é gravado no pgvector soberano via conector.
echo "== VS-02 — ingerir documento (uma regra por embedding)"
ingerir_regra() {
  local rotulo="$1" inicio="$2" fim="$3" texto emb
  if [ -n "$fim" ]; then
    texto=$(sed -n "/$inicio/,/$fim/p" "$DADOS/politica-uso-ia.md" | sed '$d')
  else
    texto=$(sed -n "/$inicio/,\$p" "$DADOS/politica-uso-ia.md")
  fi
  emb=$(curl -s "$GATEWAY/v1/embeddings" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$texto" '{model:"embedding-nomic", input:$t}')" | jq -c '.data[0].embedding')
  curl -s -X POST "$CONECTOR/v1/vector_stores/$STORE_ID/embeddings" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "$(jq -n --arg t "$texto" --argjson e "$emb" --arg lbl "$rotulo" \
      '{content:$t, embedding:$e, metadata:{regra:$lbl, filename:"politica-uso-ia.md"}}')"
}
{
  ingerir_regra "R1" '\*\*R1' '^\*\*R2'
  echo
  ingerir_regra "R2" '\*\*R2' '^\*\*R3'
  echo
  ingerir_regra "R3" '\*\*R3' ''
  echo
} | tee "$EV/VS-02.json" | grep -o '"id":"[^"]*"\|"content":"[^"]\{0,40\}'

# VS-03: busca semântica deve recuperar R1 como resultado mais relevante
# para uma pergunta sobre CPF e modelo SaaS externo.
echo "== VS-03 — busca semântica"
curl -s -X POST "$GATEWAY/v1/vector_stores/$STORE_ID/search" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"query":"posso enviar CPF de cidadão para um modelo SaaS externo?"}' \
  | tee "$EV/VS-03.json" | jq -c '[.data[] | {regra: .attributes.regra, score}]'

# VS-04: RAG — chat com vector_store_ids injeta o contexto do store antes da
# geração. Critério de sucesso: o contexto foi buscado (visível no
# /spend/logs, call_type avector_store_search, custom_llm_provider pg_vector,
# imediatamente antes da chamada de chat) — não a eloquência do local-qwen
# (0.5b, resposta tende a ser fraca/alucinada mesmo com o contexto certo).
echo "== VS-04 — chat com contexto do store (RAG)"
curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"local-qwen\",\"vector_store_ids\":[\"$STORE_ID\"],
       \"messages\":[{\"role\":\"user\",\"content\":\"Segundo a política, posso enviar CPF a modelo externo?\"}]}" \
  | tee "$EV/VS-04.json" | jq -c '{content: .choices[0].message.content[0:200]}'
sleep 2
echo "-- confirmação no log de auditoria (avector_store_search antecedendo o chat):"
curl -s "$GATEWAY/spend/logs?limit=5" -H "Authorization: Bearer $KEY" \
  | jq -c '[.[0:4][] | {call_type, custom_llm_provider, api_base, model, startTime}]' \
  | tee "$EV/VS-04-spend-logs.json"

# VS-05: chave restrita (sem qualquer object_permission de vector store)
# tenta buscar no mesmo store — resultado observado é achado de gap ou
# controle, documentado no README (comparar com deny-by-default do MCP,
# cenário 03).
echo "== VS-05 — acesso ao store por chave restrita (sem permissão explícita)"
CHAVE=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
curl -s -X POST "$GATEWAY/v1/vector_stores/$STORE_ID/search" \
  -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
  -d '{"query":"CPF"}' | tee "$EV/VS-05.json" | jq -c '{n_resultados: (.data // [] | length), erro: .error.message}'
