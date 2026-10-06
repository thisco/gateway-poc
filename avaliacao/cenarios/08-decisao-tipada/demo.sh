#!/usr/bin/env bash
# Demo ao vivo — Cenário 08: Decisão tipada local (System One)
#
# Ritmo de apresentação (não confundir com testes.sh, que reproduz os 5
# casos SO-01..05 completos): aqui só os 3 de maior impacto, escolhidos
# pelo controlador — SO-01 (o paradigma choice/score/noul funcionando
# 100% local, com probabilidades reais), SO-03 (o achado mais honesto do
# cenário: o modelo local pequeno ERROU a ordenação esperada de
# adequação de memória — prova ao vivo do limite documentado no README) e
# SO-04 (a mesma decisão tipada aparecendo no log unificado do gateway,
# com custo contabilizado — prova de que herda a governança).
#
# DEMO_AUTO=1 pula os "ENTER para continuar".
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../demo-lib.sh
source "$SCRIPT_DIR/../../demo-lib.sh"

GATEWAY=${GATEWAY:-http://localhost:4000}
DADOS="$SCRIPT_DIR/dados"

titulo_cenario "Cenário 08 — Decisão tipada local (System One)"
echo "Pré-checagens..."
check_key
check_gateway "$GATEWAY"
if [ ! -d "$DADOS/.venv" ]; then
  echo "${C_RED}ERRO: venv do cenário não existe.${C_RESET}" >&2
  echo "  Rode: cd $SCRIPT_DIR && bash testes.sh   (cria o venv na primeira execução)" >&2
  exit 1
fi
pre_checagens_ok
KEY="$LITELLM_MASTER_KEY"

if curl -sf -m 3 http://127.0.0.1:8090/health >/dev/null 2>&1; then
  MODEL="local-hermes"
else
  MODEL="local-qwen"
fi

CHAVE_DEMO=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["local-hermes","local-qwen"],"key_alias":"demo08-cenario","max_budget":1.0,"duration":"1h"}' | jq -r '.key')

# shellcheck source=/dev/null
source "$DADOS/.venv/bin/activate"
export GATEWAY API_KEY="$CHAVE_DEMO" MODEL PYTHONPATH="$DADOS"

# ---------------------------------------------------------------------------
banner "Decisão tipada, 100% local: escolher 1 de 4 famílias de instância, com probabilidades" \
  "Pilar P3 — o motor (system-one-adapter, apontado ao NOSSO gateway/$MODEL) devolve uma opção válida do conjunto + um vetor de probabilidades, não texto livre para parsear."
mostrar_comando "Choice(criteria={m7g,c7g,r7g,t4g}) via system-one-adapter -> gateway -> $MODEL"
esperar_enter
SO01=$(python "$DADOS/so01_choice.py" 2>/dev/null)
echo "$SO01" | jq -c '{decisao, valida: .decisao_e_opcao_valida, confidence, probabilities}'
if echo "$SO01" | jq -e '.decisao_e_opcao_valida == true' >/dev/null 2>&1; then
  concluir "decisão tipada validada por schema, não é texto livre — sempre uma das 4 opções, com probabilidade explícita por opção."
else
  falha "resultado inesperado — ver testes.sh SO-01 e evidencias/SO-01.json"
fi

# ---------------------------------------------------------------------------
banner "O achado mais honesto do cenário: o modelo pequeno erra a ordenação" \
  "Pilar P9 — 4 famílias pontuadas (0-3) na mesma rubrica para um workload em memória; r7g (otimizada para memória) DEVERIA liderar."
mostrar_comando "4x Score(criteria=[rubrica 0..3]) na mesma chamada, mesmo state -> gateway -> $MODEL"
esperar_enter
SO03=$(python "$DADOS/so03_score.py" 2>/dev/null)
echo "$SO03" | jq -c '{scores, ordenacao: .ordenacao_desc, r7g_no_topo}'
if echo "$SO03" | jq -e '.r7g_no_topo == true' >/dev/null 2>&1; then
  concluir "r7g liderou — ordenação coerente com o requisito de memória do workload."
else
  falha "r7g NÃO liderou — o modelo local pequeno errou a ordenação esperada. Isto É o resultado (ver README SS8): não escondemos, documentamos como limite do motor nesta escala, não como bug do harness."
fi

# ---------------------------------------------------------------------------
banner "A decisão tipada herda a governança do gateway, igual a qualquer chamada de chat" \
  "Pilar P4/P2 — a mesma chave virtual usada nas 2 chamadas acima aparece no log unificado, com custo contabilizado (mesmo que \$0 para modelo local)."
mostrar_comando "GET /spend/logs?api_key=... e GET /key/info?key=..."
esperar_enter
# log de spend é gravado de forma assíncrona (mesmo padrão do cenário 07,
# fetch_latest_log) — espera até 16s (8x2s) por pelo menos 2 entradas.
N=0
for _ in $(seq 1 8); do
  LOGS=$(curl -s "$GATEWAY/spend/logs?api_key=$CHAVE_DEMO&limit=10" -H "Authorization: Bearer $KEY")
  N=$(echo "$LOGS" | jq 'length')
  [ "$N" -ge 2 ] && break
  sleep 2
done
echo "  chamadas desta chave no log unificado: $N"
echo "$LOGS" | jq -c '[.[] | {model, call_type, spend}] | .[0:3]'
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_DEMO\"]}" >/dev/null
if [ "$N" -ge 2 ]; then
  concluir "as 2 decisões tipadas acima aparecem no MESMO log de auditoria de qualquer chamada de chat do gateway — a decisão tipada não é um caminho paralelo sem trilha."
else
  falha "log unificado não mostrou as chamadas esperadas — ver testes.sh SO-04 e evidencias/SO-04.json"
fi
deactivate

apontar_ui "http://localhost:4000/ui/logs → filtrar pela chave da demo (alias demo08-cenario, já apagada, mas as linhas de log permanecem). Este cenário não expõe tela própria no Playground (o motor é um SDK Python, não um chat) — ver README §7."
apontar_slide "Slide 26"

echo
check_gateway "$GATEWAY"
echo "${C_GREEN}Fim da demo — cenário 08. Gateway saudável.${C_RESET}"
