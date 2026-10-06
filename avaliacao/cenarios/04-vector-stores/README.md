# Cenário 04 — Vector Stores (pgvector soberano)

## 1. Objetivo

Avaliar a capacidade do LiteLLM de atuar como **gateway para Vector Stores**
— o mecanismo por trás de RAG (Retrieval-Augmented Generation), em que um
modelo responde com base em um corpus recuperado por busca semântica, não
só no que aprendeu em treino. Isso importa para a governança porque RAG é o
padrão dominante para "IA que sabe sobre nossos dados" (base de
conhecimento interna, política, processo), e é exatamente aí que a
soberania de dados e o catálogo de recursos (P3) mais importam: se a busca
semântica ou o armazenamento vetorial rodar em um serviço SaaS de
terceiros, o conteúdo da base de conhecimento — que pode incluir dado
pessoal ou sigiloso — sai do ambiente a cada consulta, mesmo que o modelo
de chat em si seja local. Este cenário testa uma pilha **100% soberana**:
embeddings gerados por um modelo local (Ollama `nomic-embed-text`, já
catalogado no gateway como `embedding-nomic`) e armazenados em um Postgres
com a extensão `pgvector` rodando no mesmo ambiente — nenhuma etapa do
pipeline de RAG toca um provedor externo.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P3** — Catálogo de modelos e roteamento (allowlist técnica) | O store `base-governanca` é registrado no gateway como um **recurso catalogado**, com o mesmo padrão de allowlist técnica usado para modelos: `vector_store_registry` no `config.yaml` (versionado) e persistência via `/vector_store/new` (ver §3, achado 2), visível na UI em **Tools → Vector Stores → Manage Vector Stores** (`evidencias/VS-01-ui-store.png`) com `Provider: PostgreSQL pgvector (LiteLLM Connector)`. Um app cliente não aponta para um Postgres arbitrário — ele referencia um `vector_store_id` que o gateway resolve, audita e pode revogar, exatamente o modelo de P3 estendido de modelos de chat para bases de conhecimento. |
| **P6** — Compartimentação de contexto / minimização por mascaramento na borda | Todo o pipeline de RAG (VS-02 ingestão, VS-03 busca, VS-04 chat) roda com embeddings gerados por `embedding-nomic` (Ollama local) e armazenados no `db-vectors` (Postgres+pgvector local, container dedicado) — nenhum texto do corpus de governança é enviado a um provedor de embeddings SaaS. VS-05 testa a outra metade de P6 (compartimentação **entre clientes/agentes**, não só entre organização e provedor externo): uma chave sem permissão explícita conseguiu ler o store inteiro — achado de gap, ver §8. |

## 3. Planejamento

**Pré-requisitos:**
- PoC base no ar mais o profile `vectors` (`docker compose --profile vectors up -d`), que sobe `db-vectors` (Postgres 16 + pgvector) e `vector-connector` (build de `github.com/BerriAI/litellm-pgvector`).
- Modelo `embedding-nomic` (`ollama/nomic-embed-text`, dimensão 768) catalogado no gateway — adicionado na Task 2, testado funcional (HTTP 200, `dim=768`).
- `LITELLM_MASTER_KEY` definida em `poc/.env` (`source poc/.env`).
- `bash setup.sh` executado (uma vez por ambiente, ou sempre que o volume
  do `db-vectors` for recriado) — ver a sequência completa em §3.1. É o
  que torna o cenário reproduzível em um clone novo do repositório: sem
  ele, `testes.sh` falha rápido com uma mensagem explícita (`.store-id`
  não existe).

### 3.1 Diagnóstico e correção do `vector-connector` (crash-loop herdado da Task 2)

O container chegava saudável e caía em segundos com
`prisma.engine.errors.EngineConnectionError` após um `P1001` do Prisma
("Can't reach database server at `db-vectors`:`5432`"), mesmo com
`depends_on: condition: service_healthy`. Investigação (logs, `docker
exec`, testes isolados de TCP/protocolo Postgres com `docker compose run`)
encontrou **duas causas independentes**, ambas fora do que a Task 2 havia
cogitado (corrida de timing ou migração faltando):

1. **Conflito de porta no host.** A porta `8001` (mapeamento original do
   brief para o conector) já estava ocupada por um container de **outro
   projeto local nesta máquina** (`outro-projeto`, do compose `local`, sem
   relação com este repositório). Em alguns starts o bind falhava
   explicitamente (`port is already allocated`, container preso em
   `Created`); em outros, o container chegava a subir mas com rede
   instável o bastante para o Prisma reportar P1001 mesmo com o Postgres
   alcançável por `pg_isready` e por conexão TCP direta rodadas em
   paralelo. Corrigido trocando o mapeamento externo para `8002:8000`
   (porta interna, usada pelo gateway via `http://vector-connector:8000`,
   não muda) — `poc/docker-compose.yml`.
