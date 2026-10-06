# Roteiro de playground (browser) — Cenário 07: Visão de Tooling

**Achado de execução deste roteiro (2026-09-11, validado via Playwright):**
como nos cenários 03/05, o Swagger interativo (`http://localhost:4000/docs`)
não existe nesta build — HTTP 404 (achado registrado desde o cenário 03,
confirmado de novo aqui). O ReDoc (`http://localhost:4000/redoc`) **existe**
e é usado aqui como referência somente-leitura do contrato de cada
endpoint listado em TI-01. Este cenário não tem um "Playground" único —
ele é sobre cinco telas diferentes da UI (uma por recurso catalogado) mais
o terminal para os casos que a UI não expõe (tool calling avançado, SDKs,
DX de erro). Por isso o roteiro caminha pelas telas na mesma ordem do
`README.md` §5 (TI-01/02/03) e fecha com os casos de terminal (TC/TD) que
mais valem a pena mostrar ao vivo — os mesmos do `demo.sh`.

**Pré-requisito:** logar em `http://localhost:4000/ui`. Nenhum profile
extra além do que os cenários 03–06 já deixaram no ar (MCP `deepwiki`,
agente `eco-governanca`, vector store `base-governanca`, skills na conta
Anthropic).

## Passo a passo

### Parte 1 — as 5 telas de inventário (TI-01/TI-03)

1. Abra `http://localhost:4000/ui/models-and-endpoints`.
   ✔ **Deve aparecer**: a tabela **Model Management**, aba **All Models**,
   com os 25 modelos do `config.yaml` (`fronteira-sonnet`, `fronteira-haiku`,
   `fronteira-gpt-nano`, `local-hermes`, `local-qwen`, `embedding-nomic`,
   14 `sandbox-*` da OpenRouter, `simulado`), cada um com Model ID, provedor
   e custo IN/OUT. Esta é a tela mais completa e correta das cinco — guarde
   como referência do que "bom inventário" parece (`evidencias/TI-03-models.png`).
2. Abra `http://localhost:4000/ui/mcp-servers` (item de primeiro nível no
   menu, **MCP Servers**).
   ✔ **Deve aparecer**: 1 card, `deepwiki`, badges `Checking`/`Healthy`,
   `HTTP`, `none`, `Public` (`evidencias/TI-03-mcp-servers.png`).
3. Abra `http://localhost:4000/ui/agents` (menu **Agentic** → **Agents**).
   ✔ **Deve aparecer**: 1 linha, `eco-governanca`, com o `Agent ID` (hash
   longo) e status `Needs Setup` — catalogado corretamente, mesmo hash
   confirmado por `GET /v1/agents` (`evidencias/TI-03-agents.png`).
4. Abra `http://localhost:4000/ui/vector-stores` (menu **Tools** →
   **Vector Stores** — repare que, diferente de MCP Servers/Skills/Agentic,
   Vector Stores não tem item de primeiro nível: já é um primeiro sinal de
   que este recurso é tratado como secundário na navegação). Clique na aba
   **Manage Vector Stores**.
   ✔ **Deve aparecer** (e este é o achado central do cenário, §8 achado 3):
   "No vector stores — Connect a vector store to enable
   retrieval-augmented generation" — **mesmo com** o store `base-governanca`
   registrado, saudável e aprovado em 4 dos 5 casos do cenário 04
   (`evidencias/TI-03-vector-stores.png`). Compare mentalmente com o passo
   6 abaixo, que mostra o mesmo store aparecendo normalmente por uma rota
   de API diferente.
5. Abra `http://localhost:4000/ui/skills` (item **Skills**).
   ✔ **Deve aparecer**: "No skills found — Add one to get started" —
   **não é um bug deste cenário**, é o mesmo achado já registrado no
   cenário 05 (achado 3): esta tela é o *Claude Code Skill Hub*
   (`/claude-code/marketplace.json`), um recurso diferente da Anthropic
   Skills API (`/v1/skills`) que os cenários 05 e este avaliam
   (`evidencias/TI-03-skills.png`).
6. Abra uma nova aba em `http://localhost:4000/redoc` e use a busca para
   localizar `vector_store/list` e depois `vector_stores` (plural, sem
   underscore). Leia os dois contratos.
   ✔ **Deve aparecer**: dois endpoints com nomes parecidos, descrevendo o
   mesmo tipo de recurso — mas nenhuma nota no próprio ReDoc avisando que
   um está desatualizado em relação ao outro (`evidencias/TI-03-redoc.png`).
