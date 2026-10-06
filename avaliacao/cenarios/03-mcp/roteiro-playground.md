# Roteiro de playground (browser) — Cenário 03: MCP Gateway

**Achado de execução deste roteiro (2026-09-10, validado via Playwright):**
o Playground do Chat *tem* um seletor "MCP Servers" — mas ele serve para
anexar um servidor MCP como ferramenta disponível ao modelo dentro de uma
conversa, não para chamar `/mcp-rest/tools/call` diretamente como o
`testes.sh` faz. E o Swagger interativo em `http://localhost:4000/docs`
citado no brief original **não existe nesta build — retorna HTTP 404**
(`{"detail":"Not Found"}`; confirmado ao vivo). Por isso este roteiro usa
o que realmente existe no navegador: a tela **MCP Servers** da UI (para
ver o servidor catalogado), o **ReDoc** em `/redoc` (referência somente
leitura do contrato da API, sem "Try it out") para ler o formato exato do
endpoint, e o terminal para executar a chamada — fechando com a tela de
**Logs** para comprovar o resultado. É o roteiro fiel ao que a build
expõe, não uma adaptação do brief original.

**Pré-requisito:** logar em `http://localhost:4000/ui`. Nenhum profile
extra — MCP é recurso puro do gateway.

## Passo a passo

1. Abra `http://localhost:4000/ui/mcp-servers`.
   ✔ **Deve aparecer**: um card `deepwiki`, badge de status `Healthy`,
   `HTTP`, `Public`, URL `https://mcp.deepwiki.com/mcp` — o servidor MCP
   registrado no `config.yaml` (versionado no git), catalogado
   centralmente pelo gateway (evidência de P1/P3).
2. Abra uma segunda aba em `http://localhost:4000/redoc` e use a caixa de
   busca no topo para procurar `mcp-rest/tools/call`. Abra o endpoint
   `POST /mcp-rest/tools/call` e leia o corpo esperado — é aqui que se
   confirma, direto na documentação real servida pelo próprio gateway
   (não uma doc externa), que o campo obrigatório é `server_id` (um hash
   opaco gerado no registro do servidor), não o nome `deepwiki`.
3. No terminal (ainda parte do "playground": é a única forma de executar
   uma chamada nesta build, já que não há Swagger interativo), rode:

   ```bash
   set -a; source poc/.env; set +a
   SERVER_ID=$(curl -s http://localhost:4000/v1/mcp/server -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     | jq -r '.[] | select(.server_name=="deepwiki") | .server_id')
   curl -s http://localhost:4000/mcp-rest/tools/call \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
     -d "{\"name\":\"read_wiki_structure\",\"server_id\":\"$SERVER_ID\",\"arguments\":{\"repoName\":\"BerriAI/litellm\"}}" | jq .
   ```

   ✔ **Deve aparecer**: `"isError": false` e um `content` com o resumo da
   wiki do repositório `BerriAI/litellm` — a tool respondeu de verdade,
   através do gateway.
4. Volte ao navegador em `http://localhost:4000/ui/logs`.
   ✔ **Deve aparecer**: a linha mais recente com `Call Type: call_mcp_tool`
   e `Model: MCP: read_wiki_structure` — na **mesma tabela** das chamadas
   de chat, não um log MCP separado. Clique nela para ver `api_key` e os
   timestamps (`startTime`/`endTime`) — a trilha de P4.
5. Agora o segundo caso, deny-by-default, ao vivo no terminal:

   ```bash
   CHAVE=$(curl -s http://localhost:4000/key/generate -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
   curl -s http://localhost:4000/mcp-rest/tools/list -H "Authorization: Bearer $CHAVE" | jq .
   ```

   ✔ **Deve aparecer**: `{"error": "access_denied", "message": "The key is not allowed to access any MCP servers."}`
   e `tools: []` — uma chave nova, sem nenhuma permissão configurada, é
   **bloqueada por padrão**.
6. (Opcional) Volte para `http://localhost:4000/ui/api-keys` e observe
   que a chave recém-criada aparece na lista — ela existe e é válida para
   o modelo `simulado`, só não tem acesso a nenhum servidor MCP.

## Conclusão de governança

A mesma do `demo.sh` deste cenário: o MCP Gateway do LiteLLM é o único,
entre os quatro recursos "além de chat" avaliados nesta suíte (MCP,
vector stores, skills, agentes A2A), que **nasce fechado por padrão**
(deny-by-default) — nenhuma chave nova acessa nenhum servidor MCP sem
`object_permission.mcp_servers` explícito, e cada chamada de tool fica
registrada no mesmo log unificado das chamadas de chat. Pilares
evidenciados: **P1** (identidade do chamador), **P4** (trilha de
auditoria) e **P5** (allowlist por chave) — ver a comparação completa dos
quatro modelos de permissão em [`README.md`](README.md) §8 e no achado 1
do [cenário 06](../06-agentes-tools/README.md).

Tela que comprova (prints já existentes): `evidencias/MC-ui-servers.png`
(servidor catalogado) e `evidencias/MC-02-ui-log.png` (chamada MCP no log
unificado).
