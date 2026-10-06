"""SO-03 — score: pontua 4 familias de instancia (r7g/c7g/m7g/t4g) para um
workload de banco em memoria, mesma rubrica ordinal nas 4 perguntas (ver
dados/workload-banco-memoria.md).
"""
from __future__ import annotations

import json
import sys

from _shared import build_client, build_provider
from system_one_adapter import Score

STATE = (
    "Workload: banco de dados relacional operado inteiramente em memoria "
    "(in-memory), com dataset ativo cabendo em RAM para eliminar I/O de "
    "disco no caminho critico de leitura/escrita. Perfil de uso: alta "
    "relacao GB de RAM por vCPU, baixa necessidade de poder de CPU para "
    "logica de aplicacao (a carga e dominada por acesso a memoria, nao "
    "por calculo)."
)

RUBRICA = [
    "Inadequada - nao atende ao requisito de memoria do workload",
    "Aceitavel com ressalvas - funciona, mas nao e otimizada para o requisito principal",
    "Boa - atende bem ao requisito principal",
    "Ideal - desenhada especificamente para este requisito",
]

FAMILIAS = {
    "score_r7g": ("r7g", "Graviton3, otimizada para memoria - alta relacao RAM/vCPU"),
    "score_c7g": ("c7g", "Graviton3, otimizada para computacao - baixa relacao RAM/vCPU"),
    "score_m7g": ("m7g", "Graviton3, uso geral - relacao RAM/vCPU balanceada"),
    "score_t4g": ("t4g", "Graviton2, burstable/entrada - pouca RAM, CPU limitada por creditos"),
}


def run() -> dict:
    provider = build_provider()
    client = build_client(structured=True)
    questions = {
        chave: Score(
            instructions=f"Pontue a familia de instancia AWS {familia} ({descricao}) para este workload, na rubrica dada.",
            criteria=RUBRICA,
        )
        for chave, (familia, descricao) in FAMILIAS.items()
    }
    try:
        response = client.system_one(state=STATE, questions=questions, model=provider)
    finally:
        provider.close()

    scores = {FAMILIAS[chave][0]: response.answers[chave].score for chave in FAMILIAS}
    ordenacao = sorted(scores.items(), key=lambda kv: kv[1], reverse=True)
    r7g_no_topo = ordenacao[0][0] == "r7g"
    r7g_acima_c7g_m7g = scores["r7g"] > scores["c7g"] and scores["r7g"] > scores["m7g"]

    resultado = {
        "caso": "SO-03",
        "tipo": "score",
        "modelo": response.model,
        "rubrica": RUBRICA,
        "scores": scores,
        "confidences": {FAMILIAS[chave][0]: response.answers[chave].confidence for chave in FAMILIAS},
        "ordenacao_desc": [fam for fam, _ in ordenacao],
        "r7g_no_topo": r7g_no_topo,
        "ordenacao_coerente_r7g_acima_c7g_e_m7g": r7g_acima_c7g_m7g,
        "usage": response.usage.model_dump(),
        "resposta_completa": response.model_dump(mode="json"),
    }
    print(f"SO-03: ordenacao={[f'{f}={s:.2f}' for f,s in ordenacao]} r7g_no_topo={r7g_no_topo}", file=sys.stderr)
    return resultado


if __name__ == "__main__":
    print(json.dumps(run(), ensure_ascii=False, indent=2))