7. Volte ao terminal e rode a comparação direta (achado 1 — a mesma que o
   `demo.sh` faz ao vivo):

   ```bash
   set -a; source poc/.env; set +a
   curl -s http://localhost:4000/vector_store/list -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq -c '[.data[].vector_store_name]'
   curl -s http://localhost:4000/v1/vector_stores -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq -c '.data'
   ```

   ✔ **Deve aparecer**: `["base-governanca"]` na primeira chamada, `[]` na
   segunda — a mesma divergência que a tela do passo 4 mostrou visualmente,
   confirmada agora por API, para descartar qualquer suspeita de cache do
   navegador.

### Parte 2 — os casos de terminal (TC/TD, os mesmos do `demo.sh`)

8. Ainda no terminal, rode o caso de tools paralelas (TC-01):

   ```bash
   TOOL='{"name":"consulta_clima","description":"Consulta o clima atual de uma cidade brasileira.","input_schema":{"type":"object","properties":{"cidade":{"type":"string"}},"required":["cidade"]}}'
   curl -s http://localhost:4000/v1/messages -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
     -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":500,\"tools\":[$TOOL],\"messages\":[{\"role\":\"user\",\"content\":\"Preciso saber o clima agora em Brasília e em Recife. Chame a ferramenta consulta_clima duas vezes, uma para cada cidade, no mesmo turno, antes de responder.\"}]}" \
     | jq -c '[.content[] | select(.type=="tool_use") | .input.cidade]'
   ```

   ✔ **Deve aparecer**: `["Brasília","Recife"]` — 2 chamadas de tool reais
   no mesmo turno, uma por cidade.
9. Volte ao navegador em `http://localhost:4000/ui/logs` e procure a
   chamada mais recente com `Model: anthropic/claude-haiku-4-5` e
   `Call Type: anthropic_messages`. Clique nela.
   ✔ **Deve aparecer**: a mesma chamada de tool do passo 8, na mesma
   tabela de Request Logs de qualquer chamada de chat comum — a prova de
   P4 para este bloco.
10. Por fim, o caso de DX de erro (TD-03), a peça central deste cenário
    para P2/P12:

    ```bash
    CHAVE=$(curl -s http://localhost:4000/key/generate -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
      -H "Content-Type: application/json" -d '{"models":["simulado"],"max_budget":0.001,"key_alias":"playground-td03"}' | jq -r '.key')
    curl -s http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
      -d '{"model":"fronteira-haiku","messages":[{"role":"user","content":"oi"}]}' | jq -c '.error.message'
    curl -s http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
      -d '{"model":"simulado","messages":[{"role":"user","content":"oi"}]}' >/dev/null
    curl -s http://localhost:4000/v1/chat/completions -H "Authorization: Bearer $CHAVE" -H "Content-Type: application/json" \
      -d '{"model":"simulado","messages":[{"role":"user","content":"oi de novo"}]}' | jq -c '.error.message'
    curl -s http://localhost:4000/key/delete -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
      -d "{\"keys\":[\"$CHAVE\"]}"
    ```

    ✔ **Deve aparecer**: a mensagem de `key_model_access_denied` citando o
    modelo permitido e o tentado, seguida da mensagem de `budget_exceeded`
    citando custo atual x teto — leia as duas em voz alta e avalie se um
    desenvolvedor de primeira viagem conseguiria se resolver sozinho com
    elas (ver a avaliação completa no `README.md` §8, achado 4). Repare
    que o comando final já apaga a chave criada — não deixe chaves de
    teste órfãs no ambiente.

## Conclusão de governança

A mesma dos outros cenários "além de chat" desta suíte, mas vista de um
ângulo novo: catalogar um recurso (registrar no `config.yaml`, aparecer em
*algum* endpoint) não é o mesmo que ele ser **auditável de forma
confiável** — nem por API (achado 1: duas rotas, dois resultados para o
mesmo vector store) nem pela UI (achado 3: a mesma divergência, visível
para um administrador humano). Nos blocos que funcionam de ponta a ponta —
tool calling avançado (TC) e compatibilidade de SDK oficial (TD) — o
gateway entrega exatamente a promessa de um gateway de IA drop-in: os
SDKs oficiais funcionam sem adaptação, e os dois erros de governança mais
comuns do dia a dia (modelo fora do perfil, orçamento estourado) chegam
claros o bastante para autoatendimento. Ver a análise completa em
[`README.md`](README.md) §8.

Telas que comprovam (prints já existentes): `evidencias/TI-03-models.png`,
`evidencias/TI-03-mcp-servers.png`, `evidencias/TI-03-agents.png`,
`evidencias/TI-03-vector-stores.png` (o achado central), `evidencias/TI-03-skills.png`
e `evidencias/TI-03-redoc.png`.
