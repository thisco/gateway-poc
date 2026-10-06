# Roteiro de playground (browser) — Cenário 05: Skills

**Achado de execução deste roteiro (2026-09-10, validado via Playwright):**
o Swagger interativo (`http://localhost:4000/docs`) citado no brief
original **não existe nesta build — retorna HTTP 404**. O Playground do
Chat não tem nenhum seletor de skills. E a tela `http://localhost:4000/ui/skills`
existe, mas é **outro recurso** (o *Claude Code Skill Hub*, para publicar
skills da CLI do Claude Code via `/claude-code/marketplace.json`) — não
tem relação com a Anthropic Skills API que este cenário avalia (achado 3
do `README.md`). Por isso este roteiro é: a tela **Skills** (para ver o
gap de visibilidade, que é ele mesmo a história de governança deste
cenário), terminal para criar/listar a skill de verdade, e de volta à
mesma tela para confirmar que ela continua "vazia" mesmo com a skill
existindo.

**Pré-requisito:** logar em `http://localhost:4000/ui`. Nenhum profile
extra — Skills é recurso puro do proxy (rota HTTP + chamada à Anthropic).

## Passo a passo

1. Abra `http://localhost:4000/ui/skills`.
   ✔ **Deve aparecer**: "No skills found — Add one to get started", com o
   texto "Register Claude Code skills. Published skills appear in the
   Skill Hub...". Guarde essa tela — você vai voltar a ela no passo 5.
2. No terminal, crie a skill institucional (o `SKILL.md` de RIPD já
   versionado em `avaliacao/cenarios/05-skills/dados/skill-relatorio-lgpd/`):

   ```bash
   set -a; source poc/.env; set +a
   cd avaliacao/cenarios/05-skills
   rm -rf /tmp/skill-stage && mkdir -p /tmp/skill-stage/relatorio-lgpd
   cp dados/skill-relatorio-lgpd/SKILL.md /tmp/skill-stage/relatorio-lgpd/
   (cd /tmp/skill-stage && zip -qr /tmp/skill.zip relatorio-lgpd)
   curl -s "http://localhost:4000/v1/skills?beta=true" \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     -F "display_title=Relatório de Impacto LGPD (RIPD) $(date +%H%M%S)" \
     -F "files[]=@/tmp/skill.zip" | jq .
   ```

   ✔ **Deve aparecer**: um `id` no formato `skill_...` — a skill foi
   criada de verdade (não é simulação).
3. Liste o catálogo:

   ```bash
   curl -s "http://localhost:4000/v1/skills?beta=true" -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
     | jq -c '[.data[]? | {id, name: (.display_title // .name)}]'
   ```

   ✔ **Deve aparecer**: a skill que você acabou de criar **junto com**
   4 skills nativas da Anthropic (`xlsx`, `pptx`, `pdf`, `docx`) que
   ninguém cadastrou nesta PoC — prova direta de que o catálogo não é
   local ao proxy (achado 1).
4. Teste a "busca por necessidade":

   ```bash
   curl -s "http://localhost:4000/v1/skills?beta=true&query=preciso+escrever+um+relatorio+de+impacto+de+dados+pessoais&top_k=3" \
     -H "Authorization: Bearer $LITELLM_MASTER_KEY" | jq -c '[.data[]? | {id, score: .search_score}]'
   ```

   ✔ **Deve aparecer**: `score` sempre `null` para todas as skills — não
   há busca semântica, é a mesma listagem estática do passo 3.
5. Volte para a aba do navegador em `http://localhost:4000/ui/skills` e
   recarregue a página (F5).
   ✔ **Deve aparecer**: ainda "No skills found" — a skill criada e
   listada por API no passo 3 **não aparece aqui**, confirmando ao vivo
   que são dois catálogos desencontrados na mesma instância (achado 3).

## Conclusão de governança

A mesma do `demo.sh` deste cenário: Skills **funciona tecnicamente**
(cria, lista, e — em `evidencias/SK-04.json`, já capturado — usa a skill
de verdade numa chamada real), mas **não é um recurso soberano nem
governado como MCP e Vector Stores**: o armazenamento é na conta
Anthropic (achado 1), não há busca semântica (achado 2), o painel
administrativo mostra um recurso homônimo e não relacionado (achado 3), e
**não existe nenhum campo de allowlist** por chave/time para este recurso
no schema `LiteLLM_ObjectPermissionBase` (achado 4 — o único, entre os
quatro recursos avaliados na suíte, sem nenhum caminho de hardening).
Pilares evidenciados: **P3** (catálogo — com a ressalva de que não é
soberano) e **P9** (versionamento, mas sem gate de homologação) — ver a
análise completa em [`README.md`](README.md) §8.

Tela que comprova (print já existente): `evidencias/SK-ui.png` (a tela
"No skills found" com a skill custom já existindo via API).
