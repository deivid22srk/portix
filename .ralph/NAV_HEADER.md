# Missão: Navigation bar + cabeçalho (redesign profissional)

Branch: `feat/navbar-header-redesign`
Base: `feat/detalhes-jogo-versoes-desenvolvedor` (a `main` está defasada e não
contém o sistema de temas, a ficha técnica nem as versões/dev do jogo).
Remoto antigo `feat/navbar-header-redesign` foi apagado pelo autor; a branch
local antiga foi renomeada para `attic/navbar-old-local` (não é enviada) e a
nova branch nasceu limpa desta base.

---

## Fase 0 — reconhecimento

### Stack
- Flutter 3.50 / Dart 3.14, Material 3 (`material_ui`).
- Riverpod 3 (`Notifier`/`FutureProvider`), go_router 18 com
  `StatefulShellRoute.indexedStack` (5 abas).
- Supabase + cache local; imagens com `cached_network_image` + placeholder
  procedural (`GameCover`, `ProfileAvatar`).
- Temas: `AppColorsTheme` (ThemeExtension) — Aurora escuro/claro, Midnight,
  Oceano e Floresta; contraste coberto por `test/ui/theme_contrast_test.dart`.

### Destinos e rotas
| # | Aba | Rota raiz | Conteúdo |
|---|-----|-----------|----------|
| 0 | Início | `/home` | feed curado |
| 1 | Explorar | `/explore` | catálogo + filtros |
| 2 | Notícias | `/news` | feed de notícias |
| 3 | Hub | `/hub` | favoritos, instalados, downloads |
| 4 | Menu | `/menu` | hub de configurações (drill-down `/menu/<id>`) |

Topo (sem barra): `/search`, `/game/:slug`, `/game/:slug/reports`, `/specs/*`,
`/news/:slug`, `/auth`, `/profile/edit`, `/u/:id`.

### Componentes antes da iteração 1
- `lib/shared/widgets/glass_header.dart` (`GlassSliverAppBar`, `GlassTopBar`,
  `GlassHeader`) — cabeçalho “de vidro” com overlay controlado por
  `ScrollNotification` (limiar fixo de 80px, animação separada do scroll).
- `GlassNavBar`/`GlassNavItem` em `primitives.dart` — barra inferior única,
  sem rail/sidebar, sem badge, sem `Semantics(selected:)`, sem foco visível.
- `MainShell` (`StatelessWidget`) montava os 5 destinos e **observava a fila de
  downloads inteira**, então cada tick de progresso reconstruía a casca.
- `bottomChromePadding` era `systemBottomInset + 140` em **todas** as telas,
  mesmo quando não havia barra inferior (futuro rail/sidebar).
- Cabeçalhos internos duplicados (voltar + título + subtítulo) em
  `game_reports_page.dart`, `device_specs_screen.dart`,
  `device_specs_search_screen.dart` e `settings_category_page.dart`.

### Eficiência — problemas encontrados
1. Re-render da casca a cada progresso de download (watch da lista inteira).
2. Sem registro de scroll por aba: re-toque não voltava ao topo.
3. Re-toque não devolvia a raiz da pilha da aba (deep link ficava preso).
4. Cabeçalho duplicado por tela (variações de padding/tipografia).
5. Reserva de 140 fixa também no desktop (espaço morto quando a navegação é
   lateral).

### CI
`.github/workflows/build.yml` roda em `push` para `main` e em
`workflow_dispatch`; portanto a branch de trabalho é acionada por
`gh workflow run build.yml --ref feat/navbar-header-redesign`.
O job roda `tool/ui_gates.sh --skip-analyze`, `flutter analyze`,
`flutter test`, e só então gera/assina os APKs.

---

## Iteração 1 — arquitetura e componentes

### Criador
1. **Tokens** (`core/theme/tokens.dart`): medidas da navegação
   (`navBarHeight`, `navRailWidth`, `navItemHeight`, `navSidebar*`,
   `navIconSize`, `glassBlur`, `navContentReserve`), breakpoints
   `navRail=768`/`navSidebar=1200` e `AppMotion.of` (reduced motion).
2. **Chrome** (`core/theme/chrome.dart`): `AppNavMode` +
   `AppChromeScope.publish(bottomPadding)`. `bottomChromePadding` passa a
   perguntar à casca (fallback = barra flutuante). Nenhuma tela adivinha mais.
3. **Navegação** (`shared/widgets/app_nav.dart`): uma lista de
   `AppNavDestination`, três apresentações — `AppNavBottomBar` (pill animada,
   cresce com a fonte do sistema), `AppNavRail` (768–1199) e
   `AppNavSidebar` recolhível (≥1200, marca + conta). Ícone contorno/preenchido,
   rótulo sempre visível, badge com limite `99+`, `Semantics(selected:)`,
   foco visível por teclado e alvo ≥48dp (`Pressable` com haptic).
