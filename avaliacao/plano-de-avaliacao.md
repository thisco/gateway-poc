# Plano de avaliação — LiteLLM × framework de governança

**Contexto:** [spec de avaliação](../docs/specs/2026-09-10-avaliacao-litellm-design.md) ·
framework de governança ·
[PoC do gateway](../poc/README.md)

## Escopo

Fase 1: sete cenários sobre o LiteLLM já usado na PoC — **Guardrails**,
**Policies**, **MCP Gateway**, **Vector Stores**, **Skills** e **Agentes
(A2A) e Tool Calling**. Fase 2: os **mesmos cenários e os mesmos IDs de
caso de teste** aplicados ao **OmniRoute** (self-hosted, MIT), para
comparação 1:1.

**Regra de dependência: a fase 2 só inicia após os cenários da fase 1
estarem desenhados e produzidos** (README, `testes.sh`, dados e evidências
completos, matriz consolidada preenchida). O plano comparativo do OmniRoute
(`fase2-omniroute/plano-comparativo.md`) pode nascer na fase 1 com a matriz de
equivalência, mas sua execução aguarda o gate.

## Matriz cenário × pilar

| # | Cenário | Casos de teste principais | Pilares |
|---|---|---|---|
| 01 | **Guardrails** (Presidio) | Mascaramento de CPF/CNPJ em entrada; detecção de injeção de prompt; `logging_only` vs bloqueio; guardrail por chave | P5, P6 |
| 02 | **Policies** | Política global de guardrails; herança (`inherit`); anexação por time/chave → documentar gap Enterprise | P5, P10 |
| 03 | **MCP Gateway** | Registrar servidor MCP; listar/chamar tools via gateway; permissão por chave/time; auditoria da chamada de tool | P1, P4, P5 |
| 04 | **Vector Stores** (pgvector) | Criar store; ingerir documento; buscar; RAG via chat com `vector_store_ids`; controle de acesso | P3, P6 |
| 05 | **Skills** | Criar skill customizada no proxy; busca semântica de skills; uso de skill em chamada | P3, P9 |
| 06 | **Agentes (A2A) e Tool Calling** | AG-01..04, TL-01..03 | P1, P3, P4, P5 |

## Critérios gerais de aceite

Todo caso de teste, em qualquer cenário, só é dado por concluído se:

- **Reproduzível por script** — o caso roda via `testes.sh` (curl) sem passo
  manual não documentado; passos exclusivamente de UI ficam no roteiro de
  demonstração, não substituem o script.
- **Evidência versionada** — print e/ou JSON de resposta capturado em
  `cenarios/NN-nome/evidencias/`, referenciável por link relativo na matriz
  consolidada.
- **Veredicto explícito** — passa, falha, gap (recurso ausente ou
  Enterprise-only) ou condicional (depende de credencial externa opcional);
  nunca deixado em aberto.
- **Mapeamento a pilar preenchido** — todo caso aponta para ao menos um dos
  pilares P1–P12 do framework de governança, refletido na matriz consolidada.

## Ambiente

| Item | Valor |
|---|---|
| LiteLLM | imagem `ghcr.io/berriai/litellm:main-stable`, digest `sha256:c8756e7b9a61fe45df2ccb5b781d388c3b2f3a21ef9e4956630caef20f9f03aa`, build criada em `2026-09-06T02:45:02Z` (data do `docker inspect poc-gateway`, Task 8, 2026-09-10). Versão do pacote `litellm`: **`1.100.0`** — confirmada em `openapi.json` (`info.version`) e no `METADATA` do pacote instalado no container (`pip show litellm`); `GET /health/readiness` com a master key **não** retorna o campo `litellm_version` nesta build (só `{"status": "healthy", "db": "connected"}`), diferente do presumido no plano original — a versão foi obtida pelas duas fontes alternativas acima. O container também traz `litellm_enterprise==0.1.62` já instalado (mesmo sendo a imagem `main-stable`, não uma tag Enterprise separada) — dado relevante para o achado de PO-03 (cenário 02) sobre anexação de policy por time ter funcionado sem cobrança de licença. |
| Guardrails | Presidio auto-hospedado (`presidio-analyzer` + `presidio-anonymizer`), profile `guardrails` |
| Vector store | pgvector no PostgreSQL da PoC + conector `litellm-pgvector` + embeddings `nomic-embed-text` (Ollama), profile `vectors` |
| Hardware | máquina de desenvolvimento local usada na PoC (sem requisito de GPU; modelo de embedding roda em CPU) |

