"""SO-02 — noul: veracidade de 2 afirmacoes com gabarito conhecido (ver
dados/afirmacoes-noul.md). Cada afirmacao e uma pergunta Noul independente
na MESMA chamada (state vazio - o enunciado inteiro vai em instructions).
"""
from __future__ import annotations

import json
import sys

from _shared import build_client, build_provider
from system_one_adapter import Noul

AFIRMACAO_1 = (
    "O custo de armazenamento por GB do Amazon S3 Standard-Infrequent "
    "Access (S3 Standard-IA) é menor que o custo de armazenamento por GB "
    "do Amazon S3 Standard. Responda se esta afirmação é verdadeira."
)
GABARITO_1 = True  # verdadeiro — ver dados/afirmacoes-noul.md

AFIRMACAO_2 = (
    "O Amazon RDS Multi-AZ elimina completamente a necessidade de "
    "backups, porque a replicação síncrona entre a instância primária e a "
    "réplica em standby já garante durabilidade total dos dados. Responda "
    "se esta afirmação é verdadeira."
)
GABARITO_2 = False  # falso — Multi-AZ e alta disponibilidade, nao backup


def veredito(noul: float, gabarito: bool) -> str:
    # limiar simetrico: >0.5 conta como "verdadeiro" respondido, <0.5 como
    # "falso" respondido; 0.5 exato conta como nao-acerto (incerteza), nunca
    # como meio-acerto — ver dados/afirmacoes-noul.md, Criterio de aceite.
    if noul == 0.5:
        return "incerto (nao conta como acerto)"
    respondeu_verdadeiro = noul > 0.5
    return "acerto" if respondeu_verdadeiro == gabarito else "erro"


def run() -> dict:
    provider = build_provider()
    client = build_client(structured=True)
    try:
        response = client.system_one(
            state="",
            questions={
                "afirmacao_1": Noul(instructions=AFIRMACAO_1),
                "afirmacao_2": Noul(instructions=AFIRMACAO_2),
            },
            model=provider,
        )
    finally:
        provider.close()

    a1 = response.answers["afirmacao_1"].noul
    a2 = response.answers["afirmacao_2"].noul
    v1 = veredito(a1, GABARITO_1)
    v2 = veredito(a2, GABARITO_2)

    resultado = {
        "caso": "SO-02",
        "tipo": "noul",
        "modelo": response.model,
        "afirmacao_1": {"texto": AFIRMACAO_1, "gabarito": GABARITO_1, "noul": a1, "veredito": v1},
        "afirmacao_2": {"texto": AFIRMACAO_2, "gabarito": GABARITO_2, "noul": a2, "veredito": v2},
        "acertos": sum(1 for v in (v1, v2) if v == "acerto"),
        "total": 2,
        "usage": response.usage.model_dump(),
        "resposta_completa": response.model_dump(mode="json"),
    }
    print(f"SO-02: afirmacao_1 noul={a1:.3f} ({v1}) | afirmacao_2 noul={a2:.3f} ({v2})", file=sys.stderr)
    return resultado


if __name__ == "__main__":
    print(json.dumps(run(), ensure_ascii=False, indent=2))
