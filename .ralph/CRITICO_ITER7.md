# CRÍTICO — Avaliação pós-iter-6 (HEAD 8a37443)

Avaliador: subagente CRÍTICO (independente, sem participação no código).
Branch `feat/configuracoes-categorias-temas-cache` @ 8a37443, `git status` limpo,
main intacta (9060a14). CI 44105416754 informado como success (API do GitHub
indisponível por rate-limit no momento — não pude confirmar por fora; os três
gates locais foram rodados por mim e passam, o que é a evidência local máxima).

## Verificações obrigatórias (rodadas por mim nesta avaliação)

| Gate | Resultado | Evidência |
|---|---|---|
| `flutter analyze` | **No issues found** | saída: "No issues found! (ran in 1.0s)" |
| `bash tool/ui_gates.sh` (com flutter no PATH) | **verdes** (`UI_GATE ok [analyze]`, exit 0) | allowlist NÃO vazia: 25 linhas (18 tok_size, 3 raw_font, 4 raw_text) — ver 🟡-5 |
| `flutter test` | **113/113 passaram** | saída: "+113: All tests passed!" |
| Greps de risco | `Color(0x` fora de core/theme = 0; `Text('<literal>')` = 0; TODO/FIXME = 0; 'Jogador' só em app_strings.dart:228 | rg output |
| `git status` | limpo | — |

## 1. Tabela dos 9 critérios

| # | Critério | Peso | Nota | Evidência principal |
|---|---|---|---|---|
| 1 | Arquitetura de informação | 20% | **9,5** | 6 categorias em settings_categories.dart:35-72; rotas/deep link router.dart:47-86 (`/menu/<id>`); master-detail ≥768px com AppContentMax (settings_category_page.dart:43-66, menu_page.dart:23-27); voltar mobile settings_category_page.dart:161-193; destrutivos com confirmação (account_settings.dart:26-35, data_settings.dart:39-49); tabela antigo→novo SEM órfão coberta por teste (settings_navigation_test.dart:183-239 percorre as 6 categorias e afirma os 13 itens; item 7 "Atalho Hub" removido com decisão registrada em SETTINGS_MISSION.md:42); painel de orientação em `/menu` largo (menu_page.dart:29-61 + teste 419-434); busca persistente settings_hub.dart:14-23/40-46 |
| 2 | Sistema de temas | 20% | **9,0** | 5 paletas + Sistema/Claro/Escuro (themes.dart:267-404); WCAG AA por teste em TODAS as paletas com cor alpha COMPOSTA sobre fundo (theme_contrast_test.dart:35-101: textPrimary/Secondary/Tertiary, accent, accentAlt, onAccent/accent, onAccent/accentAlt, danger/success/warning/favorite/bg); persistência + id inválido normalizado (settings.dart:49-69 + theme_settings_test.dart:78-85); 1º frame sem flash (theme_settings_test.dart:88-110); seletor com prévia real e split Sistema (theme_selector.dart:219-309); reduced motion nos cards (theme_selector.dart:101-103); raw_color=0 fora de core/theme. Descontos: 🟡-4 (SystemChrome no modo Sistema) e 🟢-2 (animação de troca ignora disableAnimations) |
| 3 | Cache da imagem de perfil | 15% | **8,5** | SWR keepAlive com estado inicial do cache no 1º frame (profile_controller.dart:33-68); teste SWR: cache abre instantâneo, reabrir não refaz fetch, logout limpa `cache.profile` (profile_swr_test.dart:175-266); contagem real de HTTP: 5 aberturas = 0 downloads (profile_avatar_cache_test.dart:305-323); troca de foto remove URL antiga+nova do disco (profile_edit_page.dart:95-108); fallback de iniciais offline (profile_avatar.dart:48-59, placeholder+errorWidget); memCacheWidth (profile_avatar.dart:53). Descontos: 🟡-1 (camada de memória do framework ignorada), 🟡-2 (teste "(integração)" não integra) |
| 4 | Consistência e design system | 10% | **9,0** | primitives reusados em todas as categorias (SectionTile primitives.dart:734, GlassContainer, Pressable:131, showAppConfirm:1351, AppToggle, SegmentedControl); grid 4/8 via AppSpacing (tokens.dart:25-58); raw_text=0 em `Text(`; alvos 48dp (tokens.dart:46, settings_hub.dart:199-201). Descontos: 🟡-5 (allowlist 25 entradas vs meta "vazia"), 🟢-4 (darkThemeProvider morto) |
| 5 | Acessibilidade | 10% | **9,0** | Semantics button em Pressable (primitives.dart:176-183), selected nos cards de tema (theme_selector.dart:143-147) e de categoria (settings_hub.dart:272-274); AppToggle com rótulo+estado+48dp testado (responsive_a11y_test.dart:139-162); texto 2.0 com piso 1.0/teto 2.0 (app.dart:28-35) e teste de overflow nas categorias (settings_navigation_test.dart:467-484); prévia de tema rotulada (theme_selector.dart:228-230). Desconto: campo de busca sem label explícito (só hintText) settings_hub.dart:177-186 |
| 6 | Responsividade e navegação | 10% | **9,5** | testes reais em 1200×800 (master-detail), 375×720 (drill-down), 360@2.0 (settings_navigation_test.dart:437-485); AppContentMax fixa o salto de coluna >1200px (primitives.dart:1331-1343); deep link e voltar do sistema por GoRoute aninhada (router.dart:47-86); padding reservado à navbar de vidro em AMBOS os modos (settings_category_page.dart:109-114, settings_hub.dart:121-126, theme.dart:139) |
| 7 | Estados e feedback | 5% | **8,5** | estado vazio da busca (settings_hub.dart:221-252); home com erro → SliverFillRemaining + retry (home_page.dart:45-51); sucesso/erro honesto no recarregar catálogo com teste (data_settings.dart:30-36 + settings_navigation_test.dart:366-384); limpar cache faz o que promete no CacheStore (cache_store.dart:37-45 + DefaultCacheManager().emptyCache() data_settings.dart:51-52 + teste 386-417). Desconto: 🟡-3 (sem loading na tile durante o refresh) |
| 8 | Microinterações e performance percebida | 5% | **9,0** | Pressable com haptics+scale+reduced motion (primitives.dart:159-197); troca de tema animada 220ms (app.dart:55-56, settings.dart:88-96); avatar com fadeIn e decode no tamanho certo (profile_avatar.dart:53-54); zero flash na reabertura (SWR) |
| 9 | Microcopy | 5% | **9,0** | pt/en coerente (app_strings.dart:241-315); fallbacks via l10n (`player` 228, `guestLabel` 432); confirmação honesta (272-275); nenhum '(simulado)' (rg vazio). Descontos: 🟢-6 ("Temas com contraste garantido" é microcopy de QA), 🟢-1 (confirmação agora promete MENOS do que faz) |

