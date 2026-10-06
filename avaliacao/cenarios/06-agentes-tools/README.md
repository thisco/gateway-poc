# Cenário 06 — Agentes (A2A) e Tool Calling

## 1. Objetivo

Avaliar duas capacidades relacionadas do LiteLLM que importam para a
governança de "agentes" no sentido mais amplo do termo: (a) o **A2A Gateway**
(Agent-to-Agent) — o mecanismo pelo qual o gateway registra, expõe e
audita agentes de IA externos como recursos de primeira classe, análogo ao
que os cenários 03–05 já mostraram para MCP, vector stores e skills — e
(b) **function/tool calling nativo** dos modelos de chat (o mecanismo pelo
qual um modelo como `fronteira-haiku` decide chamar uma ferramenta local,
recebe o resultado de volta e produz uma resposta final). As duas coisas
são distintas mas conectadas: um "agente" em produção normalmente é um
modelo fazendo tool calling em loop, e a pergunta de governança em ambos os
casos é a mesma — **quem** pode invocar o quê, **o que** fica registrado
sobre a chamada (incluindo argumentos, que podem carregar PII), e **que
controles** (allowlist, guardrail) se aplicam. Isso fecha o quadro
iniciado no cenário 03 (MCP) sobre "agentes com poder de ação através do
gateway", agora olhando para o A2A propriamente dito e para o tool calling
que é a base de qualquer agente.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P1** — Agente com identidade própria | O agente `eco-governanca` é registrado no gateway com um `agent_id` próprio (hash gerado no registro) e um agent card servido pelo gateway (AG-01) com identidade distinta de qualquer modelo de chat. Toda invocação (AG-02) passa pela mesma chave virtual (Bearer) usada nas chamadas de chat, e o log unificado (seção 8) atribui a chamada a essa identidade — mesmo padrão de P1 já visto em MCP (cenário 03). |
| **P3** — Catálogo de recursos (também de agentes e tools) | O agente é declarado em `config.yaml` (`agents:`, versionado) e aparece no catálogo `GET /v1/agents` e na UI (**Agentic → Agents**, `evidencias/AG-ui-agents.png`) — o mesmo padrão de catálogo central já visto para modelos (`model_list`), servidores MCP e vector stores. Tools (TL-01) não têm catálogo próprio no gateway — são definidas por request, na chamada de chat — o que por si só é um achado de escopo (seção 8). |
| **P4** — Trilha de auditoria (quem, o quê, quando) | A chamada A2A (AG-02) e o round-trip de tool calling (TL-01) aparecem no mesmo `/spend/logs` e na mesma UI de **Logs** das chamadas de chat comuns (`evidencias/AG-02-ui-logs-unified.png` mostra badges `Agent` e `LLM` lado a lado, na mesma tabela). TL-02 qualifica a profundidade dessa trilha: metadados completos (custo, tokens, guardrails aplicados) sempre presentes; conteúdo (`messages`, `response`, os argumentos reais da tool) vazio por padrão — mesmo achado de fundo do cenário 03 sobre `store_prompts_in_spend_logs`. |
| **P5** — Controles para agentes (allowlist, guardrails sobre ações) | AG-03 testa o default de permissão de agente (achado central da seção 8, ver comparação com MCP/vector stores/skills). TL-03 testa se o guardrail `mascara-pii` protege não só o texto da conversa, mas também os **argumentos estruturados de uma tool call** — o canal de vazamento mais relevante para agentes que executam ações com base em dados que o usuário forneceu em linguagem natural. |

## 3. Planejamento

**Pré-requisitos:** PoC base no ar (`poc/docker-compose.yml`), gateway em
`:4000`, `LITELLM_MASTER_KEY` em `poc/.env` (`source poc/.env` — como as
variáveis do `.env` não têm `export`, use `set -a; source poc/.env; set +a`
ou exporte manualmente antes de rodar `testes.sh`, senão os requests com
`Authorization: Bearer` vão sem a chave). Modelo `fronteira-haiku`
(Anthropic, com crédito) para TL-01..03; guardrail `mascara-pii` (Presidio)
já registrado no cenário 01. Adicionalmente, específico deste cenário:
container do agente local no ar (profile `agents`,
`docker compose -f poc/docker-compose.yml --profile agents up -d agente-eco`)
e gateway recriado para carregar o bloco `agents:` do `config.yaml`
(`docker compose -f poc/docker-compose.yml up -d --force-recreate gateway`
— um `up -d` simples não recarrega um `config.yaml` montado como volume).

### 3.1. Agente A2A local — decisão de implementação

O brief pedia um agente A2A mínimo em Python usando `a2a-sdk`. Duas
incompatibilidades reais impediram isso, nessa ordem:

