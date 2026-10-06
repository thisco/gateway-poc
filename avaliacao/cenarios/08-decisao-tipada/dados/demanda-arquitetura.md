# SO-01 — Demanda de arquitetura (seleção de instância AWS)

Caso realista usado como `state` da decisão tipada `choice`. Não há um
"gabarito" único aqui — o critério de aceite do plano é que a decisão saia
**dentro do conjunto de opções oferecido**, com um vetor de probabilidades
válido (soma ≈ 1, uma entrada por opção) — não que acerte uma resposta
"certa" fixada de antemão (ao contrário de SO-02, que tem gabarito).

## Demanda (texto enviado como `state`)

> API web stateless (sem estado de sessão local — cada requisição é
> independente, o backend não guarda contexto entre chamadas). Tráfego com
> picos de até 4× a média (campanhas/lançamentos), a maior parte do
> processamento é serialização JSON e chamadas a um banco gerenciado
> externo (RDS), não é CPU-bound em cálculo pesado. Requisito de latência:
> p95 < 100ms na resposta da API. Restrição orçamentária: **minimizar custo
> por hora** dentro dos dois requisitos acima — não é um workload de
> missão crítica que justifique superdimensionamento.

## Opções (`criteria` do `Choice`)

| Família | Descrição enviada ao modelo |
|---|---|
| `m7g` | Uso geral (Graviton3) — relação equilibrada de vCPU/RAM, sem otimização para nenhum extremo |
| `c7g` | Otimizada para computação (Graviton3) — mais vCPU por GB de RAM, melhor para processamento/serialização intensivos |
| `r7g` | Otimizada para memória (Graviton3) — mais RAM por vCPU, indicada para caches/bancos em memória, não para uma API stateless |
| `t4g` | Burstable/entrada (Graviton2) — CPU limitada por créditos acumulados, custo por hora mais baixo, adequada a cargas variáveis que não sustentam pico de CPU o tempo todo |

## Por que este desenho

- **Sem resposta única "certa" imposta**: uma API stateless com pico 4× e
  prioridade de custo admite mais de uma resposta defensável na prática
  (`c7g` pelo perfil CPU-bound de serialização, `t4g` pelo custo/hora e
  pela natureza intermitente do pico) — por isso o critério de aceite do
  cenário (README §6) é validade da opção + probabilidades coerentes, não
  acerto contra gabarito. `r7g` é a opção que menos faz sentido (o workload
  não é memory-bound) — útil como "distrator" para ver se o motor evita
  escolher a opção claramente errada.
- Reaproveita o mesmo vocabulário de família de instância (m7g/c7g/r7g/t4g)
  do caso de score (SO-03), para permitir comparar como o mesmo motor local
  trata "escolher 1 de 4" (`choice`) frente a "pontuar as 4" (`score`) para
  contextos de demanda diferentes.
