# Política de uso de IA — organização (síntese, dados fictícios)

> Corpus de ingestão do cenário 04 (vector stores). Documento **sintético**,
> pequeno e temático de propósito: a busca semântica pela pergunta "posso
> mandar CPF para modelo externo?" deve recuperar especificamente a regra R1,
> não R2 ou R3 — o teste de VS-03 verifica se a regra certa é a mais
> relevante, não apenas se alguma regra retorna.

## Regras

**R1 — Dados pessoais e modelos SaaS externos.** Dados pessoais
(CPF, nome completo, endereço, dados de saúde) não podem ser enviados a
modelos de IA hospedados por terceiros (SaaS, camada "fronteira" do
catálogo do gateway) sem mascaramento prévio por um guardrail de PII
homologado. Chamadas que precisem desses dados devem usar modelos locais
(camada "local" do catálogo) ou passar pelo guardrail `mascara-pii` antes
de sair do ambiente da organização.

**R2 — Retenção de prompts e respostas.** Prompts e respostas de chamadas
que tenham passado por dados sensíveis devem ter a retenção de log
limitada a 90 dias, e o acesso ao conteúdo do log (não apenas aos metadados
de auditoria) deve ser restrito ao papel Gestor de Portfólio de IA.

**R3 — Aprovação de novos modelos.** Nenhum modelo novo — de qualquer
camada (fronteira, local ou sandbox) — pode ser adicionado ao catálogo do
gateway em produção sem passar antes pela avaliação de governança descrita
neste documento (mapeamento aos pilares P1–P12) e sem registro explícito de
custo por token, quando aplicável.
