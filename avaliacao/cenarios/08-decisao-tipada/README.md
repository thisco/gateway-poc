# Cenário 08 — Decisão tipada local (System One)

## 1. Objetivo

Os cenários 01–07 avaliaram o gateway como intermediário de **texto livre**
entre cliente e modelo (chat, tools, RAG, skills). Este cenário testa um
paradigma diferente: **decisão tipada** — em vez de pedir uma resposta em
linguagem natural para depois parsear, a chamada declara de antemão o
formato exato da resposta (`choice`: uma opção entre N; `score`: uma nota
numa rubrica ordinal; `noul`: uma probabilidade de verdadeiro/falso) e o
motor devolve um objeto validado contra esse schema, com probabilidade e
confiança explícitas — nada de regex sobre texto do modelo. O padrão de
mercado para esse paradigma é o **System One** da TypeSafe (produto SaaS
fechado "Jev"); este cenário testa se o mesmo paradigma roda **100% local**
— sem nenhuma chamada a um serviço de terceiro — e, principalmente, se a
decisão tipada **herda a governança do gateway** (chave virtual, log
unificado, orçamento) do mesmo jeito que qualquer chamada de chat já
testada nos cenários 01–07. Isso importa para a arquitetura porque decisão
tipada é o formato natural para automação de baixo nível que hoje seria
resolvida com regra ad-hoc ou parsing frágil de texto (ex.: triagem de
chamado, checagem de afirmação factual, ranking de opção) — se esse padrão
puder rodar soberano e auditável, ele vira uma capacidade catalogável do
framework (P3), não um SaaS externo a mais para aprovar.

## 2. Mapeamento ao framework

| Pilar / princípio | Como este cenário evidencia |
|---|---|
| **P3** — Catálogo de modelos e roteamento (por extensão, catálogo de capacidade) | O cenário testa se "decisão tipada" pode existir como uma capacidade catalogada da camada soberana — motor local, modelo local, sem dependência de SaaS — e não apenas como uma feature exclusiva de um produto fechado (Jev). SO-01/02/03 provam o paradigma funcionando de ponta a ponta com um modelo já catalogado no `config.yaml` (`local-hermes`). |
| **P4** — Auditoria e observabilidade | SO-04 é o caso central deste pilar: a mesma chave virtual usada nas decisões tipadas aparece no log unificado (`/spend/logs`) do gateway, exatamente como qualquer chamada `/v1/chat/completions` dos cenários 01–07 — a decisão tipada não é um caminho paralelo sem trilha de auditoria. |
| **P2** — Controle de uso e custo (FinOps de IA) | SO-04 também confirma que o orçamento por chave (`max_budget`) se aplica à decisão tipada como a qualquer chamada — com a ressalva honesta de que modelos locais têm custo \$0 registrado, então o teto nunca é de fato testado neste cenário (ver §8). |
| **P9** — Confiabilidade/homologação de modelo | SO-02 (acerto contra gabarito), SO-03 (ordenação coerente de adequação) e SO-05 (consistência da mesma decisão repetida 10×) são, juntos, um mini-protocolo de homologação: eles respondem "este motor, neste modelo, é confiável o bastante para decidir sem revisão humana por chamada?" — a resposta real (§8) é não, ainda não, nesta escala de modelo. |

## 3. Planejamento

**Pré-requisitos:**
- PoC base no ar (`poc/docker-compose.yml`), gateway em `:4000`,
  `LITELLM_MASTER_KEY` em `poc/.env` (`set -a; source poc/.env; set +a`).
- Modelo local disponível: `local-hermes` (llama.cpp no host, `:8090`,
  ~34B) preferencialmente, com fallback automático para `local-qwen`
  (ollama, sempre disponível, `qwen2.5:0.5b`) se `:8090/health` não
  responder — o próprio `testes.sh`/`demo.sh` testam e registram qual foi
  usado (`evidencias/SO-00-motor.json`). Nesta execução, `local-hermes`
  respondeu normalmente e foi o modelo usado em todos os 5 casos.
