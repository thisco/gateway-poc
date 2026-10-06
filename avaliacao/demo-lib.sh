#!/usr/bin/env bash
# Biblioteca compartilhada dos demo.sh de cada cenário — NÃO é testes.sh
# (reprodução/evidência): isto é só o ritmo de apresentação (banners,
# pausa por ENTER, cores) reaproveitado pelos 6 demo.sh.
#
# Uso: source "$(dirname "$0")/../../demo-lib.sh" a partir de
# avaliacao/cenarios/NN-nome/demo.sh.
#
# Variável DEMO_AUTO=1 pula todos os `read -p` (usada na validação
# automatizada via demo-completa.sh e em ensaio sem plateia).

# --- Cores sóbrias (verde/vermelho/negrito/dim), com fallback --------------
# Desativadas se NO_COLOR estiver definida (https://no-color.org) ou se a
# saída não for um terminal (ex.: pipe para arquivo/CI).
if [ -z "${NO_COLOR:-}" ] && [ -t 1 ]; then
  C_BOLD=$'\033[1m'
  C_GREEN=$'\033[32m'
  C_RED=$'\033[31m'
  C_DIM=$'\033[2m'
  C_RESET=$'\033[0m'
else
  C_BOLD=""; C_GREEN=""; C_RED=""; C_DIM=""; C_RESET=""
fi

DEMO_AUTO=${DEMO_AUTO:-0}

titulo_cenario() { # $1 = título do cenário
  echo
  echo "${C_BOLD}══════════════════════════════════════════════════════${C_RESET}"
  echo "${C_BOLD}  $1${C_RESET}"
  echo "${C_BOLD}══════════════════════════════════════════════════════${C_RESET}"
}

banner() { # $1 = o que vamos provar (1 frase, liga ao pilar)   $2 = pilar/princípio
  echo
  echo "${C_BOLD}▶ $1${C_RESET}"
  [ -n "${2:-}" ] && echo "${C_DIM}  $2${C_RESET}"
}

mostrar_comando() { # $1 = comando (texto exibido, pode ser simplificado)
  echo "${C_DIM}  \$ $1${C_RESET}"
}

esperar_enter() {
  if [ "$DEMO_AUTO" != "1" ]; then
    read -r -p "  ENTER para executar... " _
  fi
}

concluir() { # $1 = frase de conclusão (sucesso)
  echo "  ${C_GREEN}↳ $1${C_RESET}"
}

falha() { # $1 = frase (achado/resultado inesperado — não interrompe a demo)
  echo "  ${C_RED}↳ $1${C_RESET}"
}

apontar_ui() { # $1 = onde olhar na UI/browser depois deste passo
  echo
  echo "  ${C_BOLD}Tela:${C_RESET} $1"
}

apontar_slide() { # $1 = referência do slide (Task 9 preenche)
  echo "  ${C_BOLD}Slide:${C_RESET} $1"
}

# --- Pré-checagens reutilizáveis --------------------------------------------

check_gateway() { # $1 = GATEWAY
  local gw="$1"
  if ! curl -sf "$gw/health/liveliness" >/dev/null 2>&1; then
    echo "${C_RED}ERRO: gateway não respondeu em $gw/health/liveliness.${C_RESET}" >&2
    echo "  Rode: cd poc && docker compose up -d" >&2
    exit 1
  fi
}

check_key() { # não recebe args — valida $LITELLM_MASTER_KEY do ambiente
  if [ -z "${LITELLM_MASTER_KEY:-}" ]; then
    echo "${C_RED}ERRO: LITELLM_MASTER_KEY não está exportada.${C_RESET}" >&2
    echo "  Rode: set -a; source poc/.env; set +a" >&2
    exit 1
  fi
}

check_container() { # $1 = nome do container   $2 = comando de correção
  local nome="$1" dica="$2" estado
  estado=$(docker inspect -f '{{.State.Running}}' "$nome" 2>/dev/null || echo "false")
  if [ "$estado" != "true" ]; then
    echo "${C_RED}ERRO: container '$nome' não está no ar.${C_RESET}" >&2
    echo "  Rode: $dica" >&2
    exit 1
  fi
}

check_file() { # $1 = caminho   $2 = comando de correção
  local caminho="$1" dica="$2"
  if [ ! -f "$caminho" ]; then
    echo "${C_RED}ERRO: $caminho não existe.${C_RESET}" >&2
    echo "  Rode: $dica" >&2
    exit 1
  fi
}

pre_checagens_ok() {
  echo "${C_GREEN}OK — pré-checagens passaram.${C_RESET}"
}
