# Matriz consolidada — resultados da avaliação

Uma linha por caso de teste executado nos oito cenários avaliados: os cinco
cenários originais da fase 1 — **Guardrails**, **Policies**, **MCP
Gateway**, **Vector Stores** e **Skills** (24 casos, dos quais 2 — SK-05 e
SK-06 — são uma extensão do cenário 05 testando skills de mercado de git
público, além da skill própria) — mais o cenário 06 —
**Agentes (A2A) e Tool Calling** — (7 casos), incluído depois do plano
original, mais o cenário 07 — **Visão de Tooling** (inventário, tool
calling avançado e dev tooling, 9 casos: TI-01..03, TC-01..03, TD-01..03) —,
um cenário transversal que não avalia um recurso isolado, mas sim como os
seis anteriores se comportam quando olhados em conjunto (catálogo
unificado, robustez do tool calling e compatibilidade de SDK/DX de erro) —
mais o cenário 08 — **Decisão tipada local (System One)** — (5 casos:
SO-01..05), que testa um paradigma novo (decisão validada por schema —
`choice`/`score`/`noul` — em vez de texto livre) rodando 100% local
(`local-hermes` via llama.cpp) e governado pelo mesmo gateway, usando o
motor `system-one-adapter` (MIT, oficial da TypeSafe, verificado contra
GitHub/PyPI) depois de descartar honestamente um motor dedicado real mas
incompatível com o requisito de governança do cenário (Laya, Apache-2.0 —
ver a §3 do [README do cenário 08](../cenarios/08-decisao-tipada/README.md)).
**45 casos no total.** Cada linha reflete o veredicto real de
execução registrado na seção 8 ("Análise de resultados") do `README.md` do
respectivo cenário — nenhum resultado nesta tabela foi inferido ou
presumido a partir do brief; todos vêm do log de execução real e do
`/spend/logs` do gateway, citados na íntegra em cada `README.md`.

Ver [`../plano-de-avaliacao.md`](../plano-de-avaliacao.md) para a matriz
cenário × pilar planejada, os critérios gerais de aceite e a versão exata
do LiteLLM testada (imagem `ghcr.io/berriai/litellm:main-stable`, digest
`sha256:c8756e7b9a61…9f03aa`, pacote `litellm==1.100.0`).

## Síntese

**O que o LiteLLM OSS cobre do framework.** Nos seis recursos avaliados —
guardrails (Presidio), policies, MCP, vector stores, skills e agentes
A2A/tool calling — o LiteLLM OSS entrega a capacidade técnica funcional
descrita em cada objetivo de cenário, sem exigir licença Enterprise para
nenhuma delas nesta build: mascaramento de PII na borda (P5/P6, GR-01/02/03
com CPF e e-mail mascarados antes de chegar ao modelo), agrupamento e
herança de guardrails via policies (P5/P10, PO-01/PO-02), um gateway
central para tools MCP com identidade e auditoria unificadas (P1/P4,
MC-01/02), um pipeline de RAG inteiramente soberano com pgvector local
(P3/P6, VS-01 a VS-04, com boa discriminação semântica — R1 em 0,860 contra
0,811/0,797 das demais regras) e um A2A Gateway funcional de ponta a ponta,
incluindo cost tracking exato por invocação (AG-01/02/04). O achado mais
importante em termos de arquitetura de controle de acesso é o **espectro de
permissão em três categorias**, que só ficou completo com o cenário 06: (a)
**MCP nasce fechado por padrão** (deny-by-default, MC-03 — único recurso
com esse comportamento sem nenhuma configuração extra); (b) **vector
stores e agentes A2A nascem abertos, mas têm um campo de restrição nativo e
funcional** (`object_permission.vector_stores` / `object_permission.agents`
— VS-05 e AG-03 confirmam o acesso aberto por padrão, mas o hardening é
possível); (c) **skills nascem abertas e não têm nenhum campo de
restrição** no schema `LiteLLM_ObjectPermissionBase` (achado 4 do cenário
05) — não existe allowlist nativa possível para este recurso, mesmo que um
operador queira configurá-la. Um achado técnico positivo adicional veio do
cenário 06: o guardrail `mascara-pii` protegeu o CPF sintético mesmo dentro
de um argumento estruturado de tool call (TL-03), embora por um mecanismo
de duas camadas (`pre_call` + `post_call` não declarado no `config.yaml`)
que só aparece investigando o log, não a configuração declarada. Fora dos
cenários, uma micro-task complementar de FinOps (integração de
`fronteira-gpt-nano`, validação registrada na execução de 2026-09-10)
confirmou que o custo calculado pelo LiteLLM bate exatamente com os preços
registrados no catálogo (`14 tokens × US$0,00000005 = 7e-07`, `30 tokens ×
US$0,0000004 = 1.2e-05`, ambos conferindo com os headers
`x-litellm-response-cost-*`) — evidência independente de que o FinOps do
gateway é fiel ao catálogo declarado, reforçando a confiabilidade dos
números de custo já usados nos cenários com modelos de fronteira pagos.

