# PORTIX — Missão Configurações (feat/configuracoes-categorias-temas-cache)

Objetivos do dono: (1) configurações por categorias com hub + telas, (2) cache da
imagem de perfil (0 downloads ao reabrir), (3) sistema de temas. Referência:
Linear / Stripe / Vercel / iOS Settings. Ciclo CRIADOR (agente principal) →
CI (build.yml via dispatch) → CRÍTICO (subagente independente), máx 10 iterações,
parada: média ≥9,5, nenhum critério <9, zero 🔴/🟡, CI verde, 2 avaliações
consecutivas.

## FASE 0 — Reconhecimento (2026-11-17)

### Suposições registradas
- Branch `feat/configuracoes-categorias-temas-cache` criada a partir de
  `ux/melhorias-iterativas` (4713dfa) — SUPOSIÇÃO CONSERVADORA: a main (9060a14,
  só dados do dono) não tem motor v2 nem as 3 iterações de UI (notas 6,6→7,9);
  basear na branch de trabalho preserva tudo. Nunca push na main.
- build.yml gatilhos: `push→main` + `workflow_dispatch` (lido no arquivo).
  Iterações via dispatch (curl, sem gh CLI) + polling por RUN_ID.
- Evidências headless (sem device): testes instrumentados — contador de
  requisições HTTP (HttpOverrides) para o cache, cálculo WCAG dos pares
  fg/bg de cada paleta, pump das telas em 375/768/1440px e texto 2.0,
  ui_gates/analyze/suíte. Screenshots não são possíveis neste ambiente.

### Stack/telas
Flutter 3.50, package `material_ui` (NÃO flutter/material), Riverpod 3.5
(**FutureProvider é autoDispose por padrão**), go_router 18 com
StatefulShellRoute (5 abas; menu = `/menu`), l10n manual `L10n` (pt/en),
`cached_network_image` 4.x, `shared_preferences`. Gates `tool/ui_gates.sh`
(proíbe raw_color/raw_font/raw_text/tok_size fora de tokens; allowlist com 50
linhas; meta: vazia). Suíte atual: 66 testes. Navbar de vidro em MainShell,
`AppContentMax` 1200px, Poppins embutida.

### Inventário TOTAL de configurações hoje (nada pode se perder)
| # | Item atual | Onde está (menu_page.dart) | Nova categoria |
|---|---|---|---|
| 1 | Cabeçalho perfil: foto (GameCover), nome, @handle, badge ADM | 121-195 | Conta e Perfil (resumo permanece no hub) |
| 2 | Status da conta (logado/convidado) | 161-189 | Conta e Perfil |
| 3 | Entrar / Cadastrar (convidado) | 217-222 | Conta e Perfil |
| 4 | Editar perfil → /profile/edit | 197-216 | Conta e Perfil |
| 5 | Sair da conta (com showAppConfirm) | 34-45, 209-214 | Conta e Perfil (destrutivo isolado) |
| 6 | Stats: favoritos/instalados/downloads | 224-254 | Conta e Perfil (resumo no hub) |
| 7 | Atalho "Hub" (/hub) | 256-267 | REMOVIDO do hub — navegação, não configuração (já há aba na navbar). Decisão registrada |
| 8 | Idioma pt/en | 271-303 (hoje em "Aparência") | Idioma e Região |
| 9 | Notificações (toggle) | 305-337 (hoje em "Aparência") | Notificações |
| 10 | Recarregar catálogo | 343-347 | Dados e Armazenamento |
| 11 | Limpar cache | 349-353 | Dados e Armazenamento |
| 12 | Sobre: marca, tagline, versão, fonte de dados, "feito com" | 357-423 | Ajuda e Sobre |
| 13 | Termos de uso (link) | 428-432 | Ajuda e Sobre |
| 14 | Política de privacidade (link) | 434-438 | Ajuda e Sobre |

Categorias finais (vazias removidas — sem itens hoje para Privacidade/Acessibilidade
como seções próprias): **Conta e Perfil · Aparência e Temas · Notificações ·
Idioma e Região · Dados e Armazenamento · Ajuda e Sobre** (6).
Novidades: Tema (Aparência e Temas).

### Causa raiz do reload da imagem de perfil (registrada)
1. `profileProvider` é `FutureProvider` **autoDispose** (Riverpod 3.5) → ao sair
   do menu o provider morre; ao reabrir refaz o fetch do Supabase e volta a
   `AsyncLoading` SEM valor anterior → `profile.coverUrl` = null durante o
   loading → menu renderiza fallback `UserProfile(displayName)` **sem foto**
   (menu_page.dart:85-87) → quando resolve, imagem entra com fade → FLASH.
2. O menu usa `GameCover(imageUrl: profile.coverUrl)` (capa quadrada de jogo,
   memCacheWidth 180) em vez do componente `ProfileAvatar` (que já existe e
   também usa CachedNetworkImage).
3. O cache de disco existe (cached_network_image), mas: sem stale-while-revalidate
   do dado (coverUrl some durante o loading), sem chave por versão (updated_at),
   e o signOut não limpa o cache de imagem (auth.dart:73-75).
Plano do fix: perfil com SWR (mantém último valor + revalida em background,
persistido no CacheStore), ProfileAvatar no menu, invalidação por versão da URL,
signOut limpa o cache de imagem; teste instrumentado contando requisições.

