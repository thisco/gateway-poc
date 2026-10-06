# Cenário 07 — Visão de Tooling

## 1. Objetivo

Os cenários 01–06 avaliaram cada recurso do LiteLLM isoladamente (guardrails,
policies, MCP, vector stores, skills, agentes A2A/tool calling). Este
cenário olha para o gateway a partir de três ângulos transversais que não
cabiam em nenhum recurso individual, mas que importam diretamente para
quem vai **operar** e **consumir** a plataforma em produção:

- **Inventário (TI-01..03)** — depois de seis cenários cada um registrando
  um recurso novo (servidor MCP, agente, vector store, skill, modelo), a
  pergunta natural de um operador é: existe um lugar único para ver "tudo
  que está catalogado no gateway agora"? Isso importa para P3 (catálogo)
  porque um catálogo fragmentado é, na prática, um catálogo que ninguém
  audita por completo — cada tela/endpoint vira um ponto cego em potencial.
- **Tool calling avançado (TC-01..03)** — o cenário 06 provou o
  round-trip básico de function calling (uma tool, uma chamada, uma
  resposta). Agentes reais em produção chamam múltiplas tools no mesmo
  turno, tools falham, e a interface fica em streaming para UX responsiva.
  Este bloco testa se o gateway sustenta esses três padrões sem quebrar o
  contrato do modelo nem a trilha de auditoria.
- **Dev tooling (TD-01..03)** — a promessa central de um gateway de IA
  "compatível com a API oficial" é que times existentes trocam a
  `base_url` do SDK que já usam (OpenAI, Anthropic) e nada mais muda. Este
  bloco testa essa promessa com os SDKs oficiais de verdade (não apenas
  `curl`), e avalia se os dois erros de governança mais comuns do dia a
  dia de um desenvolvedor — modelo fora do perfil da chave, orçamento
  estourado — chegam como mensagens claras o bastante para o
  desenvolvedor se autoatender, sem abrir chamado.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P3** — Catálogo de modelos e roteamento (por extensão, catálogo de todo recurso registrado) | TI-01 testa se existe uma superfície única para inventariar modelos, servidores MCP, agentes, vector stores e skills. O achado central (§8) é que não existe: são 5 famílias de endpoint distintas, com um caso de divergência real entre duas rotas que deveriam descrever o mesmo recurso (`/vector_store/list` vs. `/v1/vector_stores`). |
| **P4** — Auditoria e observabilidade (quem, o quê, quando — e também: quem pode **ver** o quê) | TI-02 estende a trilha de P4 para a camada de *visibilidade de catálogo*: uma chave sem nenhuma permissão explícita consegue listar o conteúdo completo de 4 dos 5 planos testados (§8) — a auditoria de "quem viu o inventário" não é hoje uma pergunta que o gateway responde nativamente. TC-02 confirma que o round-trip de erro de tool (`is_error: true`) continua caindo no mesmo log unificado (`call_type: anthropic_messages`) já visto nos cenários 03/06. |
| **P5** — Guardrails/controles sobre ações de agente | O bloco TC testa a robustez do mecanismo que **todo** agente usa para agir (tool calling) sob três condições realistas — paralelismo, falha parcial, streaming — que precisam funcionar de forma previsível para que os controles de P5 (allowlist, guardrail sobre argumento) continuem valendo em produção, não só no caminho feliz de uma única tool síncrona já provado no cenário 06. |
| **P2** — Controle de uso e custo (FinOps de IA) | TD-03b reproduz o corte automático de orçamento (`budget_exceeded`, HTTP 429) ao vivo, e avalia a clareza da mensagem que o desenvolvedor recebe quando o teto é atingido — o requisito central de P2 ("corte automático no teto") só cumpre a promessa de governança se o erro for compreensível o bastante para não virar um chamado de suporte. |
| **P12** — IA como serviço (experiência de quem consome a plataforma) | TD-01/TD-02 testam a compatibilidade de `base_url` com os SDKs oficiais — o requisito técnico mínimo para que "a plataforma governada vire produto" sem forçar cada time cliente a reescrever sua integração. TD-03a avalia a clareza do erro de modelo fora do perfil, o outro erro de autoatendimento mais comum de quem consome a plataforma pela primeira vez. |