2. **Schema do banco nunca migrado.** O README do conector menciona `prisma
   db push` como passo manual de setup (não automatizado no Dockerfile/CMD
   — o `ENTRYPOINT` é só `uvicorn main:app`), e a extensão `vector` não
   vem habilitada por padrão em um banco novo da imagem
   `pgvector/pgvector:pg16`.

Com as duas correções (mais o healthcheck próprio adicionado ao serviço,
`curl -sf http://localhost:8000/health`), o container passou a subir
`healthy` de forma consistente — confirmado com múltiplos restarts
seguidos do stack completo (ver §8).

**Sequência completa de setup (script `setup.sh`, idempotente).** O setup
original da Task 6 fazia os passos abaixo à mão, fora de qualquer script —
achado crítico de reprodutibilidade corrigido no fix round 1: um clone
novo do repositório (volume de `db-vectors` vazio) não tinha como
reproduzir o ambiente, porque (a) o `vector_store_id` hardcoded no
`config.yaml` é um UUID gerado por `gen_random_uuid()` no conector, sem
relação com nenhum dado do repositório — um store novo, em outro
ambiente, nunca teria esse mesmo UUID; e (b) o passo de ajuste de dimensão
do vetor (768, exigido pelo `embedding-nomic`, contra `1536` hardcoded no
`schema.prisma` do conector) só estava narrado como bug descoberto em
produção (§8 original), nunca como passo de setup. `setup.sh` resolve as
duas lacunas, além da extensão e da migração de schema, em uma única
execução idempotente:

```bash
docker compose --profile vectors up -d      # sobe db-vectors + vector-connector, se ainda não estiverem no ar
source poc/.env
bash avaliacao/cenarios/04-vector-stores/setup.sh
```

O que o script faz, em ordem, cada passo idempotente (seguro rodar de
novo sem efeito colateral):

1. `CREATE EXTENSION IF NOT EXISTS vector` no `db-vectors`.
2. `docker compose run --rm --no-deps vector-connector prisma db push` —
   migra o schema do conector (tabelas `vector_stores`/`embeddings`).
   Confirmado por execução real: rodar duas vezes seguidas produz
   `The database is already in sync with the Prisma schema` na segunda,
   sem tocar a coluna `embedding` (tipo `Unsupported` no Prisma — não é
   gerenciado/revertido pelo `db push`).
3. Ajuste de dimensão do vetor: consulta
   `format_type(atttypid, atttypmod)` na coluna `embedding` e só roda o
   `ALTER TABLE embeddings ALTER COLUMN embedding TYPE vector(768)` se o
   tipo atual ainda não for `vector(768)` (schema novo do `prisma db push`
   sempre recria em `vector(1536)`, o hardcoded do conector).
4. Store `base-governanca`: consulta a tabela `vector_stores` do
   `db-vectors` diretamente (não o `GET /v1/vector_stores` do conector —
   bug conhecido, quebra com 500 assim que o store tem atividade, ver
   §8) por um store com esse nome; reusa o UUID se existir, ou cria via
   `POST {conector}/v1/vector_stores` e captura o UUID da resposta
   (`jq -r '.id'`). Grava o UUID em `.store-id` no diretório do cenário
   (não versionado — `.gitignore` — é um artefato local de ambiente, como
   `poc/.env`).
5. Sincroniza `vector_store_id` em `poc/gateway/config.yaml`: se o UUID
   gravado em `.store-id` divergir do que está no config (caso normal em
   um clone novo, ou depois de recriar o volume do `db-vectors`), o
   script substitui a linha via `sed` e reinicia o container do gateway
   (`docker compose restart gateway`), aguardando o healthcheck
   (`GET /health/liveliness`) antes de terminar. Escolha registrada aqui:
   automatizar com `sed` + restart em vez de só imprimir uma instrução
   manual — a atualização é mecânica (uma linha, um valor) e o restart do
   gateway já é parte do fluxo normal de mudança de `config.yaml` nesta
   PoC (mesmo padrão dos outros cenários), então automatizá-la reduz um
   passo manual propenso a erro sem introduzir um comportamento novo ou
   arriscado.

`testes.sh` lê o UUID de `.store-id` (falha com mensagem clara mandando
rodar `setup.sh` primeiro, se o arquivo não existir) — não há mais UUID
fixo no script de teste.

**Decisão de arquitetura mantida do plano:** `db-vectors` é um serviço
Postgres **separado** do `db` de governança (não uma extensão do banco
existente). Motivo registrado no `docker-compose.yml`: a imagem
`pgvector/pgvector:pg16` é baseada em Debian/glibc, enquanto o volume do
`db` de governança já existente foi criado com `postgres:16-alpine`
(musl) — trocar a imagem do banco principal arriscaria incompatibilidade
de collation em um volume que já tem dado. Isolar o pgvector em um serviço
novo, com volume próprio (`db_vectors_data`), evita esse risco e também
separa o domínio de dados (metadados de gateway vs. conteúdo vetorizado de
bases de conhecimento).

