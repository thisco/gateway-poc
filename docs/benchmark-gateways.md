# Benchmark de Gateways de IA/LLM sob a ótica de Governança Corporativa

> **Contexto:** avaliação de gateways de IA/LLM para uma estatal brasileira que exige soberania de dados (on-premises), auditoria, controle de custo e conformidade (LGPD). Pesquisa realizada em **08/09/2026** com base em documentação oficial e fontes públicas (URLs citadas ao longo do texto). Números de preços e features mudam com frequência — validar antes de contratar.

## Escopo avaliado

| Gateway | Origem | Modelo |
|---|---|---|
| LiteLLM (BerriAI) | Startup OSS | Open source + Enterprise pago |
| Portkey AI Gateway | Startup OSS | Open source + SaaS/Enterprise |
| Kong AI Gateway | Kong Inc. (API gateway) | OSS core + plugins Enterprise/Konnect |
| Envoy AI Gateway | Comunidade Envoy/CNCF (Tetrate, Bloomberg) | 100% open source |
| OpenRouter | Startup SaaS | SaaS puro |
| Cloudflare AI Gateway | Cloudflare | SaaS puro (edge) |
| Google Apigee (+ Model Armor) | Google Cloud | Proprietário gerenciado (opção Hybrid) |
| TrueFoundry | Startup | Proprietário, deploy VPC/on-prem/air-gapped |
| Bifrost (Maxim AI) | Startup OSS | Open source + Enterprise pago |
| Apache APISIX (plugins AI) | Apache Software Foundation | 100% open source |

---

## Tabela comparativa

Legenda: ✅ atende no open source / plano base · 🟡 atende parcialmente ou só em tier pago · ❌ não atende

