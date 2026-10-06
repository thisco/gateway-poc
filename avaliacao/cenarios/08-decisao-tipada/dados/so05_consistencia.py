"""SO-05 — consistencia: repete a MESMA pergunta de SO-01 (choice, mesma
demanda de arquitetura) 10x e tabula a decisao modal + variancia das
probabilidades. Insumo do pilar P9 (a decisao e confiavel o bastante para
automacao sem revisao humana por chamada?).

Parametro de amostragem registrado com honestidade (ver README SS3): o
system-one-adapter NAO expoe `temperature` na assinatura publica de
OpenAIProvider.request() (so model/messages/response_format chegam ao
chat.completions.create) - nao ha como forcar temperature=0 pelo motor tal
como instalado. Rodamos portanto no default do backend (llama.cpp /
local-hermes, sem override de temperature pelo cliente), o que e o cenario
realista de quem usa o adapter oficial sem forkar o pacote - a variancia
observada reflete o pipeline de producao real, nao um piso artificialmente
baixo de um teste com temperature=0.
"""
from __future__ import annotations

import json
import statistics
import sys
from collections import Counter

from _shared import build_client, build_provider
from system_one_adapter import Choice

from so01_choice import OPCOES, STATE

N_REPETICOES = 10


def run() -> dict:
    provider = build_provider()
    client = build_client(structured=True)
    decisoes: list[str] = []
    prob_por_opcao: dict[str, list[float]] = {opcao: [] for opcao in OPCOES}
    confidences: list[float] = []
    erros = 0

    try:
        for i in range(N_REPETICOES):
            try:
                response = client.system_one(
                    state=STATE,
                    questions={
                        "instancia": Choice(
                            instructions="Qual familia de instancia AWS melhor atende a esta demanda de arquitetura, dentre as opcoes descritas em criteria?",
                            criteria=OPCOES,
                        ),
                    },
                    model=provider,
                )
                answer = response.answers["instancia"]
                decisoes.append(answer.choice)
                confidences.append(answer.confidence)
                for opcao in OPCOES:
                    prob_por_opcao[opcao].append(answer.probabilities.get(opcao, 0.0))
                print(f"  rodada {i + 1}/{N_REPETICOES}: decisao={answer.choice} confidence={answer.confidence:.3f}", file=sys.stderr)
            except Exception as exc:  # noqa: BLE001 — registrar, nao esconder
                erros += 1
                print(f"  rodada {i + 1}/{N_REPETICOES}: ERRO {type(exc).__name__}: {exc}", file=sys.stderr)
    finally:
        provider.close()

    contagem = Counter(decisoes)
    decisao_modal, freq_modal = (contagem.most_common(1)[0] if contagem else (None, 0))

    variancia_por_opcao = {
        opcao: {
            "media": round(statistics.mean(vs), 4) if vs else None,
            "desvio_padrao": round(statistics.pstdev(vs), 4) if len(vs) > 1 else 0.0,
        }
        for opcao, vs in prob_por_opcao.items()
    }

    resultado = {
        "caso": "SO-05",
        "tipo": "consistencia (choice repetido)",
        "n_repeticoes": N_REPETICOES,
        "temperatura": "default do backend (nao exposta pelo system-one-adapter — ver docstring deste script)",
        "erros_de_execucao": erros,
        "decisoes": decisoes,
        "contagem_decisoes": dict(contagem),
        "decisao_modal": decisao_modal,
        "frequencia_decisao_modal": freq_modal,
        "estabilidade_decisao_modal": round(freq_modal / len(decisoes), 4) if decisoes else None,
        "variancia_probabilidades_por_opcao": variancia_por_opcao,
        "confidence_media": round(statistics.mean(confidences), 4) if confidences else None,
        "confidence_desvio_padrao": round(statistics.pstdev(confidences), 4) if len(confidences) > 1 else 0.0,
    }
    print(
        f"SO-05: decisao_modal={decisao_modal} ({freq_modal}/{len(decisoes)}) "
        f"erros={erros}",
        file=sys.stderr,
    )
    return resultado


if __name__ == "__main__":
    print(json.dumps(run(), ensure_ascii=False, indent=2))