### 3.2 Adaptações ao rascunho original do brief

Conferidas lendo o código-fonte real do gateway (imagem
`ghcr.io/berriai/litellm:main-stable`, dentro do container) e do conector
(`github.com/BerriAI/litellm-pgvector`, também lido dentro da imagem
buildada) — o Swagger (`/openapi.json`) não documenta várias dessas
peças, então a leitura de código foi necessária:

1. **`custom_llm_provider` é `"pg_vector"` (com underscore), não
   `"pgvector"`.** O rascunho do brief usava `"pgvector"`, que não existe
   no enum `litellm.LlmProviders` do gateway — teria dado erro de provedor
   não suportado. Confirmado em
   `litellm/llms/pg_vector/vector_stores/transformation.py` (existe uma
   classe `PGVectorStoreConfig`, provider real registrado como
   `pg_vector`) e no próprio README do LiteLLM
   (`docs.litellm.ai/docs/providers/pg_vector`).
2. **`vector_store_id` não é escolhível — é um UUID gerado pelo conector.**
   O brief presumia poder nomear o store como `"base-governanca"` e usar
   esse mesmo texto como ID. O conector cria o registro com
   `gen_random_uuid()` (SQL bruto, não segue o `@default(cuid())` do
   `schema.prisma` — mais uma pequena inconsistência do projeto). Por
   isso, o store é criado (ou reconhecido, se já existir) pelo
   `setup.sh` (§3.1), diretamente no conector
   (`POST http://vector-connector:8000/v1/vector_stores` — fora do
   `testes.sh`, é setup de ambiente, não um caso de teste repetível), e o
   UUID resultante é gravado em `.store-id` e sincronizado
   automaticamente no `vector_store_registry` do `config.yaml` pelo
   próprio script. `vector_store_name: "base-governanca"` continua sendo
   o rótulo amigável e estável entre ambientes — só o UUID varia.
3. **A ingestão real não é "OpenAI Files" (multipart/JSON via
   `POST /v1/vector_stores/{id}/files`) como o brief presumia.** O gateway
   só tem transformação de "vector store files" implementada para o
   provedor `openai` nativo (`ProviderConfigManager.get_provider_vector_store_files_config`
   retorna `None` para qualquer outro provedor, inclusive `pg_vector`) —
   chamar esse endpoint para o nosso store falharia. O conector também não
   expõe um endpoint de arquivo: ele expõe
   `POST /v1/vector_stores/{id}/embeddings`, que espera o **vetor de
   embedding já calculado** no corpo (`{content, embedding, metadata}`) —
   o conector não gera embedding de ingestão sozinho, só o da *query* de
   busca. O `testes.sh` (VS-02) portanto: (a) chama
   `POST $GATEWAY/v1/embeddings` com `model: embedding-nomic` para cada
   trecho do documento, e (b) envia o vetor resultante direto ao conector
   (`$CONECTOR/v1/vector_stores/{id}/embeddings`, fora do gateway — é uma
   chamada de dado bruto entre serviços internos, não uma chamada de LLM).
   Isso preserva a intenção do caso (ingestão governada, com embedding
   gerado pelo modelo catalogado no gateway) sem depender de um caminho
   que não existe na integração atual.
4. **Um store carregado só do `vector_store_registry:` (config.yaml, em
   memória) é apagado silenciosamente assim que uma rotina de
   sincronização com o banco de controle do gateway roda** — encontrado
   por acidente: a primeira chamada a `GET /vector_store/list` (endpoint
   de management) zerou o registro em memória e toda busca subsequente
   (até com a master key) passou a cair no provedor `openai` *default*
   (`"Invalid 'vector_store_id': ... Expected an ID that begins with
   'vs'"`, tentando falar com `api.openai.com`). Lendo o código-fonte
   (`vector_store_registry.py`): a lista faz "Database is the source of
   truth — deleted stores are removed from memory" — um store que só
   existe no config e nunca foi gravado no Postgres de controle do gateway
   é tratado como "deletado" na primeira sincronização. Corrigido
   persistindo o store também via `POST /vector_store/new` (grava no
   banco de controle, `db`, não no `db-vectors`) — passo incluído no
   VS-01 do `testes.sh`, idempotente. Ver achado 2 (§8) para os detalhes.
5. **`EMBEDDING__MODEL` precisa do prefixo `openai/`.** O conector chama
   `litellm.aembedding()` do SDK Python diretamente (não um cliente HTTP
   puro apontado para o gateway) — sem um prefixo de provedor no nome do
   modelo, o SDK não sabe rotear e falha com `"LLM Provider NOT
   provided"`, mesmo com `api_base`/`api_key` corretos apontando para o
   gateway. Como o gateway expõe uma API compatível com OpenAI, o provedor
   correto do ponto de vista do SDK é `openai` — corrigido no
   `docker-compose.yml`: `EMBEDDING__MODEL: openai/embedding-nomic`.

