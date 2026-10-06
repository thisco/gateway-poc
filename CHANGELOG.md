# Changelog

Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/).

## [0.1.0] - 2026-10-06

### Adicionado
- Gateway de IA de referência (`poc/`): LiteLLM + PostgreSQL + Ollama, com
  catálogo de modelos em três camadas (fronteira, local e simulado), times,
  orçamento e chaves virtuais (`seed-demo.sh`).
- Avaliação do gateway (`avaliacao/`): 8 cenários e 45 casos de teste, com
  scripts reproduzíveis, evidências, demos e matriz consolidada.
- Benchmark de gateways de IA (`docs/benchmark-gateways.md`) e spec de desenho
  da avaliação (`docs/specs/`).
