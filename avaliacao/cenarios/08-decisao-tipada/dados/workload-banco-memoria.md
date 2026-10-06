# SO-03 — Workload de banco em memória (decisão tipada `score`)

Um único `state` compartilhado, com uma pergunta `Score` por família de
instância (4 perguntas na mesma chamada, mesma rubrica ordinal em todas —
o formato correto do tipo `score` do System One é "pontuar o `state` numa
rubrica", não "comparar vários itens numa lista", ver README §3, nota de
execução).

## `state` (compartilhado pelas 4 perguntas)

> Workload: banco de dados relacional operado inteiramente em memória
> (in-memory), com dataset ativo cabendo em RAM para eliminar I/O de disco
> no caminho crítico de leitura/escrita. Perfil de uso: alta relação
> GB de RAM por vCPU, baixa necessidade de poder de CPU para lógica de
> aplicação (a carga é dominada por acesso a memória, não por cálculo).

## Famílias pontuadas (4 perguntas `Score`, mesma rubrica)

| Pergunta | Família | Descrição enviada ao modelo |
|---|---|---|
| `score_r7g` | r7g | Graviton3, otimizada para memória — alta relação RAM/vCPU |
| `score_c7g` | c7g | Graviton3, otimizada para computação — baixa relação RAM/vCPU |
| `score_m7g` | m7g | Graviton3, uso geral — relação RAM/vCPU balanceada |
| `score_t4g` | t4g | Graviton2, burstable/entrada — pouca RAM, CPU limitada por créditos |

## Rubrica (`criteria`, os 4 níveis ordinais — idêntica nas 4 perguntas)

0. Inadequada — não atende ao requisito de memória do workload
1. Aceitável com ressalvas — funciona, mas não é otimizada para o
   requisito principal
2. Boa — atende bem ao requisito principal
3. Ideal — desenhada especificamente para este requisito

## Critério de aceite (README §6)

Ordenação coerente dos `score` retornados: **r7g > c7g e r7g > m7g** (r7g
é a única família literalmente desenhada para "mais RAM por vCPU", o
comportamento correto para o pilar P9 é reconhecer isso). Uma ordenação
diferente (ex.: t4g ou c7g pontuando mais alto que r7g) não é escondida —
é registrada como limite do modelo local pequeno, conforme o plano prevê
explicitamente.
