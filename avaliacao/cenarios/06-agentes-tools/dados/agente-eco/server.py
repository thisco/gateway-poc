#!/usr/bin/env python3
"""Agente A2A mínimo — "eco de governança".

Implementa à mão o subconjunto do protocolo A2A (Agent-to-Agent) necessário
para ser registrado como agente `config.yaml`-declarado no gateway LiteLLM e
invocado por ele: um endpoint JSON-RPC 2.0 (`message/send`) e, como bônus, o
endpoint de agent card em `.well-known/` (não estritamente necessário — ver
achado no README §8: para agentes declarados em `config.yaml`, o LiteLLM
NUNCA busca o card do upstream; ele serve `agent_card_params` do config
diretamente, apenas reescrevendo `url` para o proxy).

Decisão de implementação (registrada por instrução do controlador): a
tentativa de usar `a2a-sdk` (Python) esbarrou em duas incompatibilidades
sérias, documentadas no README §3:
  1. Python 3.9 (ambiente local) não suporta a-sdk >=1.1 (exige >=3.10).
  2. Mesmo instalando em Python 3.12, a API pública mudou de versão para
     versão: os símbolos usados nos tutoriais/quickstarts oficiais
     (`A2AStarletteApplication`, `DefaultRequestHandler`, `AgentExecutor`
     em `a2a.server.apps`) não existem mais em `a2a-sdk==1.1.2` — a versão
     rodando DENTRO do próprio container do gateway é `a2a-sdk==1.1.0`,
     ainda outra. Reimplementar contra uma API instável e não documentada
     custaria mais tempo do que o handshake justifica para uma PoC de
     avaliação.
Optou-se pelo fallback pré-aprovado: um servidor HTTP mínimo, sem
dependências externas (só `http.server`/`json` da stdlib), que fala o
suficiente do protocolo A2A (JSON-RPC 2.0, `message/send`, shape de
`Message` da spec 0.3 — confirmado lendo o código-fonte real do gateway,
`litellm/a2a_protocol/` e `litellm/proxy/agent_endpoints/a2a_endpoints.py`,
dentro do container `poc-gateway`) para o gateway conseguir invocá-lo de
verdade.

Comportamento: agente somente-leitura. Para qualquer pergunta recebida,
responde ecoando a pergunta e citando 3 regras fixas de política de
governança de IA. Nenhuma ação de escrita é executada.
"""

from __future__ import annotations

import json
import os
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "9000"))

REGRAS_FIXAS = [
    "Toda chamada a modelo de IA deve passar pelo gateway central de "
    "governanca -- nao ha acesso direto a provedores fora dele.",
    "Dados pessoais (PII) devem ser mascarados antes de sair do ambiente "
    "soberano, conforme o guardrail mascara-pii.",
    "Toda acao de agente e atribuida a uma identidade de chave e "
    "registrada em log de auditoria unificado.",
]

AGENT_CARD = {
    "protocolVersion": "0.3",
    "name": "Eco de Governanca",
    "description": (
        "Agente A2A local, somente leitura, que responde perguntas citando "
        "regras fixas de politica de governanca de IA."
    ),
    "url": f"http://agente-eco:{PORT}/",
    "version": "1.0.0",
    "capabilities": {},
    "defaultInputModes": ["text"],
    "defaultOutputModes": ["text"],
    "skills": [
        {
            "id": "consulta-politica",
            "name": "Consulta de politica",
            "description": (
                "Responde perguntas citando regras fixas de politica de "
                "governanca de IA (somente leitura, sem acoes de escrita)."
            ),
            "tags": ["governanca"],
        }
    ],
}


def _extract_question(message: dict) -> str:
    parts = message.get("parts") or []
    textos = []
    for p in parts:
        # aceita tanto {"kind":"text","text":...} (A2A 0.3) quanto
        # {"type":"text","text":...} (variantes vistas em SDKs diferentes)
        if isinstance(p, dict) and "text" in p:
            textos.append(str(p["text"]))
    return " ".join(textos).strip()


def _build_reply_text(question: str) -> str:
    regras = "; ".join(f"({i + 1}) {r}" for i, r in enumerate(REGRAS_FIXAS))
    pergunta = question or "(nenhum texto recebido)"
    return (
        f"[eco de governanca] Pergunta recebida: \"{pergunta}\". "
        f"Regras fixas de politica: {regras}. "
        "Este agente e somente leitura -- nenhuma acao de escrita foi executada."
    )


def _jsonrpc_result(request_id, message_result: dict) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "result": message_result}


def _jsonrpc_error(request_id, code: int, msg: str) -> dict:
    return {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": msg}}


class Handler(BaseHTTPRequestHandler):
    server_version = "agente-eco/1.0"

    def log_message(self, fmt, *args):  # menos verboso no stdout do container
        print("%s - %s" % (self.address_string(), fmt % args))

    def _send_json(self, status: int, payload: dict):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/.well-known/agent-card.json", "/.well-known/agent.json"):
            self._send_json(200, AGENT_CARD)
        elif self.path == "/health":
            self._send_json(200, {"status": "ok"})
        else:
            self._send_json(404, {"error": "not_found", "path": self.path})

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw or b"{}")
        except json.JSONDecodeError:
            self._send_json(400, _jsonrpc_error(None, -32700, "Parse error"))
            return

        request_id = body.get("id")
        method = body.get("method")

        if body.get("jsonrpc") != "2.0":
            self._send_json(400, _jsonrpc_error(request_id, -32600, "Invalid Request: jsonrpc must be '2.0'"))
            return

        if method == "message/send":
            params = body.get("params") or {}
            message = params.get("message") or {}
            question = _extract_question(message)
            reply_text = _build_reply_text(question)
            result = {
                "kind": "message",
                "messageId": uuid.uuid4().hex,
                "role": "agent",
                "parts": [{"kind": "text", "text": reply_text}],
            }
            context_id = message.get("contextId")
            if context_id:
                result["contextId"] = context_id
            self._send_json(200, _jsonrpc_result(request_id, result))
        else:
            self._send_json(200, _jsonrpc_error(request_id, -32601, f"Method not found: {method}"))


def main():
    server = ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    print(f"agente-eco (A2A minimo) escutando em 0.0.0.0:{PORT}")
    server.serve_forever()


if __name__ == "__main__":
    main()
