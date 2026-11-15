# PORTIX — UI Scorecard (loop v2)

> Criado na iteração U1 (2026-11-15). Regras: nota sobe **só com evidência** (arquivo:linha,
> teste ou golden). Missão: toda tela ≥ 4 em todas as dimensões e média geral ≥ 4,5.
>
> Dimensões: **Cons** consistência (só tokens/componentes) · **Hier** hierarquia/typografia ·
> **Esp** espaçamento/alinhamento (grid 4/8) · **Cor** cor e contraste (AA) · **Est** estados
> · **Mov** movimento · **Fdb** feedback/micro-interações · **A11y** acessibilidade ·
> **Resp** responsividade · **Perf** fluidez/performance · **i18n** microcopy/pt-BR+en.

## Resumo

| # | Tela | Cons | Hier | Esp | Cor | Est | Mov | Fdb | A11y | Resp | Perf | i18n | Média |
|---|------|------|------|-----|-----|-----|-----|-----|------|------|------|------|-------|
| 1 | Downloads (tile no Hub) | 4 | 3 | 2 | 4 | 4 | 3 | 3 | 3 | 2 | 3 | 4 | 3,2 |
| 2 | Hub (favoritos/instalados) | 4 | 3 | 3 | 4 | 4 | 3 | 3 | 3 | 2 | 3 | 4 | 3,3 |
| 3 | Home | 4 | 4 | 3 | 4 | 3 | 4 | 3 | 3 | 2 | 3 | 4 | 3,4 |
| 4 | Explorar | 4 | 3 | 3 | 4 | 3 | 3 | 3 | 3 | 2 | 3 | 4 | 3,2 |
| 5 | Notícias + matéria | 4 | 3 | 3 | 4 | 3 | 3 | 3 | 3 | 2 | 3 | 4 | 3,2 |
| 6 | Detalhe do jogo (+ reports) | 4 | 4 | 3 | 4 | 3 | 3 | 3 | 3 | 2 | 2 | 4 | 3,2 |
| 7 | Busca | 4 | 3 | 3 | 4 | 3 | 3 | 3 | 3 | 2 | 3 | 4 | 3,2 |
| 8 | Login (Auth) | 4 | 3 | 3 | 4 | 3 | 2 | 3 | 3 | 2 | 3 | 4 | 3,1 |
| 9 | Perfil (editar + público) | 4 | 3 | 3 | 4 | 3 | 2 | 3 | 3 | 2 | 3 | 4 | 3,1 |
| 10 | Menu | 4 | 3 | 3 | 4 | 3 | 2 | 3 | 3 | 2 | 3 | 4 | 3,1 |
| 11 | Splash + BootstrapError | 4 | 4 | 3 | 4 | 2 | 2 | 2 | 3 | 3 | 3 | 3 | 3,0 |
| 12 | Shell (nav + busca FAB) | 4 | 4 | 3 | 4 | 3 | 3 | 3 | 3 | 3 | 3 | 4 | 3,4 |
| 13 | Rota não encontrada | 4 | 3 | 3 | 4 | 3 | 2 | 2 | 3 | 3 | 3 | 4 | 3,1 |
| 14 | Diálogos, sheets, snackbars | 4 | 3 | 3 | 4 | 3 | 2 | 3 | 3 | 2 | 3 | 4 | 3,1 |

**Média geral: 3,2** · Meta: ≥ 4,5 com todas ≥ 4.

## Lacunas transversais (bloqueiam nota 4+ em todas as telas)

1. **Fonte do sistema limitada a 1,35×** — `app.dart:23-27` (`withClampedTextScaling maxScaleFactor: 1.35`).
   O critério de acessibilidade pede até 200%. Afeta a dimensão A11y de todas as telas.
2. **Zero testes de acessibilidade/golden/overflow** — `test/` só tem modelos, formatadores, l10n e
   primitivas soltas. Não existe `meetsGuideline`, teste de contraste ou varredura de overflow
   (360×640, 411×891, 800×1280, landscape, fonte 2.0). Evidência: `ls test/`.
3. **Sem tema claro** — tema único escuro por decisão de marca ("Aurora", `theme.dart:8`). A
   dimensão Cor avalia o tema suportado; decisão registrada em `DECISIONS.md` (D-UI1). Se o
   humano pedir tema claro, vira backlog.
4. **Portão automático inexistente** — não há `tool/ui_gates.sh` nem passo no CI para cores
   soltas, tipografia fora do tema, strings literais ou segredos (medido: 20 arquivos com
   `Color(0x…)`/`Colors.*` fora do tema, 3 com `fontSize:` literal, 76 `SizedBox` mágicos,
   6 com `tooltip:/label:` literal). Allowlist criada na U1 e drenada por tela.
5. **Sem `AnimatedSwitcher`** em troca de estado (0 usos no `lib/`); `GradientProgress` anima
   (primitives.dart:998 `TweenAnimationBuilder`), mas trocas de conteúdo pulam.
6. **`Semantics(` explícito: 0 usos** — sem rótulos para barras de progresso/porcentagem
   anunciada pelo TalkBack além do texto visível.
7. **Fonte Poppins via `google_fonts`** (runtime fetch em aparelho novo sem cache = troca de fonte
   após boot; golden instável). Critério do loop: fonte embutida em `assets/`.