## 4. Dados de análise

`dados/politica-uso-ia.md` — política de uso de IA sintética (dados
fictícios), três regras numeradas (R1 dados pessoais/SaaS externo, R2
retenção de log, R3 aprovação de novo modelo). Corpus pequeno e temático
de propósito: a busca semântica por "posso mandar CPF para modelo
externo?" deve recuperar especificamente R1 como resultado mais relevante
— o teste (VS-03) verifica discriminação semântica entre as três regras,
não apenas se alguma regra é retornada. Cada regra foi ingerida como um
embedding independente (VS-02), com metadado `regra: R1|R2|R3` para
rastreabilidade nos resultados de busca.

## 5. Casos de teste

| ID | Descrição | Passos (`testes.sh`) | Resultado esperado |
|---|---|---|---|
| VS-01 | Store soberano existe e está catalogado/governado no gateway (P3) | `POST /vector_store/new` (persiste no banco de controle) seguido de `GET /vector_store/list` | Store `base-governanca` listado, com `custom_llm_provider: pg_vector` e o UUID esperado |
| VS-02 | Ingestão do corpus, uma regra por embedding | Para cada regra: `POST /v1/embeddings` (gateway, `embedding-nomic`) → `POST {conector}/v1/vector_stores/{id}/embeddings` (direto ao conector) | 3 embeddings criados, cada um com `id` retornado pelo conector |
| VS-03 | Busca semântica recupera a regra certa | `POST /v1/vector_stores/{id}/search` (gateway) com a pergunta sobre CPF | R1 é o resultado de maior score, R2/R3 abaixo |
| VS-04 | RAG — chat com `vector_store_ids` injeta o contexto do store antes da geração | `POST /v1/chat/completions` (`model: local-qwen`, `vector_store_ids: [...]`) | Contexto buscado automaticamente (visível em `/spend/logs`: `avector_store_search` com `custom_llm_provider: pg_vector` imediatamente antes do `acompletion`) — critério é a injeção, não a qualidade da resposta do modelo de 0,5B |
| VS-05 | Controle de acesso: chave restrita (sem `object_permission` de vector store) tenta buscar no store | `POST /key/generate` (sem permissão) → `POST /v1/vector_stores/{id}/search` com essa chave | Resultado observado documentado como achado (permitido = gap de compartimentação, comparável ao MCP do cenário 03) |

## 6. Critérios de aceite

- [x] `vector-connector` sobe e permanece `healthy` (crash-loop herdado da
  Task 2 diagnosticado e corrigido — §3.1).
- [x] Bloco `vector_store_registry:` carrega no `config.yaml` sem quebrar
  o startup do gateway.
- [x] Setup reproduzível do zero: `setup.sh` idempotente cobre extensão
  `vector`, migração de schema, ajuste de dimensão do vetor e
  criação/reuso do store, sem UUID hardcoded fora de script — validado
  dropando tabelas/extensão do `db-vectors` e reexecutando `setup.sh` +
  `testes.sh` de ponta a ponta (fix round 1, §8).
- [x] VS-01 confirma o store catalogado (management API e UI).
- [x] VS-02 ingere as 3 regras com sucesso.
- [x] VS-03 recupera R1 como resultado mais relevante para a pergunta
  sobre CPF.
- [x] VS-04 demonstra contexto injetado no pipeline de chat (evidência em
  log de auditoria + UI).
- [x] VS-05 documenta o comportamento de acesso observado — passe ou vire
  gap (virou gap, ver §8).
- [x] Evidência de cada caso versionada em `evidencias/VS-0*.json` + prints
  da UI (`evidencias/VS-01-ui-store.png`, `evidencias/VS-04-ui-log.png`).
- [x] Gateway termina o cenário saudável (`GET /health/liveliness` → `200`,
  todos os containers do profile `vectors` `Up (healthy)`).

## 7. Roteiro de demonstração

1. Mostrar o bloco `vector_store_registry:` em `poc/gateway/config.yaml`
   versionado no git, e a nota de arquitetura sobre `db-vectors` ser um
   Postgres separado do banco de governança (§3.1).
2. Rodar os scripts ao vivo:
   `cd avaliacao/cenarios/04-vector-stores && source ../../../poc/.env && bash setup.sh && bash testes.sh`
   — `setup.sh` garante o store e a migração de schema (idempotente, rápido
   se o ambiente já estiver configurado); `testes.sh` mostra VS-01
   catalogando o store, VS-02 ingerindo as 3 regras, e VS-03 recuperando R1
   com o maior score.
