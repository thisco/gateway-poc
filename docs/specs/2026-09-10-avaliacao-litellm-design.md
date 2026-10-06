# Avaliação de funcionalidades do LiteLLM × framework de governança — Design

**Data:** 2026-09-10 · **Status:** aprovado para implementação
**Contexto:** Arquitetura de Governança de IA · [PoC do gateway](../../poc/README.md) · [Benchmark de gateways](../benchmark-gateways.md)

## 1. Objetivo

Produzir uma suíte de avaliação documentada e reproduzível das funcionalidades
avançadas do LiteLLM — **Guardrails, Policies, MCP Gateway, Vector Stores e
Skills** — comparando cada uma com as capacidades exigidas pelo framework de
governança (pilares P1–P12), com evidências demonstráveis ao vivo na ferramenta.
O material compõe a apresentação executiva e fica versionado no git de forma
navegável.

Em fase posterior (fase 2), os **mesmos cenários** são aplicados ao
**OmniRoute** ([omniroute.online](https://www.omniroute.online/) — roteador de
IA open source, MIT, self-hosted) para comparação 1:1. A fase 2 só inicia após
os cinco cenários LiteLLM estarem desenhados e produzidos.

## 2. Decisões de design

| Decisão | Escolha | Justificativa |
|---|---|---|
| Localização | Diretório `avaliacao/` na raiz, irmão de `poc/` | Avaliação é metodologia + análise, não infra da PoC; fase 2 (OmniRoute) não pertence à PoC LiteLLM |
| Formato dos testes | Híbrido: scripts `curl` reproduzíveis + roteiro de demonstração na UI + evidências (prints/JSON) | Reproduzibilidade para auditoria; visual para apresentação |
| Backend de vetores | **pgvector** no PostgreSQL da PoC + conector [litellm-pgvector](https://github.com/BerriAI/litellm-pgvector) + embeddings locais (`nomic-embed-text` via Ollama) | OpenSearch não é suportado pelo LiteLLM; pgvector reusa o Postgres governado existente (soberania, um único ponto de backup/acesso); Milvus/RAGFlow adicionam stacks pesadas |
| Guardrails | **Presidio auto-hospedado** (analyzer + anonymizer) | Alinhado ao P5: "nenhum dado de cidadão transita por moderador SaaS de terceiro" |
| Infra adicional | Docker Compose **profiles** (`guardrails`, `vectors`) | Demo básica da PoC continua leve; avaliação sobe só o que precisa |
| Escopo OSS vs Enterprise | Testar o que é OSS; **documentar como achado** cada recurso atrás da licença Enterprise | O gap OSS/Enterprise (ex.: anexação de policy por time/chave) é insumo de decisão de compra/arquitetura para a apresentação |

## 3. Estrutura de diretórios

```
avaliacao/
├── README.md                    # visão geral, metodologia, como navegar
├── plano-de-avaliacao.md        # planejamento mestre: escopo, matriz cenário×pilar,
│                                #   critérios gerais, fases
├── cenarios/
│   ├── 01-guardrails/
│   │   ├── README.md            # template padronizado (§4)
│   │   ├── testes.sh            # scripts curl reproduzíveis
│   │   ├── dados/               # payloads de teste com justificativa
│   │   └── evidencias/          # prints da UI + respostas JSON capturadas
│   ├── 02-policies/
│   ├── 03-mcp/
│   ├── 04-vector-stores/
│   └── 05-skills/
├── fase2-omniroute/
│   └── plano-comparativo.md     # matriz de equivalência; execução após fase 1
└── resultados/
    └── matriz-consolidada.md    # cenário × resultado × pilar × gap OSS/Enterprise
```

## 4. Template padronizado de cenário

Todo `cenarios/NN-nome/README.md` segue exatamente estas seções:

1. **Objetivo** — o que o recurso faz e por que importa para a governança
2. **Mapeamento ao framework** — pilares (P1–P12) e princípios evidenciados
3. **Planejamento** — pré-requisitos, infra, configuração necessária
4. **Dados de análise** — payloads de teste com justificativa (dados sempre
   sintéticos: CPF/CNPJ gerados, nunca dados reais)
5. **Casos de teste** — tabela: ID (`GR-01`, `PO-01`, `MC-01`, `VS-01`, `SK-01`…),
   descrição, passos, resultado esperado
6. **Critérios de aceite** — checklist objetivo (passa/falha)
7. **Roteiro de demonstração** — passo a passo UI/curl para apresentar ao vivo
8. **Análise de resultados** — preenchido após execução: o que passou, gaps,
   veredicto e implicação para o framework
9. **Referências** — documentação oficial e projetos usados como base

## 5. Cenários da fase 1 (LiteLLM)

| # | Cenário | Casos de teste principais | Pilares |
|---|---|---|---|
| 01 | **Guardrails** (Presidio) | Mascaramento de CPF/CNPJ em entrada; detecção de injeção de prompt; `logging_only` vs bloqueio; guardrail por chave | P5, P6 |
| 02 | **Policies** | Política global de guardrails; herança (`inherit`); anexação por time/chave → documentar gap Enterprise | P5, P10 |
| 03 | **MCP Gateway** | Registrar servidor MCP; listar/chamar tools via gateway; permissão por chave/time; auditoria da chamada de tool | P1, P4, P5 |
| 04 | **Vector Stores** (pgvector) | Criar store; ingerir documento; buscar; RAG via chat com `vector_store_ids`; controle de acesso | P3, P6 |
| 05 | **Skills** | Criar skill customizada no proxy; busca semântica de skills; uso de skill em chamada | P3, P9 |

Referências principais: [guardrails](https://docs.litellm.ai/docs/proxy/guardrails/quick_start),
[guardrail policies](https://docs.litellm.ai/docs/proxy/guardrails/guardrail_policies),
[MCP](https://docs.litellm.ai/docs/mcp), [vector stores](https://docs.litellm.ai/docs/completion/knowledgebase),
[skills](https://docs.litellm.ai/docs/skills).

## 6. Infra adicional (poc/docker-compose.yml)

- `presidio-analyzer` + `presidio-anonymizer` — profile `guardrails`
- Conector `litellm-pgvector` — profile `vectors`
- Extensão pgvector no PostgreSQL existente (ou container `pgvector/pgvector`
  se a imagem atual não suportar a extensão)
- Modelo `nomic-embed-text` no Ollama existente (pull único)

## 7. Fase 2 — OmniRoute

O `plano-comparativo.md` nasce na fase 1 com a matriz de equivalência: para
cada caso de teste da fase 1, qual recurso do OmniRoute o cobre (ou não). A
execução espelha os mesmos IDs para comparação 1:1. Resultado alimenta o
benchmark de gateways existente.

## 8. Integração com a apresentação

Nova seção de slides em `docs/apresentacao/` com, por cenário: evidência
(print), veredicto e gap identificado → alimenta a decisão LiteLLM OSS vs
Enterprise vs alternativas.

## 9. Critérios de sucesso do projeto de avaliação

- [ ] 5 cenários com template completo, scripts executáveis e evidências no git
- [ ] Matriz consolidada cenário × pilar × resultado × gap preenchida
- [ ] Todo recurso Enterprise-only identificado e documentado como achado
- [ ] Slides da apresentação atualizados com evidências da avaliação
- [ ] Plano comparativo OmniRoute pronto para execução da fase 2
