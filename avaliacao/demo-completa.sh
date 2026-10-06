#!/usr/bin/env bash
# Menu de live demo — encadeia os 8 demo.sh individuais por cenário.
#
# Uso:
#   bash avaliacao/demo-completa.sh            # menu interativo
#   DEMO_AUTO=1 bash avaliacao/demo-completa.sh # pula os ENTER de cada
#                                               # demo.sh individual (ex.:
#                                               # validação, ensaio)
#
# Opções do menu: 1-8 (um cenário), "t" (todos, em sequência), "q" (sair).
# DEMO_AUTO é propagada (variável de ambiente) para cada demo.sh chamado.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=demo-lib.sh
source "$SCRIPT_DIR/demo-lib.sh"

declare -a CENARIOS=(
  "01-guardrails:Guardrails (Presidio auto-hospedado)"
  "02-policies:Guardrail Policies"
  "03-mcp:MCP Gateway"
  "04-vector-stores:Vector Stores (pgvector soberano)"
  "05-skills:Skills (Anthropic Skills API)"
  "06-agentes-tools:Agentes (A2A) e Tool Calling"
  "07-tooling:Visão de Tooling (Inventário, Tool Calling, Dev Tooling)"
  "08-decisao-tipada:Decisão tipada local (System One)"
)

rodar() { # $1 = índice 0-based em CENARIOS
  local entrada="${CENARIOS[$1]}"
  local dir="${entrada%%:*}"
  bash "$SCRIPT_DIR/cenarios/$dir/demo.sh"
}

mostrar_menu() {
  echo
  echo "${C_BOLD}Live demo — Avaliação LiteLLM × Framework de Governança${C_RESET}"
  local i=1
  for entrada in "${CENARIOS[@]}"; do
    local dir="${entrada%%:*}" nome="${entrada#*:}"
    echo "  $i) $nome  (${dir}/demo.sh)"
    i=$((i + 1))
  done
  echo "  t) Rodar todos os 8, em sequência"
  echo "  q) Sair"
  [ "$DEMO_AUTO" = "1" ] && echo "${C_DIM}  (DEMO_AUTO=1 — sem pausas por ENTER dentro de cada demo)${C_RESET}"
}

rodar_todos() {
  local i
  for i in "${!CENARIOS[@]}"; do
    rodar "$i"
  done
  echo
  echo "${C_GREEN}${C_BOLD}Todos os 8 cenários rodados.${C_RESET}"
}

# Modo não interativo: se stdin não for um terminal e DEMO_AUTO=1, roda
# "todos" direto (usado por CI/validação, ex.: `DEMO_AUTO=1 bash
# demo-completa.sh <<< t`, ou sem entrada nenhuma).
if [ ! -t 0 ] && [ "$DEMO_AUTO" = "1" ]; then
  opcao="$(cat)"
  opcao="${opcao:-t}"
else
  mostrar_menu
  read -r -p "Escolha: " opcao
fi

case "$opcao" in
  1|2|3|4|5|6|7|8) rodar $((opcao - 1)) ;;
  t|T) rodar_todos ;;
  q|Q) exit 0 ;;
  *) echo "Opção inválida: $opcao" >&2; exit 1 ;;
esac
