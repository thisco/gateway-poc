# Cenário 03 — MCP Gateway

## 1. Objetivo

Avaliar a capacidade do LiteLLM de atuar como **gateway central para
servidores MCP** (Model Context Protocol) — o mecanismo pelo qual agentes de
IA descobrem e chamam *tools* externas (ler um wiki, consultar um sistema,
disparar uma ação). Isso importa para a governança porque agentes com MCP
não são mais só "um modelo respondendo texto": eles executam ações em
sistemas de terceiros em nome de alguém. Sem um gateway, cada agente se
conecta diretamente a cada servidor MCP, e a organização perde os três
controles que mais importam nesse cenário — **quem** (identidade do
chamador), **o quê** (qual tool, com quais argumentos) e **quando** (trilha
de auditoria), além de não ter como restringir *quais* servidores/tools cada
chave/agente pode usar. O gateway promete resolver isso registrando
servidores MCP centralmente e roteando toda chamada de tool pelo mesmo plano
de autenticação, autorização e log já usado para chamadas de LLM.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P1** — Agente com identidade própria | Cada chamada de tool via `/mcp-rest/tools/call` é autenticada com uma chave virtual (Bearer) — a mesma identidade usada nas chamadas de chat. O log da chamada (seção 8, MC-02) mostra explicitamente `api_key: litellm_proxy_master_key` associado à execução da tool `read_wiki_structure`, e a mesma UI de **Logs** que mostra chamadas de LLM mostra a linha MCP lado a lado. |
| **P4** — Trilha de auditoria (quem, o quê, quando) | O registro em `/spend/logs` da chamada MCP tem `call_type: "call_mcp_tool"`, `model: "MCP: read_wiki_structure"`, `startTime`/`endTime`/`request_duration_ms` e `api_key` — os mesmos campos que uma chamada de chat normal, no mesmo armazenamento. Não é um log MCP separado e paralelo: é o log unificado do gateway. Achado 1 (seção 8) qualifica o que falta para essa trilha ser completa (payload de entrada/saída). |
| **P5** — Allowlist de tools/servidores como controle de agentes | `object_permission.mcp_servers` no `/key/generate` restringe quais servidores MCP uma chave pode acessar; sem essa permissão, a chave é bloqueada com `access_denied` (MC-03) e só volta a funcionar com a permissão explícita (MC-04) — exatamente o "allowlist por identidade" que P5 exige para ações de agente, não só para modelos. |

## 3. Planejamento

**Pré-requisitos:**
- PoC base no ar (`poc/docker-compose.yml`), gateway em `:4000`,
  `LITELLM_MASTER_KEY` definido em `poc/.env` (`source poc/.env`).
- Nenhuma infra adicional — MCP é um recurso puro do gateway (roteamento de
  chamadas HTTP a um servidor MCP externo), sem profile novo de
  docker-compose.
- Servidor MCP alvo: **deepwiki** (`https://mcp.deepwiki.com/mcp`), um
  serviço público, sem autenticação, somente leitura (responde perguntas
  sobre a documentação de repositórios públicos do GitHub). Usado
  exclusivamente como alvo funcional do teste de gateway — **em produção o
  registro seria de servidores MCP internos**; a capacidade avaliada
  (registro, permissão, auditoria) é a mesma independentemente de quem
  hospeda o servidor MCP. Nenhum servidor MCP com capacidade de escrita foi
  registrado.

**Configuração adicionada (`poc/gateway/config.yaml`, sem alterar
`model_list`, `guardrails` ou `policies` existentes):**

```yaml
mcp_servers:
  deepwiki:
    url: "https://mcp.deepwiki.com/mcp"
    transport: "http"
```

O gateway foi reiniciado (`docker compose -f poc/docker-compose.yml restart
gateway`, ~10s) para carregar o bloco. Confirmado que carregou sem erro:
`GET /mcp-rest/tools/list` com a master key passou a listar as 3 tools do
deepwiki (`ask_question`, `read_wiki_contents`, `read_wiki_structure`), e a
UI (`/ui/mcp-servers`) mostra o servidor com status `Healthy`.