1. **Python do ambiente local é 3.9.6** — `a2a-sdk` exige Python **>=3.10**
   (`pip install a2a-sdk` falha com erro de resolução de dependência).
   Instalado em Python 3.12/3.13 (disponíveis via Homebrew), o pacote
   instala normalmente (`a2a-sdk==1.1.2`).
2. **A API pública do `a2a-sdk` mudou de forma incompatível entre versões
   próximas.** O quickstart oficial do protocolo A2A usa
   `a2a.server.apps.A2AStarletteApplication` +
   `a2a.server.request_handlers.DefaultRequestHandler` +
   `a2a.server.agent_execution.AgentExecutor`. Nenhum desses símbolos
   existe em `a2a-sdk==1.1.2` (`a2a.server.apps` não existe mais;
   `DefaultRequestHandler` virou `LegacyRequestHandler`). Pior: a versão
   que roda **dentro do próprio container do gateway** (`ghcr.io/berriai/
   litellm:main-stable`) é `a2a_sdk==1.1.0` — uma terceira superfície,
   internamente usada pelo LiteLLM via `litellm.a2a_protocol` (que
   reimplementa boa parte da lógica por cima do SDK, incluindo um
   `card_resolver.py` e um layer de compatibilidade
   `a2a.compat.v0_3` para lidar com o protocolo A2A 0.3 vs. 1.0). Investir
   tempo reimplementando contra uma API instável, pouco documentada e que
   trocou de forma entre patch releases não se justificava para os
   objetivos desta PoC.

**Decisão (conforme fallback pré-aprovado pelo controlador):** implementar
à mão, em **Python stdlib puro** (`http.server`, sem nenhuma dependência
externa), o subconjunto do protocolo A2A que o gateway efetivamente usa —
descoberto lendo o código-fonte real do LiteLLM dentro do container
(`litellm/proxy/agent_endpoints/a2a_endpoints.py`,
`litellm/a2a_protocol/card_resolver.py`, `litellm/a2a_protocol/
cost_calculator.py`):

- `POST /` — JSON-RPC 2.0, método `message/send`: recebe
  `{message: {role, parts: [{kind:"text", text}], messageId}}` e responde
  `{result: {kind:"message", role:"agent", parts:[{kind:"text", text}]}}`.
- `GET /.well-known/agent-card.json` (bônus — ver achado abaixo, não é
  usado pelo gateway para agentes declarados em config).

Arquivo: `dados/agente-eco/server.py` (documentado inline com a decisão
completa) + `dados/agente-eco/Dockerfile` (imagem `python:3.12-slim`, zero
dependências além da stdlib). Roda como serviço `agente-eco` no
`poc/docker-compose.yml`, **profile `agents`** (mesmo padrão dos profiles
`guardrails`/`vectors` dos cenários 01/04):
`docker compose -f poc/docker-compose.yml --profile agents up -d agente-eco`.

O agente responde de forma **somente leitura**: para qualquer pergunta,
ecoa o texto recebido e cita 3 regras fixas de política de governança de
IA (gateway central obrigatório, mascaramento de PII, auditoria por
identidade de chave) — nenhuma ação de escrita é executada em lugar
nenhum.

### 3.2. Registro no gateway (`config.yaml`, bloco `agents:` adicionado)

```yaml
agents:
  - agent_name: eco-governanca
    agent_card_params:
      protocolVersion: "0.3"
      name: "Eco de Governança"
      description: "Agente A2A local, somente leitura, que responde perguntas citando regras fixas de política de governança de IA."
      url: "http://agente-eco:9000/"
      version: "1.0.0"
      capabilities: {}
      defaultInputModes: ["text"]
      defaultOutputModes: ["text"]
      skills:
        - id: "consulta-politica"
          name: "Consulta de política"
          description: "Responde perguntas citando regras fixas de política de governança de IA (somente leitura)."
          tags: ["governanca"]
    litellm_params:
      cost_per_query: 0.001
```

Nenhum outro bloco (`model_list`, `guardrails`, `policies`, `mcp_servers`,
`vector_store_registry`) foi alterado. Gateway recriado
(`docker compose -f poc/docker-compose.yml up -d --force-recreate gateway`
— um `up -d` simples não basta porque o compose não detecta mudança no
conteúdo do arquivo montado como volume) para carregar o bloco. Confirmado
sem erro de startup via `GET /v1/agents` (lista o agente) e pela UI
(**Agentic → Agents**).

### 3.3. Adaptações em relação ao rascunho original do brief

Conferidas no Swagger real (`http://localhost:4000/openapi.json`) e lendo
o código-fonte do gateway dentro do container (mesmo método usado no
cenário 03):