- Python ≥3.10 para o motor (ver decisão de motor abaixo) — o sistema
  operacional só tem Python 3.9 disponível como `python3` "puro"; o
  `testes.sh` localiza um interpretador mais novo (`python3.12` via
  Homebrew, `/opt/homebrew/bin/python3.12` nesta máquina) e cria um venv
  isolado em `dados/.venv/` (não versionado, mesmo padrão do cenário 07).

### Nota de execução — o gateway estava fora do ar no início desta tarefa

O container `poc-gateway` tinha sido encerrado por OOM 5 dias antes desta
execução (`docker inspect` → `OOMKilled: true`, `2026-09-18`), e o
container, ao ser reiniciado, ficava preso num laço de falha na checagem
de saúde do Prisma (`httpx.ConnectError` tentando alcançar o
query-engine local) — a causa raiz era uma rede Docker órfã: o container
reutilizado (`docker compose start`, que reaproveita o container existente
em vez de recriá-lo) não estava mais anexado à rede
`governanca-ia-poc_default` (`NetworkSettings.Networks` vazio mesmo com o
container em `running`), então nunca alcançava `db`. `docker network
connect governanca-ia-poc_default poc-gateway` seguido de `docker compose
start gateway` resolveu de forma permanente — o gateway ficou saudável daí
em diante (`GET /health/readiness` → `{"status":"healthy","db":"connected"}`)
e assim permaneceu por toda a execução deste cenário. Registrado aqui
porque é uma causa raiz específica (rede órfã, não falta de memória) que
outro operador desta PoC pode encontrar de novo depois de um período longo
sem reiniciar a stack.

### Decisão de motor (honestidade sobre o que existe de verdade)

O plano listava, em ordem de preferência: **(1) Laya**, um motor Apache-2.0
com os mesmos tipos `choice`/`score`/`noul`, citado a partir de pesquisa
com fontes de confiabilidade mista; e **(2)** o fallback documentado,
`system-one-adapter-python` oficial da TypeSafe apontado ao nosso gateway.
Os dois foram verificados contra fonte primária (API do GitHub e do PyPI
direto, não busca em agregador) antes de decidir:

1. **O Laya existe de verdade — e é mais maduro do que qualquer expectativa
   razoável para um projeto citado por pesquisa de baixa confiabilidade.**
   `github.com/NandhaKishorM/laya` é um repositório real: 19.991 estrelas,
   1.703 forks, licença `Apache-2.0` confirmada pela API do GitHub
   (`GET /repos/NandhaKishorM/laya` → `license.spdx_id: "Apache-2.0"`),
   criado em `2026-09-18` (5 dias antes desta execução — viralizou muito
   rápido, o próprio README do projeto linka um artigo dev.to contando a
   origem). O pacote `laya` no PyPI existe de fato (`GET
   https://pypi.org/pypi/laya/json` → `version: "0.3.11"`, classificador
   `License :: OSI Approved :: Apache Software License`, `Development
   Status :: 4 - Beta`, publicado no mesmo dia desta execução), mantido
   por Convai Innovations, com checkpoints reais no Hugging Face
   (`convaiinnovations/laya`) baixados via `huggingface_hub` na primeira
   execução — é genuinely um motor local: um classificador
   não-autoregressivo dedicado (~33ms por pergunta, single forward pass),
   não um wrapper de LLM. Isso bate exatamente com os três tipos do plano
   (`choice`/`score`/`noul`) e roda 100% offline depois de baixar o
   checkpoint. As fontes de baixa confiabilidade citadas na pesquisa
   original eram, na verdade, o sintoma de um projeto **novo demais**:
   uma busca por repositórios "Laya" no GitHub carregava, no dia desta
   execução, majoritariamente wrappers/SDKs/bridges de terceiros
   construídos sobre ele (MCP servers, integrações Unity, CLIs) — não
   porque o motor não existisse, mas porque um projeto de 5 dias já tinha
   gerado um pequeno ecossistema de integrações antes que buscadores
   genéricos indexassem bem o próprio repositório-fonte.
