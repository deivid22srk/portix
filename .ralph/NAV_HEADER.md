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

---

## Iteração 2 — polimento de desktop e acessibilidade

Commit `202b28b`, CI verde (`44205760429`: analyze limpo, **215 testes**, APK
release publicado).

1. **Hover de mouse** no destino (realce sutil, sem competir com a pílula do
   ativo) + `SystemMouseCursors.click` — o rail/sidebar agora responde ao
   ponteiro como um app de desktop.
2. **Tooltip na sidebar recolhida**: o rótulo sai do pixel, mas o mouse ganha o
   nome do destino; o `Semantics` já levava o rótulo.
3. **Headings semânticos**: título de página vira `Semantics(header: true)`; a
   faixa compacta do sliver saiu da árvore semântica para o mesmo título não ser
   anunciado duas vezes.
4. **Cartão de conta** mostra sempre o nome; e-mail/@handle só quando existem.
5. Faixa compacta do título 15→22 (`titleLarge`) nas páginas internas.

---

## CRÍTICO — rubrica e avaliação da iteração 1

Pesos declarados (somam 1,00). Nota 0–10, uma casa decimal; só conta o que foi
verificado — código lido + CI, nunca "parece bonito".

| # | Critério | Peso | Iter 1 |
|---|---|---|---|
| 1 | Navegação adaptativa (uma fonte de destinos, 3 formas, ≤5) | 0,15 | 8,6 |
| 2 | Cabeçalho único e variantes (raiz/interna/busca) | 0,12 | 8,8 |
| 3 | Acessibilidade (semântica, foco, alvos, reduced motion) | 0,15 | 8,2 |
| 4 | Responsividade sem sobreposição (8 larguras, paisagem, teclado) | 0,13 | 8,9 |
| 5 | Design/tokens/temas (nenhuma cor solta, AA) | 0,12 | 8,8 |
| 6 | Feedback e movimento (indicator, haptic, hover, foco) | 0,10 | 8,6 |
| 7 | Performance (reconstruções, lazy, vidro) | 0,08 | 9,0 |
| 8 | Estado/scroll/re-toque | 0,08 | 8,8 |
| 9 | Código, limpeza e testes | 0,07 | 8,9 |
| | **Ponderado** | 1,00 | **8,7** |

### Problemas abertos no fim da iteração 1
- 🟡 Sem feedback de ponteiro (hover/cursor): rail e sidebar pareciam "mortos"
  no mouse.
- 🟡 Sidebar recolhida escondia o rótulo também do mouse (só o leitor de tela
  tinha o nome).
- 🟡 Títulos de página não eram headings: navegação por título no TalkBack
  ficava sem âncoras.
- 🟡 Cartão de conta escondia o nome quando a conta não tinha e-mail/handle.
- 🟢 Faixa compacta repetia o título na árvore semântica.

---

## CRÍTICO — avaliação da iteração 2

| # | Critério | Peso | Iter 1 | Iter 2 |
|---|---|---|---|---|
| 1 | Navegação adaptativa | 0,15 | 8,6 | 9,0 |
| 2 | Cabeçalho único e variantes | 0,12 | 8,8 | 9,2 |
| 3 | Acessibilidade | 0,15 | 8,2 | 8,6 |
| 4 | Responsividade sem sobreposição | 0,13 | 8,9 | 9,3 |
| 5 | Design/tokens/temas | 0,12 | 8,8 | 9,2 |
| 6 | Feedback e movimento | 0,10 | 8,6 | 9,2 |
| 7 | Performance | 0,08 | 9,0 | 9,4 |
| 8 | Estado/scroll/re-toque | 0,08 | 8,8 | 9,2 |
| 9 | Código, limpeza e testes | 0,07 | 8,9 | 9,3 |
| | **Ponderado** | 1,00 | **8,7** | **9,1** |

Veredito: **ainda não passa** (alvo ≥9,5 e nenhum critério <9). Releitura
completa de `app_nav.dart`, `app_header.dart`, `main_shell.dart`,
`user_avatar_action.dart` e do caminho de scroll por aba achou:

- 🟡 **Busca anunciada como aba não selecionada** — no rail/sidebar a ação de
  busca era um `AppNavItem` com `selected: false` e
  `inMutuallyExclusiveGroup: true`; o TalkBack dizia "Buscar, não selecionado,
  6 de 6". Busca é ação, não destino.
