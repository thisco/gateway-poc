"""SO-01 — choice: seleção de família de instância AWS para a demanda de
arquitetura descrita em dados/demanda-arquitetura.md.

Imprime em stdout o JSON completo da resposta (testes.sh salva em
evidencias/SO-01.json) mais uma linha de resumo em stderr para leitura
humana durante a execução.
"""
from __future__ import annotations

import json
import sys

from _shared import build_client, build_provider
from system_one_adapter import Choice

STATE = (
    "API web stateless (sem estado de sessao local - cada requisicao e "
    "independente, o backend nao guarda contexto entre chamadas). Trafego "
    "com picos de ate 4x a media (campanhas/lancamentos), a maior parte do "
    "processamento e serializacao JSON e chamadas a um banco gerenciado "
    "externo (RDS), nao e CPU-bound em calculo pesado. Requisito de "
    "latencia: p95 < 100ms na resposta da API. Restricao orcamentaria: "
    "minimizar custo por hora dentro dos dois requisitos acima - nao e um "
    "workload de missao critica que justifique superdimensionamento."
)

OPCOES = {
    "m7g": "Uso geral (Graviton3) - relacao equilibrada de vCPU/RAM, sem otimizacao para nenhum extremo",
    "c7g": "Otimizada para computacao (Graviton3) - mais vCPU por GB de RAM, melhor para processamento/serializacao intensivos",
    "r7g": "Otimizada para memoria (Graviton3) - mais RAM por vCPU, indicada para caches/bancos em memoria, nao para uma API stateless",
    "t4g": "Burstable/entrada (Graviton2) - CPU limitada por creditos acumulados, custo por hora mais baixo, adequada a cargas variaveis",
}


def run() -> dict:
    provider = build_provider()
    client = build_client(structured=True)
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
    finally:
        provider.close()

    answer = response.answers["instancia"]
    opcoes_validas = set(OPCOES.keys())
    valido = answer.choice in opcoes_validas
    soma_probs = sum(answer.probabilities.values())

    resultado = {
        "caso": "SO-01",
        "tipo": "choice",
        "modelo": response.model,
        "opcoes_validas": sorted(opcoes_validas),
        "decisao": answer.choice,
        "decisao_e_opcao_valida": valido,
        "confidence": answer.confidence,
        "probabilities": answer.probabilities,
        "soma_probabilities": round(soma_probs, 4),
        "usage": response.usage.model_dump(),
        "resposta_completa": response.model_dump(mode="json"),
    }
    print(f"SO-01: decisao={answer.choice} valida={valido} confidence={answer.confidence:.3f} soma_probs={soma_probs:.3f}", file=sys.stderr)
    return resultado


if __name__ == "__main__":
    print(json.dumps(run(), ensure_ascii=False, indent=2))