2. **Mas o Laya é estruturalmente incompatível com o requisito central de
   governança deste cenário (SO-04), e por isso não foi usado.** Por ser
   um classificador dedicado — não um wrapper de LLM — o Laya **não faz
   nenhuma chamada de API** durante a inferência: o forward pass roda
   inteiramente dentro do processo Python local, contra pesos baixados uma
   vez do Hugging Face. Não há nenhuma requisição HTTP para o gateway
   interceptar, autenticar com chave virtual, logar em `/spend/logs` ou
   tarifar — exatamente o mecanismo que SO-04 existe para provar. Rodar o
   Laya validaria o paradigma (choice/score/noul tipados, localmente), mas
   **não validaria a tese deste cenário dentro do framework de
   governança** (P4: toda decisão de IA passa por um ponto auditável). Por
   isso o Laya fica registrado aqui como a alternativa correta para
   produção pura (mais rápida, sem custo de token, sem dependência de LLM)
   quando o requisito for só "decisão tipada rápida e local", mas fora de
   escopo para este teste específico — e não foi instalado (o download dos
   checkpoints via `torch`/`transformers` é pesado e não seria usado nos
   casos de teste de qualquer forma, dado o motivo acima).
3. **O fallback do plano também existe de verdade, e resolve exatamente o
   requisito de SO-04 — foi o motor usado.**
   `github.com/typesafe-ai/system-one-adapter-python` é real: MIT, 281
   estrelas, criado em `2026-08-08`, com releases ativos (`v0.2.1` em
   `2026-09-22`, um dia antes desta execução). No PyPI, `system-one-adapter
   0.2.1` depende de `typesafe-sdk>=0.7.0` (também real:
   `github.com/typesafe-ai/typesafe-sdk-python`, MIT, pacote `typesafe-sdk
   0.7.1` no PyPI) — os mesmos tipos `Choice`/`Score`/`Noul` do SDK oficial
   da TypeSafe, só que o adapter troca o backend de "API da TypeSafe" para
   "qualquer LLM compatível com OpenAI/Anthropic/Gemini", incluindo
   endpoint customizado com `base_url`. Isso permite apontar exatamente
   para `$GATEWAY/v1` com uma chave virtual do nosso próprio LiteLLM — toda
   decisão tipada vira, por definição, uma chamada real
   `POST /v1/chat/completions` no gateway, herdando autenticação por chave,
   log unificado e orçamento automaticamente. Instalado limpo via
   `pip install "system-one-adapter[openai]"` num venv isolado (sem
   adicionar dependência ao repositório) — `pip install` funcionou de
   primeira, sem patch nem workaround.

**Resumo da §3 para quem só quer o veredito**: o motor certo pelo puro
paradigma (Laya) existe e é real, mas o motor certo **para este cenário**
(que exige passar pela governança do gateway) é o adapter oficial da
TypeSafe apontado ao nosso `local-hermes`/`local-qwen` — e foi o que rodou
de fato nos 5 casos abaixo.

## 4. Dados de análise

Nenhum dado de PII sintético foi necessário — os três blocos de dado deste
cenário são conhecimento técnico/arquitetural (AWS, S3, RDS), não dado
pessoal:

- **`dados/demanda-arquitetura.md`** (SO-01) — uma demanda de arquitetura
  realista (API web stateless, picos de 4×, p95 < 100ms, prioridade de
  custo) e as 4 famílias de instância AWS oferecidas como opções
  (`m7g`/`c7g`/`r7g`/`t4g`), com justificativa de por que nenhuma é
  imposta como "a única certa" (ver arquivo).
- **`dados/afirmacoes-noul.md`** (SO-02) — 2 afirmações técnicas com
  gabarito verificável em documentação pública da AWS: uma verdadeira
  (custo do S3 Standard-IA vs. Standard) e uma falsa formulada com
  gabarito inequívoco (RDS Multi-AZ não substitui backup).
- **`dados/workload-banco-memoria.md`** (SO-03) — um workload de banco em
  memória e a mesma rubrica ordinal de 4 níveis aplicada às 4 famílias.

## 5. Casos de teste

