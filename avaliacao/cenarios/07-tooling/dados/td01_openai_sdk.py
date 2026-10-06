#!/usr/bin/env python3
"""TD-01 — SDK OpenAI oficial apontado ao gateway (compatibilidade de base_url).

Não gerencia a chave (criação/exclusão ficam em testes.sh, via curl, no
mesmo padrão dos outros scripts do cenário) — este script só exercita o
SDK `openai` de verdade contra o gateway, para provar (ou refutar) que o
gateway é um substituto "drop-in" do endpoint OpenAI oficial.

Variáveis de ambiente esperadas:
  GATEWAY   - base do gateway, ex.: http://localhost:4000 (sem /v1)
  API_KEY   - chave virtual restrita já criada por testes.sh
  MODEL     - model_name a chamar (ex.: fronteira-haiku)
"""
import json
import os
import sys

from openai import OpenAI

gateway = os.environ.get("GATEWAY", "http://localhost:4000")
api_key = os.environ["API_KEY"]
model = os.environ.get("MODEL", "fronteira-haiku")

client = OpenAI(api_key=api_key, base_url=f"{gateway}/v1")

resp = client.chat.completions.create(
    model=model,
    max_tokens=60,
    messages=[
        {"role": "user", "content": "Responda em pt-BR, em 1 frase curta: o que é um gateway de IA?"}
    ],
)

out = {
    "sdk": "openai",
    "sdk_version": __import__("openai").__version__,
    "base_url_usado": f"{gateway}/v1",
    "model": resp.model,
    "id": resp.id,
    "finish_reason": resp.choices[0].finish_reason,
    "content": resp.choices[0].message.content,
    "usage": resp.usage.model_dump() if resp.usage else None,
}
print(json.dumps(out, ensure_ascii=False, indent=2))
