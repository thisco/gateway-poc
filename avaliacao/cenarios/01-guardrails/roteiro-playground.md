# Roteiro de playground (browser) — Cenário 01: Guardrails

Passo a passo 100% no navegador, usando o **Playground** da UI do gateway
(`http://localhost:4000/ui/playground`). Validado ao vivo em 2026-09-10
(Chrome, via Playwright) contra esta build (`ghcr.io/berriai/litellm:main-stable`,
v1.100.0) — os campos abaixo são os reais desta tela, não uma suposição do
brief original.

**Pré-requisito:** logar em `http://localhost:4000/ui` com usuário `admin`
e senha = `LITELLM_MASTER_KEY` (ver `poc/README.md`). Profile `guardrails`
no ar (`docker compose --profile guardrails up -d`).

## Passo a passo

1. Abra `http://localhost:4000/ui/playground`. A aba **Chat** já vem
   selecionada.
2. Em **Select Model**, clique e escolha `local-qwen` (modelo local via
   Ollama — sem custo).
3. Em **Guardrails** (abaixo de MCP Servers/Vector Store, acima de
   Policies), clique no campo "Select guardrails" e escolha `mascara-pii`.
   Um chip `mascara-pii ✕` aparece — é o guardrail que esta mensagem vai
   carregar.
4. No campo de mensagem, cole exatamente:

   ```
   Repita exatamente: meu CPF é 529.982.247-25
   ```

5. Pressione Enter (ou clique no botão de enviar). Aguarde a resposta do
   assistente (2-3s, modelo local).
   ✔ **Deve aparecer**: a resposta do assistente não repete o CPF em
   claro — em vez disso, o texto contém `<BR_CPF>` no lugar do número (o
   restante da frase pode variar, e é comum aparecer `<PERSON>`/`<LOCATION>`
   como falso-positivo do NER em português — isso já é um achado
   documentado do cenário, não um erro deste roteiro).
6. Abra `http://localhost:4000/ui/logs` em outra aba. A auto-atualização
   ("Auto-refreshing every 15 seconds") já deve trazer a chamada que você
   acabou de fazer como a linha mais recente (`model: ollama_chat/qwen2.5:0.5b`).
7. Clique nessa linha para abrir o painel de detalhe.
   ✔ **Deve aparecer**: logo abaixo de "Request Details", o campo
   `Guardrail: mascara-pii` com o badge `1 masked`.
8. Role até a seção **"Guardrails & Policy Compliance"**.
   ✔ **Deve aparecer**: `1 guardrail evaluated | 1 Passed`, e dentro de
   **Request Lifecycle**, a linha `Pre-call guardrail: mascara-pii — PASSED`
   com o tempo decorrido (`T+9ms` ou similar) — **antes** da linha
   `LLM call`. Isso é a prova visual de que o mascaramento aconteceu antes
   do modelo ver o CPF.
9. (Opcional, mais fundo) Clique em **Metadata** no fim do painel e
   procure `guardrail_information` no JSON — o campo
   `masked_entity_count: {"BR_CPF": 1}` confirma exatamente o que foi
   mascarado.

## Conclusão de governança

A mesma do `demo.sh` deste cenário: **o CPF nunca chega ao provedor em
claro** — o guardrail `mascara-pii`, configurado uma única vez no
`config.yaml` do gateway (não na aplicação cliente), mascarou o dado
*antes* da chamada ao modelo (`pre_call`), e isso é auditável por
qualquer pessoa com acesso à UI de Logs, sem precisar ler código ou
configuração. Pilares evidenciados: **P5** (guardrail mandatório herdado
pelo gateway) e **P6** (minimização de PII na borda) — ver detalhes e
achados completos em [`README.md`](README.md) §8.

Tela que comprova (print já capturado): `evidencias/GR-playground-chat.png`
(o chat no Playground) e `evidencias/GR-playground-log-guardrail-expanded.png`
(o painel de Logs expandido com o guardrail evidenciado).