**Gaps e comportamentos que exigem atenção antes de produção (sem exigir
Enterprise).** Nenhum dos gaps identificados nesta avaliação foi bloqueado
por uma licença Enterprise ausente — o padrão observado é o oposto: um
recurso Enterprise-documentado (anexação de policy por time/chave, PO-03)
**funcionou sem cobrança de licença** nesta build `main-stable`, o que é
uma ressalva de confiabilidade de teste, não uma folga de arquitetura (a
imagem testada não é uma tag de release fixa, e o pacote
`litellm_enterprise==0.1.62` já vem instalado mesmo na imagem OSS — ver
[`plano-de-avaliacao.md`](../plano-de-avaliacao.md), seção Ambiente). Os
gaps reais, todos documentados com evidência:
(1) `mode: logging_only` altera a resposta retornada ao chamador em vez de
só logar (GR-04) — contraria a expectativa textual do nome do modo; (2) os
reconhecedores nativos do Presidio rodam em inglês por padrão, produzindo
falsos-positivos recorrentes sobre texto em português (GR-03/GR-04 —
`PERSON`/`LOCATION` marcados sobre palavras comuns em pt-BR); (3) a
anexação de policy por time só funciona contra uma tag `main-stable`
(alvo móvel), não confirmada contra uma tag de release numerada — decisão
de produção não deve se apoiar nesse resultado sem reexecutar o teste
contra uma versão fixa; (4) o conector de referência `litellm-pgvector` é
imaturo — endpoint de listagem próprio quebra com HTTP 500 assim que o
store tem atividade, geração de UUID via SQL bruto inconsistente com o
schema Prisma, dimensão do vetor hardcoded em 1536 exigindo `ALTER TABLE`
manual para qualquer embedding que não seja `text-embedding-ada-002`, e um
store definido só em `config.yaml` é apagado silenciosamente da memória do
gateway na primeira sincronização com o banco de controle (achados 1, 2 e
4 do cenário 04); (5) vector stores e agentes A2A nascem com acesso aberto
por padrão — exigem hardening explícito via `object_permission` antes de
produção multi-tenant (VS-05, AG-03).

**Gaps que nenhuma edição do OSS cobre hoje, e implicação para a
arquitetura.** O achado estrutural mais relevante da suíte inteira é sobre
Skills: `/v1/skills` **não é um catálogo local do proxy** — é um
*passthrough* direto para a conta Anthropic configurada em
`ANTHROPIC_API_KEY` (achado 1 do cenário 05). A skill sintética criada em
SK-01 passou a residir nos servidores da Anthropic, não no banco do proxy
— ao contrário de MCP e Vector Stores, onde o gateway local decide o que
fica interno. **Implicação direta para LGPD/soberania**: qualquer
procedimento institucional sensível publicado como skill (nomenclaturas de
sistemas, dados de exemplo, eventualmente dado pessoal incorporado por
engano) sai do perímetro da organização — nenhuma edição, OSS ou
Enterprise, muda esse desenho, porque é a Anthropic Skills API que define o
armazenamento, não o LiteLLM. Combinado a isso, a busca semântica de skills
prometida no rascunho original **não existe nesta API** — `query`/`top_k`
são aceitos e silenciosamente ignorados, a resposta é sempre a listagem
estática completa (achado 2, SK-03) — e **não há nenhum campo de
allowlist** para restringir quem pode criar ou usar uma skill
(`LiteLLM_ObjectPermissionBase` não declara `skills`, achado 4). Para a
arquitetura, a recomendação é tratar Skills, nesta versão, como uma
capacidade de prototipagem — adequada para procedimentos não sensíveis —, e
não publicar conteúdo institucional sensível via `/v1/skills` sem um
controle de allowlist na camada da aplicação cliente (já que o gateway não
oferece um nativo), até o recurso amadurecer ou surgir um mecanismo
alternativo (ex.: injetar o `SKILL.md` como contexto de sistema via
`config.yaml`, abrindo mão do isolamento em container que a Skills API
oferece).