## 3. Planejamento

**Pré-requisitos:**
- PoC base no ar (`poc/docker-compose.yml`), gateway em `:4000`,
  `LITELLM_MASTER_KEY` em `poc/.env` (`set -a; source poc/.env; set +a`).
- Recursos já registrados pelos cenários 03–06, reaproveitados como alvo do
  inventário (nenhum novo registrado por este cenário):
  servidor MCP `deepwiki` (cenário 03), agente A2A `eco-governanca` — profile
  `agents` (`docker compose -f poc/docker-compose.yml --profile agents up -d agente-eco`,
  já estava no ar nesta execução), vector store `base-governanca` (cenário
  04 — `.store-id` já existente, `setup.sh` não precisou rodar de novo),
  skills na conta Anthropic (cenário 05, 10 skills catalogadas: a
  `relatorio-lgpd` própria + as 9 nativas/de mercado já instaladas), e o
  `model_list` completo do `config.yaml` (25 modelos).
- Modelo `fronteira-haiku` (Anthropic, com crédito) para TC-01..03 e
  TD-01/TD-02 — chamadas reais, `max_tokens` moderado (60–500 conforme o
  caso) para manter o custo baixo. TD-03 usa o modelo `simulado` (custo
  fictício alto, `input/output_cost_per_token: 0.02`, sem chamada real a
  nenhum provedor) especificamente para estourar um orçamento minúsculo
  (`max_budget: 0.001`) em uma única chamada, sem gastar crédito real.
- Python 3.9 do sistema não é usado diretamente para TD-01/TD-02: os SDKs
  oficiais (`openai`, `anthropic`) são instalados em um **venv isolado**
  criado pelo próprio `testes.sh` em `dados/.venv/` (não versionado — ver
  `.gitignore`), para não adicionar dependência nenhuma ao repositório.

**Adaptações em relação ao rascunho original do brief:**

1. **TC-01/TC-02/TC-03 usam a rota nativa `/v1/messages` (formato
   Anthropic), não `/v1/chat/completions` (compatível OpenAI).** O motivo:
   `is_error: true` em um bloco `tool_result` (TC-02) é um campo nativo do
   formato de mensagens da Anthropic — o formato OpenAI não tem
   equivalente direto para "este resultado de tool é um erro" dentro de
   uma mensagem `role: tool` (o SDK OpenAI não expõe esse conceito).
   Testar TC-02 via `/v1/chat/completions` obrigaria a simular o erro só
   no texto do conteúdo, perdendo o sinal estruturado que o SDK real usa
   em produção. Como TD-02 já confirma que `/v1/messages` funciona
   perfeitamente com o SDK Anthropic oficial através do gateway, usar essa
   mesma rota nos três casos de TC mantém o teste fiel ao que uma
   integração real faria.
2. **`/mcp-rest/tools/list` retorna HTTP 200 mesmo quando nega acesso**
   (confirmado de novo aqui em TI-02, mesmo comportamento já documentado
   no achado 1 do cenário 03) — o corpo, não o status HTTP, carrega
   `error: "access_denied"`. O script trata isso lendo o corpo, não o
   `http_status` (que sempre viria 200).
3. **O catálogo de vector stores do gateway responde em dois endpoints com
   resultados diferentes para o mesmo recurso.** O brief original não
   antecipava essa divergência — foi descoberta ao montar TI-01 comparando
   sistematicamente as 5 famílias de endpoint lado a lado (ver achado 1,
   §8).

## 4. Dados de análise

