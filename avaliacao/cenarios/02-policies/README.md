# Cenário 02 — Guardrail Policies

## 1. Objetivo

Avaliar a funcionalidade de **policies** do LiteLLM Gateway — um mecanismo
que agrupa guardrails individuais (como os do cenário 01) em conjuntos
nomeados e versionáveis, com suporte a **herança** (`inherit`) entre
policies e a **anexação** (`attachment`) de uma policy a um escopo (time,
chave, modelo, tag ou global).

Isso importa para a governança porque separa duas responsabilidades que
hoje ficam misturadas: *quais guardrails existem* (cenário 01) e *quais
guardrails se aplicam a quem* (este cenário). Sem policies, a alternativa é
ligar/desligar cada guardrail individualmente por perfil de time/chave — o
que não escala e é fácil de esquecer. Com policies, um perfil de risco
("proteção total", "proteção básica") vira uma unidade nomeada, herdável e
auditável — o mais próximo que o gateway chega de "política como código"
para controles de segurança de IA.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P5** — Guardrails mandatórios herdados | Policies formalizam a herança: `protecao-total` herda de `protecao-base` e resolve os guardrails da base + os próprios (PO-02) — exatamente o modelo "perfil de risco herda proteção mínima" que P5 exige. |
| **P10** — Política como código / conformidade executável | O bloco `policies:` do `config.yaml` é versionado no git; a saída de startup do gateway ("LiteLLM Policy Engine: Loaded 2 policies") e a API `/policies/list` são a prova de que o texto do yaml *é* a configuração em execução, não documentação à parte que pode divergir do sistema real. |
| **P7** — Clientes não são confiáveis por padrão | Achado central do cenário (seção 8): anexar uma policy a um time/chave via API funcionou **sem** licença Enterprise nesta build, mas depender do cliente para declarar `policies: [...]` na própria requisição (também testado, PO-04) viola P7 — um cliente mal-intencionado ou mal configurado simplesmente omite o parâmetro e escapa do guardrail. |

## 3. Planejamento

**Pré-requisitos:**
- PoC base no ar (`poc/docker-compose.yml`), gateway em `:4000`, `LITELLM_MASTER_KEY` definido em `poc/.env`.
- Guardrails `mascara-pii` (`pre_call`) e `mascara-pii-log` (`logging_only`) já definidos no `config.yaml` pelo cenário 01 (ambos `default_on: false`).
- Nenhuma infra adicional (sem profile novo) — policies são um recurso puro do gateway, não dependem do Presidio subir de novo (ele já está no ar por causa do cenário 01).

**Configuração adicionada (`poc/gateway/config.yaml`, sem alterar `model_list` nem os guardrails existentes):**

```yaml
policies:
  protecao-base:
    guardrails:
      add: [mascara-pii-log]
  protecao-total:
    inherit: protecao-base
    guardrails:
      add: [mascara-pii]
```