**Achado adicional (SK-05/SK-06, extensão do cenário 05): skill de mercado
e skill própria convivem no mesmo catálogo sem distinção de procedência —
o que torna `/v1/skills` um vetor de injeção de prompt em potencial.** Uma
skill real de terceiro (`internal-comms`, baixada de
`github.com/anthropics/skills`, Apache 2.0, procedência registrada no
`README.md` do cenário) foi instalada pelo exato mesmo caminho que a skill
sintética própria, com o mesmo `source: "custom"` e sem nenhum campo que
registre origem, licença ou revisão de conteúdo. SK-06 provou que o texto
da skill direciona o comportamento do modelo (uma regra de formatação da
skill — escolha de emoji — apareceu na resposta sem ter sido pedida pelo
usuário), o que significa que uma skill de mercado com instrução maliciosa
embutida seria tão fácil de instalar e tão implicitamente confiável quanto
a skill própria: nenhum gate do gateway revisa `SKILL.md` antes de ele
chegar ao container e ser lido/obedecido pelo modelo. Este teste só ficou
protegido porque a revisão de conteúdo (varredura manual contra padrões de
instrução suspeita) foi feita pelo avaliador antes do upload — não porque
existe um controle equivalente na plataforma. Implicação para P3/P8: uma
organização que queira usar skills de mercado precisa de um processo formal
de homologação de procedência (repositório, commit, licença) e revisão de
conteúdo completo antes de qualquer `POST /v1/skills` — hoje isso é
inteiramente um controle de processo humano, não de plataforma.

## Matriz de resultados