A versão exata do LiteLLM testada (digest da imagem e versão do pacote) foi
registrada na linha acima pela Task 8, em 2026-09-10, no momento da
consolidação de resultados.

## Fases e ordem

1. **Task 1** (este documento) — estrutura base de `avaliacao/`: README,
   plano mestre, esqueleto da matriz consolidada.
2. **Task 2** — infra de avaliação no `docker-compose.yml` (profiles
   `guardrails` e `vectors`) e modelos de apoio (`embedding-nomic`).
3. **Tasks 3–7** — um cenário por task, na ordem da matriz acima: Guardrails,
   Policies, MCP Gateway, Vector Stores, Skills. Cada task produz o README de
   9 seções, `testes.sh`, dados de teste e evidências do respectivo cenário.
4. **Task 8** — consolidação: preenche `resultados/matriz-consolidada.md`
   com os 29 casos executados (os 22 dos cinco cenários originais mais os 7
   do cenário 06 — Agentes A2A e Tool Calling, adicionado depois) e registra
   a versão exata do LiteLLM testada.
5. **Task 9** — leva veredictos e evidências para os slides da apresentação
   executiva (`docs/apresentacao/apresentacao-governanca-ia.md`).
6. **Task 10** — fase 2: plano comparativo do OmniRoute
   (`fase2-omniroute/plano-comparativo.md`), com gate de "fase 1 concluída"
   antes de qualquer execução.

## Gate — fase 1 → fase 2

- [x] **Fase 1 concluída em 2026-09-10** — seis cenários (Guardrails,
  Policies, MCP Gateway, Vector Stores, Skills, Agentes A2A e Tool Calling),
  29 casos de teste executados e registrados em
  [`resultados/matriz-consolidada.md`](resultados/matriz-consolidada.md),
  slides da apresentação executiva produzidos (Task 9).
- [x] **Extensões pós-gate (2026-09-11)** — cenário 05 estendido com skills
  de mercado (SK-05/SK-06) e cenário 07 — Visão de Tooling (TI/TC/TD)
  adicionados a pedido; a suíte passa a ter **sete cenários e 40 casos**,
  todos na matriz consolidada. A matriz de equivalência da fase 2 cobre os
  29 casos originais; os 11 novos entram na equivalência quando a fase 2
  executar.
- [x] **Fase 2 pronta para execução** — plano comparativo do OmniRoute com
  matriz de equivalência para os 29 casos escrito em
  `fase2-omniroute/plano-comparativo.md`
  (Task 10). Nenhum container OmniRoute foi subido e nenhum arquivo de
  ambiente (`docker-compose.yml`, `config.yaml`) foi alterado — a execução
  real dos casos contra o OmniRoute é o próximo passo, não coberto por esta
  marcação de gate.

## Riscos

- **Recurso atrás de licença Enterprise-only.** Não é motivo para pular o
  caso de teste: o caso é executado até onde a versão OSS permite, e a
  limitação vira achado documentado (veredicto "gap") na matriz consolidada e
  na análise de resultados do cenário — insumo direto para a decisão de
  compra/arquitetura na apresentação.
- **Drift de documentação do LiteLLM.** A documentação oficial referenciada
  nos cenários pode mudar entre o desenho e a execução dos testes. Mitigação:
  registrar a versão exata testada (ver seção Ambiente) e citar o link da
  documentação consultada em cada `README.md` de cenário (seção
  Referências), para que qualquer divergência futura seja rastreável à
  versão usada nesta avaliação.