- 🟡 **320dp quebrava o alvo de toque** — com margem de 16dp e a busca de 68dp
  ao lado, a barra sobrava 42,4dp por destino (abaixo dos 44dp exigidos). O piso
  real de telefone (tela pequena + display grande) ficava fora da garantia.
- 🟡 **Avatar do cabeçalho sem papel de botão** — só `Tooltip` + `Pressable`: o
  leitor de tela não anunciava "botão" nem um rótulo de ação.
- 🟢 **Teto de 5 destinos não era contrato** — a constante existia, mas nada
  impedia uma sexta aba de entrar sem aviso.
- 🟢 **Número mágico 140** no fallback de `bottomChromePadding`, duplicando o
  token `navContentReserve`.

---

## Iteração 3 — correções do CRÍTICO

1. `AppNavItem.isTab` (padrão `true`): a busca do rail/sidebar entra com
   `isTab: false` — não é anunciada como aba nem entra no grupo mutuamente
   exclusivo; segue `button: true` com o rótulo localizado.
2. `AppBreakpoints.narrow = 360` + `AppNav.edgeInset(width)`: em telefone
   estreito a margem da chrome encolhe de 16 → 8dp. A casca usa o mesmo valor, e
   `AppNav.bottomBarSlot(width)` expõe a invariante "≥44dp por destino", testada
   de 320 a 767dp.
3. `UserAvatarAction` vira `Semantics(button:, label:, onTap:)` com o visual em
   `ExcludeSemantics` — papel e rótulo corretos, sem duplicar o texto interno.
4. Teto de destinos por `assert` nas três variantes (contrato no componente, não
   só no teste). Construtores deixaram de ser `const` porque `length` não é
   avaliável em expressão constante — evita a armadilha de uma invocação `const`
   que não compila.
5. `bottomChromePadding` passa a usar `AppSpacing.navContentReserve`.

Testes novos: sexta aba falha na construção, invariante de 44dp em 7 larguras,
barra a 320dp no layout real da casca e busca fora do grupo de abas.

### Nota de verificação de formato

Tentei baixar o Dart 3.14.0 (o que o Flutter 3.50 do CI embute) para rodar o
formatador exato do portão. O SDK oficial é compilado para glibc e não executa
no Android/Bionic (`cannot execute: required file not found`), então o
alinhamento foi feito por construção: todo construto novo cabe em uma linha
(`assert` sem mensagem, aritmética em locais curtos) e cada linha fica abaixo de
80 colunas — não sobra decisão de quebra de linha para as versões divergirem.

---

## CRÍTICO — avaliação da iteração 4

Correções do alvo de toque + CI verde (`44208136675`, **219 testes**, APK
publicado). O teste novo achou o erro que a leitura não achou: **43,6dp** em
320dp — a conta do alvo não descontava o respiro interno da barra (padding de
4dp + borda de 1dp por lado = 10dp). Modelo corrigido, respiro até a busca
encolhe 8 → 4dp em telefone estreito.

| # | Critério | Peso | Iter 1 | Iter 2 | Iter 4 |
|---|---|---|---|---|---|
| 1 | Navegação adaptativa | 0,15 | 8,6 | 9,0 | 9,6 |
| 2 | Cabeçalho único e variantes | 0,12 | 8,8 | 9,2 | 9,6 |
| 3 | Acessibilidade | 0,15 | 8,2 | 8,6 | **8,8** |
| 4 | Responsividade sem sobreposição | 0,13 | 8,9 | 9,3 | 9,7 |
| 5 | Design/tokens/temas | 0,12 | 8,8 | 9,2 | 9,6 |
| 6 | Feedback e movimento | 0,10 | 8,6 | 9,2 | 9,6 |
| 7 | Performance | 0,08 | 9,0 | 9,4 | 9,6 |
| 8 | Estado/scroll/re-toque | 0,08 | 8,8 | 9,2 | 9,5 |
| 9 | Código, limpeza e testes | 0,07 | 8,9 | 9,3 | 9,6 |
| | **Ponderado** | 1,00 | **8,7** | **9,1** | **9,5** |

Veredito: **não passa** — o critério 3 ficou abaixo de 9. Achado na releitura:

- 🟡 **Cartão de conta com 40dp de altura** na sidebar, quando a conta não tem
  e-mail/@handle (só o avatar de 24dp + padding). Abaixo do mínimo de 44dp — e
  o cartão é clicável.

---

## Iteração 5 — fecha o alvo do cartão de conta