## 2. Média ponderada (soma explícita)

```
9,5×0,20 = 1,900
9,0×0,20 = 1,800
8,5×0,15 = 1,275
9,0×0,10 = 0,900
9,0×0,10 = 0,900
9,5×0,10 = 0,950
8,5×0,05 = 0,425
9,0×0,05 = 0,450
9,0×0,05 = 0,450
SOMA     = 9,050  →  Média 9,05
```

## 3. Problemas classificados

### 🔴 Grave — nenhum encontrado

Nada bloqueia release: gates/analyze/suíte verdes, os 3 objetivos têm
implementação real e provada por teste, imagem não recarrega na 2ª abertura,
temas AA medidos.

### 🟡 Médio (6)

**🟡-1 · Cache: a camada de MEMÓRIA do framework é ignorada na invalidação e no logout**
- Onde: `lib/features/profile/profile_controller.dart:95-106` (_clearCaches só remove prefs + `DefaultCacheManager().removeFile`), `lib/features/profile/profile_edit_page.dart:95-108` (_invalidateCover idem).
- Problema: `PaintingBinding.instance.imageCache` (cache de imagens decodificadas) não é limpo no logout nem evictado ao trocar foto. Reupload na MESMA URL (Supabase public URL não muda no upsert): o disco é removido, mas o `ImageCache` do framework serve a imagem antiga decodificada até sofrer eviction → avatar desatualizado na tela, exatamente o caso que a missão pediu para eu verificar ("o teste cobre reupload na MESMA URL?" — não, no nível widget). O cache de memória+disco exigido pela missão só existe de fato no disco.
- Correção esperada: em `_invalidateCover` e `_clearCaches`, fazer `CachedNetworkImageProvider(url).evict()` (ou `PaintingBinding.instance.imageCache.clear()`) além do `removeFile`; incluir teste do fluxo do editor (mesma URL → 1 download novo).