| ID | Tipo | Descrição | Script | Resultado esperado |
|---|---|---|---|---|
| SO-01 | `choice` | Seleção de família de instância AWS para a demanda de `dados/demanda-arquitetura.md` | `dados/so01_choice.py` | Decisão é uma das 4 opções válidas, com vetor de probabilidades somando ≈1 |
| SO-02 | `noul` | Veracidade de 2 afirmações com gabarito (`dados/afirmacoes-noul.md`) | `dados/so02_noul.py` | `noul` de cada afirmação comparado ao gabarito, acerto/erro registrado honestamente |
| SO-03 | `score` | Pontuação de 4 famílias (r7g/c7g/m7g/t4g) para workload em memória, mesma rubrica (`dados/workload-banco-memoria.md`) | `dados/so03_score.py` | Ordenação esperada: `r7g` acima de `c7g` e `m7g` |
| SO-04 | governança | As chamadas de SO-01/02/03/05 passam pelo gateway com a chave virtual `cenario-08` | `testes.sh` (bloco SO-04, sem script Python próprio) | Chamadas aparecem em `/spend/logs`, custo contabilizado, budget aplicável |
| SO-05 | consistência | SO-01 repetido 10× — decisão modal e variância das probabilidades | `dados/so05_consistencia.py` | Tabulação de estabilidade da decisão modal e desvio-padrão por opção — insumo P9 |

## 6. Critérios de aceite

- [x] SO-01 produz uma decisão dentro do conjunto de 4 opções, com
  probabilidades válidas (soma ≈ 1) — confirmado, `decisao_e_opcao_valida:
  true`, soma = 1,0 exato.
- [x] SO-02 registra acerto/erro contra o gabarito **com honestidade**,
  incluindo o caso de o modelo responder com incerteza (0,5) em vez de
  fingir meio-acerto — confirmado: as duas afirmações vieram como
  incerteza (0,5/0,5), registrado como 0 acertos em 2, não maquiado.
- [x] SO-03 mede a ordenação real contra a expectativa (`r7g` no topo) —
  **se o modelo errar, isso é resultado, não falha de execução** (o plano
  previa isso explicitamente): confirmado, a execução oficial (`testes.sh`)
  produziu `m7g > c7g > r7g > t4g` — ordenação **incoerente** com o
  requisito de memória, registrado sem maquiagem no §8.
- [x] SO-04 mostra evidência real em `/spend/logs` e `/key/info` para a
  chave `cenario-08`, criada com `max_budget` baixo e **apagada ao final
  do `testes.sh`** — confirmado (`{"deleted":["sk-..."]}`, seguido de
  `GET /key/info` → HTTP 404 para a mesma chave).
- [x] SO-05 tabula decisão modal e variância de 10 repetições reais (sem
  simulação) — confirmado, com o parâmetro de amostragem (`temperature`)
  registrado com honestidade: o `system-one-adapter` não expõe controle de
  temperatura na sua interface pública, então as 10 repetições rodaram no
  default do backend, não em `temperature=0` — a variância observada é a
  do pipeline real, não de um piso artificial (ver `dados/so05_consistencia.py`).
- [x] Todas as chamadas do motor usam a chave virtual do cenário
  (`cenario-08`), nunca a master key — confirmado nos scripts (`API_KEY`
  vem de `key/generate`, nunca de `LITELLM_MASTER_KEY`).
- [x] Gateway termina o cenário saudável (`GET /health/readiness` → `200`,
  `db: connected`) e sem chave de teste órfã (`GET /key/list` conferido).

## 7. Roteiro de demonstração

1. Rodar `dados/so01_choice.py` ao vivo — mostrar a decisão tipada válida
   (uma das 4 opções) com o vetor de probabilidades completo, o contraste
   central do cenário: nada de parsear texto do modelo.
2. Rodar `dados/so03_score.py` ao vivo — este é o passo mais honesto da
   demo: mostrar a ordenação real que sair (pode ou não colocar `r7g` no
   topo, já que há variância real de execução — ver §8) e a decisão de
   **não esconder** um resultado incoerente quando ele acontece.
3. Consultar `/spend/logs?api_key=...` para a chave usada nos dois passos
   acima — mostrar que as duas decisões tipadas aparecem no mesmo log
   unificado de qualquer chamada de chat dos cenários 01–07.
