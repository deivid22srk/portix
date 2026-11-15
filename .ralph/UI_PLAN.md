# PORTIX — UI Plan (loop v2)

> Backlog de UI. Substitui `PLAN.md` para este loop. Itens de MOTOR ficam congelados
> (seção 0 do prompt v2): fila no serviço Kotlin, notificação com ações e limite de
> velocidade **não** serão executados aqui.
>
> Cada iteração = 1 tarefa desta lista, com portões (`tool/ui_gates.sh`), analyze,
> format e testes verdes, e mudança real em `lib/`/`test/`/`assets/`.

## U0 — Fundação

- [x] U0-A. Inventário de 14 telas + `UI_SCORECARD.md` inicial (média 3,2) + `.ralph/ui/<tela>.md`. (U1)
- [x] U0-B. `tool/ui_gates.sh` (cores/tipografia/tamanhos/strings/segredos/analyze) com allowlist
      medida: 20 arquivos de cor, 3 de fontSize, 19 de SizedBox, 6 de label — e passo no `build.yml`.
- [x] U0-C. Helper de teste `test/ui/ui_test_helpers.dart`: pump por tamanho/escala/locale,
      `meetsGuideline` (tap targets + contraste), varredura de overflow (360×640, 411×891,
      800×1280, landscape, fonte 2.0) + primeiro teste (DownloadTile). (U1)
- [ ] U0-D. Design system: fonte embutida em `assets/fonts` (Poppins 2–3 pesos, offline, goldens
      estáveis) e `ThemeExtension<AuroraTokens>` (espaços, raios, durações, cores semânticas);
      app bar/dialog/sheet temáticos.
- [ ] U0-E. Componentes faltantes: `AppSheet`/`AppDialog` padronizados, `AppSnackbar` com
      desfazer, `EmptyState`/`ErrorStateView` com retry ilustrado, `AppProgressBar` com
      `Semantics`.

## U1 — Tela a tela (ordem de impacto; reconstruir com componentes/tokens → estados →
movimento → a11y → i18n → goldens → nota)

- [ ] U1-D. **Downloads (peça central)**: filtros ativos/concluídos/falhos, ações em lote,
      reordenação simples, card polido (capa, velocidade, ETA, bytes), transição de estado com
      `AnimatedSwitcher`, `Semantics` no progresso, snackbar com desfazer no cancelar/remover,
      estado offline/sem espaço diferenciados. Goldens × estados × fonte 1.0/1.5.
- [ ] U1-H. **Hub**: segmentos com indicador animado, grade adaptativa (2/3/4 col por largura),
      espaçamentos no grid 4/8, refresh + haptics, empty states com retry.
- [ ] U1-O. **Home**: seções com `SectionHeader` unificado, carrossel com indicador acessível,
      grade adaptativa, imagens `cacheWidth` + crossfade consistentes.
- [ ] U1-X. **Explorar**: chips de filtro no tema, sheet de filtros via `AppSheet`, remoção do
      `fontSize:` literal, esqueleto→conteúdo com fade.
- [ ] U1-T. **Detalhe**: dividir página monolítica em widgets com escopo de rebuild, Hero +
      scrim ajustados, portas/reportes nos componentes base, `Read more` animado.
- [ ] U1-N. **Notícias + matéria**: tipografia de leitura, barra de progresso de leitura,
      imagens com crossfade, states.
- [ ] U1-B. **Busca**: transição de expansão, histórico com desfazer, estados de rede.
- [ ] U1-C. **Login + Perfil (editar/público)**: validação por campo com mensagens, foco/teclado,
      avatar com picker polido, states de carregamento por botão.
- [ ] U1-M. **Menu**: linhas padronizadas com `SectionTile`/tokens, stats com `StatBadge`,
      seções com headers acessíveis.
- [ ] U1-V. **Diálogos/sheets/snackbars**: migrar todos para `AppSheet`/`AppDialog`/`AppSnackbar`.
- [ ] U1-S. **Splash/BootstrapError**: brand moment (logo animado curto), erro com retry explícito.

## U2 — Transversal

- [ ] U2-F. `style(ui)`: `dart format` em toda a base (65 arquivos fora do padrão) e gate de
      formato integral ligado no `ui_gates.sh`.
- [ ] U2-A. **A11y pass**: remover clamp de 1,35× (suportar 2,0), `Semantics` em progressos/
      imagens decorativas, contrastes AA verificados por teste em todas as telas, revisão de
      alvos < 48dp (token `circleButton: 46`).
- [ ] U2-R. **Responsivo pass**: breakpoints (compact/medium/expanded) via `LayoutBuilder` para
      grades e listas; landscape sem overflow (testes).
- [ ] U2-P. **Plataforma**: edge-to-edge audit, ícone monocromático, splash android_12 alinhada
      à marca, *predictive back* (go_router), transições coerentes entre abas.
- [ ] U2-I. **i18n pass**: revisão de microcopy pt-BR/en, formatadores por locale (datas/números),
      textos de erro cobrindo todos os códigos do motor.
- [ ] U2-G. **Goldens**: cobertura por tela × estado × tema × escala 1.0/1.5 com fonte embutida;
      artefato `portix-goldens` no CI.
- [ ] U2-Perf. **Performance pass**: `select`/`ValueListenableBuilder` nos ticks de download,
      `RepaintBoundary` nas barras animadas, keys estáveis em listas.
- [ ] U2-Doc. README com screenshots/goldens + guia do design system.

## Congelados (motor — NÃO executar neste loop)

- [congelado] Fila no serviço Kotlin (N simultâneos, START_STICKY).
- [congelado] Notificação com ações (pausar/cancelar na notificação).
- [congelado] Limite de velocidade no motor + exposição na UI.
- [congelado] SHA-256 (catálogo não publica hashes).

## Allowlist dos gates (drenar por tela)

`tool/ui_gates_allowlist.txt` lista arquivo × regra. Ao reconstruir uma tela, remova suas
linhas no mesmo commit. Meta: allowlist vazia no fim do U2.
