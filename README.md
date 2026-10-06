# gateway-poc

Gateway de IA de referência: **LiteLLM + PostgreSQL + Ollama**, com catálogo de
modelos, times, orçamento e chave virtual, mais a avaliação das funcionalidades
do gateway em **8 cenários e 45 casos de teste**, com evidências.

## O que é

- `poc/` — o gateway em Docker Compose. Todo consumo de IA passa por ele, com
  identidade (chaves virtuais), orçamento, catálogo de modelos em três camadas
  (SaaS de fronteira, modelos abertos locais e endpoint simulado) e auditoria.
- `avaliacao/` — suíte de avaliação reproduzível: guardrails, policies, MCP,
  vector stores, skills, agentes (A2A) e tool calling, tooling e decisão tipada
  local. Cada cenário tem README, `testes.sh`, `demo.sh`, dados e evidências.
- `docs/` — benchmark de gateways e spec de desenho da avaliação.

## Como subir

Requisitos: Docker com Compose. Reserve cerca de 8 GiB de memória para o Docker
(ver `poc/README.md`).

```bash
cd poc
cp .env.example .env        # troque as chaves; as chaves de provedores são opcionais
docker compose up -d
docker exec poc-ollama ollama pull qwen2.5:0.5b   # modelo local, uma vez
bash seed-demo.sh           # cria dois times e duas chaves virtuais
```

- API OpenAI-compatible: http://localhost:4000
- UI administrativa: http://localhost:4000/ui (login `admin` + `LITELLM_MASTER_KEY`)

Serviços de apoio à avaliação ficam em profiles (`guardrails`, `vectors`,
`agents`). Detalhes, catálogo de modelos e roteiro da demo em
[`poc/README.md`](poc/README.md).

## Avaliação

Resumo da [matriz consolidada](avaliacao/resultados/matriz-consolidada.md)
(snapshot de 2026-10-06; execuções entre 2026-09-10 e 2026-09-11, LiteLLM
`1.100.0`, imagem `main-stable`):

| # | Cenário | Casos |
|---|---|---|
| 01 | Guardrails (Presidio) | GR-01..05 |
| 02 | Policies | PO-01..04 |
| 03 | MCP Gateway | MC-01..04 |
| 04 | Vector Stores (pgvector) | VS-01..05 |
| 05 | Skills | SK-01..06 |
| 06 | Agentes (A2A) e Tool Calling | AG-01..04, TL-01..03 |
| 07 | Visão de Tooling | TI-01..03, TC-01..03, TD-01..03 |
| 08 | Decisão tipada local | SO-01..05 |

**Total: 8 cenários, 45 casos.** Metodologia, critérios de aceite e ambiente em
[`avaliacao/README.md`](avaliacao/README.md) e
[`avaliacao/plano-de-avaliacao.md`](avaliacao/plano-de-avaliacao.md).

Notas sobre o material:

- Os cenários citam pilares P1 a P12 de um framework de governança de IA que
  não faz parte deste repositório.
- A fase 2 (comparação com outro gateway) é citada nos textos, mas seu plano não
  está incluído.
- `avaliacao/plano-de-avaliacao.md` preserva o texto original do planejamento
  (contagens parciais de fases anteriores); os números finais são os da matriz.
- Dados de teste são sintéticos. Chaves virtuais nas
  evidências foram redigidas.

## Procedência

Snapshot de 2026-10-06 de um repositório interno de avaliação de gateway de IA,
sem o histórico original. Commit de origem: `bc9153311502128f03e74e901eb88351c79c42c0`.
O snapshot inclui as alterações não commitadas em `poc/` presentes na origem
naquela data. Foram removidos segredos e dados internos; o conteúdo da avaliação
(números e vereditos) não foi alterado.

## Licença

[MIT](LICENSE).