1. **Endpoints reais de A2A batem majoritariamente com a doc pública**
   (`docs.litellm.ai/docs/a2a*`), com uma diferença: a doc pública descreve
   `POST /a2a/{agent_id}` como o endpoint de invocação genérico; o Swagger
   real desta build expõe **três** rotas equivalentes registradas no mesmo
   handler: `POST /a2a/{agent_id}`, `POST /a2a/{agent_id}/message/send` e
   `POST /v1/a2a/{agent_id}/message/send`. O `testes.sh` usa a segunda.
2. **Para agentes declarados em `config.yaml`, o LiteLLM NUNCA busca o
   agent card do upstream.** A doc pública e o próprio código
   (`card_resolver.py`) descrevem um fluxo de *merge* entre o card do
   upstream e overrides do LiteLLM — mas isso só se aplica a agentes
   criados via API/UI sem `agent_card_params` completo. Para agentes
   declarados no config com `agent_card_params` preenchido, a função
   `get_agent_card` (`a2a_endpoints.py`) faz `deepcopy(agent.agent_card_params)`
   e só reescreve o campo `url` para o proxy — **não há nenhuma chamada de
   rede ao agente real** para obter o card. Implicação prática: o agente
   local não precisou implementar `.well-known/agent-card.json` para o
   cenário funcionar (implementado mesmo assim, como bônus, documentando o
   achado). Isso também significa que um agente mal configurado (com
   `agent_card_params` divergente da realidade) não seria pego por
   validação automática do card no momento do registro.
3. **A permissão por chave (`object_permission.agents`) usa `agent_id`
   (o hash), não `agent_name`** (o nome legível do config) — confirmado
   por tentativa (AG-03, bônus): uma chave com
   `object_permission.agents: ["eco-governanca"]` foi **negada** (403);
   a mesma chave com `object_permission.agents: ["<hash>"]` funcionou.
   Pegadinha idêntica em espírito à do `server_id` vs. nome de servidor no
   MCP (cenário 03) — outro recurso onde o identificador estável para
   controle de acesso é opaco, não o nome amigável do config.
4. **`cost_per_query` (não documentado nas páginas públicas consultadas)
   é o parâmetro real de custo fixo por invocação A2A**, lido em
   `litellm/a2a_protocol/cost_calculator.py` (`A2ACostCalculator`).
   Funciona plenamente (AG-04) — não é gap.

**Chaves:** `LITELLM_MASTER_KEY` para as operações administrativas e para
AG-01/02; chaves virtuais geradas por caso (AG-03, bônus) seguindo o
padrão dos cenários anteriores.

## 4. Dados de análise

- **TL-03** usa o CPF sintético padrão desta suíte, **529.982.247-25**,
  reaproveitando o `ad_hoc_recognizer` `reconhecedor-cpf.json` já
  registrado no cenário 01 para o guardrail `mascara-pii`. Nenhum dado real
  foi usado em nenhum caso.
- **AG-01/AG-02** não envolvem PII — o "conteúdo" trocado com o agente é a
  pergunta de teste e as 3 regras de política fixas embutidas no agente
  (texto institucional, não sensível).
- **TL-01** usa uma pergunta neutra sobre a própria política de PII (sem
  PII real embutida) — o objetivo é validar o mecanismo de tool calling,
  não repetir o teste de mascaramento (que é o foco de TL-03).

## 5. Casos de teste

| ID | Descrição | Passos (linha em `testes.sh`) | Resultado esperado |
|---|---|---|---|
| AG-01 | Registrar agente A2A local no gateway e obter o agent card via gateway | `GET /a2a/{agent_id}/.well-known/agent-card.json` (master key) | Card servido pelo gateway com identidade própria do agente (`name`, `url` reescrita para o proxy, `skills`) |
| AG-02 | Invocar o agente via gateway (A2A client + chave virtual) | `POST /a2a/{agent_id}/message/send` (JSON-RPC `message/send`), depois checar `/spend/logs` | Resposta real do agente; chamada no log unificado com atribuição à chave (`call_type: asend_message`) |
| AG-03 | Chave sem permissão de agente tenta invocar | `POST /key/generate` sem `object_permission`, depois `GET /a2a/{agent_id}/.well-known/agent-card.json` com essa chave | Comportamento de permissão observado (deny-by-default? comparar com MCP/vector stores/skills) |
| AG-04 | Custo aplicado à invocação de agente | `litellm_params.cost_per_query` no config; checar `spend` em `/spend/logs` após AG-02 | Custo registrado (ou gap documentado, se não suportado) |
| TL-01 | Function calling completo via gateway (`fronteira-haiku`, tool `consulta_politica` local) | Passo 1: `tools` + `tool_choice:"auto"` → `tool_calls`. Passo 2: reenvia com mensagem `role:"tool"` → resposta final | Round-trip íntegro através do gateway |
| TL-02 | Auditoria do tool calling: o que os spend logs registram | `GET /spend/logs?request_id=<id do passo 2 de TL-01>` | Metadados (custo, tokens, guardrails) sempre visíveis; conteúdo (`messages`/`response`, argumentos da tool) conforme `store_prompts_in_spend_logs` (achado do cenário 03) |
| TL-03 | Guardrail sobre argumento de tool: CPF sintético forçado em argumento de função, com `mascara-pii` ativo | `guardrails:["mascara-pii"]` + `tool_choice` forçado para `consulta_politica` com CPF no texto do usuário | Comportamento observado nos argumentos da tool call (mascarado? vazou?) — achado relevante para P5 em agentes |