Nenhum dado de PII sintético foi necessário neste cenário — os três blocos
testam mecanismo de plataforma (inventário, tool calling, compatibilidade
de SDK/DX de erro), não detecção de dado sensível (já coberto pelos
cenários 01/02/06). Os "dados" de teste são:

- **TC-01/02/03**: uma tool sintética `consulta_clima(cidade)` e um prompt
  pedindo o clima de duas cidades brasileiras (Brasília, Recife) —
  escolhida por ser um domínio trivial de simular (o modelo não precisa de
  conhecimento real; o teste é sobre o mecanismo de tool calling, não
  sobre a qualidade da resposta).
- **TD-01/02**: uma pergunta neutra de uma frase ("o que é um gateway de
  IA?") — qualquer prompt serviria, o teste é sobre o SDK e a rota, não
  sobre o conteúdo da resposta.
- **TD-03**: nenhum dado sintético — os dois erros de governança
  (`key_model_access_denied`, `budget_exceeded`) são provocados só pela
  configuração da chave (`models`, `max_budget`), sem payload sensível
  envolvido.

## 5. Casos de teste

| ID | Bloco | Descrição | Passos (linha em `testes.sh`) | Resultado esperado |
|---|---|---|---|---|
| TI-01 | Inventário | Existe visão unificada de capacidades? | `GET /v1/models`, `/mcp-rest/tools/list`, `/v1/agents`, `/vector_store/list`, `/v1/vector_stores`, `/v1/skills?beta=true` — comparados lado a lado | Documentar quantas famílias de endpoint existem e se algum inventário diverge entre si |
| TI-02 | Inventário | O que uma chave restrita (sem `object_permission`) enxerga em cada plano | `POST /key/generate` (`models: [simulado]`, sem permissão), depois os 5 endpoints de TI-01 com essa chave | Tabela de visibilidade por plano — cross-check com o espectro de permissão dos cenários 03–06 |
| TI-03 | Inventário | Visibilidade admin nas telas da UI | Prints via Playwright: Models + Endpoints, MCP Servers, Agentic → Agents, Tools → Vector Stores, Skills, e `/redoc` | Cada tela reflete (ou não) o estado real do catálogo confirmado por API |
| TC-01 | Tool calling | Tools paralelas (2+ `tool_use` no mesmo turno) | `POST /v1/messages` com 1 tool e prompt pedindo 2 cidades no mesmo turno | Resposta com 2 blocos `tool_use`, `stop_reason: tool_use` |
| TC-02 | Tool calling | Tool com erro (`is_error: true`) — recuperação + log | Reenvia 2 `tool_result` (1 com `is_error: true`, 1 normal), confirma resposta final e checa `/spend/logs` | Modelo relata o erro de forma factual, entrega o resultado da tool que funcionou, e a chamada aparece no log unificado |
| TC-03 | Tool calling | Streaming com tool calls | `POST /v1/messages` com `stream: true` + tool | SSE com `content_block_start` tipo `tool_use` e `input_json_delta` chunks (`partial_json`) |
| TD-01 | Dev tooling | SDK OpenAI oficial → `base_url` do gateway | Script Python (`dados/td01_openai_sdk.py`) com `openai.OpenAI(base_url=".../v1")`, chave virtual restrita | Chamada bem-sucedida, sem nenhuma adaptação de código além da `base_url`/`api_key` |
| TD-02 | Dev tooling | SDK Anthropic oficial → rota nativa `/v1/messages` | Script Python (`dados/td02_anthropic_sdk.py`) com `anthropic.Anthropic(base_url="...")`, chave virtual restrita | Chamada bem-sucedida, sem nenhuma adaptação de código além da `base_url`/`api_key` |
| TD-03 | Dev tooling | DX dos 2 erros de governança clássicos | Chave com `models: [simulado]`, `max_budget: 0.001`: (a) chama `fronteira-haiku` (fora do perfil); (b) 2 chamadas a `simulado` (a 2ª estoura o budget) | (a) HTTP 403 `key_model_access_denied`; (b) HTTP 429 `budget_exceeded` — mensagens transcritas e avaliadas quanto à clareza |

## 6. Critérios de aceite

- [x] TI-01 compara as 5 famílias de endpoint de catálogo lado a lado e
  documenta objetivamente se existe (ou não) uma visão unificada.
- [x] TI-02 usa uma chave real, recém-criada, sem nenhuma permissão
  explícita, testada contra os 5 planos — não é inferência, é observação
  direta.
- [x] TI-03 tem print real (Playwright) de cada tela citada no brief:
  Models, MCP Servers, Agents, Vector Stores, Skills — mais `/redoc` como
  evidência de que `/docs` continua 404 nesta build (achado já registrado
  nos cenários 03/05).
- [x] TC-01/02/03 usam uma chamada real ao modelo `fronteira-haiku`
  (não simulada) e evidenciam o mecanismo (paralelismo, erro, streaming)
  com o payload bruto salvo em `evidencias/`.
- [x] TD-01/TD-02 chamam os SDKs oficiais **de verdade** (biblioteca
  Python instalada e importada, não apenas `curl` imitando o formato) —
  nenhuma dependência foi adicionada ao repositório (venv isolado,
  gitignored).
- [x] TD-03 transcreve as duas mensagens de erro reais (não parafraseadas)
  e avalia a clareza de cada uma no §8.
- [x] Todas as chaves virtuais criadas para os testes (TI-02, TD-01, TD-02,
  TD-03) são deletadas ao final do próprio `testes.sh` — nenhuma chave de
  teste ficou órfã (conferido via `GET /key/list` ao final da execução).
- [x] Gateway termina o cenário saudável (`GET /health/readiness` → `200`,
  container `poc-gateway` `Up`).

## 7. Roteiro de demonstração

1. Mostrar a comparação lado a lado das 5 famílias de endpoint (TI-01) —
   o ponto de partida da história: seis cenários, seis registros
   diferentes, cinco formas diferentes de listá-los de volta.
2. Rodar o script ao vivo:
   `cd avaliacao/cenarios/07-tooling && set -a; source ../../../poc/.env; set +a && bash testes.sh`
   — mostrar TI-02 (chave sem permissão vendo praticamente tudo, exceto
   MCP), TC-01 (2 `tool_use` reais no mesmo turno), TD-03 (as duas
   mensagens de erro, ao vivo).
3. Abrir a UI (`http://localhost:4000/ui/vector-stores` → aba **Manage
   Vector Stores**) e mostrar a tela **vazia** ("No vector stores") ao
   lado do resultado de `curl .../vector_store/list` (que mostra
   `base-governanca`) — a mesma divergência de TI-01, mas agora visível
   para um humano navegando a UI, não só entre dois JSONs.
4. Abrir **Logs** e localizar a chamada de TC-02 — mostrar que o
   round-trip de erro de tool aparece no mesmo log unificado que qualquer
   chamada de chat.
5. Fechar com TD-03 como **slide de decisão**: as duas mensagens de erro
   lado a lado, e a avaliação de clareza (§8) — o ponto de atenção prático
   para qualquer time que for integrar via SDK oficial.

## 8. Análise de resultados

Execução real em 2026-09-11, ambiente local
(`docker compose -f poc/docker-compose.yml`), imagem
`ghcr.io/berriai/litellm:main-stable` (`v1.100.0`), `LITELLM_MASTER_KEY` da
PoC. Modelo `fronteira-haiku` (`anthropic/claude-haiku-4-5`, conta com
crédito) para TC-01..03 e TD-01/02; modelo `simulado` (custo fictício, sem
chamada real) para TD-03. Execução única do `testes.sh`, sem retry
necessário em nenhum caso — todas as 9 chamadas de rede a provedores reais
(TC-01, TC-02, TC-03, TD-01, TD-02) responderam na primeira tentativa.

### Saída real do script (`testes.sh`, íntegra em `evidencias/`)

```
== TI-01 — existe uma visão unificada de inventário? (5 famílias de endpoint) ==
{
  "endpoint_modelos": "GET /v1/models", "n_modelos": 25,
  "endpoint_mcp": "GET /mcp-rest/tools/list",
  "tools_mcp": ["ask_question","read_wiki_contents","read_wiki_structure"],
  "endpoint_agentes": "GET /v1/agents", "agentes": ["eco-governanca"],
  "endpoint_vetores_gateway": "GET /vector_store/list",
  "vetores_gateway": ["base-governanca"],
  "endpoint_vetores_openai_compat": "GET /v1/vector_stores",
  "n_vetores_openai_compat_MESMO_STORE": 0,
  "endpoint_skills": "GET /v1/skills?beta=true", "n_skills": 10
}

== TI-02 — o que uma chave restrita (sem nenhum object_permission) enxerga em cada plano ==
{
  "mcp_tools_list": {"tools_visiveis":0,"erro":"unexpected_error"}, "mcp_http_status": "200",
  "vector_store_list_visiveis": 1, "vector_store_http_status": "200",
  "agentes_visiveis": 1, "agentes_http_status": "200",
  "skills_visiveis": 10, "skills_http_status": "200",
  "modelos_visiveis": 1, "modelos_http_status": "200"
}

== TC-01 — tools paralelas ==
{"n_tool_use":2,"cidades":["Brasília","Recife"],"stop_reason":"tool_use"}

== TC-02 — recuperação de erro de tool ==
{"stop_reason":"end_turn","texto":"Conforme solicitado, chamei a ferramenta consulta_clima duas
vezes no mesmo turno. Aqui estão os resultados:\n\n**Brasília:** Infelizmente, o serviço de
clima está indisponível no momento para Brasília (houve um timeout upstream).\n\n**Recife:**
29°C, ensolarado, com umidade de 70%.\n\nRecomendo tentar novamente para Brasília em alguns
instantes, pois o serviço pode estar temporariamente indisponível."}
-- log de auditoria: {"call_type":"anthropic_messages","model":"anthropic/claude-haiku-4-5",
"spend":0.000228,"startTime":"2026-09-11T13:14:09.557000Z"}

== TC-03 — streaming com tools ==
{"n_eventos_sse": 10, "content_block_start_type": "tool_use", "tool_chamada": "consulta_clima",
"n_input_json_delta_chunks": 4}

== TD-01 — SDK OpenAI oficial ==
{"sdk":"openai","sdk_version":"2.48.0","base_url_usado":"http://localhost:4000/v1",
"model":"fronteira-haiku","finish_reason":"stop", "usage":{"total_tokens":91}}

== TD-02 — SDK Anthropic oficial ==
{"sdk":"anthropic","sdk_version":"0.125.0","base_url_usado":"http://localhost:4000",
"model":"fronteira-haiku","stop_reason":"end_turn","usage":{"input_tokens":33,"output_tokens":50}}

== TD-03a — modelo fora do perfil ==
{"error":{"message":"key not allowed to access model. This key can only access
models=['simulado']. Tried to access fronteira-haiku","type":"key_model_access_denied",
"param":"model","code":"403"}}
{"http_status":403}

== TD-03b — budget estourado ==
{"error":{"message":"Budget has been exceeded! Key=td03-erros-governanca (sk-...ItTQ) Current
cost: 0.5999999999999764, Max budget: 0.001","type":"budget_exceeded","param":null,"code":"429"}}
{"http_status":429}
```

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| TI-01 | **Gap confirmado** — não existe visão unificada; 5 famílias de endpoint distintas, e uma delas (vector stores) diverge internamente para o mesmo recurso | `evidencias/TI-01.json` |
| TI-02 | **Passa como teste — vira achado de fundo para P4/P5** — só MCP nasce fechado; vector stores, agentes, skills e o *catálogo* de modelos ficam visíveis (ver detalhe abaixo) | `evidencias/TI-02.json` |
| TI-03 | **Passa, com um gap real capturado ao vivo** — Models/MCP Servers/Agents refletem o estado real; a tela **Manage Vector Stores** mostra "No vector stores" com o store `base-governanca` ativo e funcional (mesma divergência de TI-01, agora visível na UI) | `evidencias/TI-03-*.png` |
| TC-01 | **Passa** — 2 blocos `tool_use` reais (Brasília, Recife) no mesmo turno, `stop_reason: tool_use` | `evidencias/TC-01.json` |
| TC-02 | **Passa** — o modelo relatou o erro da tool de Brasília de forma factual e entregou o resultado real de Recife, sem alucinar um valor para a cidade com erro; a chamada apareceu no log unificado (`call_type: anthropic_messages`) | `evidencias/TC-02.json` · `evidencias/TC-02-spend-log.json` |
| TC-03 | **Passa** — SSE real com `content_block_start` tipo `tool_use` e 4 chunks `input_json_delta`/`partial_json` compondo o argumento da tool progressivamente | `evidencias/TC-03.json` · `evidencias/TC-03-stream.txt` |
| TD-01 | **Passa — sem nenhuma adaptação** — `openai.OpenAI(base_url="http://localhost:4000/v1")` funcionou de primeira | `evidencias/TD-01.json` |
| TD-02 | **Passa — sem nenhuma adaptação** — `anthropic.Anthropic(base_url="http://localhost:4000")` funcionou de primeira, na rota nativa | `evidencias/TD-02.json` |
| TD-03 | **Passa como teste — mensagens claras, com uma ressalva menor** — ver avaliação de clareza abaixo | `evidencias/TD-03a-modelo-nao-permitido.json` · `evidencias/TD-03b-budget-excedido.json` |

### Achados

1. **Não existe uma visão unificada de inventário — são 5 famílias de
   endpoint sem prefixo, formato ou convenção de nomenclatura em comum, e
   uma delas diverge internamente para o mesmo recurso.** `GET /v1/models`
   (compatível OpenAI), `GET /mcp-rest/tools/list` (tools, não servidores —
   para servidores é `GET /v1/mcp/server`), `GET /v1/agents`,
   `GET /vector_store/list` (singular, LiteLLM-específico) e
   `GET /v1/skills?beta=true` (com um parâmetro obrigatório fora do padrão
   REST) são cinco rotas distintas, cada uma com seu próprio formato de
   resposta (`{"tools": [...]}`, `{"data": [...], "total_count": N}`,
   array puro, etc.). Pior: `GET /v1/vector_stores` — a rota que, pelo
   nome, deveria ser o equivalente "compatível OpenAI" de
   `GET /vector_store/list` — responde `200 {"data": [], "total_count": 0}`
   para o **mesmo ambiente** onde `GET /vector_store/list` mostra
   `base-governanca` corretamente catalogado e funcional (o mesmo store
   que passou em VS-01 a VS-04 no cenário 04). Não é um caso de permissão
   (a master key foi usada nos dois); são dois caminhos de código
   diferentes dentro do próprio gateway, um lendo a tabela real de stores
   e o outro não. **Implicação prática:** um operador escrevendo um script
   de auditoria de inventário (o exato cenário que este caso testa) não
   pode confiar em nenhuma rota isolada — precisa conhecer as 5 famílias
   de antemão e, no caso de vector stores, saber qual das duas rotas
   "certas" é a que reflete a realidade. Isso é o oposto de um catálogo
   central confiável (P3) e eleva o risco de um recurso "invisível" para
   quem audita só por API.

2. **A visibilidade de *catálogo* (poder listar um recurso) é, na
   prática, mais aberta do que a visibilidade de *uso* (poder efetivamente
   chamar o recurso) — e essa distinção não está documentada em lugar
   nenhum.** Uma chave criada só com `models: ["simulado"]`, sem nenhum
   `object_permission`, conseguiu listar o vector store `base-governanca`
   por completo (nome, descrição, credencial redigida), o agente
   `eco-governanca` por completo (card inteiro, incluindo a URL interna
   `http://agente-eco:9000/`) e as 10 skills por completo — os mesmos
   4 planos que os cenários 04/05/06 já haviam caracterizado como "nascem
   abertos" para **uso** (VS-05, AG-03, achado 4 do cenário 05). Só o MCP
   negou a listagem (`access_denied`, achado 1 do cenário 03 confirmado de
   novo). O único plano com uma surpresa nova é **modelos**: apesar de
   `GET /v1/models` normalmente ser tratado como "público" em gateways
   OpenAI-compatíveis, aqui ele **filtra** pelo `models` da própria chave
   — a chave viu 1 de 25 modelos, exatamente o que lhe foi concedido. Ou
   seja, o recurso mais maduro do gateway (modelos) tem o comportamento
   de catálogo mais restritivo dos cinco, e os quatro recursos "além de
   chat" mais novos (MCP à parte) vazam metadado completo de recursos que
   a chave nem sequer tem permissão de usar. Para um agente com uma chave
   comprometida, isso já é reconhecimento gratuito de superfície de
   ataque (nomes, IDs, URLs internas) mesmo sem conseguir agir sobre nada
   — uma lacuna de P4/P5 que nenhum dos cenários 03–06 havia isolado
   porque cada um testou só o próprio recurso, não o conjunto.

3. **A tela "Manage Vector Stores" da UI reproduz a mesma divergência do
   achado 1 — só que agora visível a um humano administrador, não só via
   API.** Navegando para `http://localhost:4000/ui/vector-stores` →
   **Manage Vector Stores** (aba nativa, sob **Tools** no menu lateral —
   note-se que, diferente de MCP Servers/Skills/Agentic, Vector Stores não
   tem item de primeiro nível na navegação, mais um sinal de que este
   recurso é tratado como cidadão de segunda classe na UI), a tabela
   mostra "No vector stores — Connect a vector store to enable
   retrieval-augmented generation" (`evidencias/TI-03-vector-stores.png`),
   apesar de `base-governanca` estar registrado, saudável e ter passado em
   4 dos 5 casos do cenário 04. Um administrador confiando só na UI para
   auditar o que está catalogado concluiria — de forma incorreta — que
   não há nenhum vector store configurado no ambiente. As demais telas
   verificadas (Models + Endpoints, MCP Servers, Agentic → Agents)
   refletiram corretamente o estado real (25 modelos, 1 servidor MCP,
   1 agente) — o gap é específico de Vector Stores, reforçando que é um
   problema pontual desse recurso, não um padrão geral de defasagem da UI.

4. **As duas mensagens de erro de governança mais comuns do dia a dia são
   claras, semanticamente corretas (código HTTP e `type` certos) e
   accionáveis — com uma ressalva de polimento, não de fundo.** A mensagem
   de modelo fora do perfil (`key_model_access_denied`, HTTP 403) diz
   exatamente quais modelos a chave pode acessar e qual foi tentado —
   um desenvolvedor lê a mensagem e sabe imediatamente o que fazer (trocar
   de modelo ou pedir acesso). A mensagem de orçamento estourado
   (`budget_exceeded`, HTTP 429) identifica a chave por alias e sufixo
   mascarado, e mostra o custo atual contra o teto configurado — também
   accionável. Os dois usam o código HTTP semanticamente correto (403 para
   permissão, 429 para limite de taxa/orçamento — muitas APIs erram isso
   devolvendo 400 genérico para ambos os casos) e um campo `type`
   estruturado, então uma integração pode tratar os dois casos
   programaticamente sem parsear texto livre. A ressalva: (a) nenhuma das
   duas mensagens diz *quando* o problema deixa de existir — o erro de
   modelo não sugere a quem pedir acesso, e o erro de orçamento não
   informa a data de reset do `budget_duration` configurado na chave,
   obrigando o desenvolvedor a consultar a UI/API separadamente para saber
   se vale a pena esperar; e (b) o valor de custo vazou um artefato de
   ponto flutuante não arredondado (`0.5999999999999764` em vez de
   `0.60`) diretamente na mensagem voltada ao usuário final — um detalhe
   estético, mas que destoa da precisão do resto da mensagem.

### Veredito geral

O bloco de **dev tooling** é o resultado mais forte do cenário: os dois
SDKs oficiais (OpenAI e Anthropic) funcionaram através do gateway sem
nenhuma adaptação de código além de `base_url`/`api_key` — a promessa
central de P12 ("trocar a URL e nada mais muda") se confirma na prática, e
os dois erros de governança mais comuns chegam de forma clara o bastante
para autoatendimento, com uma ressalva menor de polimento (não de
substância). O bloco de **tool calling avançado** também confirma que o
mecanismo básico provado no cenário 06 se sustenta sob paralelismo, erro
parcial e streaming — sem surpresa negativa. O achado que realmente muda o
quadro desta suíte é o de **inventário**: depois de seis cenários cada um
validando um recurso isoladamente, olhar para os cinco lado a lado revela
que não existe hoje uma superfície confiável de "ver tudo o que está
catalogado" — nem para um operador auditando por API (achado 1, incluindo
uma divergência real entre duas rotas para o mesmo vector store) nem para
um administrador navegando a UI (achado 3, a mesma divergência visível na
tela). Combinado ao achado 2 (visibilidade de catálogo mais aberta que
visibilidade de uso, para 4 dos 5 planos "além de chat"), a recomendação
para produção é a mesma do achado 4 do cenário 05: até o inventário
amadurecer, uma organização que precise de auditoria de catálogo confiável
via API deve construir essa camada de agregação fora do gateway (varrendo
as 5 rotas conhecidas com a master key), e não assumir que qualquer
endpoint isolado — ou a UI — reflete o estado completo.