### Cores/tema hoje
Tema escuro ÚNICO "Aurora": `AppTheme.dark()` estático, `AppPalette.darkPalette`
estático, `AppColors.*` estático global (345 ocorrências em lib/). ThemeData
aplicado em app.dart (3 MaterialApp; splash incluído) via `darkThemeProvider`.
`AppSettings` (locale+notifications) persiste em SharedPreferences sincronamente
(no build) — não há flash de idioma; mesma técnica servirá para o tema.
Allowlist raw_color: 20 arquivos fora de core/theme. Sem claro/sistema/extras,
sem seletor, sem persistência de tema.

## Série de notas (CRÍTICO — critérios da missão)

Base: 5/10; notas >5 exigem evidência de código/teste. Máximos: build quebrado ≤6
no geral; imagem recarregando = cache ≤5 e média ≤7; tema ilegível/sub-AA ≤6.

| Iter | Commit | Média | Δ | CI | Resumo |
|---|---|---|---|---|---|
| 0 | 4713dfa | **5,0** | — | 44087292104 | linha de base (ver abaixo) |

### CRÍTICO — iteração 0 (evidências)
| Critério | Peso | Nota | Evidência |
|---|---|---|---|
| Arquitetura de informação | 20% | 3,5 | menu_page.dart: scroll único misturando perfil+conta+stats+navegação+idioma+notificações+dados+sobre+legal; zero subtelas; zero deep link de categoria |
| Sistema de temas | 20% | 3,0 | theme.dart: `AppTheme.dark()` único; `AppPalette.darkPalette` estático; tokens.dart "Tema único (escuro)"; sem seletor/persistência |
| Cache da imagem de perfil | 15% | 4,0 | profile_controller.dart:11 FutureProvider autoDispose → refetch+loading a cada abertura; menu_page.dart:85-87 fallback sem foto (flash); menu usa GameCover:129; sem SWR/versão/limpeza no logout |
| Consistência e design system | 10% | 7,5 | primitives.dart (GlassContainer/SectionTile/AppToggle/SegmentedControl/AppContentMax/showAppConfirm) reusados; allowlist 50 pendências |
| Acessibilidade | 10% | 7,0 | alvos 48px, Semantics em AppToggle, tooltip 24/24, texto 2.0 testado em grades; telas de menu sem teste de overflow; contraste não medido por paleta (1 paleta) |
| Responsividade e navegação | 10% | 6,0 | AppContentMax 1200px no menu; sem master-detail ≥768px; sem drill-down (não há subtelas) |
| Estados e feedback | 5% | 6,5 | snackbars padrão, sign-out confirmado; limpar cache sem confirmação; reload catálogo sem loading na tile |
| Microinterações e performance | 5% | 6,5 | Pressable scale + fades; flash da foto é defeito direto de performance percebida |
| Microcopy | 5% | 8,0 | l10n pt/en consistente no menu |
| **Média ponderada** | | **5,0** | 0,70+0,60+0,60+0,75+0,70+0,60+0,325+0,325+0,40 = 5,000 |

**Problemas iter 0:**
- 🔴 P1 sem categorias/telas (objetivo 1 ausente) — menu_page.dart
- 🔴 P2 tema único estático (objetivo 3 ausente) — theme.dart/tokens.dart
- 🔴 P3 foto pisca + refetch a cada abertura (objetivo 2 violado) — profile_controller.dart/menu_page.dart
- 🟡 P4 signOut não limpa cache de imagem — auth.dart:73
- 🟡 P5 avatar no menu é GameCover (capa), não ProfileAvatar — menu_page.dart:129
- 🟡 P6 limpar cache sem confirmação (ação que apaga dados locais) — menu_page.dart:58
- 🟡 P7 raw_color em 20 arquivos fora de core/theme (blocos de reuso do multi-tema)
- 🟢 P8 tok_size (tamanhos mágicos) em 20 arquivos — drenagem gradual
- 🟢 P9 idioma dentro de "Aparência" (vai para Idioma e Região)
- 🟢 P10 sem busca nas configurações (opcional na missão)

**Veredito: CONTINUAR.**

## Plano de iterações (ordem do CRIADOR)
1. **iter 1 — fundação de temas**: paletas por tema (ThemeExtension + contexto),
   ThemeData dinâmico (claro/escuro/sistema + Midnight, Oceano, Floresta),
   persistência no AppSettings, aplicação sem flash, migração `AppColors.*` →
   cor resolvida do tema (drena raw_color), contraste AA medido por teste.
2. **iter 2 — cache do avatar**: SWR do perfil, ProfileAvatar no menu, versão na
   chave, logout limpa imagem, testes instrumentados (contagem de requisições).
3. **iter 3 — categorias**: hub + telas com rotas/deep link, master-detail ≥768px,
   voltar do sistema, tabela antiga→nova aplicada, destrutivos isolados.
4. **iter 4+ — polimento**: estados, microcopy, drenagem da allowlist, busca
   opcional, overflow 2.0, novas notas do CRÍTICO.

## Estado
- Branch local+remota `feat/configuracoes-categorias-temas-cache` @ 4713dfa.
- Baseline: analyze limpo, gates verdes (allowlist 50), suíte 66/66, CI run
  44087292104 em andamento.
- Guard: main intacta (9060a14, commits de dados do dono).
