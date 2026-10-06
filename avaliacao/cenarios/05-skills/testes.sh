#!/usr/bin/env bash
# Cenário 05 — Skills (Anthropic Skills API via proxy LiteLLM)
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY}
EV="$(dirname "$0")/evidencias"; DADOS="$(dirname "$0")/dados"; mkdir -p "$EV"

# Adaptações confirmadas no Swagger real (http://localhost:4000/openapi.json,
# tag anthropic_skills) em relação ao rascunho do brief:
#   1. Todos os endpoints exigem query param "?beta=true" (não documentado
#      no brief) — sem ele o proxy não reconhece o recurso como habilitado.
#   2. O campo de upload multipart é "files[]" (não "files") e é obrigatório
#      acompanhar "display_title" como campo de formulário.
#   3. GET /v1/skills não tem parâmetros "query"/"top_k" no schema — é um
#      list simples (limit/after_id/before_id/custom_llm_provider). SK-03
#      testa o comportamento real ao enviar esses parâmetros mesmo assim.

# SK-01: criar skill customizada (repassada pelo proxy à Anthropic Skills API)
# Nota: o zip precisa conter uma única pasta de topo com o SKILL.md dentro
# dela, e o NOME dessa pasta precisa ser idêntico ao campo "name:" do
# frontmatter do SKILL.md ("relatorio-lgpd") — a Anthropic Skills API
# rejeita zips soltos ("Zip must contain a top-level folder...") e também
# rejeita pasta com nome diferente do skill ("The folder name '...' must
# match the skill name '...' in SKILL.md"). Por isso montamos o zip a
# partir de um diretório de staging renomeado (achados, ver §8).
echo "== SK-01 — criar skill"
rm -f /tmp/skill-relatorio-lgpd.zip
rm -rf /tmp/skill-stage && mkdir -p /tmp/skill-stage/relatorio-lgpd
cp "$DADOS/skill-relatorio-lgpd/SKILL.md" /tmp/skill-stage/relatorio-lgpd/
(cd /tmp/skill-stage && zip -qr /tmp/skill-relatorio-lgpd.zip relatorio-lgpd)
curl -s "$GATEWAY/v1/skills?beta=true" \
  -H "Authorization: Bearer $KEY" \
  -F "display_title=Relatório de Impacto LGPD (RIPD)" \
  -F "files[]=@/tmp/skill-relatorio-lgpd.zip" \
  | tee "$EV/SK-01.json" | jq -c '{id: .id, name: (.display_title // .name), error: .error}'
SKILL_ID=$(jq -r '.id // empty' "$EV/SK-01.json")

# SK-02: listar skills do catálogo
echo "== SK-02 — listar skills"
curl -s "$GATEWAY/v1/skills?beta=true" -H "Authorization: Bearer $KEY" \
  | tee "$EV/SK-02.json" | jq -c '[.data[]? | {id, name: (.display_title // .name)}] // .'

# SK-03: busca semântica de skill por necessidade (GET /v1/skills não expõe
# query/top_k no schema real — testamos assim mesmo para observar o comportamento)
echo "== SK-03 — busca semântica"
curl -s "$GATEWAY/v1/skills?beta=true&query=preciso+escrever+um+relatorio+de+impacto+de+dados+pessoais&top_k=3" \
  -H "Authorization: Bearer $KEY" \
  | tee "$EV/SK-03.json" | jq -c '[.data[]? | {id, score: .search_score}] // .'

# SK-04: usar a skill em chamada real (conta Anthropic com crédito — execução real)
# Achado: sem tools[].code_execution_20250825 habilitado, o container rejeita
# com "container: skills can only be used when a code execution tool is
# enabled" — Skills SEMPRE depende do container de execução de código
# (custo/latência extra), mesmo quando a skill em si não roda nenhum código
# (a nossa é só um SKILL.md de instruções). O header "anthropic-beta" com os
# dois flags (code-execution + skills) precisou ser repassado explicitamente
# pelo proxy (achado, ver §8).
echo "== SK-04 — usar skill em chamada (fronteira-haiku)"
curl -s "$GATEWAY/v1/messages" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -H "anthropic-beta: code-execution-2025-08-25,skills-2025-10-02" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":3000,
       \"tools\":[{\"type\":\"code_execution_20250825\",\"name\":\"code_execution\"}],
       \"container\":{\"skills\":[{\"type\":\"custom\",\"skill_id\":\"$SKILL_ID\"}]},
       \"messages\":[{\"role\":\"user\",\"content\":\"Esboce um RIPD para um chatbot interno.\"}]}" \
  | tee "$EV/SK-04.json" | jq -c '{stop_reason, ok: (.content != null), error: (.error.message // .error)}'