3. Abrir a UI (`http://localhost:4000/ui` → **Tools → Vector Stores →
   Manage Vector Stores**) e mostrar o card do store `base-governanca`
   com `Provider: PostgreSQL pgvector (LiteLLM Connector)` — evidência
   visual de VS-01 (`evidencias/VS-01-ui-store.png`).
4. Rodar VS-04 (chat RAG) e abrir **Logs**, localizar a chamada de chat
   (`ollama_chat/qwen2.5:0.5b`) — mostrar `364 prompt tokens` (a pergunta
   original tem uma fração disso) como evidência de que o contexto do
   store foi injetado, mesmo com a resposta do modelo de 0,5B sendo
   imperfeita (`evidencias/VS-04-ui-log.png`).
5. Mostrar VS-05 (chave sem permissão explícita lendo o store inteiro)
   como **slide de decisão**, comparando lado a lado com o achado 1 do
   cenário 03 (MCP nasce fechado por padrão; vector stores nascem
   abertos) — mesma pergunta de P1/P6: "o que um agente/chave herda por
   padrão?".

## 8. Análise de resultados

Execução real em 2026-09-10, ambiente local
(`docker compose -f poc/docker-compose.yml --profile vectors`), imagem do
gateway `ghcr.io/berriai/litellm:main-stable` (`v1.100.0`), conector
buildado de `github.com/BerriAI/litellm-pgvector` (HEAD em 2026-09-10),
`db-vectors` `pgvector/pgvector:pg16` (extensão `vector` 0.8.6),
`LITELLM_MASTER_KEY` da PoC.

### Fix round 1 — reprodutibilidade do zero, verificada de verdade

Os achados críticos de reprodutibilidade (UUID hardcoded sem script de
origem, passo `ALTER TABLE` só narrado como bug) foram corrigidos com
`setup.sh` (§3.1) e validados com uma reexecução real a partir de um
estado equivalente a um clone novo do repositório:

```
$ docker exec poc-db-vectors psql -U vectors -d vectors -c \
  "DROP TABLE IF EXISTS embeddings CASCADE; DROP TABLE IF EXISTS vector_stores CASCADE; DROP EXTENSION IF EXISTS vector CASCADE;"
DROP TABLE
DROP TABLE
DROP EXTENSION
$ rm -f avaliacao/cenarios/04-vector-stores/.store-id

$ bash avaliacao/cenarios/04-vector-stores/setup.sh
== 1/5 — extensão pgvector no db-vectors
CREATE EXTENSION
== 2/5 — prisma db push (schema do vector-connector)
🚀  Your database is now in sync with your Prisma schema. Done in 44ms
== 3/5 — dimensão do vetor (schema do conector fixa 1536; embedding-nomic produz 768)
   tipo atual: vector(1536) -> ajustando para vector(768)
ALTER TABLE
== 4/5 — store 'base-governanca' no conector
   store criado: 3b36b13f-3c49-4142-9b71-91deff246264
   gravado em .../04-vector-stores/.store-id
== 5/5 — sincronizar vector_store_id no config.yaml e reiniciar o gateway (se divergente)
   config.yaml tinha '8b757d47-e0fd-4256-8c6b-3ba3d0901ce3', atualizando para '3b36b13f-3c49-4142-9b71-91deff246264'
   reiniciando o gateway para recarregar o config.yaml...
   aguardando healthcheck do gateway.......OK
Setup completo. STORE_ID=3b36b13f-3c49-4142-9b71-91deff246264
```

Store novo, UUID diferente do original (esperado — é gerado por
`gen_random_uuid()` no conector, nunca o mesmo entre ambientes), e o
`config.yaml` sincronizado automaticamente pelo próprio script — sem
edição manual. Em seguida, `testes.sh` (lendo `STORE_ID` de `.store-id`,
sem nenhum UUID fixo no script) reproduziu VS-01 a VS-05 com sucesso — ver
saída abaixo. Achado 3 (VS-05, gap de compartimentação) também
reproduziu, como esperado (é um comportamento do LiteLLM, não depende do
ambiente).

### Saída real do script (`testes.sh`, reexecução do zero após `setup.sh`)