**🟡-2 · Teste "(integração)" do ProfileAvatar não integra nada**
- Onde: `test/profile_avatar_cache_test.dart:350-362`.
- Problema: instanciar `ProfileAvatar(...)` e afirmar `isA<Widget>()` + campos não exercita render, cache manager nem contagem HTTP. A métrica "5 aberturas = 0 downloads" é provada no nível `DefaultCacheManager` (getSingleFile), não no nível do widget que o app usa. O rótulo "(integração)" promete o que o teste não faz.
- Correção esperada: pump de `ProfileAvatar` (ou do header do hub) com `HttpOverrides` contando, 5 rebuilds → 0 downloads; e um teste do caminho `_invalidateCover` (mesma URL → removeFile → 1 download). Alternativa honesta: renomear para "contrato do componente".

**🟡-3 · "Recarregar catálogo" sem loading real (a missão lista este requisito)**
- Onde: `lib/features/menu/categories/data_settings.dart:21-37` e tiles em 66-79; `SectionTile` é estático (primitives.dart:734-781).
- Problema: o tap dispara `await ref.read(homeFeedProvider.notifier).refresh()` sem nenhum feedback de progresso: em rede lenta o usuário fica segundos sem saber se o toque funcionou (só há snackbar no fim). A reavaliação iter-0 já apontava "reload catálogo sem loading na tile".
- Correção esperada: durante o refresh, trocar o `trailing` da tile por spinner e desabilitar o tap (watch do estado do provider ou estado local `_busy`), como já se faz em profile_edit (`_busy`).

**🟡-4 · SystemChrome não reage à mudança de brilho do SO no modo Sistema; e o listener resolve "Sistema" sempre como escuro**
- Onde: `lib/app/app.dart:110-129`.
- Problema: (a) o listener (110-118) aplica `pairNext.dark` quando themeId = system — se o aparelho está em modo CLARO, aplica ícones claros sobre fundo claro (estado errado, só corrigido porque o rebuild logo em seguida passa por build()); (b) `PortixApp.build` não observa `platformBrightness` (lê `View.of(context).platformDispatcher.platformBrightness` sem depender de inherited widget, app.dart:119-125): com tema "Sistema", o usuário trocando claro↔escuro no SO fica com ícones da status bar do estado antigo (ex.: brancos invisíveis sobre fundo claro) até qualquer rebuild.
- Correção esperada: resolver o chrome via `AnnotatedRegion<SystemUiOverlayStyle>` no shell (reativo) ou um `WidgetsBindingObserver`/`MediaQuery.platformBrightnessOf` assistido; no listener, resolver `system` com o brilho REAL da plataforma.

**🟡-5 · Allowlist dos gates não vazia (meta explícita da missão)**
- Onde: `tool/ui_gates_allowlist.txt` — 25 linhas (18 `tok_size`, 3 `raw_font`, 4 `raw_text`) em details/news/profile/search/shell/shared.
- Problema: SETTINGS_MISSION.md:29-30 e o cabeçalho do gate dizem "meta: vazia"; os arquivos de settings saíram da lista (bom), mas 25 pendências continuam legalizadas, incluindo `raw_text` em update_dialog/compat_report_sheet (texto sem l10n) e `fontSize` solto em primitives.dart:937/game_media.dart:189/explore_page.dart:268.
- Correção esperada: drenar por arquivo a cada iteração (tokens/constantes nomeadas + l10n), removendo as linhas no mesmo commit, até o arquivo ficar só com comentários.