4. Apontar a UI (`http://localhost:4000/ui/logs`) filtrando pela chave da
   demo, e fechar com o veredito geral do §8: paradigma funciona 100%
   local e governado; a confiabilidade do modelo pequeno, não.
   Script executável: `demo.sh` (`DEMO_AUTO=1` pula os `ENTER`).

## 8. Análise de resultados

Execução real em 2026-09-23, ambiente local
(`docker compose -f poc/docker-compose.yml`), gateway `poc-gateway`
(`ghcr.io/berriai/litellm:main-stable`), `LITELLM_MASTER_KEY` da PoC.
Motor: `system-one-adapter==0.2.1` + `typesafe-sdk==0.7.1` (venv isolado,
`dados/.venv`), `OpenAIProvider` apontado a `$GATEWAY/v1`. Modelo:
`local-hermes` (llama.cpp, host `:8090`, respondeu normalmente —
`local-qwen` não foi necessário nesta execução). Chave virtual
`cenario-08` (`max_budget: 2.0`, `duration: 6h`), apagada ao final.
`structured_outputs=True` (response_format JSON Schema `strict`) funcionou
de primeira contra `local-hermes` — achado positivo não previsto: um
servidor `llama.cpp` (`system_fingerprint` do build `b10809`) honra o modo
estrito de saída estruturada da API OpenAI, não só provedores de nuvem.

### Saída real do script (`testes.sh`, íntegra em `evidencias/`)

```
== SO-01 — choice ==
{"decisao":"r7g","decisao_e_opcao_valida":true,"confidence":0.333,"soma_probabilities":1.0}
probabilities: {"m7g":0.15,"c7g":0.25,"r7g":0.5,"t4g":0.1}

== SO-02 — noul ==
{"af1":"incerto (nao conta como acerto)","af2":"incerto (nao conta como acerto)","acertos":0,"total":2}
afirmacao_1.noul=0.5 (gabarito: verdadeiro) | afirmacao_2.noul=0.5 (gabarito: falso)

== SO-03 — score ==
{"scores":{"r7g":0.15,"c7g":1.40,"m7g":2.15,"t4g":0.05},"r7g_no_topo":false,
 "ordenacao_coerente_r7g_acima_c7g_e_m7g":false}
ordenacao real: m7g > c7g > r7g > t4g

== SO-04 — governança ==
{"chave":"sk-...(alias cenario-08)","n_chamadas_no_log_unificado":13,
 "modelos_usados":["openai/hermes-local"],"spend_acumulado":0.0,"max_budget":2.0}
-- chave apagada: {"deleted":["sk-..."]}
-- confirmação: GET /key/info da chave apagada -> HTTP 404

== SO-05 — consistência (SO-01 repetido 10x) ==
decisoes: [m7g,m7g,m7g,m7g,m7g,m7g,m7g,c7g,m7g,m7g]
{"decisao_modal":"m7g","frequencia_decisao_modal":9,"estabilidade_decisao_modal":0.9,
 "confidence_media":0.5362,"confidence_desvio_padrao":0.2384,"erros_de_execucao":0}
variancia_probabilidades_por_opcao.m7g: {"media":0.6299,"desvio_padrao":0.2194}

== Saúde final do gateway ==
{"status":"healthy","db":"connected"} -- gateway saudável
```

### Veredito por caso

