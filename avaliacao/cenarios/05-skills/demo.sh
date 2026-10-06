#!/usr/bin/env bash
# Demo ao vivo — Cenário 05: Skills (Anthropic Skills API via proxy)
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 4
# casos SK-01..SK-04): aqui só os 2 de maior impacto — SK-01 (criar a
# skill institucional) e SK-03 (o achado: não existe busca semântica,
# query/top_k são ignorados). SK-04 (usar a skill em chamada real) NÃO é
# reexecutado aqui — é uma chamada cara (~9k tokens de entrada, container
# de execução de código) já documentada em evidencias/SK-04.json.
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}
DADOS="$SCRIPT_DIR/dados"

titulo_cenario "Cenário 05 — Skills (Anthropic Skills API via proxy)"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

# ---------------------------------------------------------------------------
banner "A skill institucional (RIPD) é criada — e passa a existir de verdade" \
  "Pilar P3/P9 — skill como ativo versionável (SKILL.md no git), catalogada, referenciável por ID em qualquer chamada futura."
mostrar_comando 'POST /v1/skills?beta=true  (multipart: display_title + SKILL.md zipado)'
esperar_enter
# display_title precisa ser único na conta Anthropic (achado, descoberto ao
# validar esta demo: reexecutar com o mesmo título dá 400 "Skill cannot
# reuse an existing display_title") — por isso um sufixo de timestamp,
# só para a demo (SK-01 em testes.sh não precisa disso, roda uma vez).
TITULO="Relatório de Impacto LGPD (RIPD) — demo $(date +%H%M%S)"
rm -f /tmp/skill-relatorio-lgpd-demo.zip
rm -rf /tmp/skill-stage-demo && mkdir -p /tmp/skill-stage-demo/relatorio-lgpd
cp "$DADOS/skill-relatorio-lgpd/SKILL.md" /tmp/skill-stage-demo/relatorio-lgpd/
(cd /tmp/skill-stage-demo && zip -qr /tmp/skill-relatorio-lgpd-demo.zip relatorio-lgpd)
RESP=$(curl -s "$GATEWAY/v1/skills?beta=true" \
  -H "Authorization: Bearer $KEY" \
  -F "display_title=$TITULO" \
  -F "files[]=@/tmp/skill-relatorio-lgpd-demo.zip")
echo "$RESP" | jq -c '{id: .id, name: (.display_title // .name), error: .error}'
SKILL_ID=$(echo "$RESP" | jq -r '.id // empty')
if [ -n "$SKILL_ID" ]; then
  concluir "skill criada com id $SKILL_ID — mas atenção: ela passa a existir na conta Anthropic (ANTHROPIC_API_KEY), não no banco do proxy (achado 1 do cenário)."
else
  falha "criação falhou nesta execução — ver evidencias/SK-01.json para a evidência já validada"
fi

# ---------------------------------------------------------------------------
banner "\"Busca por necessidade\" não existe — é listagem estática" \
  "Pilar P9 — query/top_k são aceitos e silenciosamente ignorados; a resposta é idêntica a um GET simples, sem search_score."
mostrar_comando 'GET /v1/skills?beta=true&query=preciso+escrever+um+relatorio+de+impacto+de+dados+pessoais&top_k=3'
esperar_enter
RESP=$(curl -s "$GATEWAY/v1/skills?beta=true&query=preciso+escrever+um+relatorio+de+impacto+de+dados+pessoais&top_k=3" \
  -H "Authorization: Bearer $KEY")
echo "$RESP" | jq -c '[.data[]? | {id, name: (.display_title // .name), score: .search_score}] // .'
concluir "score sempre null — não há descoberta semântica de skill neste endpoint, mesmo aceitando os parâmetros sem erro (gap documentado, achado 2)."

apontar_ui "http://localhost:4000/ui/skills mostra \"No skills found\" mesmo com a skill acima existindo de verdade — é OUTRO catálogo (Claude Code Skill Hub), achado 3 do cenário. A skill real só aparece via API. Roteiro completo: roteiro-playground.md deste cenário."
apontar_slide "Slide 23"

# ---------------------------------------------------------------------------
# Extensão SK-05/SK-06: skill de MERCADO (não sintética), baixada de
# github.com/anthropics/skills (Apache 2.0, procedência completa no
# README §4). Passo curto — só a instalação (SK-05); o uso real (SK-06,
# ~18k tokens de entrada com o container) fica documentado em
# evidencias/SK-06.json, igual à decisão já tomada para SK-04 nesta demo.
banner "Skill de MERCADO entra no mesmo catálogo, sem distinção de procedência" \
  "Pilar P3/P8 — achado 6: skill própria e skill de terceiro (baixada de um git público) ficam indistinguíveis no catálogo (mesmo source: \"custom\"), o que exige homologação manual de procedência/conteúdo ANTES do upload."
mostrar_comando 'POST /v1/skills?beta=true  (multipart: display_title + internal-comms.zip, de github.com/anthropics/skills)'
esperar_enter
TITULO_MERCADO="Internal Comms (skill de mercado) — demo $(date +%H%M%S)"
rm -f /tmp/skill-internal-comms-demo.zip
rm -rf /tmp/skill-stage-mercado-demo && mkdir -p /tmp/skill-stage-mercado-demo/internal-comms
cp -R "$DADOS/skill-mercado-internal-comms/." /tmp/skill-stage-mercado-demo/internal-comms/
(cd /tmp/skill-stage-mercado-demo && zip -qr /tmp/skill-internal-comms-demo.zip internal-comms)
RESP=$(curl -s "$GATEWAY/v1/skills?beta=true" \
  -H "Authorization: Bearer $KEY" \
  -F "display_title=$TITULO_MERCADO" \
  -F "files[]=@/tmp/skill-internal-comms-demo.zip")
echo "$RESP" | jq -c '{id: .id, name: (.display_title // .name), error: .error}'
MERCADO_ID=$(echo "$RESP" | jq -r '.id // empty')
if [ -n "$MERCADO_ID" ]; then
  concluir "skill de mercado criada com id $MERCADO_ID — mesmo caminho, mesmo source: \"custom\" da skill própria. Uso real (SK-06) e a leitura de conteúdo pré-upload contra injeção: ver evidencias/SK-06.json e README §4/§8 (achado 6)."
else
  falha "criação falhou nesta execução — ver evidencias/SK-05.json para a evidência já validada"
fi

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 05. Gateway saudável.${C_RESET}"