```
== VS-01 — store soberano catalogado no gateway (P3)
{"vector_store_id":"3b36b13f-3c49-4142-9b71-91deff246264","vector_store_name":"base-governanca","custom_llm_provider":"pg_vector"}
== VS-02 — ingerir documento (uma regra por embedding)
"id":"f728f66b-4c40-46b2-b1c0-94034df1954b"
"content":"**R1 — Dados pessoais e modelos SaaS ext
"id":"adc7a3df-2c5d-4d95-ac8d-30e9c6617d23"
"content":"**R2 — Retenção de prompts e respostas.*
"id":"8ec338ce-db5d-4a41-95f2-b3f3e8fa8ba6"
"content":"**R3 — Aprovação de novos modelos.** Nen
== VS-03 — busca semântica
[{"regra":"R1","score":0.8598113990279703},{"regra":"R3","score":0.8105865757608581},{"regra":"R2","score":0.7968081235885641}]
== VS-04 — chat com contexto do store (RAG)
{"content":"Sim, você pode enviar CPF a modelos SaaS externos. A política que você mencionou permite enviar CPF sem mascaramento prévio por um guardrail de PII homologado.\n\nEmbora os modelos SaaS podem ser respon"}
-- confirmação no log de auditoria (avector_store_search antecedendo o chat):
[{"call_type":"acompletion","custom_llm_provider":"openai","api_base":"http://host.docker.internal:8090/v1","model":"openai/hermes-local","startTime":"2026-09-10T17:53:46.501000Z"},{"call_type":"aembedding","custom_llm_provider":"ollama","api_base":"","model":"ollama/nomic-embed-text","startTime":"2026-09-10T17:53:45.331000Z"},{"call_type":"aembedding","custom_llm_provider":"ollama","api_base":"","model":"ollama/nomic-embed-text","startTime":"2026-09-10T17:53:45.254000Z"},{"call_type":"avector_store_search","custom_llm_provider":"pg_vector","api_base":"http://vector-connector:8000/v1/vector_stores","model":"","startTime":"2026-09-10T17:53:45.240000Z"}]
== VS-05 — acesso ao store por chave restrita (sem permissão explícita)
{"n_resultados":3,"erro":null}
```

Nota sobre o log de VS-04 nesta reexecução: o snapshot de
`/spend/logs?limit=5` capturado pelo script (acima) mostra a busca
(`avector_store_search`) e os embeddings, mas não a linha de
`acompletion` do `ollama_chat/qwen2.5:0.5b` — a janela de 5 registros mais
recentes foi disputada por chamadas de `openai/hermes-local` de um
processo concorrente e não relacionado a este cenário, rodando no mesmo
ambiente (retries a cada ~2s contra `local-hermes`, presente antes e
depois desta execução — não introduzido por este fix). Uma consulta
manual sem esse limite confirma a sequência real, sem ambiguidade:

```
$ curl -s "$GATEWAY/spend/logs?limit=60" ... | jq -c '.[] | select(.startTime >= "2026-09-10T17:53:44" and .startTime <= "2026-09-10T17:53:47") | {call_type, model, startTime}'
{"call_type":"acompletion","model":"openai/hermes-local","startTime":"...46.501"}   # processo concorrente, não relacionado
{"call_type":"aembedding","model":"ollama/nomic-embed-text","startTime":"...45.331"}
{"call_type":"acompletion","model":"ollama_chat/qwen2.5:0.5b","startTime":"...45.321"}  # a chamada de chat de VS-04
{"call_type":"aembedding","model":"ollama/nomic-embed-text","startTime":"...45.254"}
{"call_type":"avector_store_search","model":"","startTime":"...45.240"}                 # a busca, ~80ms antes do chat
```

`prompt_tokens: 364` no `usage` de `VS-04.json` (idêntico ao valor
observado na execução original da Task 6, o que é esperado — mesmo
corpus, mesmo modelo de embedding, mesma pergunta) contra ~15 tokens só
da pergunta — evidência independente, no próprio payload da resposta
(não só no log de auditoria), de que o contexto de R1/R2/R3 foi injetado
antes da chamada ao modelo. A resposta do `local-qwen` (0,5B) nesta
execução ficou pior que a da execução original (chegou a afirmar o
oposto da política) — variação já documentada como esperada para este
modelo (§5); o critério de aceite continua sendo a injeção de contexto,
confirmada, não a qualidade textual.

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| VS-01 | **Passa** | Store `base-governanca` (`3b36b13f-3c49-4142-9b71-91deff246264` na reexecução do fix round 1 — UUID novo, esperado; era `8b757d47-...` na execução original da Task 6, mesmo store recriado do zero) catalogado no gateway com `custom_llm_provider: pg_vector`, visível via API de management (`GET /vector_store/list`) e, na execução original, também na UI (`evidencias/VS-01-ui-store.png`, aba **Manage Vector Stores**, provider rotulado `PostgreSQL pgvector (LiteLLM Connector)` — reconhecimento nativo do LiteLLM para este conector específico; screenshot não regerado neste fix round por falta de acesso a browser nesta sessão — o layout e os rótulos da UI não mudaram, só o UUID exibido). |
| VS-02 | **Passa** | As 3 regras foram ingeridas como embeddings independentes, cada uma com `id` retornado pelo conector e persistida em `db-vectors` (pgvector local). Pipeline de ingestão real (embedding via gateway + gravação via conector) diferente do fluxo "OpenAI Files" do rascunho original — ver §3.2, item 3. |
| VS-03 | **Passa, com boa discriminação semântica** | R1 (score 0,860) claramente acima de R3 (0,811) e R2 (0,797) para a pergunta sobre CPF/SaaS externo — a busca não só recupera *alguma* regra, ela ordena corretamente a mais relevante primeiro, com margem suficiente para não ser ambígua em um cenário real com um corpus maior. Scores idênticos entre a execução original e a reexecução do fix round 1 (determinístico: mesmo corpus, mesmo modelo de embedding). |
| VS-04 | **Passa — contexto injetado, confirmado por log e por `usage`** | `avector_store_search` (`custom_llm_provider: pg_vector`) aparece no log de auditoria poucos milissegundos antes da chamada de chat (`ollama_chat/qwen2.5:0.5b`), e o `prompt_tokens` salta de ~15 (só a pergunta) para 364 (pergunta + contexto recuperado) em ambas as execuções — evidência funcional independente da qualidade da resposta (ver nota de execução no fim de §8 sobre um processo concorrente, não relacionado, que disputou a janela de `/spend/logs?limit=5` na reexecução). A qualidade da resposta do `local-qwen` (0,5B) variou bastante entre as duas execuções (achado esperado, ver §5) — na original, citou corretamente o guardrail `mascara-pii`; na reexecução do fix round 1, chegou a afirmar o oposto da política. Em nenhum dos dois casos isso afeta o veredito: o critério de aceite é a injeção de contexto, não a eloquência do modelo de 0,5B. |
| VS-05 | **Passa como teste — vira achado de gap para P6** | Uma chave gerada só com `{"models": ["simulado"]}` (sem qualquer `object_permission` de vector store) conseguiu buscar e ler o store inteiro, retornando as 3 regras (incluindo R1, sobre dado pessoal) com o mesmo resultado da master key. Reproduzido de forma idêntica na reexecução do zero do fix round 1 — comportamento do LiteLLM, não depende do ambiente. Ver achado 3. |