| ID | Veredito | Evidência |
|---|---|---|
| SO-01 | **Passa** — decisão (`r7g`) é uma opção válida do conjunto, probabilidades somam exatamente 1,0. Nenhum "gabarito" era exigido aqui (ver `dados/demanda-arquitetura.md`) — mas vale notar que a confiança (0,333) é baixa e, mais adiante (SO-05), a decisão modal em 10 repetições foi outra (`m7g`) — a instabilidade já aparece antes mesmo do caso dedicado a medi-la. | `evidencias/SO-01.json` |
| SO-02 | **Passa como teste — achado é o resultado: 0 acertos em 2, ambas "incertas" (0,5)**. Isoladamente, em testes exploratórios durante o desenho do caso, o mesmo modelo respondeu a afirmação do S3 corretamente (`noul=1.0`) quando perguntada sozinha, com frase ligeiramente diferente — mas a execução **oficial** registrada aqui (2 perguntas na mesma chamada, texto final de `dados/afirmacoes-noul.md`) produziu incerteza nas duas. Não maquiamos o resultado bom do teste exploratório sobre o resultado real da execução oficial. | `evidencias/SO-02.json` |
| SO-03 | **Passa como teste — o achado é a ordenação incoerente, aceito e documentado**: `m7g` (uso geral) pontuou mais alto que `r7g` (a família literalmente desenhada para memória), que por sua vez ficou quase empatada com `t4g` (a opção mais fraca do conjunto). O critério de aceite do plano previa exatamente este desfecho como resultado válido — "se o modelo local errar a ordenação, isso É resultado, documente" — e é isso que está registrado aqui. | `evidencias/SO-03.json` |
| SO-04 | **Passa** — 13 chamadas da chave `cenario-08` aparecem no log unificado do gateway (mesmo endpoint `/spend/logs` usado nos cenários 01–07), `spend_acumulado: 0.0` (esperado — modelos locais não têm custo por token no `config.yaml`), `max_budget` aplicado e consultável via `/key/info`, chave apagada e confirmada inacessível (HTTP 404) ao final. A decisão tipada herda a mesma trilha de auditoria de qualquer chamada de chat. | `evidencias/SO-04.json` |
| SO-05 | **Passa como teste — achado central para P9: a decisão NÃO é estável o bastante para automação sem revisão**. Decisão modal `m7g` com 90% de frequência (9/10) — mas isso significa que **a decisão "oficial" de SO-01 (`r7g`) foi a MINORIA estatística** das 11 execuções totais deste cenário (1 de SO-01 + 10 de SO-05): rodando a mesma pergunta de novo, o motor teria discordado de si mesmo em ~9 de cada 10 vezes. `confidence` variou de 0,185 a 0,927 (desvio-padrão 0,238) — mesmo dentro da decisão majoritária, a confiança declarada é instável. | `evidencias/SO-05.json` |

### Achados

1. **O paradigma funciona de ponta a ponta, 100% local e governado — a
   parte "mecânica" do cenário é um sucesso sem ressalva.** Um motor real
   (`system-one-adapter`, não um mock) produzindo decisões tipadas e
   validadas por schema (`Choice`/`Score`/`Noul` do `typesafe-sdk`) contra
   um LLM que roda inteiramente no host (`local-hermes`, llama.cpp,
   nenhum dado sai do ambiente), passando pelo NOSSO gateway com
   autenticação por chave virtual, log unificado e orçamento — sem
   nenhuma dependência de SaaS de terceiro (nem da própria TypeSafe, cujo
   SDK original foi só reaproveitado pelo tipo, não pela chamada de rede).
   Isso confirma que "decisão tipada soberana" é uma capacidade real e
   catalogável do framework (P3), não uma promessa teórica.
2. **A confiabilidade do modelo pequeno é o gap real, e ele aparece em
   TRÊS ângulos diferentes e independentes do mesmo cenário — não é um
   caso isolado.** SO-02 (0 acertos em 2 afirmações factuais bem
   definidas), SO-03 (ordenação de adequação ao contrário do esperado) e
   SO-05 (a decisão "oficial" de SO-01 foi estatisticamente a minoria em
   11 execuções da mesma pergunta) convergem para a mesma conclusão por
   caminhos independentes: um modelo de ~34B rodando localmente via
   llama.cpp, sem nenhum ajuste fino para o domínio AWS/FinOps, não produz
   decisões tipadas confiáveis o bastante para automação de baixo risco
   sem revisão humana — **isso é uma característica do modelo escolhido,
   não do mecanismo de decisão tipada em si** (o schema, a validação e a
   governança funcionaram perfeitamente nos 5 casos; o que variou foi
   sempre o *conteúdo* da decisão). Para produção, a implicação é: (a) um
   modelo maior/mais capaz (ou um motor dedicado como o Laya, fine-tunado
   para o domínio) tende a resolver isso sem mudar nada da integração com
   o gateway; ou (b) decisão tipada de baixa confiança deve ser tratada
   como um sinal para roteamento a revisão humana (o próprio campo
   `confidence`, sempre presente na resposta, é exatamente o mecanismo que
   permitiria essa política — não seria preciso inventar um campo novo).