## Notas por tela (evidência e caminho para 4+)

### 1. Downloads (DownloadTile) — 3,2
- **Cons 4** — usa `GlassContainer`/`BadgeChip`/`GradientProgress`/tokens (downloads_tile.dart:100-199).
  Débito: `EdgeInsets`/`SizedBox` mágicos (3, 5, 9, 58, 78) — 7 ocorrências.
- **Hier 3** — título+badge ok; linha de stats e ETA competem com mesmo peso (labelSmall todas).
- **Esp 2** — valores fora do grid 4/8: `height: 3` (:140), `5` (:157), `9` (:148, :198).
- **Cor 4** — só `AppColors` (verificado por rg). Contraste AA a confirmar com teste.
- **Est 4** — 7 estados com rótulo, cor e ação próprios; erro humanizado via `downloadErrorLabel`
  (:160). Falta estado offline/sem espaço distinto visualmente (hoje caem em `failed`).
- **Mov 3** — barra anima (TweenAnimationBuilder); mudanças de estado sem transição.
- **Fdb 3** — ripple via `Pressable`; haptics só no controller. Sem snackbar com desfazer no cancelar/remover.
- **A11y 3** — botões 48dp (:184-194); sem `Semantics` no progresso; percentual só visível quando
  status=downloading (badge), não anunciado.
- **Resp 2** — linha fixa 58×78 sem adaptativo; landscape/teste de overflow inexistente.
- **Perf 3** — `ConsumerWidget`; tile inteira reconstrói a cada tick de progresso (sem `select`).
- **i18n 4** — todo texto via `L10n`; formatadores pt/en (`formatters.dart`).

### 2. Hub — 3,3
- Evidência: `hub_page.dart`. **Est 4** (vazio com EmptyState + ação, contadores por segmento),
  **Esp 3** (`height: 360` mágico :136, :180), **Mov 3** (troca de segmento sem animação),
  **Resp 2** (grade fixa 2 colunas — em tablet 800×1280 deveria ter 3-4).
- Downloads sem filtros (ativos/concluídos/falhos), sem ações em lote, sem reordenação — peça
  central do loop v2 (UI_PLAN U1-D).

### 3. Home — 3,4
- Evidência: `home_page.dart` + `hero_carousel.dart`. **Hier 4** (displaySmall + seções),
  **Mov 4** (carrossel autoplay + `RevealOnMount`), **Est 3** (skeleton `HomeSkeleton` existe;
  erro usa `ErrorStateView`? verificar), **Resp 2** (colunas fixas).

### 4. Explorar — 3,2
- Evidência: `explore_page.dart`. Busca/filtros polidos dependem do FilterSheet; `fontSize:`
  literal presente (1 arquivo na regra raw_font). Estados de rede idem Home.

### 5. Notícias — 3,2
- Evidência: `news_page.dart`, `news_article_page.dart`. Matéria longa sem barra de leitura;
  imagens com `cacheWidth` (news_media.dart) — **Perf** ok nas imagens.

### 6. Detalhe — 3,2
- Evidência: `game_detail_page.dart` (1808 linhas), `game_reports_page.dart`. **Hier 4** (scrim +
  título display), **Perf 2** (página monolítica, rebuild amplo; sem `select`), **Resp 2**
  (grade de ports fixa). Hero presente via `heroTag` (router.dart:76).

### 7. Busca — 3,2
- Evidência: `search_page.dart`, `filter_sheet.dart`. **Est 3** (SearchSkeleton + vazio com
  ação). Histórico limpa sem desfazer (**Fdb 3**).

### 8-10. Auth / Perfil / Menu — 3,1
- Evidência: `auth_page.dart`, `profile_edit_page.dart`, `user_profile_page.dart`, `menu_page.dart`.
  Formulários sem validação visível de erro por campo (Est 3), sem transições (Mov 2).

### 11. Splash + BootstrapError — 3,0
- Evidência: `splash_page.dart`, `app.dart:48-61`. **Est 2** (erro de bootstrap com ação de
  tentar de novo? verificar — hoje só mensagem), **Fdb 2** (sem indicação do que está carregando).

### 12. Shell — 3,4
- Evidência: `main_shell.dart`. Vidro flutuante + FAB; **Mov 3** (troca de aba sem transição
  direcional), **A11y 3** (`GlassNavItem` com label; targets a medir — `circleButton: 46` < 48dp
  no token `AppSpacing.circleButton`).

### 13. NotFound — 3,1
- Evidência: `not_found_page.dart`. **Fdb 2** (sem haptics/ação clara além do voltar).

### 14. Diálogos/sheets — 3,1
- Evidência: `update_dialog.dart`, `compat_report_sheet.dart`, `star_picker`/`StarPicker`
  (primitives.dart:901). Sem padrão único de sheet (raio, handle, insets) — virar componente
  `AppSheet`/`AppDialog` (UI_PLAN U0-C).

## Histórico de notas

| Iteração | Ação | Média | Evidência nova |
| --- | --- | --- | --- |
| U1 | Auditoria inicial + gates + helper de teste a11y/overflow | 3,2 | `test/ui/downloads_tile_test.dart` (guidelines + overflow), `tool/ui_gates.sh` |
