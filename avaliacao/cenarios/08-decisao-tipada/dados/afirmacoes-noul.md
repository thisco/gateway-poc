# SO-02 — Afirmações com gabarito (decisão tipada `noul`)

Duas afirmações técnicas independentes (cada uma é uma pergunta `noul`
própria, sem contexto compartilhado em `state`), cada uma com gabarito
verificável em documentação pública — não uma opinião, um fato conferível.

## Afirmação 1 — verdadeira (gabarito: `noul` ≈ 1)

> O custo de armazenamento por GB do Amazon S3 Standard-Infrequent Access
> (S3 Standard-IA) é menor que o custo de armazenamento por GB do Amazon S3
> Standard.

**Gabarito: VERDADEIRO.** É a proposta de valor central da classe
Standard-IA (preço de armazenamento mais baixo, em troca de custo de
recuperação por GB e cobrança mínima de 30 dias por objeto) — documentado
na página oficial de preços do S3 (ver README §9).

## Afirmação 2 — falsa (gabarito: `noul` ≈ 0)

> O Amazon RDS Multi-AZ elimina completamente a necessidade de backups,
> porque a replicação síncrona entre a instância primária e a réplica em
> standby já garante durabilidade total dos dados.

**Gabarito: FALSO.** Multi-AZ é um mecanismo de **alta disponibilidade**
(failover automático se a primária falhar), não de **backup** — os dois
resolvem problemas diferentes. A réplica standby replica também erros
lógicos (um `DELETE` ou `DROP TABLE` indevido é replicado igualmente para o
standby), então Multi-AZ sozinho não protege contra perda de dados por erro
de aplicação/operador; backups automáticos (point-in-time recovery) e
snapshots continuam necessários independentemente de Multi-AZ estar
habilitado — documentado na página oficial de alta disponibilidade do RDS
(ver README §9).

## Critério de aceite

Cada afirmação é enviada como uma pergunta `Noul` independente (`state`
vazio, o texto inteiro vai em `instructions` — não há PII nem dado
sintético aqui, é conhecimento técnico público). O script registra
`noul` (probabilidade de verdadeiro) devolvido pelo motor contra o
gabarito acima e contabiliza acerto/erro honestamente — incluindo o caso
de o modelo local pequeno "empatar" perto de 0,5 (incerteza), que conta
como não-acerto, não como meio-acerto.
