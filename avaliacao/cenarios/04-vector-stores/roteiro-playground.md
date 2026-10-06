# Roteiro de playground (browser) — Cenário 04: Vector Stores

**Achado de execução deste roteiro (2026-09-10, validado via Playwright):**
o Playground do Chat tem um seletor **Vector Store** — mas, testado ao
vivo com o store soberano `base-governanca` já criado e populado, ele
mostra **"No options found"**: o store não aparece como opção
selecionável no chat. As telas administrativas `Tools → Vector Stores →
Manage Vector Stores` e `→ Test Vector Store` também mostram **"No
vector stores"** / **"No vector stores available"**, mesmo com o store
funcionando perfeitamente por API (confirmado no mesmo instante via
`curl`). Isso bate com o achado 4/5 já documentado no `README.md` deste
cenário: o conector de referência tem um bug de listagem, e a tela
administrativa aparenta depender dele. **Por isso este roteiro não é
"chat no Playground" como nos cenários 01/02** — é: tela **Vector
Stores** (para ver o gap real, que é ele mesmo parte da história de
governança), terminal para a busca/RAG de verdade, e tela de **Logs**
para a prova.

**Pré-requisito:** logar em `http://localhost:4000/ui`. Profile `vectors`
no ar e `bash avaliacao/cenarios/04-vector-stores/setup.sh` já executado
ao menos uma vez (grava `.store-id`).

## Passo a passo

1. Abra `http://localhost:4000/ui/vector-stores` → aba **Manage Vector
   Stores**.
   ✔ **Deve aparecer** (achado, não erro seu): "No vector stores" — a
   tela não lista o `base-governanca`, mesmo ele existindo e respondendo
   normalmente por API. Isso é a evidência visual do achado 4/5 do
   cenário (conector com bug de listagem) — vale a pena mostrar
   exatamente por ser contra-intuitivo.
2. No terminal, confirme que o store existe de verdade pela API de
   gestão do próprio gateway (não a do conector, que é a que quebra):

   ```bash
   set -a; source poc/.env; set +a
   curl -s http://localhost:4000/vector_store/list -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     | jq -c '.data[] | {vector_store_id, vector_store_name, custom_llm_provider}'
   ```

   ✔ **Deve aparecer**: `{"vector_store_id":"...","vector_store_name":"base-governanca","custom_llm_provider":"pg_vector"}`
   — o gateway sabe que o store existe; é a tela específica que tem o gap.
3. Rode a busca semântica (o caso VS-03):

   ```bash
   STORE_ID=$(cat avaliacao/cenarios/04-vector-stores/.store-id)
   curl -s -X POST "http://localhost:4000/v1/vector_stores/$STORE_ID/search" \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
     -d '{"query":"posso enviar CPF de cidadão para um modelo SaaS externo?"}' \
     | jq -c '[.data[] | {regra: .attributes.regra, score}]'
   ```

   ✔ **Deve aparecer**: `R1` com o maior score (≈0.86), à frente de `R3`
   (≈0.81) e `R2` (≈0.80) — a base soberana discrimina a regra certa.
4. Rode o RAG (o caso VS-04 — chat com o contexto do store injetado):

   ```bash
   curl -s http://localhost:4000/v1/chat/completions \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H "Content-Type: application/json" \
     -d "{\"model\":\"local-qwen\",\"vector_store_ids\":[\"$STORE_ID\"],\"messages\":[{\"role\":\"user\",\"content\":\"Segundo a política, posso enviar CPF a modelo externo?\"}]}" \
     | jq -c '{content: .choices[0].message.content[0:200]}'
   ```

5. Volte para o navegador em `http://localhost:4000/ui/logs` e clique na
   chamada mais recente (`model: ollama_chat/qwen2.5:0.5b`).
   ✔ **Deve aparecer**: `prompt_tokens` bem acima do tamanho da pergunta
   original (a pergunta tem ~15 tokens; o prompt real passa de 300) — a
   prova de que o contexto do store foi injetado antes da geração, mesmo
   a resposta do modelo local de 0,5B sendo imperfeita.

## Conclusão de governança

A mesma do `demo.sh` deste cenário: o pipeline de RAG é **100% soberano**
— embeddings locais (`embedding-nomic`/Ollama) e armazenamento local
(`pgvector`), nenhum dado do corpus de governança sai para um provedor
externo — e o store é um recurso catalogado no gateway (P3), mesmo a tela
administrativa de gestão tendo um gap de listagem real (não um erro deste
roteiro). Pilares evidenciados: **P3** (catálogo) e **P6**
(compartimentação/soberania de dados) — ver a análise completa, incluindo
o achado de acesso aberto por padrão (VS-05), em [`README.md`](README.md) §8.

Tela que comprova (prints já existentes e o novo capturado agora):
`evidencias/VS-04-ui-log.png` (contexto injetado no log) e
`evidencias/VS-ui-manage-tab-gap.png` (o gap real da tela "Manage Vector
Stores", capturado ao validar este roteiro).
