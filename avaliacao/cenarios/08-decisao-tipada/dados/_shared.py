"""Boilerplate compartilhado pelos drivers so0N_*.py do cenário 08.

Lê GATEWAY / API_KEY / MODEL do ambiente (exportados pelo testes.sh) e monta
um SystemOneAdapterClient apontando para o NOSSO gateway (rota
OpenAI-compatible /v1, chave virtual do cenário) — não para nenhum serviço
de nuvem. Fica em dados/ (não em cenarios/08.../*.py na raiz) para seguir a
mesma convenção do cenário 07 (scripts de SDK em dados/, venv isolado em
dados/.venv, nada disso versionado exceto os próprios .py).
"""
from __future__ import annotations

import os

from system_one_adapter import SystemOneAdapterClient
from system_one_adapter.providers.openai import OpenAIProvider


def build_provider() -> OpenAIProvider:
    gateway = os.environ.get("GATEWAY", "http://localhost:4000")
    api_key = os.environ["API_KEY"]  # obrigatório — sem default silencioso
    model = os.environ.get("MODEL", "local-hermes")
    return OpenAIProvider(model, base_url=f"{gateway}/v1", api_key=api_key)


def build_client(*, structured: bool = True) -> SystemOneAdapterClient:
    # structured_outputs=True usa response_format json_schema (strict) da
    # rota /v1/chat/completions do gateway — confirmado funcional com
    # local-hermes (llama.cpp) nesta build, ver README §3. normalize_
    # probabilities=True evita que um vetor de probabilidade que não soma 1
    # (comum em modelos pequenos) derrube a chamada inteira.
    return SystemOneAdapterClient(
        structured_outputs=structured,
        llm_answer_mode="probabilities",
        normalize_probabilities=True,
        n_retry_malformed_structure=1,
    )