**🟡-6 · Commit message do iter-6 afirma "o SystemChrome sai do build", mas a chamada no build permanece (fix parcial)**
- Onde: `lib/app/app.dart:129` (`_applySystemChrome(colors);` dentro de `build`).
- Problema: o apontamento da 8,60 era exatamente "efeito colateral dentro do build". O iter-6 adicionou o listener (correto) mas manteve o efeito colateral no build e o commit descreve remoção que não ocorreu. É idempotente e cobre o 1º frame, por isso não é 🔴 — mas é fix parcial com mensagem não fiel, o que as regras mandam penalizar.
- Correção esperada: `ref.listen(settingsProvider, ..., fireImmediately: true)` + pós-frame (ou AnnotatedRegion), removendo a chamada do corpo do `build`; e commit messages passíveis de verificação linha a linha.

### 🟢 Menor (8)

1. **Confirmação promete MENOS do que faz** — `app_strings.dart:272-275` fala só em "cache local de dados do catálogo", mas `data_settings.dart:51-56` também apaga `cache.profile` e imagens. Ajustar o texto (ex.: "dados do catálogo e do perfil") — inverso do problema anterior, agora sub-promessa.
2. **Troca de tema anima mesmo com reduced motion** — `app.dart:55` fixa `themeAnimationDuration: AppMotion.base` sem olhar `disableAnimations` (os cards do seletor respeitam, theme_selector.dart:101-103; a troca em si não). Usar `View.of(context).platformDispatcher.accessibilityFeatures.disableAnimations` para escolher `Duration.zero`.
3. **Contraste não cobre `glassFloating`** — `theme_contrast_test.dart:42-101` testa bg/bgElevated/glassStrong; o vidro do FAB (glassFloating, mais opaco, themes.dart:52) não tem par testado.
4. **Código morto** — `darkThemeProvider` (theme.dart:123-125) não tem uso em lib/ (testes usam `AppTheme.dark()` direto). Remover.
5. **Caminho do e-mail no header sem teste** — settings_profile_header.dart:31-38 mostra e-mail antes de @handle, mas o teste só cobre o caminho @handle (settings_navigation_test.dart:163-164).
6. **Microcopy dev-speak** — `settingsCatAppearanceDesc` "Temas com contraste garantido" (app_strings.dart:258-259) descreve garantia interna, não benefício ao usuário ("Temas claros e escuros" / "Light, dark and more").
7. **Busca só alcança títulos/descrições de categoria** — settings_hub.dart:54-64; Linear/iOS Settings indexam itens internos ("Tema", "Idioma", "Sair"). Aceitável com 6 categorias, mas é o próximo degrau da IA.
8. **Botão de confirmação destrutiva não se distingue visualmente** — showAppConfirm usa `accent` no confirm (primitives.dart:1389-1398); sair/limpar cache mereceriam variante `danger` para sinalizar destrutivo.

## 4. Conferência item a item dos apontamentos da reavaliação 8,60

| # | Apontamento 8,60 | Status | Evidência |
|---|---|---|---|
| 1 | Header sem e-mail real; convidado duplicado; nome vazio → l10n.player | ✅ **Corrigido de verdade** | settings_profile_header.dart:31-41 (linha secundária = e-mail OU @handle, nunca "Convidado"; cor neutra 86-88; nome vazio → `l10n.player` 39-41); teste novo settings_navigation_test.dart:314-334 ('Jogador' 1×, 'Convidado' 1×). Lacuna mínima: caminho com e-mail real sem teste (🟢-5) |
| 2 | SystemChrome aplicado dentro do build → deveria ser listener/efeito | ⚠️ **PARCIAL** | listener adicionado (app.dart:110-118) MAS a chamada direta permanece no build (app.dart:129) e o commit message afirma remoção inexistente; além disso o listener resolve system→dark sem olhar o brilho real (🟡-4/🟡-6) |
| 3 | Master-detail sem AppContentMax (salto >1200px) | ✅ **Corrigido de verdade** | menu_page.dart:23 e settings_category_page.dart:48 envolvem o Row com `AppContentMax` (primitives.dart:1331-1343, teto 1200) |
| 4 | Busca dessincronizada (controller não semeado) | ✅ **Corrigido de verdade** | settings_hub.dart:40-46 semeia o controller do `settingsSearchProvider`; teste settings_navigation_test.dart:336-364 valida campo='tema' após voltar ao hub |
| 5 | 'Jogador' hardcoded em lib/models | ✅ **Corrigido de verdade** | rg: 'Jogador' existe apenas em app_strings.dart:228; modelos devolvem vazio e a UI resolve (settings_profile_header.dart:39-41, account_settings.dart:46-48) |
| 6 | data_settings com ref.read em callback assíncrono | ✅ **Corrigido de verdade** | data_settings.dart:27-32: `context.mounted` verificado antes de ler o estado pós-refresh; leituras de ref antes do await; teste 366-384 prova o erro honesto |
| 7 | Microcopy de confirmação prometia mais do que o código faz | ✅ **Corrigido de verdade** (com nova sub-promessa 🟢-1) | app_strings.dart:272-275 descreve exatamente o cache de dados; teste 386-417 prova que `cache.profile` sai (o código faz o que diz — e um pouco mais) |
| 8 | Hint redundante no Semantics dos temas | ✅ **Corrigido de verdade** | theme_selector.dart:143-147 usa só `label` + flag `selected` (sem hint duplicando estado); `themeOptionSemantic` limpo (app_strings.dart:296-297) |