## 6. Critérios de aceite

- [x] Bloco `agents:` carrega no `config.yaml` sem quebrar o startup do
  gateway (confirmado via `GET /v1/agents` e UI **Agentic → Agents**).
- [x] AG-01 obtém um agent card real, servido pelo gateway, com a URL
  reescrita para o proxy.
- [x] AG-02 executa uma invocação A2A real através do gateway e a chamada
  aparece no log de auditoria unificado (mesma tabela `/spend/logs` e
  mesma UI **Logs** das chamadas de chat — `evidencias/AG-02-ui-logs-unified.png`).
- [x] AG-03 demonstra o modelo de permissão por chave para agentes —
  resultado observado documentado como achado (seção 8) e comparado com
  MCP/vector stores/skills.
- [x] AG-04 confirma (ou documenta como gap) o rastreio de custo por
  invocação A2A.
- [x] TL-01 executa um round-trip completo de function calling
  (definição → `tool_use` → `tool_result` → resposta final) via
  `fronteira-haiku` através do gateway.
- [x] TL-02 caracteriza o que a auditoria registra sobre tool calling.
- [x] TL-03 observa e documenta o comportamento real do guardrail
  `mascara-pii` sobre argumentos de tool — resultado é o achado,
  qualquer que seja.
- [x] Evidência de cada caso versionada em `evidencias/AG-*.json` /
  `evidencias/TL-*.json`, mais prints da UI
  (`evidencias/AG-ui-agents.png`, tela **Agentic → Agents**;
  `evidencias/AG-02-ui-logs-unified.png`, **Logs** com chamadas `Agent` e
  `LLM` lado a lado).
- [x] Gateway termina o cenário saudável (`GET /health/readiness` → `200`,
  container `poc-gateway` `Up`; `poc-agente-eco` também `Up`).

## 7. Roteiro de demonstração

1. Subir o agente local e recarregar o gateway (só necessário se o
   ambiente ainda não estiver de pé):
   `docker compose -f poc/docker-compose.yml --profile agents up -d agente-eco`
   seguido de
   `docker compose -f poc/docker-compose.yml up -d --force-recreate gateway`
   (um `up -d` simples não recarrega o `config.yaml` montado como volume).
   Mostrar o bloco `agents:` no `poc/gateway/config.yaml` versionado no
   git, e a nota da seção 3.1 sobre a decisão de implementar o agente
   local sem `a2a-sdk` (incompatibilidade de versão do SDK, não do
   protocolo).
2. Rodar o script ao vivo:
   `cd avaliacao/cenarios/06-agentes-tools && set -a; source ../../../poc/.env; set +a; bash testes.sh`
   — mostrar AG-01 obtendo o card, AG-02 invocando o agente e recebendo a
   resposta com as 3 regras fixas, e TL-01 completando o round-trip de
   tool calling com `fronteira-haiku`.
3. Abrir a UI (`http://localhost:4000/ui` → **Agentic → Agents**) e
   mostrar o agente `eco-governanca` catalogado (`evidencias/AG-ui-agents.png`)
   — evidência visual de P3.
4. Abrir **Logs** e mostrar a tabela unificada com badges `Agent` e `LLM`
   lado a lado (`evidencias/AG-02-ui-logs-unified.png`) — este é o ponto
   central de P1/P4 do cenário, o mesmo argumento já usado no cenário 03
   para MCP, agora estendido a agentes A2A.
5. Mostrar AG-03 e TL-03 como **slides de decisão**: o resultado observado
   (seção 8) sobre o default de permissão de agentes (comparando com
   MCP/vector stores/skills) e sobre o comportamento do guardrail nos
   argumentos de tool — este último conecta diretamente com o achado do
   estudo paralelo de harnesses (confabulação de sucesso após bloqueio de
   tool call), reforçando que controles sobre tools são um ponto crítico
   de P5 em qualquer arquitetura de agentes.

## 8. Análise de resultados