3. **O teste de orçamento (P2) não tem como falhar com um modelo
   gratuito — uma limitação conhecida do desenho do teste, não um gap do
   gateway.** `max_budget: 2.0` foi configurado e é consultável, mas como
   `local-hermes`/`local-qwen` não têm `input_cost_per_token`/
   `output_cost_per_token` no `config.yaml`, o `spend` de 13 chamadas
   reais ficou em `0.0` — o corte automático (`budget_exceeded`, já
   comprovado nos cenários 02/07 com o modelo `simulado`) nunca seria
   disparado por este cenário especificamente, porque o requisito de
   soberania (modelo 100% local) e o requisito de FinOps mensurável
   (custo por token > 0) empurram em direções opostas para este caso de
   teste. O mecanismo de corte já está provado noutro cenário; aqui só se
   confirma que ele *se aplicaria* (o campo existe, é lido corretamente).

### Veredito geral

O cenário confirma a tese central com uma divisão limpa entre **mecanismo**
e **conteúdo**: o mecanismo de decisão tipada soberana e governada — schema
validado, motor real, gateway próprio, chave virtual, log unificado — **passa
integralmente**, sem nenhuma ressalva; já o *conteúdo* das decisões
produzidas por um modelo local pequeno (~34B, sem fine-tuning de domínio)
**não é confiável o bastante para automação sem revisão humana**, confirmado
de três formas independentes (gabarito factual, ordenação de adequação,
consistência entre repetições). A recomendação para a arquitetura é usar
este padrão (motor tipado + gateway soberano) já em produção para os usos
onde `confidence` baixo ou decisão inconsistente pode ser roteado para
revisão humana sem risco, e reavaliar com um modelo maior — ou com o Laya
(§3, item 1, o motor dedicado que existia mas foi descartado só por não
atravessar o gateway) rodando como serviço próprio de decisão, sem LLM no
caminho — antes de confiar decisão tipada de alto risco a este pipeline sem
supervisão.

## 9. Referências

- [TypeSafe — Documentação de conceitos](https://docs.typesafe.ai/) —
  base conceitual do System One e dos três tipos de pergunta
  (`choice`/`score`/`noul`); página de rubrica de `Score`
  (`docs.typesafe.ai/primitives/score.md`) usada para confirmar a
  semântica de `criteria` (níveis ordinais de um rubrica, não itens
  comparados).
- [LiteLLM — pass-through TypeSafe](https://docs.litellm.ai/docs/pass_through/typesafe) —
  a perna Jev SaaS (fora de escopo aqui, registrada como "pronta para
  execução" quando houver chave de early access — ver plano mestre).
- [`typesafe-ai/system-one-adapter-python`](https://github.com/typesafe-ai/system-one-adapter-python)
  (MIT) e [`typesafe-ai/typesafe-sdk-python`](https://github.com/typesafe-ai/typesafe-sdk-python)
  (MIT) — motor usado nos 5 casos, verificados contra a API do GitHub e o
  PyPI direto (§3).
- [`NandhaKishorM/laya`](https://github.com/NandhaKishorM/laya)
  (Apache-2.0) e pacote [`laya`](https://pypi.org/project/laya/) no PyPI —
  motor dedicado verificado como real (§3, item 1), mas não usado neste
  cenário por não atravessar nenhuma API (item 2).
- [Cenário 07 — Visão de Tooling](../07-tooling/README.md) — mesmo padrão
  de log unificado (`/spend/logs`) e criação/exclusão de chave virtual de
  teste reaproveitado aqui em SO-04.
- [Spec de avaliação](../../../docs/specs/2026-09-10-avaliacao-litellm-design.md)
  e framework de governança de IA
  (pilares P1–P12).