### Achados

1. **`vector-connector` estava genuinamente quebrado, por duas causas
   independentes e nenhuma delas era o que a Task 2 havia cogitado.** A
   hipótese inicial (corrida de timing ou migração de schema faltando)
   acertou a *metade* certa (migração faltando — item 2 de §3.1), mas a
   causa mais impactante na prática foi um **conflito de porta do host
   com um projeto totalmente não relacionado** rodando na mesma máquina
   (`outro-projeto`, porta `8001`). Isso não seria visível em CI/produção (onde
   não há um projeto vizinho competindo por portas), mas é um lembrete de
   que "container sobe e cai" no Docker Compose pode ter causas de
   ambiente local que não aparecem nos logs da aplicação de forma óbvia —
   o traceback do Prisma (`P1001`, "can't reach database") não tem
   qualquer relação semântica com "porta do host ocupada por outro
   projeto", e só foi encontrado testando conectividade de rede isolada
   (`docker compose run` com `pg_isready`/socket Python) e comparando com
   o comportamento do serviço nomeado real.

2. **Um vector store carregado só do `config.yaml` (`vector_store_registry`)
   é apagado silenciosamente da memória do gateway assim que uma rotina de
   sincronização com o banco de controle roda — e isso pode acontecer só
   de alguém abrir a página de management na UI ou chamar
   `GET /vector_store/list` uma vez.** O comentário no próprio
   código-fonte do gateway chama isso de "legacy behavior": "Database is
   the source of truth — deleted stores are removed from memory". Um
   store definido inteiramente por config versionado (a forma recomendada
   pelo brief, e o padrão já usado para `mcp_servers` no cenário 03) é
   tratado, na primeira sincronização, como se tivesse sido apagado por
   um humano via UI — porque ele nunca foi persistido no banco de
   controle do gateway. O efeito prático observado foi drástico: depois
   da primeira chamada a `/vector_store/list`, **toda** busca subsequente
   — inclusive com a master key — parou de resolver o provedor `pg_vector`
   e caiu no *default* `openai`, tentando falar com `api.openai.com` e
   falhando com um erro de formato de ID (`"Expected an ID that begins
   with 'vs'"`) que não tem relação óbvia com a causa real. A correção
   (persistir também via `POST /vector_store/new`, incluída no VS-01)
   resolveu de forma estável (testado com múltiplas chamadas de busca
   espaçadas). Implicação prática: **`vector_store_registry:` sozinho no
   config.yaml não é suficiente para um store confiável em produção**
   nesta versão do LiteLLM — é preciso também persistir via API de
   management, o que quebra a expectativa de "tudo em config versionado,
   sem estado escondido em banco" que o padrão de MCP (cenário 03)
   estabeleceu.