4. **Cabeçalho único** (`shared/widgets/app_header.dart`): `AppHeaderSliver`
   (raiz, pinned, título grande → compacto, vidro aparece só ao rolar),
   `AppHeaderBar` (interna) e `AppHeaderSearchBar` (busca); ações com overflow
   automático (máx. 3) e slot `trailing` para o avatar.
5. **Avatar em cache**: `UserAvatarAction` reusa `ProfileAvatar` →
   `CachedNetworkImage` com fallback de iniciais, sem recarregar ao trocar aba.
6. **Casca** (`features/shell/main_shell.dart`): `ConsumerWidget` com
   `downloadsProvider.select(...)` (só o contador de ativos reconstrói),
   `AppChromeScope`, barra inferior escondida com o teclado, rail/sidebar em
   larguras maiores e `TabScrollRegistry` para re-toque → topo + raiz da pilha.
7. **Telas migradas**: Início, Explorar, Notícias e Hub usam
   `AppHeaderSliver`; Menu usa `AppHeaderBar`; Busca usa
   `AppHeaderSearchBar`; Relatos e Ficha técnica usam `AppHeaderBar`.
   `glass_header.dart` e a antiga `GlassNavBar` foram removidos.
8. **Testes** (`test/ui/nav_header_test.dart`): forma por largura, ícone
   ativo + `selected`, re-toque, badge `99+`, alvo de toque, fonte 2.0,
   rail/sidebar, 3 variantes do cabeçalho, overflow de ações, título longo,
   inset da chrome e controlador de scroll por aba.

### Suposições registradas
- **Ambiente**: não existe Flutter SDK para Linux/Android arm64 no Termux.
  O build/test/análise são executados no GitHub Actions (fonte de verdade);
  localmente rodamos `dart format` 3.14 (mesma versão do CI) e
  `tool/ui_gates.sh --skip-analyze`. Sem DevTools/screenshots locais.
- Badge da navegação = downloads ativos (único contador real do app hoje).
- Ações de cabeçalho limitadas a 2 visíveis + overflow, para não virar fila.
- Telas de mídia (`/game/:slug`, `/news/:slug`, `/u/:id`) mantêm o botão de
  voltar sobreposto à capa — é um padrão de “hero header”, não uma duplicata.
- `settings_category_page.dart` mantém o título grande dentro do conteúdo
  (drill-down/master-detail); não foi convertido para não regredir o layout
  de duas colunas.

---

## Revisão estática antes do 1º CI (sem Flutter local)

Como não há SDK Flutter para arm64/Termux, a revisão abaixo foi feita lendo as
APIs reais do repositório (`primitives.dart`, `themes.dart`, `auth.dart`,
`profile_controller.dart`) antes de gastar um ciclo de CI.

### Defeitos encontrados e corrigidos
1. **Overflow nunca disparava** — `maxVisible = 3` com `visible = max ? len : max-1`
   mostrava as 3 ações e nenhum menu. Agora `maxActions = 2` e, com excesso,
   aparecem 2 botões + menu (3 alvos de 48dp).
2. **Destino sem ação acessível** — o visual interno está sob `ExcludeSemantics`,
   então o nó não tinha `onTap`: TalkBack não ativava a aba. A ação foi movida
   para o `Semantics` externo, que agora é `container: true` (nó próprio,
   seleção anunciada por destino).
3. **Re-toque não voltava ao topo de verdade** — o registro existia, mas nenhuma
   tela usava os controladores. `TabScrollScope` (InheritedWidget) publica o
   registro e Início/Explorar/Notícias/Hub/Menu usam o controlador da própria
   aba. Em Exploração/Notícias o controlador deixou de ser criado/descartado na
   tela (pertence ao registro).
4. **Rail estourava em paisagem** (891x411 pede ~512dp de altura). Destinos do
   rail e da sidebar agora vivem num `ListView` dentro de `Expanded`; busca e
   conta continuam ancoradas no pé.
5. **Alvo de toque encolhia para o tamanho do ícone** — a `Stack` da barra usava
   `StackFit.loose`; com `StackFit.expand` cada destino herda os 60dp úteis da
   barra.
6. **Teclado** — deslizar a barra deixava 68dp reservados acima do teclado; a
   barra agora sai da árvore (`bottomNavigationBar: null`) e o corpo recupera a
   altura.
7. **Hierarquia tipográfica** — título de raiz passou a `headlineMedium` (30) e
   o interno a `titleLarge` (22), mantendo o peso do desenho anterior
   (`displaySmall`/`titleLarge`); faixa recolhida em `titleSmall` (15), igual ao
   `GlassTopBar` antigo.
8. **Menu e master-detail** — o controlador da aba Menu só é entregue à instância
   da raiz; a instância do master-detail recebe `null` (dois scroll views no
   mesmo controlador lançariam erro).

### Verificação que continua sendo do CI
`flutter analyze` (fatal para warnings/infos), `flutter test` e o APK. Nada de
screenshot/DevTools foi produzido localmente — os goldens existentes
(`test/goldens_out`) cobrem a tela de detalhes, que não foi alterada.
