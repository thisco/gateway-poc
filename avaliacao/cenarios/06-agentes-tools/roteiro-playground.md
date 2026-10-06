# Roteiro de playground (browser) — Cenário 06: Agentes (A2A) e Tool Calling

**Achado de execução deste roteiro (2026-09-10, validado via Playwright):**
o Swagger interativo (`http://localhost:4000/docs`) não existe nesta
build (HTTP 404). O Playground do Chat não tem seletor de agentes A2A
(o campo mais próximo, "MCP Servers", é para tools MCP, não para
agentes). Por isso este roteiro é: a tela **Agentic → Agents** (real, e é
onde o agente `eco-governanca` está de fato catalogado), terminal para os
dois casos de maior impacto (AG-03 e TL-03), e tela de **Logs** para a
prova, com o mesmo padrão dos demais cenários 03/04/05.

**Pré-requisito:** logar em `http://localhost:4000/ui`. Profile `agents`
no ar (`docker compose --profile agents up -d agente-eco`) e gateway
recriado (`docker compose up -d --force-recreate gateway`) para carregar
o bloco `agents:` do config — ver `README.md` §3 deste cenário.

## Passo a passo

1. Abra `http://localhost:4000/ui/agents` (menu lateral **Agentic** →
   **Agents**).
   ✔ **Deve aparecer**: uma linha `eco-governanca`, com um `Agent ID`
   (hash longo) — o agente A2A local, registrado em `config.yaml`
   (versionado no git), catalogado como recurso de primeira classe pelo
   gateway (evidência de P3), igual ao padrão já visto para modelos, MCP
   e vector stores.
2. No terminal, resolva o `agent_id` (você vai precisar dele nas
   próximas chamadas) e teste o caso AG-03 — uma chave **sem** nenhuma
   permissão de agente:

   ```bash
   set -a; source poc/.env; set +a
   AGENT_ID=$(curl -s http://localhost:4000/v1/agents -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     | jq -r '.[] | select(.agent_name=="eco-governanca") | .agent_id')
   CHAVE=$(curl -s http://localhost:4000/key/generate -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     -H "Content-Type: application/json" -d '{"models":["simulado"]}' | jq -r '.key')
   curl -s "http://localhost:4000/a2a/$AGENT_ID/.well-known/agent-card.json" \
     -H "Authorization: Bearer $CHAVE" | jq -c '{name, protocolVersion}'
   ```

   ✔ **Deve aparecer**: o card do agente (`"name": "Eco de Governança"`)
   — a chave **conseguiu**, mesmo sem `object_permission.agents`
   configurado. Isso é o oposto do MCP (cenário 03): agentes A2A **nascem
   abertos** por padrão.
3. Agora o caso TL-03 — um guardrail protegendo o argumento estruturado
   de uma chamada de tool, com um CPF sintético:

   ```bash
   TOOL='{"type":"function","function":{"name":"consulta_politica","description":"Consulta a regra de politica de governanca de IA aplicavel a um tema.","parameters":{"type":"object","properties":{"tema":{"type":"string"}},"required":["tema"]}}}'
   curl -s http://localhost:4000/v1/chat/completions \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
     -d "{\"model\":\"fronteira-haiku\",\"max_tokens\":400,\"guardrails\":[\"mascara-pii\"],\"tools\":[$TOOL],\"tool_choice\":{\"type\":\"function\",\"function\":{\"name\":\"consulta_politica\"}},\"messages\":[{\"role\":\"user\",\"content\":\"Registre uma consulta de politica para o titular de CPF 529.982.247-25. Chame a ferramenta consulta_politica com o argumento tema igual exatamente ao CPF do titular: 529.982.247-25\"}]}" \
     | jq -c '{tool_call_arguments: .choices[0].message.tool_calls[0].function.arguments}'
   ```

   ✔ **Deve aparecer**: `{"tool_call_arguments":"{\"tema\": \"<BR_CPF>\"}"}`
   — o CPF veio **mascarado** dentro do argumento estruturado da tool, não
   em claro. O modelo (`fronteira-haiku`, Anthropic real) nunca viu o CPF
   de verdade.
4. Volte para o navegador em `http://localhost:4000/ui/logs`.
   ✔ **Deve aparecer**: chamadas recentes com badge `Agent` (a invocação
   A2A) e `LLM` (a chamada de tool calling) lado a lado, na mesma tabela
   — a mesma trilha de auditoria unificada já vista nos cenários
   anteriores, agora estendida a agentes e tool calls.

## Conclusão de governança

A mesma do `demo.sh` deste cenário: agentes A2A **nascem abertos**
(allow-by-default) — diferente do MCP (fechado por padrão) — mas têm um
campo de restrição nativo e funcional (`object_permission.agents`, que
usa o `agent_id`, não o nome legível — outra pegadinha documentada no
achado 4). E o guardrail `mascara-pii` protege até o **argumento
estruturado** de uma tool call, não só o texto solto da conversa — um
resultado positivo para P5 em qualquer arquitetura de agentes. Pilares
evidenciados: **P1** (identidade do agente), **P3** (catálogo de
agentes), **P4** (trilha unificada) e **P5** (controles sobre ações de
agente) — ver a análise completa, incluindo a comparação com os outros
três recursos avaliados nesta suíte, em [`README.md`](README.md) §8.

Tela que comprova (prints já existentes): `evidencias/AG-ui-agents.png`
(agente catalogado) e `evidencias/AG-02-ui-logs-unified.png` (badges
`Agent`/`LLM` lado a lado no log).