| Critério | LiteLLM | Portkey | Kong AI GW | Envoy AI GW | OpenRouter | Cloudflare | Apigee | TrueFoundry | Bifrost | APISIX |
|---|---|---|---|---|---|---|---|---|---|---|
| **Licença OSS** | ✅ MIT (core)¹ | ✅ MIT/Apache 2.0² | 🟡 Apache 2.0 (core); plugins AI críticos são Enterprise | ✅ Apache 2.0 | ❌ | ❌ | ❌ | 🟡 core MIT, plataforma proprietária | ✅ Apache 2.0 | ✅ Apache 2.0 (ASF) |
| **On-premises / air-gapped** | ✅ (air-gapped no Enterprise) | ✅ gateway; control plane completo é Enterprise | ✅ data plane; control plane Konnect é SaaS (ou Kong Enterprise on-prem) | ✅ Kubernetes nativo | ❌ SaaS apenas | ❌ SaaS apenas | 🟡 Apigee Hybrid (runtime on-prem, control plane Google) | ✅ VPC/on-prem/air-gapped (pago) | ✅ | ✅ |
| **Virtual keys / times / RBAC** | ✅ virtual keys, teams, orgs no OSS; RBAC avançado/SSO no Enterprise | 🟡 RBAC e orgs só no Enterprise | 🟡 consumers/consumer groups; RBAC via Kong Enterprise | ❌ (usa CRDs K8s + auth externa, sem conceito de virtual key) | 🟡 API keys e controles básicos | 🟡 tokens de gateway | 🟡 apps/developers do modelo API mgmt | ✅ (pago) | ✅ virtual keys/teams no OSS; RBAC/SSO Enterprise | 🟡 consumers genéricos |
| **Budgets e rate limits** | ✅ budgets por key/team/org/modelo, TPM/RPM no OSS | 🟡 usage policies OSS; hierarquia completa no pago | 🟡 rate limit básico OSS; por token (TPM) exige "AI Rate Limiting Advanced" (Enterprise) | ✅ rate limit por token (input/output/cached/reasoning), QuotaPolicy — sem budget monetário nativo | 🟡 limites de crédito/spend | ✅ rate limiting simples | ✅ LLMTokenQuota / PromptTokenLimit | ✅ (pago) | ✅ budgets hierárquicos | ✅ ai-rate-limiting por token |
| **Logging / auditoria** | ✅ spend + request logging OSS; audit logs com retenção no Enterprise | 🟡 storage de logs/dashboard ficou no tier gerenciado | 🟡 audit logging = Enterprise/Konnect | 🟡 métricas/traces OTel; sem trilha de auditoria de negócio | 🟡 metadados apenas (não armazena prompts por padrão) | ✅ logs e analytics no SaaS | ✅ (dentro do GCP) | ✅ (pago) | ✅ + export automatizado no Enterprise | 🟡 logging genérico do gateway |
| **Guardrails (PII, moderação)** | ✅ Presidio PII masking no OSS; LlamaGuard/LLMGuard etc. no Enterprise | ✅ 50+ guardrails no OSS; PII redaction gerenciada no pago | 🟡 AI Sanitizer (PII), Prompt Guard semântico = Enterprise | ❌ (delegado a filtros externos/extensões) | ❌ | 🟡 guardrails básicos no SaaS | ✅ Model Armor (PII, jailbreak, prompt injection) | ✅ (pago) | 🟡 guardrails no Enterprise | 🟡 só via AWS Comprehend (ai-aws-content-moderation) |
| **Multi-provider (SaaS + Ollama/vLLM)** | ✅ 100+ providers, incl. Ollama/vLLM/OpenAI-compatible | ✅ 1.600+ modelos / 45+ providers | ✅ OpenAI, Anthropic, Bedrock, Gemini, Azure + self-hosted via formato OpenAI | ✅ 16+ providers + qualquer endpoint OpenAI-compatible (vLLM) | ✅ (400+ modelos SaaS; não roteia p/ modelos internos) | ✅ (providers SaaS + Workers AI) | ✅ (Vertex + externos) | ✅ | ✅ 20+ incl. Ollama | ✅ (formato OpenAI) |
| **UI administrativa** | ✅ Admin UI no OSS (SSO na UI = Enterprise) | 🟡 dashboard completo é o produto pago | 🟡 Kong Manager OSS limitado; Konnect completo | ❌ (GitOps/CRDs, sem UI) | ✅ (console SaaS) | ✅ (dashboard SaaS) | ✅ (console GCP) | ✅ | ✅ UI embutida | 🟡 Dashboard APISIX básico |
| **Maturidade / comunidade** | Alta — projeto OSS de LLM gateway mais adotado | Alta — 12,9k⭐, 10B tokens/dia | Alta (empresa consolidada de API gateway) | Média-alta — v1.0 (jun/2026), CNCF lineage, Bloomberg/Nutanix em produção | Alta como SaaS | Alta como SaaS | Muito alta (API mgmt) | Média | Baixa-média (recente) | Alta como API gateway; AI recente |
| **Custo (ordem de grandeza)** | OSS grátis; Enterprise ~US$ 250/mês (básico) a ~US$ 30k/ano | OSS grátis; SaaS por uso + Enterprise sob consulta | OSS grátis; Enterprise/Konnect sob consulta (caro) | Grátis (custo operacional K8s) | 5,5% sobre créditos; BYOK 5% após 1M req/mês | Incluído nos planos CF | Licenciamento Apigee (alto) + GCP | Pro US$ 499/mês (VPC); Enterprise sob consulta | OSS grátis; Enterprise sob consulta | Grátis |