Execução real em 2026-09-10, ambiente local
(`docker compose -f poc/docker-compose.yml`), imagem
`ghcr.io/berriai/litellm:main-stable` (`v1.100.0`), `LITELLM_MASTER_KEY` da
PoC, modelo `fronteira-haiku` (`anthropic/claude-haiku-4-5`, custo real
registrado), guardrail `mascara-pii` (Presidio). Agente local `agente-eco`
rodando como container próprio (`poc-agente-eco`, profile `agents`).
Execução única do `testes.sh`, sem falhas — apenas foi necessário
transformar um `sleep` fixo em polling (`fetch_spend_log`, até 10
tentativas / 2s) porque o log de chamadas A2A é gravado de forma
assíncrona e às vezes leva mais de 2s para aparecer em `/spend/logs`
(`logging_obj._defer_async_logging = True`, visto no código-fonte do
handler A2A).

### Saída real do script (`testes.sh`, resumida)

```
agent_id(eco-governanca)=13f9ea7a5d539a2b3650a69fcaa40467aee6fc879cdb08eac359c1d579a48b89
== AG-01 — agent card via gateway
{"name":"Eco de Governança","url":"http://localhost:4000/a2a/13f9ea7a5d539a2b3650a69fcaa40467aee6fc879cdb08eac359c1d579a48b89","protocolVersion":"0.3","skills":["consulta-politica"]}
== AG-02 — invocar agente via gateway
{"text":"[eco de governanca] Pergunta recebida: \"Quais sao as regras de politica de governanca de IA?\". Regras fixas de politica: (1) Toda chamada a modelo de IA deve passar pelo gateway central de governanca -- nao ha acesso direto a provedores fora dele.; (2) Dados pessoais (PII) devem ser mascarados antes de sair do ambiente soberano, conforme o guardrail mascara-pii.; (3) Toda acao de agente e atribuida a uma identidade de chave e registrada em log de auditoria unificado.. Este agente e somente leitura -- nenhuma acao de escrita foi executada.","error":null}
-- AG-02: confirmação no log unificado --
{"call_type":"asend_message","api_key":"litellm_proxy_master_key","model":"a2a_agent/Eco de Governanca","spend":0.001,"startTime":"2026-09-10T18:25:39.068000Z","endTime":"2026-09-10T18:25:39.073000Z"}
== AG-03 — chave sem object_permission.agents (default)
{"protocolVersion":"0.3","name":"Eco de Governança", ...}   {"http_status":200}
-- AG-03 (bônus): object_permission.agents com agent_name NÃO funciona --
{"detail":"Agent '13f9ea...' is not allowed for your key/team. Contact proxy admin for access."}   {"http_status":403}
-- AG-03 (bônus): object_permission.agents com agent_id FUNCIONA --
{"protocolVersion":"0.3","name":"Eco de Governança", ...}   {"http_status":200}
== AG-04 — custo por invocação (litellm_params.cost_per_query)
{"spend":0.001,"total_tokens":174,"model":"a2a_agent/Eco de Governanca"}
== TL-01 — passo 1: definição de tool -> tool_use
{"tool_call":{"function":{"arguments":"{\"tema\": \"uso de dados pessoais PII em prompts de IA\"}","name":"consulta_politica"},"id":"toolu_01X2Tp...","type":"function"},"finish_reason":"tool_calls"}
== TL-01 — passo 2: tool_result -> resposta final
{"content":"Com base na consulta realizada, aqui está a política sobre uso de dados pessoais (PII)...", "finish_reason":"stop"}
== TL-02 — auditoria do round-trip de tool calling
{"call_type":"acompletion","model":"anthropic/claude-haiku-4-5","spend":0.00254,"applied_guardrails":[],"messages_stored":false,"response_stored":false}
== TL-03 — CPF sintético em argumento de tool, guardrail mascara-pii ativo
{"tool_call_arguments":"{\"tema\": \"<BR_CPF>\"}"}
-- TL-03: guardrail_information no log de auditoria --
{"applied_guardrails":["mascara-pii"],"guardrail_information":[{"guardrail_mode":"pre_call","guardrail_name":"mascara-pii","guardrail_status":"success","guardrail_provider":"presidio","masked_entity_count":{"BR_CPF":2,"PERSON":1}},{"guardrail_mode":"post_call","guardrail_name":"mascara-pii","guardrail_status":"success"}]}
```

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| AG-01 | **Passa** | `GET /a2a/{agent_id}/.well-known/agent-card.json` retornou o card completo do agente `eco-governanca`, com `url` reescrita para `http://localhost:4000/a2a/<agent_id>` (não a URL real do container) — confirma que o cliente A2A nunca fala diretamente com o agente, sempre com o proxy (`evidencias/AG-01.json`). |
| AG-02 | **Passa** | `POST /a2a/{agent_id}/message/send` retornou a resposta real do agente (as 3 regras fixas + eco da pergunta). A chamada apareceu em `/spend/logs` com `call_type: "asend_message"`, `api_key: litellm_proxy_master_key`, `model: "a2a_agent/Eco de Governanca"` (`evidencias/AG-02.json`, `AG-02-spend-log.json`) e na mesma UI de **Logs** das chamadas de chat, lado a lado com badges `Agent`/`LLM` (`evidencias/AG-02-ui-logs-unified.png`) — evidência direta de P1/P4. |
| AG-03 | **Passa — default observado é permissivo (allow-by-default), diferente de MCP** | Uma chave gerada **sem** `object_permission.agents` conseguiu obter o card e invocar o agente normalmente (`HTTP 200`, mesmo resultado da master key). Ver achado 1 abaixo — é o oposto do resultado observado para MCP no cenário 03. |
| AG-04 | **Passa — cost tracking A2A funciona, não é gap** | `litellm_params.cost_per_query: 0.001` no config resultou em `spend: 0.001` exato no log de auditoria de AG-02, junto com contagem de tokens (`prompt_tokens: 17`, `completion_tokens: 157`) mesmo sendo uma chamada síncrona a um agente local sem custo real de provedor — o LiteLLM não distingue "custo real vs. custo configurado manualmente", apenas aplica o parâmetro. |
| TL-01 | **Passa** | Passo 1 (`tools` + `tool_choice:"auto"`) produziu `tool_calls[0]` com `name:"consulta_politica"` e argumento coerente com a pergunta; passo 2 (reenviando com `role:"tool"` contendo o resultado simulado) produziu uma resposta final em linguagem natural, coerente com o conteúdo do `tool_result`, `finish_reason:"stop"` — round-trip completo e íntegro através do gateway, usando `fronteira-haiku` real (Anthropic). |
| TL-02 | **Passa — mesmo padrão do cenário 03: metadado sempre presente, conteúdo exige configuração extra** | O log da chamada final de TL-01 trouxe `call_type`, `model`, `spend` (custo real cobrado por tokens Anthropic), `applied_guardrails` (vazio, pois TL-01 não usou guardrail) — mas os campos `messages` e `response` vieram como objetos vazios (`{}`). Ou seja: nem os argumentos da tool nem o conteúdo da resposta ficam armazenados por padrão, mesma ressalva de `store_prompts_in_spend_logs` já documentada no cenário 03. |
| TL-03 | **Passa — resultado é um achado positivo para P5 (ver achado 2)** | O argumento da tool call, que o prompt tentou forçar a conter o CPF real (`"529.982.247-25"`), veio como `{"tema": "<BR_CPF>"}` — **mascarado**, não vazado. O log de auditoria confirma dois guardrails aplicados na mesma chamada: um `pre_call` (que mascarou `BR_CPF: 2, PERSON: 1` ocorrências no texto do usuário antes de chegar ao modelo) e um `post_call` (rodando mesmo sem estar explicitamente configurado com esse modo no `config.yaml` — ver achado 3). |