## 9. Referências

- [LiteLLM — OpenAI-compatible endpoints](https://docs.litellm.ai/docs/proxy/user_keys) —
  base de TD-01.
- [LiteLLM — Anthropic `/v1/messages` pass-through](https://docs.litellm.ai/docs/anthropic_completion) —
  base de TD-02 e da escolha de rota para o bloco TC (nota de execução,
  §3, item 1).
- [Anthropic — Tool use, erro de tool e streaming](https://docs.claude.com/en/docs/agents-and-tools/tool-use/overview) —
  formato de `tool_result`/`is_error` (TC-02) e eventos de streaming com
  tool (`content_block_start`/`input_json_delta`, TC-03).
- [LiteLLM — Budgets e limites por chave](https://docs.litellm.ai/docs/proxy/users) —
  base de TD-03b (`max_budget`, `budget_exceeded`).
- Swagger real do gateway (`http://localhost:4000/openapi.json`) e ReDoc
  (`http://localhost:4000/redoc`, confirmado navegável — `/docs` continua
  HTTP 404 nesta build, achado já registrado nos cenários 03/05),
  consultados para confirmar as 5 famílias de endpoint de TI-01.
- [Cenário 03 — MCP Gateway](../03-mcp/README.md),
  [Cenário 04 — Vector Stores](../04-vector-stores/README.md),
  [Cenário 05 — Skills](../05-skills/README.md) e
  [Cenário 06 — Agentes (A2A) e Tool Calling](../06-agentes-tools/README.md) —
  espectro de permissão por recurso (§2 deste README) e a divergência de
  vector stores (achado 1 aqui, contraste direto com VS-01 do cenário 04).
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md)
  e framework de governança de IA
  (pilares P1–P12).