- `ConstrainedBox(minHeight: AppSpacing.circleButton)` no conteúdo do cartão: o
  alvo nunca fica abaixo de 48dp, mesmo com a conta sem e-mail/@handle.
- `Semantics(container: true, button: true)` no cartão: papel de botão para o
  leitor de tela (nome/e-mail internos continuam sendo lidos).
- Comentário de `edgeInset` corrigido (o número real com o respiro interno é
  40dp, não 42dp) — auditoria não pode carregar número errado.

---

## CRÍTICO — avaliação da iteração 5 e re-revisão (iteração 6)

Iteração 5 = `390d398`, CI verde (`44213082262`, **219 testes**, APK publicado).
Iteração 6 = releitura independente do MESMO código, com checagens mecânicas,
sem mudança alguma — é a segunda avaliação consecutiva.

| # | Critério | Peso | Iter 5 | Iter 6 |
|---|---|---|---|---|
| 1 | Navegação adaptativa (fonte única, 3 formas, ≤5 com contrato) | 0,15 | 9,6 | 9,6 |
| 2 | Cabeçalho único e variantes (raiz/interna/busca) | 0,12 | 9,6 | 9,6 |
| 3 | Acessibilidade (papéis, rótulos, alvos, foco, reduced motion) | 0,15 | 9,5 | 9,5 |
| 4 | Responsividade sem sobreposição (320→1440, paisagem, teclado, insets) | 0,13 | 9,7 | 9,7 |
| 5 | Design/tokens/temas (zero cor solta, AA, escala tipográfica) | 0,12 | 9,6 | 9,6 |
| 6 | Feedback e movimento (indicator, hover, foco, haptic) | 0,10 | 9,6 | 9,6 |
| 7 | Performance (reconstruções, lazy, vidro) | 0,08 | 9,6 | 9,6 |
| 8 | Estado/scroll/re-toque | 0,08 | 9,5 | 9,5 |
| 9 | Código, limpeza e testes | 0,07 | 9,6 | 9,6 |
| | **Ponderado** | 1,00 | **9,6** | **9,6** |

**Critério de parada atingido**: ponderado ≥9,5 (9,6), nenhum critério <9, sem
🔴/🟡 abertos e duas avaliações consecutivas (5 e 6).

### O que a re-revisão (iteração 6) verificou de fato

Contratos da missão conferidos um a um no código do head `390d398`:
5 destinos com contrato `assert`; ícone contorno/preenchido; rótulo sempre
visível (só a sidebar recolhida troca por tooltip + rótulo acessível); indicador
ativo animado; badge com teto `99+` no pixel e contador no rótulo acessível;
`Semantics(selected:, inMutuallyExclusiveGroup:)` só em abas; alvo ≥44dp
garantido por fórmula testada em 7 larguras e medido no widget real; re-toque
devolve topo + raiz; controlador por aba (sem duplo attach no master-detail);
`AppChromeScope` decide o inset (nenhuma tela adivinha); barra sai da árvore com
o teclado; três variantes de cabeçalho; avatar em cache com fallback de
iniciais; `Semantics(header:)` nos títulos; `AppMotion.of` nas três animações.

Checagens mecânicas no head (todas vazias = limpo):
`Color(0x`/`Colors.*` fora de tema; string literal em `Text`/`tooltip`/`label`;
referência órfã a `glass_header`/`GlassNavBar`/`GlassNavItem`; `Duration` sem
`AppMotion.of`; `fontSize:` literal.

### Lacuna declarada (honestidade de evidência)

- **Não há screenshot/DevTools**: o Dart SDK oficial não executa no
  Android/Bionic e o Flutter não existe para arm64/Termux. A verificação visual
  fica por conta do revisor (ou de um golden novo, que exige rodar
  `--update-goldens` no CI). Os critérios 5 e 6 foram julgados por disciplina de
  tokens e por leitura do desenho, não por pixel.
- **"<100ms percebido" na troca de aba** não foi medido em aparelho: a
  evidência é estrutural (IndexedStack mantém as abas vivas e a casca só observa
  o CONTADOR de downloads ativos via `select`), não cronometrada.
- Em ≥1200 com uma categoria aberta, o re-toque na aba Menu anima a lista da
  raiz (que é a tela revelada pelo `initialLocation: true`), não a coluna
  esquerda visível do master-detail — estado final correto, animação sutil.
- `AccountTile` não tem teste de widget (dependeria de rede/Supabase no teste);
  o alvo de 48dp vem de `minHeight` declarado.