### Achados

1. **O default de acesso a agentes A2A é permissivo (allow-by-default),
   mas com um campo de restrição disponível — diferente tanto de MCP
   quanto de skills.** Uma chave recém-criada, sem qualquer
   `object_permission.agents`, conseguiu obter o card e invocar o agente
   `eco-governanca` normalmente — o mesmo resultado da master key. Isso
   **fecha o quadro comparativo** que vinha sendo construído nesta suíte de
   avaliação, e ele tem **três categorias distintas**, não duas: (a) **MCP
   (cenário 03) nasce fechado por padrão** (deny-by-default) — o único dos
   quatro recursos onde o gateway já nega acesso sem nenhuma configuração
   extra; (b) **vector stores (cenário 04) e agentes A2A (este cenário)
   nascem abertos, mas têm um campo de restrição nativo e funcional**
   (`object_permission.vector_stores` / `object_permission.agents`) —
   hardening é possível, só não é o default, e exige que um operador
   configure a restrição explicitamente; (c) **skills (cenário 05) nascem
   abertas e não têm NENHUM caminho de hardening via `object_permission`**
   — o schema `LiteLLM_ObjectPermissionBase` (confirmado no cenário 05,
   lendo o Swagger real) simplesmente não tem campo `skills`, então não
   existe allowlist nativa para restringir esse recurso por chave/time,
   mesmo que um operador queira configurá-la. Para uma organização que
   planeja habilitar agentes A2A em produção, isso significa que a
   allowlist de agentes **precisa ser tratada operacionalmente como um
   passo obrigatório de hardening, não como algo que "já vem seguro"** —
   mas ao menos existe um campo para isso, ao contrário de skills, onde a
   única mitigação possível hoje é não publicar conteúdo sensível via
   skill (ou aguardar o recurso amadurecer) — não há botão de restrição
   para apertar.

