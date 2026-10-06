# Roteiro de playground (browser) — Cenário 02: Policies

Passo a passo 100% no navegador, usando o **Playground** da UI do gateway
(`http://localhost:4000/ui/playground`). Validado ao vivo em 2026-09-10
(Chrome, via Playwright) contra esta build — os campos abaixo são os
reais desta tela.

**Pré-requisito:** logar em `http://localhost:4000/ui` (usuário `admin`,
senha = `LITELLM_MASTER_KEY`). Profile `guardrails` no ar (a policy
dispara os guardrails do cenário 01).

## Passo a passo

1. Abra `http://localhost:4000/ui/playground` → aba **Chat**.
2. Se houver um chip de guardrail selecionado de uma demo anterior,
   clique em "Clear all" ao lado de **Guardrails** para limpar — este
   roteiro usa **Policies**, não guardrail direto.
3. Em **Select Model**, escolha `simulado` (resposta simulada pelo
   gateway, sem custo e sem depender de um provedor real).
4. Em **Policies** (última seção da coluna de Configurations, abaixo de
   Guardrails), clique no campo "Select policies (production or published
   versions)" e escolha `protecao-total — v1 (production)`. Um chip
   aparece confirmando a seleção.
5. No campo de mensagem, cole exatamente:

   ```
   Meu CPF é 529.982.247-25
   ```

6. Pressione Enter. Aguarde a resposta (instantânea — `simulado` não
   chama nenhum provedor real).
   ✔ **Deve aparecer**: a resposta simulada do gateway, mas com uma
   palavra do texto trocada por `<LOCATION>` (falso-positivo do NER em
   português sobre a palavra "autorizada") — sinal de que o guardrail
   rodou de verdade sobre a resposta, mesmo você não tendo escolhido
   nenhum guardrail diretamente (só a *policy*).
7. Abra `http://localhost:4000/ui/logs` em outra aba e clique na linha
   mais recente (`model: openai/simulado`).
   ✔ **Deve aparecer**: `Guardrail: mascara-pii` no painel de Request
   Details, e em **Metadata** (JSON no fim do painel) o campo
   `applied_guardrails: ["mascara-pii", "mascara-pii-log"]` — os DOIS
   guardrails da policy (o próprio de `protecao-total` e o herdado de
   `protecao-base`), aplicados só por você ter referenciado a *policy*,
   não os guardrails individualmente.
8. (Opcional) Volte para `http://localhost:4000/ui/policies` e confira a
   tabela: `protecao-base` (badge `Config`) e `protecao-total` (mostra
   que herda de `protecao-base`) — a mesma herança que você acabou de ver
   em ação na chamada.

## Conclusão de governança

A mesma do `demo.sh` deste cenário: uma **policy nomeada e versionada no
git** (`config.yaml`) resolve e aplica um *conjunto* de guardrails numa
chamada — o cliente não escolhe guardrail a guardrail, só referencia o
perfil de risco (`protecao-total`). Isso é o mais próximo que o LiteLLM
chega de "política como código" para segurança de IA. Pilares
evidenciados: **P5** (guardrails herdados por perfil) e **P10** (política
como código) — ver a análise completa, incluindo o achado sobre anexação
por time sem exigir Enterprise nesta build, em [`README.md`](README.md) §8.

Tela que comprova (print já capturado): `evidencias/PO-playground-chat.png`
(o chat no Playground com a policy aplicada) e
`evidencias/PO-playground-log-guardrails.png` (o painel de Logs mostrando
os dois guardrails resolvidos).