| Caso | Cenário | Resultado (passa/falha/gap) | Pilar | OSS ou Enterprise | Evidência (link) |
|---|---|---|---|---|---|
| GR-01 | Guardrails | Passa — CPF mascarado (`<BR_CPF>`) | P5, P6 | OSS | [`GR-01.json`](../cenarios/01-guardrails/evidencias/GR-01.json) |
| GR-02 | Guardrails | Passa — e-mail mascarado (entidade nativa) | P5, P6 | OSS | [`GR-02.json`](../cenarios/01-guardrails/evidencias/GR-02.json) |
| GR-03 | Guardrails | Passa (critério ajustado — entrada mascarada antes do modelo) | P5, P6 | OSS | [`GR-03.json`](../cenarios/01-guardrails/evidencias/GR-03.json) · [`GR-03-ui-log.png`](../cenarios/01-guardrails/evidencias/GR-03-ui-log.png) |
| GR-04 | Guardrails | Falha / gap — `logging_only` alterou a resposta ao chamador | P5, P6 | OSS | [`GR-04.json`](../cenarios/01-guardrails/evidencias/GR-04.json) |
| GR-05 | Guardrails | Passa — zero falso-positivo em frase neutra | P5, P6 | OSS | [`GR-05.json`](../cenarios/01-guardrails/evidencias/GR-05.json) |
| PO-01 | Policies | Passa — policies do config aparecem na API (`total_count: 2`) | P5, P10 | OSS | [`PO-01.json`](../cenarios/02-policies/evidencias/PO-01.json) · [`PO-ui.png`](../cenarios/02-policies/evidencias/PO-ui.png) |
| PO-02 | Policies | Passa — herança resolve `resolved_guardrails` corretamente | P5, P10 | OSS | [`PO-02.json`](../cenarios/02-policies/evidencias/PO-02.json) · [`PO-ui.png`](../cenarios/02-policies/evidencias/PO-ui.png) |
| PO-03 | Policies | Passa (resultado alternativo ao esperado — achado, não falha; funcionou sem licença Enterprise nesta build `main-stable`, ressalva de tag móvel) | P5, P10 | OSS (nesta build; doc oficial descreve como Enterprise) | [`PO-03.json`](../cenarios/02-policies/evidencias/PO-03.json) |
| PO-04 | Policies | Passa — `policies` por request disparou os guardrails resolvidos | P5, P10 | OSS | [`PO-04.json`](../cenarios/02-policies/evidencias/PO-04.json) |
| MC-01 | MCP Gateway | Passa — lista as 3 tools reais do servidor registrado | P1, P4, P5 | OSS | [`MC-01.json`](../cenarios/03-mcp/evidencias/MC-01.json) · [`MC-ui-servers.png`](../cenarios/03-mcp/evidencias/MC-ui-servers.png) |
| MC-02 | MCP Gateway | Passa — chamada de tool via gateway, auditoria unificada em `/spend/logs` | P1, P4, P5 | OSS | [`MC-02.json`](../cenarios/03-mcp/evidencias/MC-02.json) · [`MC-02-ui-log.png`](../cenarios/03-mcp/evidencias/MC-02-ui-log.png) |
| MC-03 | MCP Gateway | Passa — default é restritivo (deny-by-default), achado positivo para P1/P7 | P1, P4, P5 | OSS | [`MC-03.json`](../cenarios/03-mcp/evidencias/MC-03.json) |
| MC-04 | MCP Gateway | Passa — chave com `object_permission.mcp_servers` lista as tools normalmente | P1, P4, P5 | OSS | [`MC-04.json`](../cenarios/03-mcp/evidencias/MC-04.json) |
| VS-01 | Vector Stores | Passa — store catalogado no gateway (`custom_llm_provider: pg_vector`) | P3, P6 | OSS | [`VS-01.json`](../cenarios/04-vector-stores/evidencias/VS-01.json) · [`VS-01-ui-store.png`](../cenarios/04-vector-stores/evidencias/VS-01-ui-store.png) |
| VS-02 | Vector Stores | Passa — 3 regras ingeridas como embeddings independentes | P3, P6 | OSS | [`VS-02.json`](../cenarios/04-vector-stores/evidencias/VS-02.json) |
| VS-03 | Vector Stores | Passa, com boa discriminação semântica (R1 0,860 > R3 0,811 > R2 0,797) | P3, P6 | OSS | [`VS-03.json`](../cenarios/04-vector-stores/evidencias/VS-03.json) |
| VS-04 | Vector Stores | Passa — contexto injetado, confirmado por log (`avector_store_search`) e `prompt_tokens` (364 vs. ~15) | P3, P6 | OSS | [`VS-04.json`](../cenarios/04-vector-stores/evidencias/VS-04.json) · [`VS-04-ui-log.png`](../cenarios/04-vector-stores/evidencias/VS-04-ui-log.png) |
| VS-05 | Vector Stores | Passa como teste — vira gap de compartimentação para P6 (chave sem permissão leu o store inteiro) | P3, P6 | OSS | [`VS-05.json`](../cenarios/04-vector-stores/evidencias/VS-05.json) |
| SK-01 | Skills | Passa (com adaptações de formato de zip) — skill criada de verdade na Anthropic | P3, P9 | OSS (passthrough Anthropic) | [`SK-01.json`](../cenarios/05-skills/evidencias/SK-01.json) |
| SK-02 | Skills | Passa — revela achado 1 (catálogo mistura skill custom com 4 skills nativas da Anthropic) | P3, P9 | OSS (passthrough Anthropic) | [`SK-02.json`](../cenarios/05-skills/evidencias/SK-02.json) |
| SK-03 | Skills | Gap confirmado — não há busca semântica, `query`/`top_k` são ignorados | P3, P9 | OSS | [`SK-03.json`](../cenarios/05-skills/evidencias/SK-03.json) |
| SK-04 | Skills | Passa (com adaptações) — execução real completa, `SKILL.md` lido dentro do container efêmero | P3, P9 | OSS (passthrough Anthropic) | [`SK-04.json`](../cenarios/05-skills/evidencias/SK-04.json) |
| SK-05 | Skills | Passa — skill de mercado real (`internal-comms`, `github.com/anthropics/skills`, Apache 2.0) instalada pelo mesmo caminho de SK-01, revela achado 6 (sem distinção de procedência no catálogo) | P3, P9 | OSS (passthrough Anthropic) | [`SK-05.json`](../cenarios/05-skills/evidencias/SK-05.json) |
| SK-06 | Skills | Passa — uso real completo da skill de mercado, modelo aplicou regra de formatação vinda só da skill (prova de influência = vetor de injeção potencial sem revisão prévia) | P3, P9 | OSS (passthrough Anthropic) | [`SK-06.json`](../cenarios/05-skills/evidencias/SK-06.json) |
| AG-01 | Agentes/Tools | Passa — agent card servido pelo gateway, URL reescrita para o proxy | P1, P3, P4, P5 | OSS | [`AG-01.json`](../cenarios/06-agentes-tools/evidencias/AG-01.json) · [`AG-ui-agents.png`](../cenarios/06-agentes-tools/evidencias/AG-ui-agents.png) |
| AG-02 | Agentes/Tools | Passa — invocação real via gateway, log unificado (`call_type: asend_message`) | P1, P3, P4, P5 | OSS | [`AG-02.json`](../cenarios/06-agentes-tools/evidencias/AG-02.json) · [`AG-02-ui-logs-unified.png`](../cenarios/06-agentes-tools/evidencias/AG-02-ui-logs-unified.png) |
| AG-03 | Agentes/Tools | Passa — default é permissivo (allow-by-default), diferente de MCP; campo de restrição existe mas usa `agent_id` (hash), não `agent_name` | P1, P3, P4, P5 | OSS | [`AG-03.json`](../cenarios/06-agentes-tools/evidencias/AG-03.json) · [`AG-03-bonus-nome.json`](../cenarios/06-agentes-tools/evidencias/AG-03-bonus-nome.json) · [`AG-03-bonus-id.json`](../cenarios/06-agentes-tools/evidencias/AG-03-bonus-id.json) |
| AG-04 | Agentes/Tools | Passa — `cost_per_query` aplicado com exatidão, não é gap | P1, P3, P4, P5 | OSS | [`AG-04.json`](../cenarios/06-agentes-tools/evidencias/AG-04.json) |
| TL-01 | Agentes/Tools | Passa — round-trip completo de function calling via `fronteira-haiku` | P1, P3, P4, P5 | OSS | [`TL-01-step1-tool_use.json`](../cenarios/06-agentes-tools/evidencias/TL-01-step1-tool_use.json) · [`TL-01-step2-resposta_final.json`](../cenarios/06-agentes-tools/evidencias/TL-01-step2-resposta_final.json) |
| TL-02 | Agentes/Tools | Passa — metadado sempre presente; conteúdo (`messages`/`response`) exige `store_prompts_in_spend_logs` | P1, P3, P4, P5 | OSS | [`TL-02.json`](../cenarios/06-agentes-tools/evidencias/TL-02.json) |
| TL-03 | Agentes/Tools | Passa — achado positivo para P5: CPF mascarado (`<BR_CPF>`) dentro do argumento estruturado da tool call, via duas camadas de guardrail (`pre_call` + `post_call` não declarado) | P1, P3, P4, P5 | OSS | [`TL-03.json`](../cenarios/06-agentes-tools/evidencias/TL-03.json) · [`TL-03-spend-log.json`](../cenarios/06-agentes-tools/evidencias/TL-03-spend-log.json) |
| TI-01 | Visão de Tooling | Gap confirmado — não existe visão unificada de inventário; 5 famílias de endpoint distintas, e `/v1/vector_stores` diverge de `/vector_store/list` para o MESMO store (0 vs. 1) | P3, P4 | OSS | [`TI-01.json`](../cenarios/07-tooling/evidencias/TI-01.json) |
| TI-02 | Visão de Tooling | Passa como teste — achado: só MCP nasce fechado para *listagem*; vector stores, agentes e skills ficam visíveis por completo mesmo sem `object_permission`, e só o catálogo de modelos filtra pela chave | P3, P4 | OSS | [`TI-02.json`](../cenarios/07-tooling/evidencias/TI-02.json) |
| TI-03 | Visão de Tooling | Passa, com gap real capturado ao vivo — Models/MCP Servers/Agents corretos na UI; **Vector Stores mostra "No vector stores"** com o store `base-governanca` ativo e funcional | P3, P4 | OSS | [`TI-03-models.png`](../cenarios/07-tooling/evidencias/TI-03-models.png) · [`TI-03-vector-stores.png`](../cenarios/07-tooling/evidencias/TI-03-vector-stores.png) · [`TI-03-mcp-servers.png`](../cenarios/07-tooling/evidencias/TI-03-mcp-servers.png) · [`TI-03-agents.png`](../cenarios/07-tooling/evidencias/TI-03-agents.png) · [`TI-03-skills.png`](../cenarios/07-tooling/evidencias/TI-03-skills.png) · [`TI-03-redoc.png`](../cenarios/07-tooling/evidencias/TI-03-redoc.png) |
| TC-01 | Visão de Tooling | Passa — 2 blocos `tool_use` reais (Brasília, Recife) no mesmo turno, `stop_reason: tool_use` | P4, P5 | OSS | [`TC-01.json`](../cenarios/07-tooling/evidencias/TC-01.json) |
| TC-02 | Visão de Tooling | Passa — recuperação factual do erro de tool (`is_error: true`) sem alucinar valor para a cidade com falha; round-trip registrado no log unificado (`call_type: anthropic_messages`) | P4, P5 | OSS | [`TC-02.json`](../cenarios/07-tooling/evidencias/TC-02.json) · [`TC-02-spend-log.json`](../cenarios/07-tooling/evidencias/TC-02-spend-log.json) |
| TC-03 | Visão de Tooling | Passa — streaming real com `content_block_start` tipo `tool_use` e 4 chunks `input_json_delta`/`partial_json` | P4, P5 | OSS | [`TC-03.json`](../cenarios/07-tooling/evidencias/TC-03.json) · [`TC-03-stream.txt`](../cenarios/07-tooling/evidencias/TC-03-stream.txt) |
| TD-01 | Visão de Tooling | Passa sem nenhuma adaptação — SDK `openai` oficial contra `base_url` do gateway (`/v1`) | P2, P12 | OSS | [`TD-01.json`](../cenarios/07-tooling/evidencias/TD-01.json) |
| TD-02 | Visão de Tooling | Passa sem nenhuma adaptação — SDK `anthropic` oficial contra a rota nativa `/v1/messages` do gateway | P2, P12 | OSS | [`TD-02.json`](../cenarios/07-tooling/evidencias/TD-02.json) |
| TD-03 | Visão de Tooling | Passa — mensagens de `key_model_access_denied` (403) e `budget_exceeded` (429) claras e acionáveis, com código HTTP semanticamente correto; ressalva menor (sem data de reset do budget, float não arredondado na mensagem) | P2, P12 | OSS | [`TD-03a-modelo-nao-permitido.json`](../cenarios/07-tooling/evidencias/TD-03a-modelo-nao-permitido.json) · [`TD-03b-budget-excedido.json`](../cenarios/07-tooling/evidencias/TD-03b-budget-excedido.json) |
| SO-01 | Decisão tipada | Passa — decisão (`r7g`) é opção válida do conjunto, probabilidades somam 1,0; confiança baixa (0,333) já sinaliza a instabilidade confirmada em SO-05 | P3, P9 | OSS (motor MIT `system-one-adapter`) | [`SO-01.json`](../cenarios/08-decisao-tipada/evidencias/SO-01.json) |
| SO-02 | Decisão tipada | Passa como teste — achado é o resultado: 0 acertos em 2 afirmações com gabarito, motor respondeu incerteza (`noul=0,5`) nas duas | P9 | OSS | [`SO-02.json`](../cenarios/08-decisao-tipada/evidencias/SO-02.json) |
| SO-03 | Decisão tipada | Passa como teste — achado é o resultado: ordenação de adequação a memória saiu incoerente (`m7g > c7g > r7g > t4g`, `r7g` deveria liderar) | P9 | OSS | [`SO-03.json`](../cenarios/08-decisao-tipada/evidencias/SO-03.json) |
| SO-04 | Decisão tipada | Passa — 13 chamadas da chave virtual do cenário no log unificado (`/spend/logs`), orçamento aplicável (`max_budget` consultável), chave apagada e confirmada inacessível (HTTP 404) ao final | P2, P4 | OSS | [`SO-04.json`](../cenarios/08-decisao-tipada/evidencias/SO-04.json) |
| SO-05 | Decisão tipada | Passa como teste — achado central para P9: decisão modal (`m7g`, 9/10) diverge da decisão "oficial" de SO-01 (`r7g`), que foi minoria estatística nas 11 execuções da mesma pergunta | P9 | OSS | [`SO-05.json`](../cenarios/08-decisao-tipada/evidencias/SO-05.json) |