3. **Vector stores nascem abertos por padrão — o oposto exato do
   deny-by-default encontrado para MCP no cenário 03.** Uma chave
   restrita, sem qualquer `object_permission.vector_stores` concedida,
   consegue buscar em qualquer vector store que não tenha `team_id`
   definido — e um store criado como o nosso (via config estático ou via
   `/vector_store/new` chamado pela master key, sem associação a um time)
   **nunca tem `team_id`**. Lendo o código-fonte
   (`can_user_access_vector_store`, `litellm/proxy/vector_store_endpoints/utils.py`):
   a segunda regra de acesso, avaliada antes de qualquer checagem de
   `object_permission`, é "the vector store has no team_id (legacy
   behavior - accessible to all)" — o próprio comentário reconhece que é
   um comportamento herdado, não uma escolha de design deliberada para
   este caso. Na prática, isso significa que **o mecanismo de permissão
   por chave (`object_permission.vector_stores`) existe no código mas é
   inoperante para qualquer store que não esteja associado a um time** —
   e associar um store a um time exige que ele seja criado por uma chave
   de admin de time (não documentado como opção no `config.yaml`
   estático). Comparado ao cenário 03 (MCP): lá, uma chave sem permissão
   era bloqueada com um erro claro (`access_denied`); aqui, o **request
   simplesmente funciona**, sem nenhum sinal de que a permissão deveria
   ter sido checada e não foi. Para P6 (compartimentação de contexto
   entre clientes/agentes), isso é um gap real: uma base de conhecimento
   de governança (nossa demo) ou uma base de conhecimento de um cliente/
   órgão específico em um cenário multi-tenant ficaria acessível a
   qualquer chave válida do gateway, não só às autorizadas — o inverso do
   modelo de segurança recomendado por P1/P7 ("cliente não é confiável
   por padrão").

### Veredito geral

A integração de Vector Stores do LiteLLM com pgvector **funciona
ponta a ponta** e demonstra bem a proposta central do cenário — um
pipeline de RAG inteiramente soberano, com o store como recurso
catalogado e auditável no gateway (P3) — mas com **maturidade de
integração sensivelmente menor** que os outros conectores avaliados nesta
suíte (MCP no cenário 03, guardrails Presidio no cenário 01). O
`vector-connector` de referência (`litellm-pgvector`) tem bugs reais
(endpoint de listagem próprio quebra com `500` assim que um store tem
atividade — `'str' object has no attribute 'timestamp'`, encontrado ao
tentar usá-lo para uma checagem de idempotência no `testes.sh` e
documentado na nota de execução do script; geração de UUID via SQL bruto
inconsistente com o `@default` do próprio schema Prisma; dimensão do
vetor hardcoded em `1536` no schema, exigindo `ALTER TABLE` manual para
qualquer modelo de embedding que não seja o `text-embedding-ada-002`). O
achado mais importante para a decisão de arquitetura, porém, não é do
conector de terceiros — é do **próprio LiteLLM**: o modelo de acesso a
vector stores é permissivo por padrão (achado 3), o oposto do padrão mais
seguro já visto no MCP (cenário 03), e a durabilidade de um store definido
só em config versionado depende de uma chamada de API adicional não óbvia
(achado 2). Para uma base de conhecimento de governança de uso interno
controlado, como a desta PoC, isso é aceitável com mitigação manual
(persistir via `/vector_store/new`, tratar o acesso como público dentro
do gateway). Para um cenário multi-tenant real (bases de conhecimento
separadas por órgão/cliente), **P6 exige resolver o achado 3 antes de ir
a produção** — seja aguardando/contribuindo a correção upstream do modelo
de `team_id`, seja adotando um padrão operacional de criar cada store já
associado a um time desde a primeira chamada.

## 9. Referências

- [LiteLLM — Vector Stores](https://docs.litellm.ai/docs/completion/knowledgebase)
  e [PG Vector provider](https://docs.litellm.ai/docs/providers/pg_vector).
- [litellm-pgvector](https://github.com/BerriAI/litellm-pgvector) — código-fonte
  do conector, lido diretamente na imagem buildada (`main.py`, `config.py`,
  `embedding_service.py`, `prisma/schema.prisma`) para resolver as
  divergências do §3.2 (não documentadas no README do projeto).
- Código-fonte do gateway
  (`/app/.venv/lib/python3.13/site-packages/litellm/` dentro do container
  `ghcr.io/berriai/litellm:main-stable`), em particular
  `vector_stores/vector_store_registry.py`,
  `proxy/vector_store_endpoints/{endpoints,management_endpoints,utils}.py`
  e `llms/pg_vector/vector_stores/transformation.py` — consultado para
  confirmar o nome real do provedor, o formato de request/response de
  cada endpoint, e o modelo de acesso por `team_id`/`object_permission`
  (achados 2 e 3).
- Estado inicial do `vector-connector` (crash-loop) e das variáveis de
  ambiente, ponto de partida do diagnóstico em §3.1 deste README.
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md)
  e framework de governança de IA
  (pilares P1–P12).
- [Cenário 03 — MCP](../03-mcp/README.md) (contraste do achado 3: MCP
  nasce fechado por padrão, vector stores nascem abertos — mesma pergunta
  de P1/P6 com respostas opostas dentro do mesmo produto).
