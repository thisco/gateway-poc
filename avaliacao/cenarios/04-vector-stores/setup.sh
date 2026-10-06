#!/usr/bin/env bash
# Cenário 04 — Vector Stores: setup idempotente do store soberano.
#
# Corrige o achado crítico de reprodutibilidade (ver README §3.1): o
# store `base-governanca` e a migração de schema do `vector-connector`
# eram feitos à mão, fora de qualquer script, com o UUID resultante
# hardcoded em `poc/gateway/config.yaml`. Um clone novo do repositório
# (db-vectors vazio) quebrava, porque:
#   - a extensão `vector` não vem habilitada por padrão no Postgres novo;
#   - o schema do conector (`prisma/schema.prisma`) nunca é migrado
#     automaticamente (README do conector trata isso como passo manual);
#   - a coluna `embedding` do conector é fixa em `vector(1536)`, mas o
#     modelo de embedding real da PoC (`embedding-nomic`, Ollama
#     `nomic-embed-text`) produz vetores de 768 dimensões;
#   - o `vector_store_id` é um UUID gerado pelo conector via
#     `gen_random_uuid()` na criação — não é escolhível — então cada
#     ambiente novo gera um UUID diferente do hardcoded no config.yaml.
#
# Este script resolve as quatro etapas de forma idempotente: pode ser
# rodado em um ambiente já configurado sem efeito colateral (cada passo
# checa o estado atual antes de agir).
set -uo pipefail

CONECTOR=${CONECTOR:-http://localhost:8002}
GATEWAY_URL=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY (ex.: source poc/.env)}
STORE_NAME="base-governanca"
EMBED_DIM=768

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
COMPOSE_FILE="$REPO_ROOT/poc/docker-compose.yml"
CONFIG_YAML="$REPO_ROOT/poc/gateway/config.yaml"
STORE_ID_FILE="$SCRIPT_DIR/.store-id"

echo "== 1/5 — extensão pgvector no db-vectors"
docker exec poc-db-vectors psql -U vectors -d vectors -c \
  "CREATE EXTENSION IF NOT EXISTS vector;" || {
    echo "ERRO: não foi possível falar com poc-db-vectors — stack no ar? (docker compose --profile vectors up -d)" >&2
    exit 1
  }

echo "== 2/5 — prisma db push (schema do vector-connector)"
docker compose -f "$COMPOSE_FILE" run --rm --no-deps vector-connector prisma db push || {
  echo "ERRO: prisma db push falhou" >&2
  exit 1
}

echo "== 3/5 — dimensão do vetor (schema do conector fixa 1536; embedding-nomic produz $EMBED_DIM)"
TIPO_ATUAL=$(docker exec poc-db-vectors psql -U vectors -d vectors -tAc \
  "SELECT format_type(atttypid, atttypmod) FROM pg_attribute WHERE attrelid = 'embeddings'::regclass AND attname = 'embedding';")
if [ "$TIPO_ATUAL" != "vector($EMBED_DIM)" ]; then
  echo "   tipo atual: $TIPO_ATUAL -> ajustando para vector($EMBED_DIM)"
  docker exec poc-db-vectors psql -U vectors -d vectors -c \
    "ALTER TABLE embeddings ALTER COLUMN embedding TYPE vector($EMBED_DIM);"
else
  echo "   já é vector($EMBED_DIM) — nada a fazer"
fi

echo "== 4/5 — store '$STORE_NAME' no conector"
# Consulta o Postgres diretamente (não o GET /v1/vector_stores do conector:
# bug conhecido, quebra com 500 assim que o store tem atividade — README §8).
EXISTENTE=$(docker exec poc-db-vectors psql -U vectors -d vectors -tAc \
  "SELECT id FROM vector_stores WHERE name = '$STORE_NAME' ORDER BY created_at DESC LIMIT 1;" | tr -d '[:space:]')
if [ -n "$EXISTENTE" ]; then
  STORE_ID="$EXISTENTE"
  echo "   store já existe: $STORE_ID (reuso)"
else
  RESP=$(curl -s -X POST "$CONECTOR/v1/vector_stores" \
    -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
    -d "{\"name\":\"$STORE_NAME\"}")
  STORE_ID=$(echo "$RESP" | jq -r '.id // empty')
  if [ -z "$STORE_ID" ]; then
    echo "ERRO: falha ao criar store no conector: $RESP" >&2
    exit 1
  fi
  echo "   store criado: $STORE_ID"
fi
echo "$STORE_ID" > "$STORE_ID_FILE"
echo "   gravado em $STORE_ID_FILE (lido por testes.sh; NÃO versionado — ver .gitignore)"

echo "== 5/5 — sincronizar vector_store_id no config.yaml e reiniciar o gateway (se divergente)"
ID_NO_CONFIG=$(grep 'vector_store_id:' "$CONFIG_YAML" | head -1 | sed -E 's/.*vector_store_id: *"?([a-f0-9-]+)"?.*/\1/')
if [ "$ID_NO_CONFIG" != "$STORE_ID" ]; then
  echo "   config.yaml tinha '$ID_NO_CONFIG', atualizando para '$STORE_ID'"
  sed -i.bak -E "s/(vector_store_id: \")[a-f0-9-]+(\")/\1$STORE_ID\2/" "$CONFIG_YAML"
  rm -f "$CONFIG_YAML.bak"
  echo "   reiniciando o gateway para recarregar o config.yaml..."
  docker compose -f "$COMPOSE_FILE" restart gateway
  echo -n "   aguardando healthcheck do gateway"
  ok=""
  for _ in $(seq 1 30); do
    if curl -sf "$GATEWAY_URL/health/liveliness" >/dev/null 2>&1; then
      ok=1; break
    fi
    echo -n "."; sleep 2
  done
  echo
  if [ -z "$ok" ]; then
    echo "ERRO: gateway não voltou saudável a tempo" >&2
    exit 1
  fi
  echo "   gateway OK"
else
  echo "   config.yaml já está com o UUID correto ($STORE_ID) — nada a fazer"
fi

echo
echo "Setup completo. STORE_ID=$STORE_ID"
echo "Próximo passo: bash testes.sh"
