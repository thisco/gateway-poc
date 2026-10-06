# Avaliação de funcionalidades — Gateway de IA

Suíte de avaliação documentada e reproduzível das funcionalidades avançadas do
LiteLLM — **Guardrails, Policies, MCP Gateway, Vector Stores, Skills,
Agentes (A2A) e Tool Calling**, mais um cenário transversal de **Visão de
Tooling** (inventário, tool calling avançado e dev tooling) e um cenário de
**Decisão tipada local** (System One — `choice`/`score`/`noul` soberano e
governado pelo gateway) — comparando
cada uma com as capacidades exigidas pelo
framework de governança de IA
(pilares P1–P12). A avaliação roda em cima da
[PoC do gateway](../poc/README.md) já existente, acrescentando apenas a infra
que cada cenário exige (via profiles do `docker-compose.yml`). O desenho
completo — decisões, estrutura de diretórios e template de cenário — está na
[spec de avaliação](../docs/specs/2026-09-10-avaliacao-litellm-design.md).

Em fase 2, os mesmos cenários são aplicados ao OmniRoute para comparação 1:1
(ver `fase2-omniroute/`). A fase 2 só inicia após os cenários da fase 1 (hoje oito)
estarem desenhados e produzidos.

## Navegação

| # | Cenário | Diretório | Pilares |
|---|---|---|---|
| 01 | Guardrails (Presidio) | [`cenarios/01-guardrails/`](cenarios/01-guardrails/) | P5, P6 |
| 02 | Policies | [`cenarios/02-policies/`](cenarios/02-policies/) | P5, P10 |
| 03 | MCP Gateway | [`cenarios/03-mcp/`](cenarios/03-mcp/) | P1, P4, P5 |
| 04 | Vector Stores (pgvector) | [`cenarios/04-vector-stores/`](cenarios/04-vector-stores/) | P3, P6 |
| 05 | Skills | [`cenarios/05-skills/`](cenarios/05-skills/) | P3, P9 |
| 06 | Agentes (A2A) e Tool Calling | [`cenarios/06-agentes-tools/`](cenarios/06-agentes-tools/) | P1, P3, P4, P5 |
| 07 | Visão de Tooling (Inventário, Tool Calling, Dev Tooling) | [`cenarios/07-tooling/`](cenarios/07-tooling/) | P2, P3, P4, P5, P12 |
| 08 | Decisão tipada local (System One) | [`cenarios/08-decisao-tipada/`](cenarios/08-decisao-tipada/) | P2, P3, P4, P9 |
| — | OmniRoute (fase 2) | `fase2-omniroute/` | mesmos pilares, por caso de teste |

Planejamento mestre (escopo, matriz cenário × pilar, critérios de aceite,
ambiente, riscos): [`plano-de-avaliacao.md`](plano-de-avaliacao.md).
Resultado consolidado: [`resultados/matriz-consolidada.md`](resultados/matriz-consolidada.md).

## Como executar

1. Subir a PoC base: `cd ../poc && docker compose up -d` (ver
   [`poc/README.md`](../poc/README.md) para variáveis de ambiente e catálogo
   de modelos).
2. Subir os profiles adicionais que o cenário exigir, por exemplo:
   `docker compose --profile guardrails up -d` (Presidio, cenário 01) ou
   `docker compose --profile vectors up -d` (pgvector, cenário 04).
3. Entrar no diretório do cenário e rodar o script reproduzível:
   `cd cenarios/01-guardrails && ./testes.sh`.
4. Evidências (prints, JSON capturado) ficam versionadas em
   `cenarios/NN-nome/evidencias/`; o veredicto de cada caso é registrado no
   próprio `README.md` do cenário e depois consolidado em
   `resultados/matriz-consolidada.md`.

## Live demo

Cada cenário tem, além do `testes.sh` (reprodução/evidência dos casos
completos), um roteiro enxuto para apresentar **ao vivo**: um `demo.sh`
(terminal, 2-3 casos de maior impacto, com pausa por `ENTER` entre passos)
e um `roteiro-playground.md` (o mesmo roteiro, mas clicável no navegador —
Playground da UI onde ele expõe o recurso, ou terminal + telas da UI
quando não expõe, sempre registrando o que foi validado de verdade contra
esta build). Os dois terminam na mesma conclusão de governança do
`README.md` do cenário e apontam a tela de Logs/Usage que comprova.