**Adaptações em relação ao rascunho original do brief** (conferidas no
Swagger real, `http://localhost:4000/openapi.json`, e em
[docs.litellm.ai/docs/mcp](https://docs.litellm.ai/docs/mcp)):

1. **Endpoints de listar/chamar tool batem com o brief** —
   `GET /mcp-rest/tools/list` e `POST /mcp-rest/tools/call` existem
   exatamente como descritos, sem mudança de rota.
2. **Campo de permissão por chave não é `allowed_mcp_servers`.** Esse nome
   não existe no schema `GenerateKeyRequest`. O campo real é
   `object_permission.mcp_servers` (uma lista de nomes de servidor), dentro
   do objeto `LiteLLM_ObjectPermissionBase` — o mesmo objeto que também
   controla permissão de `vector_stores`, `agents` e `models` por chave. O
   `testes.sh` usa `{"object_permission": {"mcp_servers": ["deepwiki"]}}`
   em vez de `{"allowed_mcp_servers": [...]}`. (Nota: a resposta de
   `/key/generate` ecoa `"object_permission": null` mesmo quando a
   permissão foi aplicada com sucesso — checado empiricamente com MC-04,
   é uma inconsistência cosmética da resposta, não um bug funcional.)
3. **`POST /mcp-rest/tools/call` exige `server_id` no corpo**, não
   documentado no Swagger (o `requestBody` do endpoint aparece vazio no
   schema OpenAPI) nem mencionado no rascunho do brief. Descoberto por
   tentativa (`400 {"error":"missing_parameter","message":"server_id is
   required in request body"}`) e confirmado lendo o código-fonte do
   container (`rest_endpoints.py`, função `call_tool_rest_api`). `server_id`
   é um hash gerado pelo gateway no momento do registro do servidor (ex.:
   `266024044f9612bf481c78f6cfef1ff0`), não o nome (`deepwiki`) usado no
   `config.yaml`. O `testes.sh` resolve esse hash dinamicamente via
   `GET /v1/mcp/server` (filtrando `server_name == "deepwiki"`) antes de
   MC-02, em vez de hardcodá-lo.

**Chaves:** `LITELLM_MASTER_KEY` (`source poc/.env`), Bearer token nas
chamadas administrativas; chaves virtuais geradas por caso (MC-03, MC-04)
seguindo o padrão dos cenários anteriores.

## 4. Dados de análise

Nenhum dado sintético de PII foi necessário neste cenário — o objetivo é
testar o mecanismo de gateway MCP (registro, roteamento, permissão,
auditoria), não detecção de dados sensíveis. O único "dado" de teste é o
argumento passado à tool `read_wiki_structure`: `repoName: "BerriAI/litellm"`
— um repositório público do GitHub, escolhido por já ser o próprio projeto
avaliado nesta suíte (dogfooding leve, sem relação com dados da
organização).

## 5. Casos de teste

| ID | Descrição | Passos (linha em `testes.sh`) | Resultado esperado |
|---|---|---|---|
| MC-01 | Gateway lista as tools do servidor MCP registrado | `GET /mcp-rest/tools/list` (master key) | Lista com as 3 tools do deepwiki (`ask_question`, `read_wiki_contents`, `read_wiki_structure`) |
| MC-02 | Chamada de tool passa pelo gateway (proxy + auditoria) | Resolve `server_id` via `GET /v1/mcp/server`, depois `POST /mcp-rest/tools/call` com `name: read_wiki_structure`, `server_id`, `arguments.repoName` | Conteúdo retornado pela tool (`isError: false`); chamada aparece no log unificado do gateway (`/spend/logs`, `call_type: call_mcp_tool`) |
| MC-03 | Chave restrita **sem** permissão MCP não acessa tools | `POST /key/generate` sem `object_permission`, depois `GET /mcp-rest/tools/list` com essa chave | Comportamento default do gateway (permissivo ou restritivo) — observado e documentado como achado |
| MC-04 | Chave com permissão explícita ao servidor deepwiki | `POST /key/generate` com `object_permission.mcp_servers: ["deepwiki"]`, depois `GET /mcp-rest/tools/list` com essa chave | Lista as 3 tools do deepwiki normalmente |

## 6. Critérios de aceite

- [x] Bloco `mcp_servers:` carrega no `config.yaml` sem quebrar o startup do
  gateway (confirmado via `/mcp-rest/tools/list` e UI **MCP Servers**,
  status `Healthy`).
- [x] MC-01 lista as tools reais do servidor registrado.
- [x] MC-02 executa uma chamada de tool real através do gateway e a chamada
  aparece no log de auditoria unificado (mesma tabela `/spend/logs` e mesma
  UI **Logs** das chamadas de chat).
- [x] MC-03/MC-04 demonstram o modelo de permissão por chave para MCP —
  resultado observado documentado como achado, passe ou vire gap.
- [x] Evidência de cada caso versionada em `evidencias/MC-0*.json` + prints
  da UI (`evidencias/MC-ui-servers.png`, aba **MCP Servers**;
  `evidencias/MC-02-ui-log.png`, detalhe do log da chamada MC-02).
- [x] Gateway termina o cenário saudável (`GET /health/readiness` → `200`,
  container `poc-gateway` `Up`).

## 7. Roteiro de demonstração

1. Mostrar o bloco `mcp_servers:` no `poc/gateway/config.yaml` versionado no
   git, e a nota sobre deepwiki ser um alvo público de teste (produção usaria
   servidores MCP internos).
2. Rodar o script ao vivo:
   `cd avaliacao/cenarios/03-mcp && LITELLM_MASTER_KEY=$(grep LITELLM_MASTER_KEY ../../../poc/.env | cut -d= -f2) bash testes.sh`
   — mostrar MC-01 listando as tools, MC-02 chamando `read_wiki_structure` e
   recebendo conteúdo real do deepwiki.
3. Abrir a UI (`http://localhost:4000/ui` → **MCP Servers**) e mostrar o
   card do servidor `deepwiki` (`Healthy`, `HTTP`, `Public`) —
   evidência visual de MC-01 (`evidencias/MC-ui-servers.png`).
4. Abrir **Logs**, localizar a linha `MCP` da chamada de MC-02 e clicar nela
   — mostrar que ela aparece na mesma tabela de Request Logs das chamadas de
   chat, com `Call Type: call_mcp_tool`, `Model: MCP: read_wiki_structure`,
   IP e timestamps (`evidencias/MC-02-ui-log.png`) — este é o ponto central
   de P1/P4 do cenário.
5. Mostrar MC-03 (chave sem permissão MCP) como **slide de decisão**: o
   resultado observado (seção 8) e o que ele implica para "agentes herdam
   tudo por padrão" (P1).

## 8. Análise de resultados

Execução real em 2026-09-10, ambiente local
(`docker compose -f poc/docker-compose.yml`), imagem
`ghcr.io/berriai/litellm:main-stable` (`v1.100.0`), `LITELLM_MASTER_KEY` da
PoC, servidor MCP `deepwiki` (`https://mcp.deepwiki.com/mcp`, público, sem
autenticação). Execução única do script, sem instabilidade de rede — nenhum
retry precisou ser usado.

### Saída real do script (`testes.sh`)

```
== MC-01 — listar tools via gateway
["ask_question","read_wiki_contents","read_wiki_structure"]
== MC-02 — chamar tool via gateway
server_id(deepwiki)=266024044f9612bf481c78f6cfef1ff0
{"ok":true,"error":null,"isError":false}
== MC-03 — chave sem permissão MCP
{"tools":[],"error":"unexpected_error","message":"An unexpected error occurred: {'error': 'access_denied', 'message': 'The key is not allowed to access any MCP servers.'}"}
== MC-04 — chave com permissão explícita ao servidor deepwiki
["ask_question","read_wiki_contents","read_wiki_structure"]
```

Confirmado no log de auditoria (`GET /spend/logs?request_id=<id da MC-02>`):

```json
{
  "request_id": "400077c6-9f00-4ef8-8eb0-ef1b11250a05",
  "call_type": "call_mcp_tool",
  "api_key": "litellm_proxy_master_key",
  "model": "MCP: read_wiki_structure",
  "startTime": "2026-09-10T15:38:06.466000Z",
  "endTime": "2026-09-10T15:38:09.556000Z",
  "request_duration_ms": 3090,
  "user": "default_user_id"
}
```

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| MC-01 | **Passa** | `GET /mcp-rest/tools/list` retorna as 3 tools reais do servidor `deepwiki` registrado no config, cada uma com `mcp_info.server_name: "deepwiki"` e `server_id`. Confirmado também na UI (`evidencias/MC-ui-servers.png`, card `deepwiki` com status `Healthy`). |
| MC-02 | **Passa** | `POST /mcp-rest/tools/call` (com `server_id` resolvido dinamicamente — achado 2 abaixo) executou `read_wiki_structure` no repositório `BerriAI/litellm` e retornou conteúdo real (`isError: false`, sumário da wiki do repositório). A chamada apareceu em `/spend/logs` com `call_type: "call_mcp_tool"` e na UI de **Logs**, na mesma tabela das chamadas de chat (`evidencias/MC-02-ui-log.png`) — evidência direta de P1 (identidade: `api_key`) e P4 (trilha: quem, qual tool, quando). |
| MC-03 | **Passa — default observado é restritivo (bom para P1/P7)** | Uma chave gerada sem `object_permission.mcp_servers` foi **bloqueada** ao tentar `GET /mcp-rest/tools/list`: `{"error": "access_denied", "message": "The key is not allowed to access any MCP servers."}`, com `tools: []`. Isto é o oposto do risco que o controlador havia sinalizado como possível achado ("agentes herdam tudo por padrão") — nesta build, o comportamento default do gateway para MCP é **negar por padrão**, não herdar. Ver achado 1. |
| MC-04 | **Passa** | Uma chave gerada com `object_permission.mcp_servers: ["deepwiki"]` (adaptação do campo `allowed_mcp_servers` do brief — ver seção 3, item 2) listou as 3 tools do deepwiki normalmente, idêntico ao resultado de MC-01 com a master key. Confirma que a permissão por chave é o mecanismo funcional de allowlist (P5) — apesar de a resposta de `/key/generate` ecoar `object_permission: null` (ver achado 4). |

### Achados

1. **O default de acesso a MCP é restritivo (deny-by-default), não
   permissivo — um resultado positivo para P1/P7.** Diferente do padrão
   observado em outras áreas do LiteLLM nesta mesma suíte de avaliação (por
   exemplo, guardrails com `default_on: false` no cenário 01, onde a
   proteção só roda se alguém a ligar explicitamente), o acesso a servidores
   MCP por uma chave recém-criada **sem** `object_permission.mcp_servers`
   é negado, não permitido. Isso significa que, ao contrário do risco que o
   controlador cogitou para este caso ("agentes herdam tudo por padrão"), a
   capacidade mais sensível do MCP gateway — executar ações em sistemas
   externos — já nasce fechada por chave/agente, exigindo concessão
   explícita (MC-04) para funcionar. É o modelo correto para P1 (agente só
   age dentro da identidade que lhe foi concedida) e P7 (cliente não é
   confiável por padrão) sem depender de nenhuma configuração adicional do
   operador do gateway — ao contrário do cenário de guardrails/policies
   (cenário 02), aqui não há um "Warning: nada será aplicado até você
   configurar um attachment": o deny já é o estado de repouso.

2. **`server_id` (não o nome do servidor) é obrigatório para chamar uma
   tool, e não está documentado no Swagger.** `POST /mcp-rest/tools/call`
   rejeita com `400 missing_parameter` se o corpo não incluir `server_id` —
   um hash opaco gerado pelo gateway no momento do registro
   (`266024044f9612bf481c78f6cfef1ff0` para `deepwiki`), diferente do nome
   usado no `config.yaml`. Isso não aparece no `requestBody` do
   `/openapi.json` (schema vazio) nem no rascunho do brief, que presumia
   bastar `{"name": ..., "arguments": ...}`. Só foi descoberto por
   tentativa e confirmado lendo o código-fonte do container. Implicação
   prática: qualquer integração cliente com `/mcp-rest/tools/call` precisa
   primeiro consultar `GET /v1/mcp/server` (ou `/mcp-rest/tools/list`, que
   já inclui `server_id` em `mcp_info`) para resolver o nome amigável para o
   hash — um passo extra não documentado que aumenta o risco de integração
   quebrada se o hash for tratado como estável e hardcodado (ele é estável
   enquanto o servidor não for removido/recriado, mas isso também não está
   documentado).

3. **A trilha de auditoria de MCP está unificada com a de LLM, mas o
   payload da chamada (argumentos, resposta da tool) não fica no log por
   padrão.** O ponto forte confirmado em MC-02: a chamada MCP aparece na
   mesma tabela `/spend/logs` e na mesma UI de **Logs** das chamadas de
   chat, com os mesmos campos estruturais (`call_type`, `api_key`, `model`,
   timestamps, `request_duration_ms`) — não é um sistema de auditoria
   paralelo. Porém, o detalhe da chamada na UI (`evidencias/MC-02-ui-log.png`)
   mostra explicitamente "Request/Response Data Not Available" e instrui
   habilitar `store_prompts_in_spend_logs: true` em `general_settings` para
   capturar o conteúdo (quais argumentos foram passados, o que a tool
   retornou). Ou seja: o **metadado** de auditoria (quem, qual tool, quando)
   já vem por padrão — suficiente para P4 no nível "houve uma chamada,
   por quem, a qual tool" — mas o **conteúdo** da chamada (o que
   exatamente foi perguntado/retornado, relevante para investigar um
   incidente) exige uma configuração adicional explícita, com a mesma
   ressalva de custo/retenção de dados sensíveis em log que qualquer
   `store_prompts_in_spend_logs` traria para chamadas de chat.

4. **A resposta de `/key/generate` ecoa `object_permission: null` mesmo
   quando a permissão foi aplicada com sucesso — inconsistência cosmética,
   não funcional.** Ao criar a chave de MC-04 com
   `{"object_permission": {"mcp_servers": ["deepwiki"]}}`, o JSON retornado
   por `POST /key/generate` trouxe `"object_permission": null`, como se a
   permissão não tivesse sido gravada. A evidência de que ela **foi**
   aplicada é o próprio resultado de MC-04: a mesma chave, testada em
   seguida contra `GET /mcp-rest/tools/list`, listou as 3 tools do deepwiki
   normalmente — comportamento idêntico ao de MC-01 com a master key, e
   completamente diferente do bloqueio (`access_denied`) visto em MC-03 para
   uma chave sem essa permissão. Ou seja, a permissão foi persistida e
   aplicada corretamente pelo gateway; apenas o campo de eco na resposta de
   criação da chave está com um bug de serialização (não reflete o valor
   gravado). Implicação prática: um operador ou script de automação que
   valide permissões inspecionando a resposta de `/key/generate` (em vez de
   testar a chave contra o recurso protegido, como o script fez) chegaria a
   uma conclusão errada — de que a permissão não foi concedida — quando na
   verdade ela está ativa. A verificação funcional (testar a chave contra
   `/mcp-rest/tools/list`), não a leitura da resposta de criação, é a fonte
   confiável de verdade aqui.

### Veredito geral

O MCP Gateway do LiteLLM **cumpre bem as três capacidades centrais
avaliadas**: registro de servidor via config versionado (P10, por extensão
do padrão já visto no cenário 02), identidade do chamador preservada na
chamada de tool (P1) e trilha de auditoria unificada com o log de LLM (P4).
O achado mais relevante é uma **boa notícia estrutural**: diferente de
guardrails e policies (cenários 01 e 02), que nascem desligados por padrão
e exigem configuração explícita para virar enforcement, o acesso a MCP
nasce **fechado** por chave — o modelo de segurança mais alinhado a P1/P7
entre todos os recursos avaliados até aqui nesta suíte. O ponto de atenção
prático é de usabilidade/documentação (achado 2, `server_id` não
documentado) e de profundidade de auditoria por padrão (achado 3, conteúdo
da chamada exige configuração extra) — nenhum dos dois é um gap de
governança, mas ambos afetam o esforço de integração e de investigação de
incidentes em produção.

## 9. Referências

- [LiteLLM — MCP (Model Context Protocol) Gateway](https://docs.litellm.ai/docs/mcp)
- Swagger real do gateway (`http://localhost:4000/openapi.json` / `/docs`),
  consultado para confirmar os endpoints reais de MCP
  (`/mcp-rest/tools/list`, `/mcp-rest/tools/call`, `/v1/mcp/server`) e os
  schemas de `GenerateKeyRequest`/`LiteLLM_ObjectPermissionBase`.
- Código-fonte do container (`rest_endpoints.py`,
  `/app/.venv/lib/python3.13/site-packages/litellm/proxy/_experimental/mcp_server/`),
  consultado para confirmar o requisito de `server_id` em `/mcp-rest/tools/call`
  (não documentado no Swagger).
- [deepwiki](https://mcp.deepwiki.com/mcp) — servidor MCP público usado como
  alvo funcional do teste (sem autenticação, somente leitura).
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md)
  e framework de governança de IA
  (pilares P1–P12).
- [Cenário 02 — Policies](../02-policies/README.md) (contraste do achado 1:
  MCP nasce fechado por padrão, policies/guardrails nascem abertos).