¹ Core MIT; funcionalidades do diretório `enterprise/` sob licença comercial. ² Historicamente MIT; o Gateway 2.0 foi unificado e aberto sob Apache 2.0 segundo [The New Stack](https://thenewstack.io/portkey-gateway-open-source/).

---

## Análise por critério

### 1. Licença / open source e on-premises (critério eliminatório para soberania)

- **LiteLLM**: core MIT ([github.com/BerriAI/litellm](https://github.com/BerriAI/litellm)). O próprio vendor anuncia deploy "self-hosted ou air-gapped" ([litellm.ai/enterprise](https://www.litellm.ai/enterprise)). O OSS já entrega o essencial de governança: "an OpenAI-compatible gateway, virtual keys, spend tracking, budgets, fallbacks, and request/response logging" ([docs.litellm.ai/docs/enterprise](https://docs.litellm.ai/docs/enterprise)).
- **Portkey**: gateway open source ([github.com/Portkey-AI/gateway](https://github.com/Portkey-AI/gateway), 12,9k⭐). Em 2026 o Gateway 2.0 abriu sob Apache 2.0 recursos antes exclusivos do SaaS (circuit breakers, usage policies, MCP gateway, catálogo de modelos) ([The New Stack](https://thenewstack.io/portkey-gateway-open-source/)). **Porém** a camada de observabilidade (banco de logs, dashboard), RBAC multi-time e certificações permanecem no tier gerenciado. **Atenção**: análises de 2026 apontam aquisição da Portkey pela Palo Alto Networks ([chatforest.com](https://chatforest.com/reviews/portkey-ai-gateway-review/)) — risco de roadmap a validar antes de qualquer decisão.
- **Kong**: o Kong Gateway OSS é Apache 2.0 e o data plane roda no seu ambiente, mas os plugins de IA que interessam à governança (PII Sanitizer, Semantic Prompt Guard, AI Rate Limiting Advanced por token, audit logging) são **Enterprise/Konnect** ([developer.konghq.com/plugins/ai-sanitizer/](https://developer.konghq.com/plugins/ai-sanitizer/), [konghq.com — token rate limiting](https://konghq.com/blog/engineering/token-rate-limiting-and-tiered-access-for-ai-usage)). Na prática, para uma estatal, Kong só faz sentido com licença Enterprise (Konnect é control plane SaaS; existe Kong Enterprise totalmente on-prem).
- **Envoy AI Gateway**: Apache 2.0, construído sobre Envoy Gateway/Envoy Proxy (CNCF graduated), v1.0 lançada em junho/2026 e considerada production-ready, com uso em produção por Bloomberg e Nutanix ([github.com/envoyproxy/ai-gateway](https://github.com/envoyproxy/ai-gateway), [tetrate.io](https://tetrate.io/blog/envoy-ai-gateway-v1-0-release)). Kubernetes-nativo, 100% on-prem, sem tier pago. *Nota: durante esta pesquisa o site de docs redirecionava para um domínio de terceiros (theagentrouter.ai, da Tetrate); use o repositório oficial `envoyproxy/ai-gateway` como fonte canônica.*
- **OpenRouter**: SaaS puro, **sem opção de self-hosting** — todo tráfego passa pela nuvem deles, incompatível com residência de dados e air-gap ([getmaxim.ai — comparação](https://www.getmaxim.ai/articles/best-openrouter-alternative-in-2026-a-production-ai-gateway-comparison/), [openrouter.ai/docs — BYOK](https://openrouter.ai/docs/guides/overview/auth/byok)). **Eliminado para o caso de uso soberano**; útil apenas como catálogo/sandbox de modelos SaaS.
- **Cloudflare AI Gateway**: SaaS de borda, tráfego transita pela rede da Cloudflare; sem on-prem ([developers.cloudflare.com/ai-gateway/](https://developers.cloudflare.com/ai-gateway/), [truefoundry.com — alternativas](https://www.truefoundry.com/blog/top-9-cloudflare-ai-alternatives-and-competitors-for-2026-ranked)). **Eliminado** pelo mesmo motivo.
- **Apigee**: proprietário; o Apigee Hybrid permite runtime on-prem, mas o control plane permanece no Google Cloud ([docs.cloud.google.com/apigee — AI capabilities](https://docs.cloud.google.com/apigee/docs/api-platform/get-started/ai-capabilities)). Soberania parcial e forte lock-in GCP.
- **TrueFoundry**: plataforma proprietária (core do gateway sob MIT), com deploy VPC, on-premises e **air-gapped** via Helm no tier Enterprise ([truefoundry.com/pricing](https://www.truefoundry.com/pricing), [truefoundry.com/blog/ai-gateway-on-premise](https://www.truefoundry.com/blog/ai-gateway-on-premise)). Atende soberania, mas com dependência de licença comercial de startup estrangeira.
- **Bifrost**: Apache 2.0, binário Go self-hosted (Docker/NPX) ([github.com/maximhq/bifrost](https://github.com/maximhq/bifrost)).
- **Apache APISIX**: Apache 2.0 sob governança da ASF — a licença mais "segura" institucionalmente ([apisix.apache.org/ai-gateway/](https://apisix.apache.org/ai-gateway/)).

### 2. Chaves virtuais, times e RBAC

- **LiteLLM** é a referência: virtual keys com tracking por key/user/team/org/modelo, hierarquia Organizations → Teams → Users, e papéis (`proxy_admin`, `org_admin`, `team_admin`, `internal_user`) ([docs.litellm.ai/docs/proxy/virtual_keys](https://docs.litellm.ai/docs/proxy/virtual_keys), [docs.litellm.ai/docs/proxy/access_control](https://docs.litellm.ai/docs/proxy/access_control), [multi-tenant architecture](https://docs.litellm.ai/docs/proxy/multi_tenant_architecture)). SSO na UI é gratuito até 5 usuários; acima disso exige Enterprise ([truefoundry.com/blog/litellm-pricing-guide](https://www.truefoundry.com/blog/litellm-pricing-guide)).
- **Bifrost** replica o modelo (virtual keys, teams, budgets hierárquicos no OSS; SSO Okta/Entra e RBAC no Enterprise) ([docs.getbifrost.ai](https://docs.getbifrost.ai/overview)).
- **Portkey** deixa RBAC multi-time e gestão de organizações no tier pago ([github.com/Portkey-AI/gateway](https://github.com/Portkey-AI/gateway)).
- **Kong/APISIX/Apigee** usam o modelo clássico de API management (consumers, apps, developer portals) — funciona, mas não é "AI-aware" (sem noção nativa de budget por modelo/time).
- **Envoy AI Gateway** não tem conceito de virtual key/tenant de negócio; a autenticação/autorização é resolvida via padrões K8s (Gateway API, JWT/OIDC externo), o que exige montar a camada de governança por fora.

### 3. Budgets e rate limits

- **LiteLLM**: budgets monetários rígidos por key/team/org/modelo com reset diário/mensal, TPM/RPM por entidade — no open source ([litellm.ai/enterprise](https://www.litellm.ai/enterprise), [docs.litellm.ai/docs/proxy/virtual_keys](https://docs.litellm.ai/docs/proxy/virtual_keys)).
- **Envoy AI Gateway**: o rate limiting por token mais sofisticado do mercado OSS — atribui custo separado para tokens de input, output, cache e reasoning, com `QuotaPolicy` para roteamento quota-aware ([aigateway.envoyproxy.io — v1.0](https://aigateway.envoyproxy.io/blog/v1.0-release-announcement/)). Mas conta **tokens**, não **reais/dólares**: budget financeiro precisa ser construído por cima.
- **Kong**: limite por token (TPM) exige o plugin pago "AI Rate Limiting Advanced" ([konghq.com](https://konghq.com/blog/engineering/token-rate-limiting-and-tiered-access-for-ai-usage)).
- **Apigee**: políticas `LLMTokenQuota` e `PromptTokenLimit` para cotas de tokens por app/usuário ([docs.cloud.google.com/apigee — token policies](https://docs.cloud.google.com/apigee/docs/api-platform/tutorials/using-ai-token-policies)).
- **APISIX**: plugin `ai-rate-limiting` por consumo de tokens, open source ([apisix.apache.org — introdução AI Gateway](https://apisix.apache.org/blog/2025/04/08/introducing-apisix-ai-gateway/)).
- **OpenRouter**: apenas controles de crédito/gasto simples, sem budgets hierárquicos ([getmaxim.ai](https://www.getmaxim.ai/articles/best-openrouter-alternative-in-2026-a-production-ai-gateway-comparison/)).

### 4. Logging e auditoria

- **LiteLLM**: logging de request/response e spend no OSS; **audit logs com política de retenção**, export para GCS/Azure Blob e logging por equipe no Enterprise ([docs.litellm.ai/docs/enterprise](https://docs.litellm.ai/docs/enterprise)). Para uma estatal, a trilha de auditoria formal implica o tier Enterprise (ou instrumentação própria via callbacks OSS + OTel).
- **Portkey**: o ponto fraco do OSS — a camada de armazenamento de logs e o dashboard de observabilidade ficaram no produto gerenciado ([The New Stack](https://thenewstack.io/portkey-gateway-open-source/)).
- **Kong**: audit logging é feature Enterprise/Konnect; boa integração OTel e dashboards de LLM analytics no Konnect ([developer.konghq.com/ai-gateway/](https://developer.konghq.com/ai-gateway/)).
- **Envoy AI Gateway**: métricas e traces OpenTelemetry de qualidade (ex.: integração com Apache SkyWalking — [skywalking.apache.org](https://skywalking.apache.org/blog/2026-04-02-envoy-ai-gateway-monitoring/)), mas é telemetria de infraestrutura, não trilha de auditoria de uso por usuário/projeto.
- **OpenRouter**: não armazena prompts/respostas por padrão, só metadados — bom para privacidade, ruim para auditoria corporativa ([datastudios.org](https://www.datastudios.org/post/openrouter-pricing-and-byok-explained-provider-keys-routing-costs-privacy-controls-and-cost-opti)).

### 5. Guardrails (PII masking, moderação)

- **LiteLLM**: integração nativa e gratuita com **Microsoft Presidio** para detecção/mascaramento/bloqueio de PII por entidade, aplicável por key/team, configurável pela UI ([docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2](https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2), [tutorial](https://docs.litellm.ai/docs/tutorials/presidio_pii_masking)). Guardrails adicionais (LlamaGuard, LLMGuard, Bedrock/Azure moderation) e "guardrails per key/team" avançados no Enterprise. Importante para LGPD: Presidio permite treinar/configurar reconhecedores para CPF/CNPJ.
- **Portkey**: 50+ guardrails no gateway OSS (regex, validadores, integrações com Pillar/Patronus etc.); PII redaction gerenciada no pago ([github.com/Portkey-AI/gateway](https://github.com/Portkey-AI/gateway)).
- **Kong**: conjunto forte — AI Sanitizer (PII com placeholders ou substituições sintéticas e restauração opcional), Prompt Guard, Semantic Prompt Guard, Semantic Response Guard, integrações AWS Guardrails/Azure Content Safety/GCP Model Armor — **tudo Enterprise** ([developer.konghq.com/plugins/ai-sanitizer/](https://developer.konghq.com/plugins/ai-sanitizer/), [Kong 3.10 — PII sanitization](https://konghq.com/blog/product-releases/ai-gateway-3-10)).
- **Apigee + Model Armor**: detecção de jailbreak, prompt injection e PII com redação/bloqueio na camada de proxy, disponível em todos os tiers Apigee ([docs.cloud.google.com/model-armor](https://docs.cloud.google.com/model-armor/model-armor-apigee-integration), [InfoQ](https://www.infoq.com/news/2025/07/google-apigee-llm-model-armor)).
- **Envoy AI Gateway**: sem guardrails nativos; o desenho assume filtros externos (ext_proc) ou soluções de terceiros.

### 6. Multi-provider (SaaS + modelos locais Ollama/vLLM)

Todos os candidatos on-prem falam o "dialeto OpenAI", portanto roteiam para **vLLM/Ollama/TGI** locais além de OpenAI/Anthropic/Bedrock/Azure/Gemini:
- LiteLLM: 100+ providers, incluindo Ollama e vLLM explícitos ([litellm.ai](https://www.litellm.ai/)).
- Portkey: 1.600+ modelos/45+ providers ([github.com/Portkey-AI/gateway](https://github.com/Portkey-AI/gateway)).
- Envoy AI Gateway: 16+ providers + endpoints OpenAI-compatible, com fallback automático entre provedores ([github.com/envoyproxy/ai-gateway](https://github.com/envoyproxy/ai-gateway)).
- Bifrost: 20+ providers incluindo Ollama ([github.com/maximhq/bifrost](https://github.com/maximhq/bifrost)).
- OpenRouter/Cloudflare roteiam essencialmente para provedores SaaS — não servem como fachada para modelos internos on-prem.

### 7. UI administrativa

LiteLLM (Admin UI completa no OSS: keys, teams, budgets, guardrails, logs), Bifrost (UI embutida) e os consoles SaaS (Portkey, Konnect, Cloudflare, OpenRouter, Apigee, TrueFoundry) atendem. **Envoy AI Gateway não tem UI** — gestão 100% declarativa via CRDs/GitOps, o que agrada equipes de plataforma mas dificulta a operação por áreas de negócio.

### 8. Maturidade, comunidade e risco

- **LiteLLM**: o gateway OSS de LLM mais adotado (usado inclusive como engine interna por outros produtos); desenvolvimento muito ativo. Ressalva técnica: proxy em Python — overhead maior por requisição que gateways em Go/C++ (relevante só em milhares de RPS; comparativos de vendors como [Bifrost](https://github.com/maximhq/bifrost) exploram isso, ler com ceticismo).
- **Envoy AI Gateway**: herda a credibilidade do ecossistema Envoy/CNCF; v1.0 estável com Bloomberg/Nutanix em produção ([prnewswire](https://www.prnewswire.com/news-releases/envoy-ai-gateway-reaches-v1-0--establishing-the-open-source-standard-for-enterprise-ai-traffic-302808088.html)).
- **Kong/Apigee/APISIX**: empresas/fundações maduras; risco baixo de descontinuidade, mas o feature set de IA da APISIX é mais raso (sem semantic cache, sem MCP, governança de IA limitada no OSS — [getmaxim.ai](https://www.getmaxim.ai/articles/top-open-source-ai-gateways-for-enterprises-in-2026/)).
- **Portkey**: sinalização de aquisição pela Palo Alto Networks em 2026 ([chatforest.com](https://chatforest.com/reviews/portkey-ai-gateway-review/)) — incerteza de roadmap do OSS.
- **Bifrost/TrueFoundry**: startups recentes; capacidade técnica boa, mas menor histórico.

### 9. Custo

| Opção | Custo de licença | Observação |
|---|---|---|
| LiteLLM OSS | R$ 0 | Cobre virtual keys, budgets, Presidio, UI |
| LiteLLM Enterprise | ~US$ 250/mês (básico) a ~US$ 30k/ano (premium) | SSO, audit logs, RBAC avançado, SLA ([truefoundry.com/blog/litellm-pricing-guide](https://www.truefoundry.com/blog/litellm-pricing-guide)) |
| Envoy AI GW / APISIX / Portkey OSS / Bifrost OSS | R$ 0 | Custo é operacional (K8s, observabilidade) |
| Kong Enterprise / Konnect | Sob consulta | Plugins de IA essenciais são pagos |
| Apigee | Licenciamento GCP (alto) | + lock-in de nuvem |
| TrueFoundry | US$ 499/mês (Pro/VPC); Enterprise sob consulta | Air-gapped só no Enterprise |
| OpenRouter | 5,5% sobre créditos; BYOK 5% após 1M req/mês | Sem valor para cenário soberano ([gatewayscore.com](https://gatewayscore.com/providers/openrouter/)) |

---

## Recomendação para a PoC e para produção

### Eliminações objetivas

**OpenRouter** e **Cloudflare AI Gateway** não oferecem execução on-premises — todo o tráfego (prompts, potencialmente com dados pessoais sob LGPD) transitaria por infraestrutura estrangeira de terceiros. Para uma estatal com requisito de soberania, ambos ficam restritos, no máximo, a experimentação com dados públicos. **Apigee** só atinge soberania parcial (Hybrid mantém control plane no Google) e adiciona lock-in e custo altos sem vantagem clara sobre as opções abertas.

### Para a PoC: **LiteLLM (open source)**

É a escolha de melhor relação esforço/cobertura de requisitos, porque **no tier gratuito e MIT** já entrega exatamente os controles de governança que a PoC precisa demonstrar:

1. **Virtual keys + times + budgets monetários + TPM/RPM** por key/team/org/modelo — nenhum outro OSS entrega esse conjunto pronto ([docs](https://docs.litellm.ai/docs/proxy/virtual_keys));
2. **PII masking com Presidio** (extensível a CPF/CNPJ) aplicável por chave/time ([docs](https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2));
3. **Multi-provider real**: mesma API para SaaS (Bedrock/Azure/Vertex/Anthropic) e modelos locais (vLLM/Ollama) — essencial para testar a tese "modelos soberanos + SaaS sob o mesmo controle";
4. **Admin UI** incluída, o que acelera demonstrações para gestores;
5. Sobe com Docker Compose + Postgres em minutos, sem exigir cluster Kubernetes.

Como contraprova/plano B na PoC, vale subir também o **Bifrost** (Apache 2.0, virtual keys e budgets no OSS, binário Go leve) — cobre o risco de o desempenho do LiteLLM em Python ser insuficiente e serve de benchmark comparativo.

### Para produção: **LiteLLM Enterprise** como camada de governança, com **Envoy AI Gateway** como opção de data plane em escala

- **Cenário A (recomendado, menor complexidade)** — *LiteLLM Enterprise self-hosted/air-gapped*: acrescenta o que auditoria pública exige e o OSS não tem — **audit logs com retenção**, SSO/OIDC com o IdP corporativo, JWT auth, RBAC completo, integração com secret managers e SLA de suporte — por custo previsível (ordem de US$ 30k/ano, marginal frente ao gasto com tokens que ele ajuda a controlar). Mantém a mesma base validada na PoC (migração PoC→produção quase nula).
- **Cenário B (escala alta / padrão de plataforma)** — *Envoy AI Gateway (Apache 2.0, CNCF) como data plane* para tráfego massivo com rate limiting por token de precisão fina e fallback entre provedores, **combinado com LiteLLM** (ou camada própria) para o plano de governança de negócio (virtual keys, budgets em moeda, UI, auditoria por time), já que o Envoy AI Gateway não possui virtual keys, budgets monetários, guardrails nem UI. É o desenho adequado se a organização padronizar Gateway API/Envoy na plataforma de contêineres.
- **Alternativa condicional** — *Kong AI Gateway Enterprise* apenas se a organização **já** possuir contrato Kong Enterprise: os guardrails (AI Sanitizer/Prompt Guard) e o rate limiting por token são maduros, mas todos pagos, e o modelo de governança não é "AI-native" (sem budgets por time/modelo em moeda).
- **A monitorar**: Portkey (excelente engine de guardrails OSS, mas observabilidade presa ao SaaS e incerteza pós-aquisição) e TrueFoundry (air-gapped completo, porém proprietário e de startup — risco de dependência maior que o de um Enterprise sobre base MIT como o LiteLLM).

**Síntese**: para uma estatal que precisa de on-premises, auditoria e controle de custo, o caminho de menor risco é **padronizar o plano de governança no LiteLLM (OSS na PoC → Enterprise em produção)**, mantendo **Envoy AI Gateway** como evolução de data plane caso a escala e a padronização Kubernetes o justifiquem — ambos com núcleo open source, elimináveis de lock-in e capazes de colocar modelos SaaS e modelos locais (vLLM/Ollama) sob a mesma política de chaves, orçamento, mascaramento de PII e trilha de logs.

---

## Fontes principais

- LiteLLM: https://www.litellm.ai/enterprise · https://docs.litellm.ai/docs/enterprise · https://docs.litellm.ai/docs/proxy/virtual_keys · https://docs.litellm.ai/docs/proxy/access_control · https://docs.litellm.ai/docs/proxy/guardrails/pii_masking_v2 · https://www.truefoundry.com/blog/litellm-pricing-guide
- Portkey: https://github.com/Portkey-AI/gateway · https://thenewstack.io/portkey-gateway-open-source/ · https://chatforest.com/reviews/portkey-ai-gateway-review/
- Kong: https://developer.konghq.com/plugins/ai-sanitizer/ · https://konghq.com/blog/product-releases/ai-gateway-3-10 · https://konghq.com/blog/engineering/token-rate-limiting-and-tiered-access-for-ai-usage
- Envoy AI Gateway: https://github.com/envoyproxy/ai-gateway · https://aigateway.envoyproxy.io/blog/v1.0-release-announcement/ · https://tetrate.io/blog/envoy-ai-gateway-v1-0-release · https://skywalking.apache.org/blog/2026-04-02-envoy-ai-gateway-monitoring/
- OpenRouter: https://openrouter.ai/docs/guides/overview/auth/byok · https://gatewayscore.com/providers/openrouter/ · https://www.getmaxim.ai/articles/best-openrouter-alternative-in-2026-a-production-ai-gateway-comparison/
- Cloudflare: https://developers.cloudflare.com/ai-gateway/ · https://www.truefoundry.com/blog/cloudflare-ai-gateway-pricing
- Apigee/Model Armor: https://docs.cloud.google.com/apigee/docs/api-platform/get-started/ai-capabilities · https://docs.cloud.google.com/model-armor/model-armor-apigee-integration · https://docs.cloud.google.com/apigee/docs/api-platform/tutorials/using-ai-token-policies
- TrueFoundry: https://www.truefoundry.com/pricing · https://www.truefoundry.com/blog/ai-gateway-on-premise
- Bifrost: https://github.com/maximhq/bifrost · https://docs.getbifrost.ai/overview
- APISIX: https://apisix.apache.org/ai-gateway/ · https://apisix.apache.org/blog/2025/04/08/introducing-apisix-ai-gateway/