| # | Cenário | `demo.sh` | `roteiro-playground.md` | Slide |
|---|---|---|---|---|
| 01 | Guardrails | [`demo.sh`](cenarios/01-guardrails/demo.sh) | [`roteiro-playground.md`](cenarios/01-guardrails/roteiro-playground.md) | Slide 19 — Cenário 01: Guardrails (Presidio) |
| 02 | Policies | [`demo.sh`](cenarios/02-policies/demo.sh) | [`roteiro-playground.md`](cenarios/02-policies/roteiro-playground.md) | Slide 20 — Cenário 02: Policies |
| 03 | MCP Gateway | [`demo.sh`](cenarios/03-mcp/demo.sh) | [`roteiro-playground.md`](cenarios/03-mcp/roteiro-playground.md) | Slide 21 — Cenário 03: MCP Gateway |
| 04 | Vector Stores | [`demo.sh`](cenarios/04-vector-stores/demo.sh) | [`roteiro-playground.md`](cenarios/04-vector-stores/roteiro-playground.md) | Slide 22 — Cenário 04: Vector Stores (pgvector) |
| 05 | Skills | [`demo.sh`](cenarios/05-skills/demo.sh) | [`roteiro-playground.md`](cenarios/05-skills/roteiro-playground.md) | Slide 23 — Cenário 05: Skills |
| 06 | Agentes (A2A) e Tool Calling | [`demo.sh`](cenarios/06-agentes-tools/demo.sh) | [`roteiro-playground.md`](cenarios/06-agentes-tools/roteiro-playground.md) | Slide 24 — Cenário 06: Agentes (A2A) e Tool Calling |
| 07 | Visão de Tooling | [`demo.sh`](cenarios/07-tooling/demo.sh) | [`roteiro-playground.md`](cenarios/07-tooling/roteiro-playground.md) | Slide 25 — Cenário 07: Visão de Tooling |
| 08 | Decisão tipada local | [`demo.sh`](cenarios/08-decisao-tipada/demo.sh) | — (sem tela própria no Playground — o motor roda por script, ver README §7) | Slide 26 — Cenário 08: Decisão tipada local |

`avaliacao/demo-completa.sh` encadeia os 8 (menu `1`-`8`, `t` para todos
em sequência, `q` para sair). Toda variável `DEMO_AUTO=1` pula os `ENTER`
de cada passo — útil para validação/ensaio sem plateia:

```bash
cd poc && docker compose --profile guardrails --profile vectors --profile agents up -d
set -a; source .env; set +a
cd .. && bash avaliacao/demo-completa.sh          # menu interativo
DEMO_AUTO=1 bash avaliacao/demo-completa.sh <<< t # roda os 8, sem pausas
```

Pré-checagens de cada `demo.sh` conferem gateway saudável, `LITELLM_MASTER_KEY`
exportada e os profiles/containers que aquele cenário específico exige
(ex.: `guardrails` para os cenários 01/02, `vectors` + `.store-id` para o
04, `agents` para o 06) — com a mensagem de correção exata se algo faltar.

## Metodologia

Cada cenário segue um template padronizado de 9 seções, definido na
[spec §4](../docs/specs/2026-09-10-avaliacao-litellm-design.md#4-template-padronizado-de-cenário):

1. **Objetivo** — o que o recurso faz e por que importa para a governança
2. **Mapeamento ao framework** — pilares (P1–P12) e princípios evidenciados
3. **Planejamento** — pré-requisitos, infra, configuração necessária
4. **Dados de análise** — payloads de teste com justificativa (sempre
   sintéticos: CPF/CNPJ gerados, nunca dados reais)
5. **Casos de teste** — tabela com ID (`GR-01`, `PO-01`, `MC-01`, `VS-01`,
   `SK-01`…), descrição, passos e resultado esperado
6. **Critérios de aceite** — checklist objetivo (passa/falha)
7. **Roteiro de demonstração** — passo a passo UI/curl para apresentar ao vivo
8. **Análise de resultados** — preenchido após execução: o que passou, gaps,
   veredicto e implicação para o framework
9. **Referências** — documentação oficial e projetos usados como base

Todo recurso disponível apenas na licença Enterprise do LiteLLM é testado até
onde a versão OSS permite e documentado como achado (gap), não descartado —
ver critérios gerais de aceite no plano mestre.