# SK-05: instalar skill de MERCADO de git público (github.com/anthropics/skills,
# commit 34040c9c568585f6929bedeaad110ad08f079624, skill "internal-comms",
# Apache 2.0 — ver §4 do README para a procedência completa e a revisão de
# conteúdo feita antes deste upload, contra injeção). A pasta local
# dados/skill-mercado-internal-comms/ é uma cópia exata do que está no
# repositório upstream (SKILL.md + LICENSE.txt + examples/); igual a SK-01,
# o zip precisa de uma pasta-topo com o nome do skill ("internal-comms").
echo "== SK-05 — instalar skill de mercado (anthropics/skills, internal-comms)"
rm -f /tmp/skill-internal-comms.zip
rm -rf /tmp/skill-stage-mercado && mkdir -p /tmp/skill-stage-mercado/internal-comms
cp -R "$DADOS/skill-mercado-internal-comms/." /tmp/skill-stage-mercado/internal-comms/
(cd /tmp/skill-stage-mercado && zip -qr /tmp/skill-internal-comms.zip internal-comms)
curl -s "$GATEWAY/v1/skills?beta=true" \
  -H "Authorization: Bearer $KEY" \
  -F "display_title=Internal Comms (skill de mercado — anthropics/skills)" \
  -F "files[]=@/tmp/skill-internal-comms.zip" \
  | tee "$EV/SK-05.json" | jq -c '{id: .id, name: (.display_title // .name), error: .error}'
MERCADO_SKILL_ID=$(jq -r '.id // empty' "$EV/SK-05.json")

# SK-06: usar a skill de mercado em chamada real — mesmo mecanismo de SK-04
# (container.skills + tool code_execution_20250825 + header anthropic-beta).
# max_tokens menor (1500) que SK-04 (3000) por pedido do controlador; o
# pedido ("3P update" curto) é compatível com uma resposta mais enxuta.
echo "== SK-06 — usar skill de mercado em chamada (fronteira-haiku)"
curl -s "$GATEWAY/v1/messages" \
  -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -H "anthropic-beta: code-execution-2025-08-25,skills-2025-10-02" \
  -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":1500,
       \"tools\":[{\"type\":\"code_execution_20250825\",\"name\":\"code_execution\"}],
       \"container\":{\"skills\":[{\"type\":\"custom\",\"skill_id\":\"$MERCADO_SKILL_ID\"}]},
       \"messages\":[{\"role\":\"user\",\"content\":\"Escreva um 3P update (Progress, Plans, Problems) curto para o time de plataforma de IA, status desta semana: avaliação do LiteLLM concluída, próxima semana início do rollout de policies.\"}]}" \
  | tee "$EV/SK-06.json" | jq -c '{stop_reason, ok: (.content != null), error: (.error.message // .error)}'

# Observação extra (não é um ID SK-* novo — pedido do controlador em §8):
# o catálogo de skills é por chave/time ou global ao proxy? Gera uma chave
# restrita (só o modelo fronteira-haiku, sem nenhuma permissão de skills —
# o schema LiteLLM_ObjectPermissionBase nem tem um campo "skills", ao
# contrário de mcp_servers/vector_stores/agents/models) e testa se ela lista
# o catálogo de skills mesmo assim.
echo "== bônus — chave restrita consegue listar skills?"
RESTRICTED=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" \
  -H "Content-Type: application/json" -d '{"models": ["fronteira-haiku"]}')
RKEY=$(jq -r '.key' <<<"$RESTRICTED")
curl -s "$GATEWAY/v1/skills?beta=true" -H "Authorization: Bearer $RKEY" \
  | tee "$EV/SK-bonus-chave-restrita.json" | jq -c '{ids: [.data[]?.id], error}'