Sintaxe conferida contra a
[doc oficial de guardrail policies](https://docs.litellm.ai/docs/proxy/guardrails/guardrail_policies)
— o bloco carregou sem erro e o log de startup do gateway confirmou:

```
LiteLLM Policy Engine: Loaded 2 policies

  - protecao-base
      guardrails.add: ['mascara-pii-log']
  - protecao-total (inherits: protecao-base)
      guardrails.add: ['mascara-pii']

Warning: No policy_attachments configured. Policies will not be applied to any requests.
```

O aviso final é relevante: **policies definidas em config não se aplicam a
nada sozinhas** — precisam de uma anexação (`attachment`) a um time, chave,
modelo, tag ou escopo global (`*`), ou de referência explícita por request.
Isso é o gatilho do achado principal da seção 8.

**Endpoints reais (Swagger `/docs` → `/openapi.json`), diferentes do
rascunho original do brief:** o brief presumia `GET /policies` e
`POST /policies/{nome}/attach`. Conferido na build real
(`ghcr.io/berriai/litellm:main-stable`, v1.100.0), o gateway expõe uma API
de policies bem mais completa do que o esperado — `/policies/list`,
`/policy/info/{policy_name}`, `/policies/attachments`, `/policies/resolve`,
versionamento (`/policies/name/{nome}/versions`) e até templates prontos na
UI. O script (`testes.sh`) usa os endpoints reais, mantendo os IDs
PO-01..PO-04 do brief.

**Chaves:** `LITELLM_MASTER_KEY` (`source poc/.env`), Bearer token em todas as chamadas.

## 4. Dados de análise

Reaproveita o payload sintético do cenário 01 — CPF gerado
`529.982.247-25` (não corresponde a pessoa física) — na chamada de chat de
PO-04, para poder comparar diretamente o comportamento do guardrail
`mascara-pii` quando disparado **via policy** (este cenário) contra quando
disparado **por nome direto** (cenário 01, GR-03/GR-04). Não foram
necessários payloads novos: o objetivo aqui não é testar detecção de PII de
novo, é testar o mecanismo de agrupamento/herança/anexação de guardrails.

## 5. Casos de teste

| ID | Descrição | Passos (linha em `testes.sh`) | Resultado esperado |
|---|---|---|---|
| PO-01 | Policies definidas no config aparecem na API de gestão | `GET /policies/list` | Lista com `protecao-base` e `protecao-total`, `total_count: 2` |
| PO-02 | Herança — `protecao-total` resolve guardrails da base + o próprio | `GET /policy/info/protecao-total` | `resolved_guardrails` contém `mascara-pii` (próprio) e `mascara-pii-log` (herdado de `protecao-base`) |
| PO-03 | Anexar policy a um time (teste de licença Enterprise) | `POST /team/new` → `POST /policies` (recria a policy como DB, pré-requisito da anexação) → `POST /policies/attachments` com `teams` | Esperado pelo controlador: erro de licença Enterprise (evidência de gap). Resultado real: **sucedeu sem erro** — também é resultado válido, documentado como achado |
| PO-04 | Policy invocada em chamada real de chat | `POST /v1/chat/completions`, `model: simulado`, `policies: ["protecao-total"]`, payload com CPF | Parâmetro `policies` não está documentado para request de chat, mas funcionou: guardrails da policy resolvida (`mascara-pii` + `mascara-pii-log`) rodaram na chamada |

## 6. Critérios de aceite

- [x] Bloco `policies:` carrega no `config.yaml` sem quebrar o startup do gateway (PO-01, evidência de carregamento no log + API).
- [x] Herança (`inherit`) resolve corretamente a união de guardrails da policy base com os da policy filha (PO-02).
- [x] Tentativa de anexação por time é exercida e documentada — como erro de licença **ou**, se funcionar no OSS, como achado registrado (PO-03: funcionou, ver seção 8).
- [x] Comportamento de `policies` por request é testado e documentado, passe ou vire gap (PO-04: passou, e reproduziu o achado 4 do cenário 01 — `mascara-pii` rodou em pre_call **e** post_call).
- [x] Evidência de cada caso versionada em `evidencias/PO-0*.json` + print da UI (`evidencias/PO-ui.png`, aba **Policies**; `evidencias/PO-ui-templates.png`, aba **Templates**).
- [x] Gateway termina o cenário saudável (`GET /health/readiness` → `200`, container `poc-gateway` `Up`).

## 7. Roteiro de demonstração

1. Mostrar o bloco `policies:` no `poc/gateway/config.yaml` versionado no git — "isso é o yaml, e o yaml é a política em produção" (P10).
2. Rodar o script ao vivo: `cd avaliacao/cenarios/02-policies && LITELLM_MASTER_KEY=$(grep LITELLM_MASTER_KEY ../../../poc/.env | cut -d= -f2) bash testes.sh` — mostrar PO-01/PO-02 confirmando a herança resolvida, e PO-04 aplicando os dois guardrails numa chamada real via `policies: ["protecao-total"]`.
3. Abrir a UI (`http://localhost:4000/ui` → **Policies**) e mostrar a tabela com `protecao-base` (badge `Config`) e `protecao-total` (herda de `protecao-base`, guardrail `mascara-pii`) — evidência visual de PO-01/PO-02 (`evidencias/PO-ui.png`).
4. Mostrar o resultado de PO-03 como **slide de decisão**: a anexação por time funcionou nesta build OSS avaliada — contrariando a documentação oficial, que descreve esse recurso como Enterprise. Usar isso para abrir a discussão: mesmo quando o recurso "funciona" no OSS hoje, uma decisão de arquitetura não deveria depender de um comportamento não documentado e potencialmente removido/gateado em versão futura.

## 8. Análise de resultados

Execução real em 2026-09-10, ambiente local (`docker compose -f poc/docker-compose.yml`), imagem `ghcr.io/berriai/litellm:main-stable` (`v1.100.0`), `LITELLM_MASTER_KEY` da PoC, `model: simulado` (custo zero).

### Saída real do script (`testes.sh`)

```
== PO-01 — listar policies (GET /policies/list)
{"total_count":2,"nomes":["protecao-total","protecao-base"]}
== PO-02 — herança de policy (GET /policy/info/protecao-total)
{"inherit":"protecao-base","guardrails":{"add":["mascara-pii"],"remove":[]},"resolved_guardrails":["mascara-pii","mascara-pii-log"],"inheritance_chain":["protecao-base","protecao-total"]}
== PO-03 — anexação por time (teste de licença)
team_id=bd7911b9-9434-412c-943d-ced0699bb013
{"policy_id":null,"definition_location":null}
{"attachment_id":"a98ee485-2bea-4ce8-b527-897e69665534","policy_name":"protecao-total","scope":null,"teams":["avaliacao-policies"],"keys":[],"models":[],"tags":[],"created_at":"2026-09-10T15:27:50.663000Z","updated_at":"2026-09-10T15:27:50.663000Z","created_by":"default_user_id","updated_by":"default_user_id","definition_location":"db"}
== PO-04 — policy aplicada em chat
{"content":"Resposta simulada pelo gateway de IA da PoC — nenhum modelo real foi chamado. Esta chamada foi autenticada, <LOCATION>, contabilizada e registrada para auditoria.","error":null}
```

(A linha `{"policy_id":null,"definition_location":null}` de PO-03 é o
resultado de uma etapa intermediária do script — `POST /policies` recriando
a policy como DB antes de anexá-la — que retornou `{"detail":"Policy with
name 'protecao-total' already exists"}` porque a policy DB já havia sido
criada numa exploração manual anterior à execução "oficial" do script; a
etapa de anexação em si, capturada em `PO-03.json`, não depende disso e
sucedeu normalmente. Ver achado 1 abaixo.)

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| PO-01 | **Passa** | `GET /policies/list` retorna as duas policies definidas no config, `total_count: 2`. Confirmado também no log de startup ("LiteLLM Policy Engine: Loaded 2 policies") e na UI (`evidencias/PO-ui.png`). |
| PO-02 | **Passa** | `GET /policy/info/protecao-total` retorna `resolved_guardrails: ["mascara-pii", "mascara-pii-log"]` — união correta do guardrail próprio (`mascara-pii`) com o herdado de `protecao-base` (`mascara-pii-log`), e `inheritance_chain: ["protecao-base", "protecao-total"]`. |
| PO-03 | **Passa (resultado alternativo ao esperado — achado, não falha)** | O controlador previu erro de licença Enterprise para anexação por time; a chamada real (`POST /policies/attachments` com `teams: ["avaliacao-policies"]`) **sucedeu** com HTTP 200 e retornou `attachment_id`, sem nenhum sinal de gate de licença. Confirmado com `POST /policies/resolve` para o contexto do time, que devolveu `effective_guardrails: ["mascara-pii", "mascara-pii-log"]` — a policy realmente resolve para esse time. Isso contradiz a doc oficial (seção 3), que afirma "Team/key-based policy attachment requires a LiteLLM Enterprise license." Ver achado 2. |
| PO-04 | **Passa** | O parâmetro `policies: ["protecao-total"]` — não documentado para `/v1/chat/completions` — foi aceito e efetivamente disparou os guardrails da policy. Confirmado via `GET /spend/logs?request_id=...`: `guardrail_information` mostra `mascara-pii` em `pre_call` (`masked_entity_count: {"BR_CPF": 1}` — o CPF foi mascarado antes de chegar ao "modelo") e novamente em `post_call` (`masked_entity_count: {"LOCATION": 1}`), mais `mascara-pii-log` em `post_call`. O texto retornado ao chamador teve "autorizada" trocado por `<LOCATION>` — mesmo padrão de falso-positivo de NER em português já registrado no cenário 01. |

### Achados

1. **Anexação (`/policies/attachments`) só reconhece policies "DB", não
   policies "config".** `GET /policies/attachments` (com `policy_name` de
   uma policy definida só no `config.yaml`, como `protecao-total`)
   retornou `{"detail":"Policy 'protecao-total' not found. Create the
   policy first."}` até eu recriar a mesma policy via `POST /policies`
   (o que a torna `definition_location: "db"`). A partir daí, a anexação
   funcionou. Efeito colateral notado em `PO-01.json`: depois da recriação,
   `GET /policies/list` passou a mostrar `protecao-total` com
   `definition_location: "db"` (a versão criada via API), enquanto
   `protecao-base` continuou `"config"` — ou seja, **uma policy DB com o
   mesmo nome sombreia (shadow) a policy config de mesmo nome** na listagem.
   Implicação para o framework: se times diferentes puderem criar policies
   via UI/API com o mesmo nome de uma policy "oficial" definida em
   `config.yaml`/git, a policy versionada deixa de ser a fonte da verdade em
   runtime sem nenhum aviso — um risco direto para P10 (política como
   código) se a API de gestão ficar aberta a quem não tem acesso ao
   repositório.

2. **Anexação por time/chave funcionou sem licença Enterprise nesta
   build, contrariando a documentação oficial.** A doc
   (`docs.litellm.ai/docs/proxy/guardrails/guardrail_policies`) afirma
   explicitamente que "Team/key-based policy attachment requires a
   LiteLLM Enterprise license" — mas na imagem
   `ghcr.io/berriai/litellm:main-stable` (tag "main", não uma tag de
   release fixa) usada nesta PoC, tanto `POST /policies/attachments` com
   `teams: [...]` quanto a resolução efetiva via `POST /policies/resolve`
   (`effective_guardrails` populado corretamente para o contexto do time)
   funcionaram sem qualquer erro 402/403 de licença. Duas hipóteses, sem
   como distinguir sem inspecionar o código-fonte da checagem de licença:
   (a) a tag `main-stable` empacota código que só terá o gate de licença
   ativado em uma tag de release numerada; (b) a documentação está
   desatualizada em relação ao comportamento real do OSS. De qualquer
   forma, **decisão de arquitetura não deveria se apoiar nesse
   comportamento**: ele não está documentado como suportado no OSS, pode
   ser removido/gateado numa próxima release sem aviso, e testar contra uma
   tag `main-stable` (em vez de uma tag de versão fixa, ex. `v1.100.0`) é
   por definição testar um alvo móvel. Para produção, a recomendação segue
   sendo tratar anexação por time/chave como **dependente de confirmação
   contra uma tag de release fixa antes de qualquer decisão de
   licenciamento**, não como capacidade garantida do OSS.

3. **Sem anexação, uma policy definida em config não afeta nenhuma
   chamada — mesmo referenciada indiretamente pelo `guardrails.add`.** O
   próprio gateway avisa isso no startup ("Warning: No policy_attachments
   configured. Policies will not be applied to any requests.") até que
   PO-03/PO-04 criem uma anexação ou um request passe `policies`
   explicitamente. Isso implica que **P5 (guardrails herdados
   mandatoriamente) não é satisfeito só por definir a policy no yaml** — é
   necessário também um `attachment` de escopo (idealmente global, `scope:
   "*"`, ou por time) para que vire enforcement de fato. Ver análise das
   três alternativas abaixo.

4. **Parâmetro `policies` por request funciona, mas repete o mesmo
   problema de confiança no cliente do achado 4 do cenário 01.** Como em
   GR-03 (cenário 01), quando o guardrail `mascara-pii` (`mode: pre_call`
   na config) é disparado via referência explícita da requisição — aqui
   indiretamente, através de `policies: ["protecao-total"]`, que resolve
   para `mascara-pii` — o spend log mostra o guardrail rodando **duas
   vezes**: uma vez em `pre_call` (mascarando o CPF de entrada) e outra em
   `post_call` (mascarando `LOCATION` na saída, um falso positivo de NER em
   português). Isso confirma, num caminho de código diferente (via policy,
   não via `guardrails: [...]` direto), o mesmo comportamento já registrado
   no cenário 01: referenciar um guardrail explicitamente na requisição
   parece disparar mais pontos do ciclo de vida do que o `mode` declarado
   na config sozinho sugere.

### Três alternativas para "guardrails herdados por perfil" avaliadas contra P7

O framework (princípio 4 + P5) exige guardrails herdados por perfil de
risco, não por escolha do cliente a cada chamada. À luz do achado 3
(policy sem anexação não faz nada) e do achado 2 (anexação por time é o
caminho documentado como Enterprise, mesmo tendo funcionado aqui), há três
caminhos possíveis — avaliados contra **P7** (clientes não são confiáveis
por padrão):

| Alternativa | Como funciona | Avaliação contra P7 |
|---|---|---|
| **(a) Licença Enterprise** | Anexar policy a time/chave via `/policies/attachments` (ou UI), como testado em PO-03. Governança fica no gateway, fora do alcance do cliente. | **Atende P7.** É o único caminho onde nenhuma ação do chamador pode contornar o controle — a anexação é dado de configuração central, não parâmetro de request. Custo: depende de licença Enterprise (mesmo que tenha funcionado sem gate nesta build de teste — achado 2, não confiável para produção). |
| **(b) `default_on: true` global no guardrail** | Trocar `default_on: false` para `true` nos guardrails do cenário 01, sem usar policies/attachments. Todo request passa pelo guardrail, sempre. | **Atende P7** (cliente não pode desligar), mas é **menos granular**: não dá para variar proteção por perfil de time (ex.: time com dado sensível vs. time de uso interno) sem herança de policy — é tudo ou nada, o oposto do que P5 pede ("herdado **por perfil**"). |
| **(c) Guardrails/policies por request, confiando no cliente** | O que PO-04 testou: cliente passa `guardrails: [...]` ou `policies: [...]` no corpo da chamada. | **Viola P7 diretamente.** Um cliente (intencional ou por bug) que simplesmente omite o campo escapa de qualquer proteção — não há enforcement no gateway, só uma convenção que depende de todo integrador seguir corretamente. Só é aceitável como *default* combinado com (a) ou (b) como piso mandatório — nunca como único controle. |

**Conclusão:** para atender P5 + P7 juntos sem licença Enterprise
confirmada, a alternativa (b) é o piso realista no OSS hoje — aceitando a
perda de granularidade por perfil. (a) é a solução correta arquiteturalmente
mas depende de negociar/confirmar a licença Enterprise (o comportamento
observado em PO-03 não deve ser tomado como garantia). (c) nunca deve ser o
único controle.

### Veredito geral

O mecanismo de policies do LiteLLM **cumpre bem sua função de agrupamento e
herança de guardrails** (PO-01, PO-02) — a sintaxe do brief funcionou sem
alteração e o resultado de herança é exatamente o esperado pelo framework
(P5). O achado que mais importa para a decisão de produto não é uma falha
técnica, é um **gap de confiabilidade do próprio teste**: o recurso mais
sensível para P7 — anexação por time sem depender do cliente — funcionou
nesta build sem cobrança de licença Enterprise (achado 2), o que é bom
notícia operacional mas ruim como base de decisão, porque a documentação
oficial diz o oposto e a imagem testada não é uma tag de release fixa. A
recomendação prática é reexecutar PO-03 contra uma tag numerada antes de
apostar a arquitetura de produção nesse caminho.

## 9. Referências

- [LiteLLM — Guardrail Policies](https://docs.litellm.ai/docs/proxy/guardrails/guardrail_policies)
- [LiteLLM — Guardrails Quick Start](https://docs.litellm.ai/docs/proxy/guardrails/quick_start)
- [LiteLLM — PII Masking v2 (Presidio)](https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2)
- Swagger real do gateway (`http://localhost:4000/openapi.json` / `/docs`), consultado para confirmar os endpoints reais de policies (`/policies/list`, `/policy/info/{nome}`, `/policies/attachments`, `/policies/resolve`) e seus schemas de request/response.
- [Cenário 01 — Guardrails](../01-guardrails/README.md) (achados 3 e 4, reproduzidos aqui via policy no achado 4 deste cenário).
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md) e framework de governança de IA (pilares P1–P12).