Saldo: 7 corrigidos de verdade (com teste de regressão específico para 1, 4, 6, 7 e o header), 1 parcial (SystemChrome).

## 5. Veredito: **CONTINUAR**

Condições de parada e o estado atual:

| Condição | Estado |
|---|---|
| Média ≥ 9,5 | ❌ 9,05 |
| Nenhum critério < 9 | ❌ Cache 8,5 e Estados 8,5 |
| Zero 🔴/🟡 | ❌ 6 🟡 |
| Imagem comprovadamente sem recarregar na 2ª abertura | ✅ profile_swr_test.dart:175-197 (keepAlive) + profile_avatar_cache_test.dart:305-323 (0 downloads) |
| Temas AA sem cores hardcoded | ✅ theme_contrast_test.dart verde p/ 5 paletas; raw_color = 0 fora de core/theme |
| CI verde | ✅ local (analyze/gates/testes); run 44105416754 não pude confirmar por API (rate limit) — presumido success |
| 2 avaliações consecutivas ≥ 9,5 | ❌ sequência: 8,43 → 8,60 → 9,05 |

Caminho para APROVADO (objetivo da próxima iteração): resolver os 6 🟡
(especialmente 🟡-1/🟡-2 para levar Cache a ≥9, e 🟡-3 para Estados ≥9),
drenar a allowlist e subir os critérios 9,0 para 9,5 — depois manter ≥9,5 numa
reavaliação consecutiva.

## 6. TOP problemas priorizados para o CRIADOR (do mais grave ao mais leve)

1. **🟡-1 Invalidar também o cache de MEMÓRIA** — `CachedNetworkImageProvider(url).evict()`/`imageCache.clear()` no logout (profile_controller.dart:95-106) e na troca de foto (profile_edit_page.dart:95-108); cobre reupload na mesma URL. + teste do fluxo real.
2. **🟡-2 Teste de integração real do ProfileAvatar** — pump do widget com HttpOverrides contando 5 aberturas → 0 downloads (profile_avatar_cache_test.dart:350-362 hoje é cosmético).
3. **🟡-3 Loading real no "Recarregar catálogo"** — spinner no trailing da tile + tap desabilitado durante o refresh (data_settings.dart:66-79).
4. **🟡-4/🟡-6 SystemChrome reativo e fora do build** — AnnotatedRegion ou observer de brilho; listener resolve `system` com o brilho real da plataforma (app.dart:110-129); remover a chamada de build() de fato.
5. **🟡-5 Drenar a allowlist (25 → 0)** — começar por raw_text em update_dialog/compat_report_sheet/feedback_report_row e raw_font em primitives.dart:937/game_media.dart:189/explore_page.dart:268.
6. **🟢-1 Microcopy da confirmação** — mencionar perfil/imagens no texto de limpar cache (app_strings.dart:272-275).
7. **🟢-2 Reduced motion na troca de tema** — `themeAnimationDuration` condicionado a disableAnimations (app.dart:55).
8. **🟢-8 Confirm destrutivo em danger** + **🟢-4 remover darkThemeProvider** + **🟢-6 reescrever settingsCatAppearanceDesc**.
