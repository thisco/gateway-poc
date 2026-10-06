#!/usr/bin/env python3
"""TD-02 — SDK Anthropic oficial via /v1/messages do gateway (rota nativa).

Mesma lógica do TD-01: a chave é gerenciada em testes.sh (curl); este
script só exercita o SDK `anthropic` de verdade contra o gateway, na rota
nativa (não a compatível com OpenAI), para provar que o gateway funciona
como substituto "drop-in" do endpoint api.anthropic.com para quem já usa
o SDK oficial.

Variáveis de ambiente esperadas:
  GATEWAY   - base do gateway, ex.: http://localhost:4000 (sem /v1)
  API_KEY   - chave virtual restrita já criada por testes.sh
  MODEL     - model_name a chamar (ex.: fronteira-haiku)
"""
import json
import os

import anthropic

gateway = os.environ.get("GATEWAY", "http://localhost:4000")
api_key = os.environ["API_KEY"]
model = os.environ.get("MODEL", "fronteira-haiku")

client = anthropic.Anthropic(api_key=api_key, base_url=gateway)

resp = client.messages.create(
    model=model,
    max_tokens=60,
    messages=[
        {"role": "user", "content": "Responda em pt-BR, em 1 frase curta: o que é um gateway de IA?"}
    ],
)

out = {
    "sdk": "anthropic",
    "sdk_version": anthropic.__version__,
    "base_url_usado": gateway,
    "model": resp.model,
    "id": resp.id,
    "stop_reason": resp.stop_reason,
    "content": resp.content[0].text if resp.content else None,
    "usage": resp.usage.model_dump() if resp.usage else None,
}
print(json.dumps(out, ensure_ascii=False, indent=2))
