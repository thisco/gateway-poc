# PoC — Gateway de IA governado

Prova de conceito da arquitetura de governança de IA: um gateway central por onde
passa todo o consumo de IA da organização, com identidade, orçamento, catálogo de
modelos e auditoria. Implementação de referência: LiteLLM + PostgreSQL + Ollama.

## Subir o ambiente

```bash
cp .env.example .env        # preencha as chaves (ANTHROPIC_API_KEY é opcional)
docker compose up -d
docker exec poc-ollama ollama pull qwen2.5:0.5b   # modelo local (~400 MB, uma vez)
```

- Gateway (API OpenAI-compatible): http://localhost:4000
- UI administrativa: http://localhost:4000/ui — login `admin` + valor de `LITELLM_MASTER_KEY`

## Profiles de avaliação

Serviços de apoio à avaliação de cenários (ver `../avaliacao/`) ficam atrás de
[profiles do Docker Compose](https://docs.docker.com/compose/how-tos/profiles/) —
não sobem com `docker compose up -d` normal, então a demo básica continua
funcionando sem eles.

```bash
docker compose --profile guardrails up -d          # Presidio (cenário 01)
docker compose --profile vectors up -d             # pgvector + conector (cenário 04)
docker exec poc-ollama ollama pull nomic-embed-text  # embeddings locais (uma vez)
```

- `guardrails` — sobe `presidio-analyzer` e `presidio-anonymizer` (detecção e
  mascaramento de PII auto-hospedados), usados no cenário 01 de avaliação.
- `vectors` — sobe `db-vectors` (Postgres + pgvector) e `vector-connector`
  (API de vector store OpenAI-compatible na porta 8002 do host — porta
  interna, usada pelo gateway, continua 8000; 8001 conflita com um projeto
  local não relacionado nesta máquina de avaliação, ver
  `poc/docker-compose.yml`), usados no cenário 04 para testar um vector
  store soberano com embeddings locais. Depois de subir o profile, rode
  `bash ../avaliacao/cenarios/04-vector-stores/setup.sh` (setup idempotente:
  extensão `vector`, migração de schema, ajuste de dimensão do vetor e
  criação/reuso do store — ver o README do cenário §3.1).

Detalhes de cada cenário: [`../avaliacao/`](../avaliacao/).

## Catálogo de modelos (3 camadas)

| Modelo no gateway | Camada | Argumento de governança |
|---|---|---|
| `fronteira-sonnet` | SaaS de fronteira | Realismo: multi-provider com chave centralizada, nunca na mão do usuário |
| `fronteira-haiku` | SaaS de fronteira (Anthropic, econômico) | Preço explícito (US$ 1,00/5,00 por 1M tokens in/out) — FinOps fiel |
| `fronteira-gpt-nano` | SaaS de fronteira (OpenAI, gpt-5-nano) | Preço explícito (US$ 0,05/0,40 por 1M tokens in/out) — FinOps fiel |
| `fronteira-deepseek-flash` | SaaS de fronteira (DeepSeek, V4.1-Flash, 1M ctx) | Multi-provider de verdade: 3º provedor SaaS; **fora da jurisdição brasileira** — apenas dados públicos |
| `fronteira-deepseek-pro` | SaaS de fronteira (DeepSeek, V4-Pro, 1M ctx) | Idem; preço vem do mapa nativo do LiteLLM (US$ 1,32/3,96 por 1M in/out) |
| `local-hermes` | Modelo aberto (~34B) no host (llama.cpp em `127.0.0.1:8090`) | Soberania com qualidade real: o dado não sai da máquina |
| `local-qwen` | Modelo aberto pequeno no container | Soberania portátil: demo funciona em qualquer máquina, sem o servidor do host |
| `sandbox-*` (18 modelos, 14 ativos) | Modelos free OpenRouter — sandbox, apenas dados públicos | Custo zero: explora catálogo multi-provider sem gasto real; SaaS sem soberania. Revalidado em 2026-09-25: 4 indisponíveis (`nex-*` descatalogados, `inkling*` restritos a agentic harnesses) — ver comentário no `config.yaml` |
| `simulado` | Mock | Resiliência: a demo de governança funciona sem nenhum provedor |

## Memória do Docker

O gateway LiteLLM usa ~950 MiB em regime e pede mais no startup; o Ollama chega
a ~900 MiB com um modelo carregado. Com o limite padrão do Docker Desktop
(4,8 GiB nesta máquina) e outros projetos no ar, o gateway é morto pelo OOM
killer no momento em que o Ollama carrega um modelo — `docker inspect
poc-gateway --format '{{.State.OOMKilled}}'` confirma. Sintoma característico:
`curl` devolve HTTP 000 instantaneamente (conexão recusada, não timeout).
Folga recomendada: 8 GiB, ou derrube os profiles de avaliação (`presidio`,
`vectors`) que não estiverem em uso.

## Roteiro da demo (cada passo vira print)

1. **Perfis** — na UI, criar dois times: `equipe-dev` (todos os modelos, budget USD 50/mês)
   e `perfil-restrito` (apenas `local-qwen` e `simulado`, budget USD 1/mês).
   Gerar uma chave virtual para cada.
2. **Bloqueio de modelo** — com a chave do `perfil-restrito`, chamar
   `fronteira-sonnet` → o gateway nega (modelo fora do perfil).
3. **Estouro de orçamento** — reduzir o budget do `perfil-restrito` para um valor
   simbólico já consumido → próxima chamada é cortada automaticamente.
4. **Custo por equipe** — dashboard de gastos (Usage) segmentado por time/chave.
5. **Auditoria** — abrir o log de uma chamada: quem, quando, qual modelo, quantos
   tokens, custo.
6. **Assistente de codificação governado** — apontar o assistente (endpoint
   OpenAI-compatible `http://localhost:4000` + chave virtual) e usá-lo passando
   pelo gateway, herdando perfil, orçamento e auditoria.

Chamada de teste rápida:

```bash
curl -s http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer <CHAVE_VIRTUAL_OU_MASTER>" \
  -H "Content-Type: application/json" \
  -d '{"model": "simulado", "messages": [{"role": "user", "content": "olá"}]}'
```

## Encerrar

```bash
docker compose down          # mantém dados (volumes)
docker compose down -v       # apaga tudo
```