2. **O guardrail `mascara-pii` protegeu o CPF sintético mesmo dentro do
   argumento estruturado de uma tool call — mas por um mecanismo em duas
   camadas que só apareceu ao investigar o log, não pela leitura do
   `config.yaml`.** O resultado observado (`{"tema": "<BR_CPF>"}`) é
   positivo para P5: um agente que decidisse executar uma ação real com
   base nesse argumento (ex.: "registrar consulta para o CPF X") receberia
   o placeholder mascarado, não o dado real. A causa raiz, vista em
   `guardrail_information` no spend log, é dupla: (a) o guardrail
   `pre_call` mascarou o CPF **no texto da mensagem do usuário antes de
   chegar ao modelo** — o modelo literalmente nunca viu o CPF real, então
   não podia colocá-lo no argumento mesmo que quisesse; e (b) um segundo
   guardrail rodou em modo **`post_call`** sobre a resposta do modelo —
   modo que **não está declarado em nenhum lugar do `config.yaml`** (o
   guardrail `mascara-pii` só está configurado com `mode: "pre_call"`).
   Isto sugere que o LiteLLM aplica automaticamente uma passada adicional
   sobre a saída do modelo quando um guardrail é referenciado por request
   (`guardrails: ["mascara-pii"]`), independentemente do `mode` configurado
   no `config.yaml` — um comportamento de defesa em profundidade que é uma
   boa notícia de segurança, mas que **não é visível olhando só a
   configuração declarada**, o que é um problema de auditabilidade/
   documentação para quem precisa explicar formalmente "por que isso é
   seguro" a um avaliador de conformidade.

3. **Para agentes declarados em `config.yaml`, o LiteLLM nunca busca o
   agent card do upstream — ele serve o `agent_card_params` do config como
   a verdade, sem verificação de rede.** Confirmado lendo
   `a2a_endpoints.py:get_agent_card`: a função faz `deepcopy` direto de
   `agent.agent_card_params` e só reescreve `url`. Isso é diferente do
   fluxo descrito na documentação pública (merge entre card do upstream e
   overrides), que só se aplica a agentes registrados via API/UI. Na
   prática, o agente local implementado para este cenário **não
   precisaria sequer responder a `.well-known/agent-card.json`** para o
   caso AG-01 passar — só precisa responder corretamente a
   `message/send` (AG-02). Implicação de governança: um card divergente
   da realidade (nome, descrição, skills que o agente não tem de fato) não
   seria pego automaticamente por nenhuma validação no momento do
   registro — a integridade do card depende inteiramente de quem escreve o
   `config.yaml` mantê-lo honesto.

4. **`object_permission.agents` usa `agent_id` (hash opaco), não
   `agent_name` (nome legível do config) — mesma classe de pegadinha já
   vista com `server_id` no MCP (cenário 03).** Uma chave com
   `object_permission.agents: ["eco-governanca"]` (o nome usado no
   `config.yaml`) foi **negada** com `403`; a mesma chave com o hash
   correto funcionou. Combinado com o achado 1 (default permissivo), isso
   significa que um operador tentando **restringir** acesso por nome teria
   uma falsa sensação de segurança dupla: acharia que restringiu (porque
   configurou `object_permission.agents`) mas na verdade **bloqueou a
   chave inteira** (porque o nome não bate com nenhum `agent_id` real) —
   um erro de configuração que se manifesta como "bloqueado demais", não
   "aberto demais", o que ao menos falha para o lado seguro neste caso
   específico, mas ainda assim é uma fonte de confusão operacional.

5. **Tools (function calling) não têm catálogo próprio no gateway — ao
   contrário de modelos, servidores MCP, vector stores, skills e agora
   agentes A2A.** `TOOL_DEF` em TL-01/TL-03 é definido inteiramente pelo
   cliente, por request, no campo `tools` do payload de chat completion —
   não existe um `tools:` no `config.yaml` nem um catálogo consultável via
   `GET /v1/tools` (o `/v1/agents/fields`, `/public/agent_hub` etc. são
   sobre agentes A2A, não sobre funções de tool calling). Isso é esperado
   — tool calling é um recurso padrão da API de chat completions, não um
   recurso do gateway — mas tem uma implicação de P3/P5: o gateway não tem
   como aplicar uma allowlist de "quais funções uma chave pode expor ao
   modelo", porque ele nem vê a definição da função como um recurso
   nomeado e persistente. O controle de P5 sobre tool calling, nesta
   build, está inteiramente no conteúdo dos argumentos (via guardrail,
   achado 2), não em uma allowlist de quais tools existem.

### Veredito geral

