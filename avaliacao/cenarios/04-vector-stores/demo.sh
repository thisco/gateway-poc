#!/usr/bin/env bash
# Demo ao vivo — Cenário 04: Vector Stores (pgvector soberano)
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 5
# casos VS-01..VS-05): aqui só os 2 de maior impacto — VS-03 (busca
# semântica recupera a regra certa) e VS-04 (RAG: chat injeta o contexto
# do store soberano antes de responder).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}

titulo_cenario "Cenário 04 — Vector Stores (pgvector soberano)"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
check_container poc-db-vectors "docker compose --profile vectors up -d"
check_container poc-vector-connector "docker compose --profile vectors up -d"
check_file "$SCRIPT_DIR/.store-id" "bash $SCRIPT_DIR/setup.sh  (cria/reconhece o store soberano e grava o UUID)"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"
STORE_ID=$(cat "$SCRIPT_DIR/.store-id")

# Reconciliação silenciosa: um store carregado só do config.yaml some da
# memória do gateway assim que alguém chama GET /vector_store/list (ex.:
# navegando pela UI) — achado 4 do cenário. Persistir de novo aqui é
# idempotente e garante a demo mesmo que isso já tenha acontecido.
curl -s -X POST "$GATEWAY/vector_store/new" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"vector_store_id\":\"$STORE_ID\",\"custom_llm_provider\":\"pg_vector\",\"vector_store_name\":\"base-governanca\",\"litellm_params\":{\"api_base\":\"http://vector-connector:8000\",\"api_key\":\"$KEY\"}}" \
  >/dev/null

# ---------------------------------------------------------------------------
banner "Busca semântica recupera a regra certa, sem ambiguidade" \
  "Pilar P3/P6 — catálogo do store é governado pelo gateway; embeddings 100% locais (Ollama + pgvector), nenhum dado sai para um provedor externo."
mostrar_comando 'POST /v1/vector_stores/{id}/search  {"query":"posso enviar CPF de cidadão para um modelo SaaS externo?"}'
esperar_enter
RESP=$(curl -s -X POST "$GATEWAY/v1/vector_stores/$STORE_ID/search" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"query":"posso enviar CPF de cidadão para um modelo SaaS externo?"}')
echo "$RESP" | jq -c '[.data[] | {regra: .attributes.regra, score}]'
concluir "R1 (dados pessoais/SaaS externo) volta como resultado de maior score — a base soberana discrimina a regra certa, não só \"alguma\" regra."

# ---------------------------------------------------------------------------
banner "RAG: o chat injeta o contexto do store antes de responder" \
  "Pilar P3/P6 — o critério é o contexto ter sido buscado e injetado (visível no log), não a eloquência do modelo local 0.5B."
mostrar_comando "POST /v1/chat/completions  {\"model\":\"local-qwen\",\"vector_store_ids\":[\"$STORE_ID\"],\"messages\":[...]}"
esperar_enter
RESP=$(curl -s "$GATEWAY/v1/chat/completions" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"model\":\"local-qwen\",\"vector_store_ids\":[\"$STORE_ID\"],
       \"messages\":[{\"role\":\"user\",\"content\":\"Segundo a política, posso enviar CPF a modelo externo?\"}]}")
echo "$RESP" | jq -c '{content: (.choices[0].message.content[0:180] // .error)}'
concluir "o pipeline buscou no store antes de chamar o modelo (avector_store_search no log, prompt_tokens bem acima da pergunta original) — contexto soberano injetado de fato."

apontar_ui "http://localhost:4000/ui/logs → clique na chamada acima (model ollama_chat/qwen2.5:0.5b) → prompt_tokens alto confirma o contexto injetado. (A tela Tools → Vector Stores → Manage/Test tem um gap conhecido de listagem — ver achado 4/5 do cenário — por isso a prova aqui é o log, não essa tela.) Roteiro completo: roteiro-playground.md deste cenário."
apontar_slide "Slide 22"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 04. Gateway saudável.${C_RESET}"
