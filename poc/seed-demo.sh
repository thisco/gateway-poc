#!/usr/bin/env bash
# Monta o cenário da demo: dois perfis (times) com políticas distintas + chaves virtuais.
# Uso: ./seed-demo.sh   (requer o stack de pé e o .env preenchido)
set -euo pipefail
cd "$(dirname "$0")"
source .env

GW="http://localhost:4000"
AUTH=(-H "Authorization: Bearer ${LITELLM_MASTER_KEY}" -H "Content-Type: application/json")

echo "==> Criando time 'equipe-dev' (todos os modelos, budget USD 50/mês)"
DEV_TEAM=$(curl -sf "$GW/team/new" "${AUTH[@]}" -d '{
  "team_alias": "equipe-dev",
  "models": ["fronteira-sonnet", "fronteira-haiku", "local-qwen", "simulado"],
  "max_budget": 50.0,
  "budget_duration": "30d"
}' | python3 -c "import sys,json; print(json.load(sys.stdin)['team_id'])")

echo "==> Criando time 'perfil-restrito' (só modelo local e simulado, budget USD 1/mês)"
RESTRITO_TEAM=$(curl -sf "$GW/team/new" "${AUTH[@]}" -d '{
  "team_alias": "perfil-restrito",
  "models": ["local-qwen", "simulado"],
  "max_budget": 1.0,
  "budget_duration": "30d"
}' | python3 -c "import sys,json; print(json.load(sys.stdin)['team_id'])")

echo "==> Gerando chave virtual para 'equipe-dev'"
DEV_KEY=$(curl -sf "$GW/key/generate" "${AUTH[@]}" -d "{
  \"team_id\": \"$DEV_TEAM\",
  \"key_alias\": \"chave-equipe-dev\"
}" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

echo "==> Gerando chave virtual para 'perfil-restrito'"
RESTRITO_KEY=$(curl -sf "$GW/key/generate" "${AUTH[@]}" -d "{
  \"team_id\": \"$RESTRITO_TEAM\",
  \"key_alias\": \"chave-perfil-restrito\"
}" | python3 -c "import sys,json; print(json.load(sys.stdin)['key'])")

cat > .demo-keys <<EOF
# Gerado por seed-demo.sh — chaves virtuais da demo (não versionar)
DEV_KEY=$DEV_KEY
RESTRITO_KEY=$RESTRITO_KEY
EOF

echo
echo "Cenário pronto. Chaves salvas em poc/.demo-keys"
echo
echo "Demo 2 — bloqueio de modelo fora do perfil (deve FALHAR):"
echo "  curl -s $GW/v1/chat/completions -H \"Authorization: Bearer \$RESTRITO_KEY\" -H 'Content-Type: application/json' -d '{\"model\":\"fronteira-sonnet\",\"messages\":[{\"role\":\"user\",\"content\":\"oi\"}]}'"
echo
echo "Demo OK — chamada dentro do perfil (deve FUNCIONAR):"
echo "  curl -s $GW/v1/chat/completions -H \"Authorization: Bearer \$RESTRITO_KEY\" -H 'Content-Type: application/json' -d '{\"model\":\"simulado\",\"messages\":[{\"role\":\"user\",\"content\":\"oi\"}]}'"
