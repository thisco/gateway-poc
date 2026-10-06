#!/usr/bin/env bash
# Cenário 08 — Decisão tipada local (System One: choice/score/noul)
#
# Motor: system-one-adapter (typesafe-ai/system-one-adapter-python, MIT),
# apontado para o NOSSO gateway (rota OpenAI-compatible /v1) com um modelo
# local (local-hermes por padrão — llama.cpp no host :8090 — com fallback
# automático para local-qwen se o host:8090 não responder). NÃO é o Laya
# (github.com/NandhaKishorM/laya, Apache-2.0) — Laya existe de verdade e
# foi verificado (README §3), mas é um classificador não-autoregressivo
# dedicado, sem nenhuma chamada de API a interceptar: estruturalmente
# incompatível com o requisito de governança deste cenário (SO-04, decisão
# tem que passar pelo gateway). Ver README §3 para a análise completa.
#
# SO-01 choice / SO-02 noul / SO-03 score / SO-05 consistência chamam o
# gateway através do adapter (dados/so0N_*.py, venv isolado em
# dados/.venv — não versionado). SO-04 (governança) não tem script próprio:
# reaproveita as chamadas de SO-01..03/05 (mesma chave virtual cenario-08)
# e só consulta /key/info e /spend/logs do gateway.
set -uo pipefail
GATEWAY=${GATEWAY:-http://localhost:4000}
KEY=${LITELLM_MASTER_KEY:?exporte LITELLM_MASTER_KEY (set -a; source poc/.env; set +a)}
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EV="$SCRIPT_DIR/evidencias"; mkdir -p "$EV"
DADOS="$SCRIPT_DIR/dados"

echo "== Pré-checagem do gateway =="
curl -sf "$GATEWAY/health/readiness" >/dev/null || { echo "ERRO: gateway não saudável em $GATEWAY" >&2; exit 1; }
echo "gateway OK ($GATEWAY)"

echo
echo "== Escolha do modelo local (ordem: local-hermes -> local-qwen) =="
if curl -sf -m 3 http://127.0.0.1:8090/health >/dev/null 2>&1; then
  MODEL="local-hermes"
  echo "local-hermes (llama.cpp, host:8090) respondeu — usando local-hermes."
else
  MODEL="local-qwen"
  echo "local-hermes (host:8090) NÃO respondeu — usando local-qwen (ollama, sempre disponível)."
fi
echo "{\"motor\":\"system-one-adapter (typesafe-ai/system-one-adapter-python, MIT)\",\"modelo_local_usado\":\"$MODEL\",\"hermes_disponivel\":$(curl -sf -m 3 http://127.0.0.1:8090/health >/dev/null 2>&1 && echo true || echo false)}" \
  | tee "$EV/SO-00-motor.json"

echo
echo "== Preparando venv Python isolado (dados/.venv, não versionado) =="
if [ ! -d "$DADOS/.venv" ]; then
  PYBIN=$(command -v python3.12 || command -v python3.11 || command -v python3.13 || echo /opt/homebrew/bin/python3.12)
  "$PYBIN" -m venv "$DADOS/.venv"
fi
# shellcheck source=/dev/null
source "$DADOS/.venv/bin/activate"
pip install -q --upgrade pip >/dev/null
pip install -q "system-one-adapter[openai]" >/dev/null
echo "system-one-adapter=$(python -c 'import system_one_adapter; print(system_one_adapter.__version__)') typesafe-sdk=$(python -c 'import typesafe_sdk; print(typesafe_sdk.__version__)')"

echo
echo "== Chave virtual do cenário (alias cenario-08, budget baixo) =="
CHAVE_CENARIO=$(curl -s "$GATEWAY/key/generate" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d '{"models":["local-hermes","local-qwen"],"key_alias":"cenario-08","max_budget":2.0,"duration":"6h"}' | jq -r '.key')
echo "chave_cenario=$CHAVE_CENARIO"

export GATEWAY API_KEY="$CHAVE_CENARIO" MODEL PYTHONPATH="$DADOS"

echo
echo "== SO-01 — choice: seleção de instância AWS (demanda em dados/demanda-arquitetura.md) =="
python "$DADOS/so01_choice.py" | tee "$EV/SO-01.json" >/dev/null
jq -c '{decisao, decisao_e_opcao_valida, confidence, soma_probabilities}' "$EV/SO-01.json"

echo
echo "== SO-02 — noul: veracidade de 2 afirmações com gabarito (dados/afirmacoes-noul.md) =="
python "$DADOS/so02_noul.py" | tee "$EV/SO-02.json" >/dev/null
jq -c '{af1: .afirmacao_1.veredito, af2: .afirmacao_2.veredito, acertos, total}' "$EV/SO-02.json"

echo
echo "== SO-03 — score: 4 famílias para workload de banco em memória (dados/workload-banco-memoria.md) =="
python "$DADOS/so03_score.py" | tee "$EV/SO-03.json" >/dev/null
jq -c '{scores, r7g_no_topo, ordenacao_coerente_r7g_acima_c7g_e_m7g}' "$EV/SO-03.json"

echo
echo "== SO-05 — consistência: SO-01 repetido 10x (decisão modal + variância) =="
python "$DADOS/so05_consistencia.py" | tee "$EV/SO-05.json" >/dev/null
jq -c '{decisao_modal, frequencia_decisao_modal, estabilidade_decisao_modal, erros_de_execucao, confidence_media, confidence_desvio_padrao}' "$EV/SO-05.json"
deactivate

echo
echo "== SO-04 — governança: chamadas do motor passando pelo gateway com a chave virtual =="
sleep 2
INFO=$(curl -s "$GATEWAY/key/info?key=$CHAVE_CENARIO" -H "Authorization: Bearer $KEY")
LOGS=$(curl -s "$GATEWAY/spend/logs?api_key=$CHAVE_CENARIO&limit=50" -H "Authorization: Bearer $KEY")
N_LOGS=$(echo "$LOGS" | jq 'length')
MODELOS_USADOS=$(echo "$LOGS" | jq -c '[.[].model] | unique')
SPEND_TOTAL=$(echo "$INFO" | jq -r '.info.spend')
MAX_BUDGET=$(echo "$INFO" | jq -r '.info.max_budget')
cat <<EOF | tee "$EV/SO-04.json"
{
  "chave": "$CHAVE_CENARIO (alias cenario-08)",
  "n_chamadas_no_log_unificado": $N_LOGS,
  "modelos_usados": $MODELOS_USADOS,
  "spend_acumulado": $SPEND_TOTAL,
  "max_budget": $MAX_BUDGET,
  "nota": "modelos locais (local-hermes/local-qwen) não têm custo por token registrado no config.yaml -> spend=0.0 é esperado; o controle de budget existe e é aplicável (HTTP 429 budget_exceeded se estourasse), mas não há como este teste específico disparar o corte com modelos gratuitos — achado registrado no README SS8, não um gap deste cenário."
}
EOF

echo
echo "== Limpeza: apagando a chave virtual do cenário =="
curl -s "$GATEWAY/key/delete" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" \
  -d "{\"keys\":[\"$CHAVE_CENARIO\"]}" | jq -c '{deleted: .deleted_keys}'
echo "-- confirmando que a chave não responde mais --"
curl -s -w '\n{"http_status":%{http_code}}\n' "$GATEWAY/key/info?key=$CHAVE_CENARIO" -H "Authorization: Bearer $KEY" | tail -1

echo
echo "== Saúde final do gateway =="
curl -sf "$GATEWAY/health/readiness" && echo " -- gateway saudável"

echo
echo "== fim =="