O A2A Gateway do LiteLLM **funciona de ponta a ponta** com um agente
externo real (implementado por fora, sem `a2a-sdk`, e ainda assim
compatível — confirmando que o protocolo em si é simples mesmo quando o
SDK oficial em Python está instável entre versões): registro versionado,
identidade própria do agente, invocação proxied com auditoria unificada
com as chamadas de chat, e cost tracking por invocação funcionando sem
gaps (AG-04). O achado mais importante para a apresentação executiva é o
**achado 1**: com este cenário, a suíte de avaliação agora tem uma
comparação completa de default de permissão em quatro recursos "além de
chat", com **três categorias, não duas** — **MCP nasce fechado (cenário
03, deny-by-default); vector stores (cenário 04) e agentes A2A (este
cenário) nascem abertos mas têm campo de restrição nativo e funcional
(`object_permission`, hardening possível); skills (cenário 05) nasce
aberta e NÃO tem nenhum campo de restrição no schema
`LiteLLM_ObjectPermissionBase` (hardening por `object_permission`
inexistente para esse recurso)**. Isso é o fio condutor mais forte da
seção de controles de agentes na apresentação: a organização não pode
assumir que "registrar um recurso no gateway" já implica em controle de
acesso — precisa tratar `object_permission` como um passo de hardening
obrigatório para vector stores e agentes A2A, e reconhecer que, para
skills, esse caminho de hardening **não existe hoje** (a única mitigação é
não publicar conteúdo sensível via skill, ou aguardar o recurso
amadurecer). O **achado 2** (guardrail protegendo argumentos de tool via uma
camada `post_call` não declarada explicitamente) é uma boa notícia técnica
de defesa em profundidade, mas também um lembrete de que a superfície real
de proteção de um gateway LiteLLM é maior do que o que está escrito no
`config.yaml` — e isso conecta diretamente com o achado do estudo paralelo
de harnesses (`repos/llama-lab/docs/estudo-harnesses-2026-09-10.md`): lá,
um modelo local **confabulou sucesso depois de ter uma tool call
bloqueada** — o oposto do resultado positivo visto aqui, mas o mesmo ponto
de fundo: **controles sobre tool calling (bloqueio, mascaramento,
auditoria de argumentos) são um ponto crítico de P5 em qualquer
arquitetura de agentes**, seja o agente um A2A externo, seja um modelo
fazendo function calling em loop dentro de um harness — e o comportamento
do controle (mascarar silenciosamente vs. bloquear e deixar o modelo
inventar uma explicação) muda completamente o risco operacional.

## 9. Referências

- [LiteLLM — A2A (Agent-to-Agent)](https://docs.litellm.ai/docs/a2a),
  [Invoking Agents](https://docs.litellm.ai/docs/a2a_invoking_agents),
  [Agent Headers](https://docs.litellm.ai/docs/a2a_agent_headers),
  [Function Calling](https://docs.litellm.ai/docs/completion/function_call)
- Swagger real do gateway (`http://localhost:4000/openapi.json` / `/docs`),
  consultado para confirmar os endpoints reais de A2A
  (`/a2a/{agent_id}`, `/a2a/{agent_id}/message/send`,
  `/v1/a2a/{agent_id}/message/send`, `/v1/agents`) e os schemas
  `AgentConfig`, `AgentCard`, `LiteLLM_ObjectPermissionBase` (campo
  `agents`).
- Código-fonte do container (`/app/.venv/lib/python3.13/site-packages/`):
  `litellm/proxy/agent_endpoints/a2a_endpoints.py` (rotas de card e
  invocação, resolução de `agent_url`, roteamento de `guardrails` por
  agente), `litellm/a2a_protocol/card_resolver.py` (regras de merge do
  agent card — não usadas para agentes de config), `litellm/a2a_protocol/
  cost_calculator.py` (`cost_per_query`).
- [a2a-protocol.org](https://a2a-protocol.org/) e pacote `a2a-sdk` no PyPI
  — consultados para entender por que a API pública do SDK não bateu com o
  quickstart oficial (seção 3.1).
- [Cenário 03 — MCP](../03-mcp/README.md) (contraste do achado 1: MCP
  nasce fechado por padrão, único dos quatro recursos com deny-by-default),
  [Cenário 04 — Vector Stores](../04-vector-stores/README.md) (allow-by-
  default, mas com `object_permission.vector_stores` como caminho de
  hardening — mesma categoria de agentes A2A neste cenário) e
  [Cenário 05 — Skills](../05-skills/README.md) (allow-by-default **sem
  nenhum campo de restrição** no schema `LiteLLM_ObjectPermissionBase` —
  categoria distinta, sem caminho de hardening via `object_permission` —
  mesmo padrão de recurso sem allowlist nativa observado para tools,
  achado 5).
- `repos/llama-lab/docs/estudo-harnesses-2026-09-10.md` — estudo paralelo
  de harnesses citado no achado 2/veredito geral (modelo local confabulando
  sucesso após bloqueio de tool call).
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md)
  e framework de governança de IA
  (pilares P1–P12).
